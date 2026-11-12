import Foundation

/// The margin and commission IB works out for an order. A what-if answer fills the margins; live openOrders
/// carry `commission` and `commissionCurrency` too (seen on Filled ones). Unset values are `nil`.
public struct OrderState: Sendable, Equatable {
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
}
