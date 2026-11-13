import Foundation

/// One held position (position, in 61; positionMulti, in 71).
public struct Position: Sendable, Equatable, Encodable {
    /// The account id that holds it.
    public var account: String
    /// The instrument held.
    public var contract: Contract
    /// Shares or contracts held; negative for a short position.
    public var quantity: Decimal
    /// IB's average cost per unit, the multiplier included as IB sends it.
    public var averageCost: Decimal
    /// Set only by the Multi stream (71); empty everywhere else.
    public var modelCode: String

    /// Creates a position with every field given.
    public init(account: String, contract: Contract, quantity: Decimal, averageCost: Decimal, modelCode: String = "") {
        self.account = account
        self.contract = contract
        self.quantity = quantity
        self.averageCost = averageCost
        self.modelCode = modelCode
    }
}

/// One row of the account-updates portfolio (in 7). `contract.primaryExchange` is set and `exchange` is empty,
/// which is how IB lays this message out.
public struct PortfolioItem: Sendable, Equatable, Encodable {
    /// The account id that holds the position.
    public var account: String
    /// The instrument held.
    public var contract: Contract
    /// Shares or contracts held (updatePortfolio's `position`); negative for a short position.
    public var quantity: Decimal
    /// IB's current price of one unit.
    public var marketPrice: Decimal
    /// The position's market value as IB reports it.
    public var marketValue: Decimal
    /// IB's average cost per unit, the multiplier included as IB sends it.
    public var averageCost: Decimal
    /// `nil` when IB sent its unset value.
    public var unrealizedPNL: Decimal?
    /// `nil` when IB sent its unset value.
    public var realizedPNL: Decimal?

    /// Creates a portfolio row with every field given.
    public init(
        account: String, contract: Contract, quantity: Decimal, marketPrice: Decimal, marketValue: Decimal,
        averageCost: Decimal, unrealizedPNL: Decimal? = nil, realizedPNL: Decimal? = nil
    ) {
        self.account = account
        self.contract = contract
        self.quantity = quantity
        self.marketPrice = marketPrice
        self.marketValue = marketValue
        self.averageCost = averageCost
        self.unrealizedPNL = unrealizedPNL
        self.realizedPNL = realizedPNL
    }
}

/// Account-level P&L (in 94); each part is nil while IB has not set it. `account` and `modelCode` are the
/// subscription's, set by the `pnl` stream (`ib_async`'s `PnL`); a decoded message leaves them empty.
public struct AccountPnL: Sendable, Equatable, Encodable {
    /// The day's P&L (pnl's `dailyPnL`); `nil` while IB has not set it.
    public var daily: Decimal?
    /// Unrealized P&L (pnl's `unrealizedPnL`); `nil` while IB has not set it.
    public var unrealized: Decimal?
    /// Realized P&L (pnl's `realizedPnL`); `nil` while IB has not set it.
    public var realized: Decimal?
    /// The account the `pnl` subscription asked for; empty in a decoded message.
    public var account: String
    /// The model code the `pnl` subscription asked for; empty when none.
    public var modelCode: String

    /// Creates a P&L with every field given.
    public init(daily: Decimal? = nil, unrealized: Decimal? = nil, realized: Decimal? = nil, account: String = "",
                modelCode: String = "") {
        self.daily = daily
        self.unrealized = unrealized
        self.realized = realized
        self.account = account
        self.modelCode = modelCode
    }
}

/// One row of an account summary; `value` stays IB's string because some tags are text.
public struct AccountValue: Sendable, Equatable, Encodable {
    /// The account id the value belongs to.
    public var account: String
    /// IB's key for the value, such as `NetLiquidation`.
    public var tag: String
    /// IB's text, unparsed: some tags are text, not numbers.
    public var value: String
    /// The currency code IB sends with the value.
    public var currency: String
    /// Set only by the Multi stream (73); empty everywhere else.
    public var modelCode: String

    /// Creates a value with every field given.
    public init(account: String, tag: String, value: String, currency: String, modelCode: String = "") {
        self.account = account
        self.tag = tag
        self.value = value
        self.currency = currency
        self.modelCode = modelCode
    }
}

/// One position's P&L (pnlSingle, in 95). `account`, `modelCode` and `conID` are the subscription's, set by the
/// `pnlSingle` stream (`ib_async`'s `PnLSingle`); a decoded message leaves them empty and 0.
public struct PnL: Sendable, Equatable, Encodable {
    /// pnlSingle's `pos`: shares or contracts held; negative for a short position.
    public var position: Decimal
    /// pnlSingle's `dailyPnL`; `nil` when IB sent its unset value.
    public var daily: Decimal?
    /// pnlSingle's `unrealizedPnL`; `nil` when IB sent its unset value.
    public var unrealized: Decimal?
    /// pnlSingle's `realizedPnL`; `nil` when IB sent its unset value.
    public var realized: Decimal?
    /// pnlSingle's `value`; `nil` when IB sent its unset value.
    public var value: Decimal?
    /// The account the `pnlSingle` subscription asked for; empty in a decoded message.
    public var account: String
    /// The model code the `pnlSingle` subscription asked for; empty when none.
    public var modelCode: String
    /// The position's contract id the `pnlSingle` subscription asked for; 0 in a decoded message.
    public var conID: Int

    /// Creates a P&L with every field given.
    public init(
        position: Decimal,
        daily: Decimal? = nil,
        unrealized: Decimal? = nil,
        realized: Decimal? = nil,
        value: Decimal? = nil,
        account: String = "",
        modelCode: String = "",
        conID: Int = 0
    ) {
        self.position = position
        self.daily = daily
        self.unrealized = unrealized
        self.realized = realized
        self.value = value
        self.account = account
        self.modelCode = modelCode
        self.conID = conID
    }
}
