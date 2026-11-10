import Foundation
#if os(Windows)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// The OS socket to the gateway. Blocking calls run on dedicated threads, never on the cooperative pool.
// @unchecked Sendable: the only mutable state, `closed`, sits behind `lock`; `sendLock` only keeps writes whole.
final class TCPSocket: Transport, @unchecked Sendable {
    let incoming: AsyncThrowingStream<[UInt8], any Error>
    private let continuation: AsyncThrowingStream<[UInt8], any Error>.Continuation
    private let handle: Handle
    private let lock = NSLock()
    private let sendLock = NSLock()
    private var closed = false

    /// Wraps a connected socket and starts its reader thread.
    init(handle: Handle) {
        self.handle = handle
        (incoming, continuation) = AsyncThrowingStream.makeStream()
        Thread { [self] in readLoop() }.start()
    }

    static func connect(host: String, port: Int, timeout: Duration) async throws -> TCPSocket {
        try await withCheckedThrowingContinuation { continuation in
            Thread {
                continuation.resume(with: Result { () throws(IBClientError) in
                    TCPSocket(handle: try openHandle(host: host, port: port, timeout: timeout))
                })
            }.start()
        }
    }

    func write(_ bytes: [UInt8]) throws(IBClientError) {
        sendLock.lock()
        defer { sendLock.unlock() }
        guard isOpen else { throw .connectionClosed }
        var sent = 0
        while sent < bytes.count {
            let n = bytes.withUnsafeBytes { sendBytes(handle, $0.baseAddress! + sent, $0.count - sent) }
            guard n > 0 else {
                let code = lastError()
                throw isOpen ? .transport("send: \(code)") : .connectionClosed
            }
            sent += n
        }
    }

    func close() {
        lock.withLock {
            guard !closed else { return }
            closed = true
            shutdownHandle(handle)   // wakes a blocked recv or send
        }
    }

    private var isOpen: Bool { lock.withLock { !closed } }

    private func readLoop() {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = buffer.withUnsafeMutableBytes { recvBytes(handle, $0.baseAddress!, $0.count) }
            if n > 0 { continuation.yield(Array(buffer[..<n])); continue }
            let code = lastError()
            if n == 0 || !isOpen {
                continuation.finish()
            } else {
                continuation.finish(throwing: IBClientError.transport("recv: \(code)"))
            }
            break
        }
        // Released here, not in close(): no recv or send can still hold the handle, so a reused one is never touched.
        sendLock.withLock { lock.withLock { closed = true; closeHandle(handle) } }
    }

    /// Resolves `host` and connects to the first address that answers, all within `timeout`.
    private static func openHandle(host: String, port: Int, timeout: Duration) throws(IBClientError) -> Handle {
        _ = startup
        let deadline = ContinuousClock.now + timeout
        var hints = AddrInfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = streamType
        var list: UnsafeMutablePointer<AddrInfo>?
        let rc = getaddrinfo(host, String(port), &hints, &list)
        guard rc == 0, let list else { throw .transport("getaddrinfo: \(rc)") }
        defer { freeaddrinfo(list) }
        var failure = IBClientError.transport("connect: no address")
        for ai in sequence(first: list, next: { $0.pointee.ai_next }) {
            do throws(IBClientError) {
                return try attempt(ai, deadline: deadline)
            } catch .timeout {
                throw .timeout
            } catch {
                failure = error
            }
        }
        throw failure
    }

    /// Non-blocking connect bounded by `deadline`, then back to blocking.
    private static func attempt(_ ai: UnsafeMutablePointer<AddrInfo>, deadline: ContinuousClock.Instant) throws(IBClientError) -> Handle {
        let h = socket(ai.pointee.ai_family, ai.pointee.ai_socktype, ai.pointee.ai_protocol)
        guard h != invalidHandle else { throw .transport("socket: \(lastError())") }
        do throws(IBClientError) {
            guard setNonBlocking(h, true) else { throw .transport("nonblocking: \(lastError())") }
            if connectHandle(h, ai) != 0 {
                let code = lastError()
                guard code == connectPending else { throw .transport("connect: \(code)") }
                let (s, atto) = (deadline - .now).components
                let ms = Int32(clamping: s * 1000 + atto / 1_000_000_000_000_000)
                guard ms > 0 else { throw .timeout }
                let ready = pollWritable(h, ms)
                if ready == 0 { throw .timeout }
                if ready < 0 { throw .transport("poll: \(lastError())") }
                let failed = socketError(h)
                if failed != 0 { throw .transport("connect: \(failed)") }
            }
            guard setNonBlocking(h, false) else { throw .transport("blocking: \(lastError())") }
            tune(h)
            return h
        } catch {
            closeHandle(h)
            throw error
        }
    }
}

#if os(Windows)
extension TCPSocket {
    typealias Handle = SOCKET
    static let startup: Void = { var data = WSADATA(); _ = WSAStartup(0x0202, &data) }()
    static let streamType = SOCK_STREAM
}
private typealias AddrInfo = ADDRINFOA
private let invalidHandle = SOCKET.max   // INVALID_SOCKET, a cast macro that does not import
private let connectPending = WSAEWOULDBLOCK
private let fionbio = Int32(bitPattern: 0x8004_667E)   // FIONBIO, a function-like macro that does not import

private func lastError() -> Int32 { WSAGetLastError() }
private func closeHandle(_ h: SOCKET) { _ = closesocket(h) }
private func shutdownHandle(_ h: SOCKET) { _ = shutdown(h, SD_BOTH) }

private func setNonBlocking(_ h: SOCKET, _ on: Bool) -> Bool {
    var mode: u_long = on ? 1 : 0
    return ioctlsocket(h, fionbio, &mode) == 0
}

/// Windows reports a refused connect only after ~2 s of SYN retries. Loopback loses no SYN, so there it
/// sends just one: a refused 127.0.0.1 fails at once, and "localhost" falls from ::1 to 127.0.0.1 without the wait.
private func connectHandle(_ h: SOCKET, _ ai: UnsafeMutablePointer<ADDRINFOA>) -> Int32 {
    if isLoopback(ai.pointee.ai_addr) {
        // TCP_INITIAL_RTO_PARAMETERS { Rtt = TCP_INITIAL_RTO_UNSPECIFIED_RTT, MaxSynRetransmissions = NO_SYN_RETRANSMISSIONS },
        // packed little-endian; SIO_TCP_INITIAL_RTO = _WSAIOW(IOC_VENDOR, 17). Both are macros that do not import.
        var params: UInt32 = 0x00FE_FFFF
        var returned: DWORD = 0
        _ = WSAIoctl(h, 0x9800_0011, &params, 4, nil, 0, &returned, nil, nil)
    }
    return connect(h, ai.pointee.ai_addr, Int32(ai.pointee.ai_addrlen))
}

private func isLoopback(_ address: UnsafeMutablePointer<sockaddr>) -> Bool {
    switch Int32(address.pointee.sa_family) {
    case AF_INET:
        address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.S_un.S_addr) >> 24 == 127 }
    case AF_INET6:
        address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
            withUnsafeBytes(of: $0.pointee.sin6_addr) { Array($0) == Array(repeating: 0, count: 15) + [1] }
        }
    default:
        false
    }
}

private func pollWritable(_ h: SOCKET, _ ms: Int32) -> Int32 {
    var p = WSAPOLLFD(fd: h, events: Int16(POLLOUT), revents: 0)
    return WSAPoll(&p, 1, ms)
}

private func socketError(_ h: SOCKET) -> Int32 {
    var e: Int32 = 0
    var len = Int32(MemoryLayout<Int32>.size)
    let rc = withUnsafeMutableBytes(of: &e) {
        getsockopt(h, SOL_SOCKET, SO_ERROR, $0.baseAddress!.assumingMemoryBound(to: CChar.self), &len)
    }
    return rc == 0 ? e : WSAGetLastError()
}

private func tune(_ h: SOCKET) {
    _ = withUnsafeBytes(of: Int32(1)) {
        setsockopt(h, Int32(IPPROTO_TCP.rawValue), TCP_NODELAY, $0.baseAddress!.assumingMemoryBound(to: CChar.self), 4)
    }
}

private func recvBytes(_ h: SOCKET, _ p: UnsafeMutableRawPointer, _ n: Int) -> Int {
    Int(recv(h, p.assumingMemoryBound(to: CChar.self), Int32(clamping: n), 0))
}

private func sendBytes(_ h: SOCKET, _ p: UnsafeRawPointer, _ n: Int) -> Int {
    Int(send(h, p.assumingMemoryBound(to: CChar.self), Int32(clamping: n), 0))
}
#else
extension TCPSocket {
    typealias Handle = Int32
    static let startup: Void = ()
    #if canImport(Glibc)
    static let streamType = Int32(SOCK_STREAM.rawValue)
    #else
    static let streamType = SOCK_STREAM
    #endif
}
private typealias AddrInfo = addrinfo
private let invalidHandle: Int32 = -1
private let connectPending = EINPROGRESS
#if canImport(Glibc)
private let sendFlags = Int32(MSG_NOSIGNAL)
#else
private let sendFlags: Int32 = 0   // Darwin uses SO_NOSIGPIPE, set in tune
#endif

private func lastError() -> Int32 { errno }
private func closeHandle(_ h: Int32) { _ = close(h) }
private func shutdownHandle(_ h: Int32) { _ = shutdown(h, Int32(SHUT_RDWR)) }

private func setNonBlocking(_ h: Int32, _ on: Bool) -> Bool {
    let flags = fcntl(h, F_GETFL)
    return flags >= 0 && fcntl(h, F_SETFL, on ? flags | O_NONBLOCK : flags & ~O_NONBLOCK) == 0
}

private func connectHandle(_ h: Int32, _ ai: UnsafeMutablePointer<addrinfo>) -> Int32 {
    connect(h, ai.pointee.ai_addr, ai.pointee.ai_addrlen)
}

private func pollWritable(_ h: Int32, _ ms: Int32) -> Int32 {
    var p = pollfd(fd: h, events: Int16(POLLOUT), revents: 0)
    return poll(&p, 1, ms)
}

private func socketError(_ h: Int32) -> Int32 {
    var e: Int32 = 0
    var len = socklen_t(MemoryLayout<Int32>.size)
    return getsockopt(h, SOL_SOCKET, SO_ERROR, &e, &len) == 0 ? e : errno
}

private func tune(_ h: Int32) {
    var one: Int32 = 1
    let size = socklen_t(MemoryLayout<Int32>.size)
    _ = setsockopt(h, Int32(IPPROTO_TCP), TCP_NODELAY, &one, size)
    #if canImport(Darwin)
    _ = setsockopt(h, SOL_SOCKET, SO_NOSIGPIPE, &one, size)
    #endif
}

private func recvBytes(_ h: Int32, _ p: UnsafeMutableRawPointer, _ n: Int) -> Int { recv(h, p, n, 0) }
private func sendBytes(_ h: Int32, _ p: UnsafeRawPointer, _ n: Int) -> Int { send(h, p, n, sendFlags) }
#endif
