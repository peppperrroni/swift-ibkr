import Foundation

/// The margin and commission IB works out for an order; filled only on a what-if answer, else all `nil`.
public struct OrderState: Sendable, Equatable {
    public var initMarginBefore: Decimal?
    public var maintMarginBefore: Decimal?
    public var equityWithLoanBefore: Decimal?
    public var initMarginChange: Decimal?
    public var maintMarginChange: Decimal?
    public var equityWithLoanChange: Decimal?
    public var initMarginAfter: Decimal?
    public var maintMarginAfter: Decimal?
    public var equityWithLoanAfter: Decimal?
    public var commission: Decimal?
    public var minCommission: Decimal?
    public var maxCommission: Decimal?
    public var commissionCurrency: String
    public var warningText: String

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
