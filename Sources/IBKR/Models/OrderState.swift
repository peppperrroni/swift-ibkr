import Foundation

/// The margin and commission IB works out for an order. A what-if answer fills the margins; live openOrders
/// carry `commission` and `commissionCurrency` too (seen on Filled ones). Unset values are `nil`.
public struct OrderState: Sendable, Equatable, Encodable {
    /// The initial margin before the order; `nil` when IB sends `""` or its unset marker.
    public var initMarginBefore: Decimal?
    /// The maintenance margin before the order; `nil` when IB sends `""` or its unset marker.
    public var maintMarginBefore: Decimal?
    /// The equity with loan value before the order; `nil` when IB sends `""` or its unset marker.
    public var equityWithLoanBefore: Decimal?
    /// The change in initial margin the order causes; `nil` when IB sends `""` or its unset marker.
    public var initMarginChange: Decimal?
    /// The change in maintenance margin the order causes; `nil` when IB sends `""` or its unset marker.
    public var maintMarginChange: Decimal?
    /// The change in equity with loan value the order causes; `nil` when IB sends `""` or its unset marker.
    public var equityWithLoanChange: Decimal?
    /// The initial margin after the order; `nil` when IB sends `""` or its unset marker.
    public var initMarginAfter: Decimal?
    /// The maintenance margin after the order; `nil` when IB sends `""` or its unset marker.
    public var maintMarginAfter: Decimal?
    /// The equity with loan value after the order; `nil` when IB sends `""` or its unset marker.
    public var equityWithLoanAfter: Decimal?
    /// The commission IB charges or would charge; `nil` when IB sends `""` or its unset marker.
    public var commission: Decimal?
    /// The smallest commission IB would charge; `nil` when IB sends `""` or its unset marker.
    public var minCommission: Decimal?
    /// The largest commission IB would charge; `nil` when IB sends `""` or its unset marker.
    public var maxCommission: Decimal?
    /// The currency of the commissions; empty when IB sends none.
    public var commissionCurrency: String
    /// IB's warning about the order; empty when there is none.
    public var warningText: String

    /// A state with these values; every margin and commission defaults to `nil`.
    public init(
        initMarginBefore: Decimal? = nil,
        maintMarginBefore: Decimal? = nil,
        equityWithLoanBefore: Decimal? = nil,
        initMarginChange: Decimal? = nil,
        maintMarginChange: Decimal? = nil,
        equityWithLoanChange: Decimal? = nil,
        initMarginAfter: Decimal? = nil,
        maintMarginAfter: Decimal? = nil,
        equityWithLoanAfter: Decimal? = nil,
        commission: Decimal? = nil,
        minCommission: Decimal? = nil,
        maxCommission: Decimal? = nil,
        commissionCurrency: String = "",
        warningText: String = ""
    ) {
        self.initMarginBefore = initMarginBefore
        self.maintMarginBefore = maintMarginBefore
        self.equityWithLoanBefore = equityWithLoanBefore
        self.initMarginChange = initMarginChange
        self.maintMarginChange = maintMarginChange
        self.equityWithLoanChange = equityWithLoanChange
        self.initMarginAfter = initMarginAfter
        self.maintMarginAfter = maintMarginAfter
        self.equityWithLoanAfter = equityWithLoanAfter
        self.commission = commission
        self.minCommission = minCommission
        self.maxCommission = maxCommission
        self.commissionCurrency = commissionCurrency
        self.warningText = warningText
    }

    /// The twelve margins and commissions by field name, in declaration order.
    private static var numbers: [(name: String, path: WritableKeyPath<OrderState, Decimal?>)] {
        [("initMarginBefore", \.initMarginBefore), ("maintMarginBefore", \.maintMarginBefore),
         ("equityWithLoanBefore", \.equityWithLoanBefore), ("initMarginChange", \.initMarginChange),
         ("maintMarginChange", \.maintMarginChange), ("equityWithLoanChange", \.equityWithLoanChange),
         ("initMarginAfter", \.initMarginAfter), ("maintMarginAfter", \.maintMarginAfter),
         ("equityWithLoanAfter", \.equityWithLoanAfter), ("commission", \.commission),
         ("minCommission", \.minCommission), ("maxCommission", \.maxCommission)]
    }

    /// `ib_async`'s `transform`: this state with `transform` applied to each of the twelve margins and commissions
    /// that is set; `nil` stays `nil`, and the currency and warning text are kept.
    public func map(_ transform: (Decimal) -> Decimal) -> OrderState {
        var s = self
        for n in Self.numbers { s[keyPath: n.path] = s[keyPath: n.path].map(transform) }
        return s
    }

    /// `ib_async`'s `formatted`: the twelve margins and commissions keyed by field name (`"initMarginChange"` …),
    /// rounded half-even to `digits` decimals and grouped by thousands (`"300,000.21"`), the same on every platform;
    /// `""` for an unset one. A negative `digits` counts as 0.
    public func formatted(digits: Int = 2) -> [String: String] {
        Dictionary(uniqueKeysWithValues: Self.numbers.map { n in
            (n.name, self[keyPath: n.path].map { Self.grouped($0, digits: max(digits, 0)) } ?? "")
        })
    }

    /// Groups by hand: ICU's en_US_POSIX pattern has no grouping, and Decimal's description is locale-free.
    private static func grouped(_ value: Decimal, digits: Int) -> String {
        var value = value, rounded = Decimal()
        NSDecimalRound(&rounded, &value, digits, .bankers)   // Python's format rounds half-even
        let parts = "\(abs(rounded))".split(separator: ".", omittingEmptySubsequences: false)
        var whole = "", count = 0
        for c in parts[0].reversed() {
            if count > 0, count % 3 == 0 { whole.insert(",", at: whole.startIndex) }
            whole.insert(c, at: whole.startIndex)
            count += 1
        }
        let fraction = (parts.count > 1 ? String(parts[1]) : "").padding(toLength: digits, withPad: "0", startingAt: 0)
        return (rounded < 0 ? "-" : "") + whole + (digits > 0 ? "." + fraction : "")
    }
}
