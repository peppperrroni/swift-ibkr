import Foundation

func body(_ fields: String...) -> [UInt8] { fields.flatMap { Array($0.utf8) + [0] } }

func d(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }

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
