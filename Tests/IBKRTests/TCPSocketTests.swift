import Testing
@testable import IBKR
#if os(Windows)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#else
import Glibc
#endif

private func isTransport(_ error: any Error) -> Bool {
    if case .transport = error as? IBClientError { true } else { false }
}

@Test func connectToClosedPortFails() async {
    let start = ContinuousClock.now
    await #expect(performing: {
        _ = try await TCPSocket.connect(host: "127.0.0.1", port: 1, timeout: .seconds(2))
    }, throws: isTransport)
    #expect(ContinuousClock.now - start < .seconds(2))
}

/// A blackholed address keeps the connect waiting; the cancel must end it at the next poll slice, not the timeout.
@Test func connectReturnsSoonAfterCancel() async throws {
    let attempt = Task { try await TCPSocket.connect(host: "10.255.255.1", port: 4002, timeout: .seconds(30)) }
    try await Task.sleep(for: .milliseconds(100))
    let cancelledAt = ContinuousClock.now
    attempt.cancel()
    if case .success(let socket) = try await within2s({ await attempt.result }) { socket.close() }
    #expect(ContinuousClock.now - cancelledAt < .seconds(1))
}

@Test func interruptedCallsAreRetried() {
    var calls = 0
    let n = retryingSocketEINTR { () -> Int in
        calls += 1
        guard calls == 3 else { setLastError(socketEINTR); return -1 }
        return 5
    }
    #expect(n == 5 && calls == 3)
    calls = 0
    #expect(retryingSocketEINTR { () -> Int in calls += 1; setLastError(socketEINTR + 1); return -1 } == -1)
    #expect(calls == 1)   // any other failure returns at once
}

#if os(Windows)
private func setLastError(_ code: Int32) { WSASetLastError(code) }
#else
private func setLastError(_ code: Int32) { errno = code }
#endif

@Test func unknownHostFails() async {
    await #expect(performing: {
        _ = try await TCPSocket.connect(host: "no-such-host.invalid", port: 4001, timeout: .seconds(2))
    }, throws: isTransport)
}

/// Collects `stream` until it finishes.
private func drain(_ stream: AsyncThrowingStream<[UInt8], any Error>) async throws -> [UInt8] {
    try await within2s { try await stream.reduce([], +) }
}

@Test func socketsExchangeBytesAndCloseEndsBothStreams() async throws {
    let listener = Listener()
    let client = try await TCPSocket.connect(host: "localhost", port: listener.port, timeout: .seconds(2))
    let peer = listener.accept()

    try client.write(Array("hello".utf8))
    client.close()
    client.close()   // idempotent
    #expect(throws: IBClientError.connectionClosed) { try client.write([1]) }

    #expect(try await drain(client.incoming) == [])                  // finishes without throwing
    #expect(try await drain(peer.incoming) == Array("hello".utf8))   // bytes, then end of stream
    peer.close()
}

/// A peer that hangs up must cost a write an error, not the process a SIGPIPE.
@Test func writeAfterPeerCloseThrowsConnectionClosed() async throws {
    let listener = Listener()
    let client = try await TCPSocket.connect(host: "127.0.0.1", port: listener.port, timeout: .seconds(2))
    let peer = listener.accept()
    peer.close()

    // The first writes may still fit in the send buffer. Then either send meets the peer's reset, or our reader has
    // seen the close first: the error must be the same either way.
    let error = try await within2s { () async throws -> IBClientError in
        while true {
            do throws(IBClientError) { try client.write([1]) } catch { return error }
            await Task.yield()
        }
    }
    #expect(error == .connectionClosed)
    client.close()
}

/// A reset or abort is a closed connection on the read path as well as the write path (the old `.transport` raced).
@Test func peerResetCodesMapToConnectionClosed() {
#if os(Windows)
    #expect(peerGone.contains(WSAECONNRESET) && peerGone.contains(WSAECONNABORTED))
#else
    #expect(peerGone.contains(ECONNRESET) && peerGone.contains(EPIPE))
#endif
}
