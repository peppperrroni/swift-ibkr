import Foundation

func body(_ fields: String...) -> [UInt8] { fields.flatMap { Array($0.utf8) + [0] } }

func d(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }

struct TimedOut: Error {}

/// Runs `operation`, failing with `TimedOut` after 2 s instead of hanging.
func within2s<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask { try await Task.sleep(for: .seconds(2)); throw TimedOut() }
        defer { group.cancelAll() }
        return try await group.next()!
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
