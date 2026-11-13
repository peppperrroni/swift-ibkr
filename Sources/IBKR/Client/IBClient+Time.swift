import Foundation

extension IBClient {
    /// `ib_async`'s `util.timeRange`: yields `start`, `start + step`, ... up to `end`, each when it is reached. Points
    /// already past are skipped. Stopping the consumer ends it; a `step` of zero or less gives an empty stream.
    public nonisolated static func timeRange(from start: Date, to end: Date, every step: Duration) -> AsyncStream<Date> {
        let seconds = Double(step.components.seconds) + Double(step.components.attoseconds) / 1e18
        return AsyncStream { continuation in
            guard seconds > 0 else { return continuation.finish() }
            let task = Task {
                var k = max(0, (Date().timeIntervalSince(start) / seconds).rounded(.up))   // the first point not past
                while case let t = start.addingTimeInterval(k * seconds), t <= end {
                    do { try await wait(until: t) } catch { break }
                    continuation.yield(t)
                    k += 1
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// `ib_async`'s `util.waitUntil`: returns once `date` has been reached (at once when it is past); throws
    /// `CancellationError` when the task is cancelled.
    public nonisolated static func wait(until date: Date) async throws {
        while case let remaining = date.timeIntervalSinceNow, remaining > 0 {
            try await Task.sleep(for: .seconds(remaining))
        }
    }
}
