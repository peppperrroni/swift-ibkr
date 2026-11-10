import Foundation

/// Holds the account's positions, keyed by (account, conID). Pure value, no I/O: the owner publishes whatever
/// `apply` returns. After `reload()` the new set is collected aside and replaces the visible one whole at
/// `positionEnd`, so a position closed in the meantime disappears then, without an intermediate set.
public struct PositionTracker: Sendable {
    private struct Key: Hashable { var account: String; var conID: Int }

    private var current: [Key: Position] = [:]
    private var pending: [Key: Position] = [:]
    private var reloading = false

    public init() {}

    /// Sorted by account, then conID.
    public var positions: [Position] { Self.sorted(current) }

    public mutating func reload() {
        reloading = true
        pending = [:]
    }

    /// The new whole set when the visible set changed (or a reload ended), else nil.
    public mutating func apply(_ message: IBMessage) -> [Position]? {
        switch message {
        case .position(let p):
            let key = Key(account: p.account, conID: p.contract.conID)
            if reloading {
                if p.quantity != 0 { pending[key] = p }
                return nil
            }
            let next: Position? = p.quantity == 0 ? nil : p
            guard current[key] != next else { return nil }
            current[key] = next
            return positions
        case .positionEnd:
            guard reloading else { return nil }
            reloading = false
            current = pending
            pending = [:]
            return positions
        default:
            return nil
        }
    }

    private static func sorted(_ set: [Key: Position]) -> [Position] {
        set.sorted { ($0.key.account, $0.key.conID) < ($1.key.account, $1.key.conID) }.map(\.value)
    }
}
