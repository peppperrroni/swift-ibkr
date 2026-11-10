import Foundation

public struct Position: Sendable, Equatable {
    public var account: String
    public var contract: Contract
    public var quantity: Decimal
    public var averageCost: Decimal
}

/// One row of an account summary; `value` stays IB's string because some tags are text.
public struct AccountValue: Sendable, Equatable {
    public var account: String
    public var tag: String
    public var value: String
    public var currency: String
}

public struct PnL: Sendable, Equatable {
    public var position: Decimal
    public var daily: Decimal?
    public var unrealized: Decimal?
    public var realized: Decimal?
    public var value: Decimal?
}
