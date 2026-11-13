import Foundation

/// What `AccountTracker.apply` publishes: the whole visible portfolio, or one changed account value.
enum AccountChange: Equatable {
    case portfolio([PortfolioItem])
    case value(AccountValue)
}

/// Holds the portfolio (keyed by account, conID) and the account values (keyed by account, model, tag,
/// currency). Pure value, no I/O. After `reload()` the new portfolio is collected aside and replaces the
/// visible one whole at `accountDownloadEnd`, like `PositionTracker`. The caller filters Multi updates by reqId.
struct AccountTracker: Sendable {
    private struct ItemKey: Hashable { var account: String; var conID: Int }
    private struct ValueKey: Hashable { var account: String; var model: String; var tag: String; var currency: String }

    private var items: [ItemKey: PortfolioItem] = [:]
    private var pending: [ItemKey: PortfolioItem] = [:]
    private var valueSet: [ValueKey: AccountValue] = [:]
    private var reloading = false

    init() {}

    /// Sorted by account, then conID.
    var portfolio: [PortfolioItem] { Self.sorted(items) }

    /// Sorted by account, modelCode, tag, currency.
    var values: [AccountValue] {
        valueSet.sorted {
            ($0.key.account, $0.key.model, $0.key.tag, $0.key.currency)
                < ($1.key.account, $1.key.model, $1.key.tag, $1.key.currency)
        }.map(\.value)
    }

    mutating func reload() {
        reloading = true
        pending = [:]
    }

    /// Drops the values of accounts not in `accounts` and, when there are several, the portfolio of every account but
    /// `keeping` (the one the sync subscribes with reqAccountUpdates, whose set the next `accountDownloadEnd` replaces
    /// whole). Returns true when that changed the visible portfolio.
    mutating func prune(to accounts: [String], keeping: String? = nil) -> Bool {
        valueSet = valueSet.filter { accounts.contains($0.key.account) }
        guard accounts.count > 1 else { return false }
        (reloading, pending) = (false, [:])
        let before = items.count
        items = items.filter { $0.key.account == keeping }
        return items.count != before
    }

    mutating func apply(_ message: IBMessage) -> AccountChange? {
        switch message {
        case .accountValue(let v), .accountUpdateMulti(_, let v):
            let key = ValueKey(account: v.account, model: v.modelCode, tag: v.tag, currency: v.currency)
            guard valueSet[key] != v else { return nil }
            valueSet[key] = v
            return .value(v)
        case .portfolioItem(let p):
            let key = ItemKey(account: p.account, conID: p.contract.conID)
            let next: PortfolioItem? = p.quantity == 0 ? nil : p
            if reloading {
                pending[key] = next
                return nil
            }
            guard items[key] != next else { return nil }
            items[key] = next
            return .portfolio(portfolio)
        case .accountDownloadEnd:
            guard reloading else { return nil }
            reloading = false
            items = pending
            pending = [:]
            return .portfolio(portfolio)
        default:
            return nil
        }
    }

    private static func sorted(_ set: [ItemKey: PortfolioItem]) -> [PortfolioItem] {
        set.sorted { ($0.key.account, $0.key.conID) < ($1.key.account, $1.key.conID) }.map(\.value)
    }
}
