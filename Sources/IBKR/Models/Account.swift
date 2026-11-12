import Foundation

public struct Position: Sendable, Equatable {
    public var account: String
    public var contract: Contract
    public var quantity: Decimal
    public var averageCost: Decimal

    public init(account: String, contract: Contract, quantity: Decimal, averageCost: Decimal) {
        self.account = account
        self.contract = contract
        self.quantity = quantity
        self.averageCost = averageCost
    }
}

/// One row of an account summary; `value` stays IB's string because some tags are text.
public struct AccountValue: Sendable, Equatable {
    public var account: String
    public var tag: String
    public var value: String
    public var currency: String

    public init(account: String, tag: String, value: String, currency: String) {
        self.account = account
        self.tag = tag
        self.value = value
        self.currency = currency
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
