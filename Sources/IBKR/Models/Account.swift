import Foundation

public struct Position: Sendable, Equatable {
    public var account: String
    public var contract: Contract
    public var quantity: Decimal
    public var averageCost: Decimal
    /// Set only by the Multi stream (71); empty everywhere else.
    public var modelCode: String

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
public struct PortfolioItem: Sendable, Equatable {
    public var account: String
    public var contract: Contract
    public var quantity: Decimal
    public var marketPrice: Decimal
    public var marketValue: Decimal
    public var averageCost: Decimal
    public var unrealizedPNL: Decimal?
    public var realizedPNL: Decimal?

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

/// Account-level P&L (in 94); each part is nil while IB has not set it.
public struct AccountPnL: Sendable, Equatable {
    public var daily: Decimal?
    public var unrealized: Decimal?
    public var realized: Decimal?

    public init(daily: Decimal? = nil, unrealized: Decimal? = nil, realized: Decimal? = nil) {
        self.daily = daily
        self.unrealized = unrealized
        self.realized = realized
    }
}

/// One row of an account summary; `value` stays IB's string because some tags are text.
public struct AccountValue: Sendable, Equatable {
    public var account: String
    public var tag: String
    public var value: String
    public var currency: String
    /// Set only by the Multi stream (73); empty everywhere else.
    public var modelCode: String

    public init(account: String, tag: String, value: String, currency: String, modelCode: String = "") {
        self.account = account
        self.tag = tag
        self.value = value
        self.currency = currency
        self.modelCode = modelCode
    }
}

public struct PnL: Sendable, Equatable {
    public var position: Decimal
    public var daily: Decimal?
    public var unrealized: Decimal?
    public var realized: Decimal?
    public var value: Decimal?

    public init(
        position: Decimal,
        daily: Decimal? = nil,
        unrealized: Decimal? = nil,
        realized: Decimal? = nil,
        value: Decimal? = nil
    ) {
        self.position = position
        self.daily = daily
        self.unrealized = unrealized
        self.realized = realized
        self.value = value
    }
}
