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
