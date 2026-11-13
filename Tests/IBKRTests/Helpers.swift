import Foundation
@testable import IBKR
#if os(Windows)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#else
import Glibc
#endif

func body(_ fields: String...) -> [UInt8] { fields.flatMap { Array($0.utf8) + [0] } }

func d(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }

/// Inserts each group after the base-case index given, so the indices stay those of the table.
func inserting(_ groups: [(after: Int, fields: [String])], into f: [String]) -> [String] {
    var f = f
    for g in groups.sorted(by: { $0.after > $1.after }) { f.insert(contentsOf: g.fields, at: g.after + 1) }
    return f
}

/// `f` with the field at each index replaced.
func replacing(_ f: [String], _ changes: [Int: String]) -> [String] {
    var f = f
    for (i, v) in changes { f[i] = v }
    return f
}

struct TimedOut: Error {}

/// Resumes its continuation once: the first of the operation and the timer wins.
private final class Race<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<T, any Error>?
    init(_ cont: CheckedContinuation<T, any Error>) { self.cont = cont }
    func finish(_ result: Result<T, any Error>) {
        lock.lock(); let c = cont; cont = nil; lock.unlock()
        c?.resume(with: result)
    }
}

/// Runs `operation`, failing with `TimedOut` after 2 s instead of hanging. A task group would wait for a stuck
/// child on exit (one that awaits an unstructured `Task.value` ignores cancellation), so the two race through a
/// continuation and a timed-out operation is cancelled and left behind.
func within2s<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { cont in
        let race = Race(cont)
        let work = Task { do { race.finish(.success(try await operation())) } catch { race.finish(.failure(error)) } }
        let timer = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { race.finish(.failure(TimedOut())); work.cancel() }
        }
        Task { _ = await work.value; timer.cancel() }
    }
}

/// Reads `count` elements, or until the stream throws. The reader keeps the stream until cancelled, so a test
/// that wants the consumer to stop cancels `.reader`.
func take<T: Sendable>(_ count: Int, _ stream: AsyncThrowingStream<T, any Error>)
    -> (reader: Task<Void, Never>, result: Task<[T], any Error>) {
    let (seen, out) = AsyncThrowingStream.makeStream(of: T.self, throwing: (any Error).self)
    let reader = Task {
        do { for try await t in stream { out.yield(t) }; out.finish() } catch { out.finish(throwing: error) }
    }
    let result = Task {
        var got: [T] = []
        if count > 0 { for try await t in seen { got.append(t); if got.count == count { break } } }
        else { for try await t in seen { got.append(t) } }
        return got
    }
    return (reader, result)
}

struct TimedOutWaiting: Error, CustomStringConvertible { var description: String }

/// `within2s` with a longer limit for live runs: fails with a message naming `what` after `seconds` instead of hanging.
func within<T: Sendable>(_ what: String, seconds: Int = 15, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { cont in
        let race = Race(cont)
        let work = Task { do { race.finish(.success(try await operation())) } catch { race.finish(.failure(error)) } }
        let timer = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { race.finish(.failure(TimedOutWaiting(description: "timed out after \(seconds) s waiting for \(what)"))); work.cancel() }
        }
        Task { _ = await work.value; timer.cancel() }
    }
}

/// A loopback listener on an ephemeral port, so the test never touches a real gateway.
struct Listener: Sendable {
    var handle: TCPSocket.Handle
    var port = 0

    init() {
        _ = TCPSocket.startup
        var addr = sockaddr_in()
        addr.sin_family = .init(AF_INET)
        #if os(Windows)
        addr.sin_addr.S_un.S_addr = UInt32(0x7F00_0001).bigEndian
        handle = socket(AF_INET, SOCK_STREAM, 0)
        var len = Int32(MemoryLayout<sockaddr_in>.size)
        #else
        addr.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
        handle = socket(AF_INET, TCPSocket.streamType, 0)
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        #endif
        let h = handle
        withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = bind(h, $0, len)
                _ = getsockname(h, $0, &len)
            }
        }
        _ = listen(h, 1)
        port = Int(UInt16(bigEndian: addr.sin_port))
    }

    /// Returns at once when a connection is already queued.
    func accept() -> TCPSocket { TCPSocket(handle: acceptHandle(handle)) }

    /// Waits for the next connection on a thread of its own: a blocking accept on the cooperative pool could starve
    /// the client that is about to connect.
    func acceptOffPool() async -> TCPSocket {
        await withCheckedContinuation { c in Thread { c.resume(returning: accept()) }.start() }
    }
}

#if os(Windows)
private func acceptHandle(_ h: TCPSocket.Handle) -> TCPSocket.Handle { WinSDK.accept(h, nil, nil) }
#elseif canImport(Darwin)
private func acceptHandle(_ h: TCPSocket.Handle) -> TCPSocket.Handle { Darwin.accept(h, nil, nil) }
#else
private func acceptHandle(_ h: TCPSocket.Handle) -> TCPSocket.Handle { Glibc.accept(h, nil, nil) }
#endif

/// Pumps a loopback peer into `gateway` one frame per write, the hello first (as `FakeGateway` expects), and the
/// gateway's bytes back, until either side ends; then closes both.
func bridge(_ peer: TCPSocket, _ gateway: FakeGateway) -> Task<Void, Never> {
    Task {
        let back = Task {
            do { for try await chunk in gateway.incoming { try peer.write(chunk) } } catch {}
            peer.close()
        }
        var frames = FrameReader(), prefix = 4   // the "API" prefix and its NUL come before the first length
        do {
            for try await chunk in peer.incoming {
                let skip = min(prefix, chunk.count)
                prefix -= skip
                try frames.append(Array(chunk.dropFirst(skip)))
                while let frame = try frames.next() { try gateway.write(try Frame.encode(frame)) }
            }
        } catch {}
        gateway.close()
        await back.value
    }
}
