import Foundation

public struct Execution: Sendable, Equatable {
    public var execID: String
    public var time: String
    public var account: String
    public var exchange: String
    public var side: String  // BOT / SLD
    public var shares: Decimal
    public var price: Decimal
    public var permID: Int
    public var clientID: Int
    public var orderID: Int
    public var liquidation: Int
    public var cumulativeQuantity: Decimal
    public var averagePrice: Decimal
    public var orderRef: String
    public var lastLiquidity: Int
    public var pendingPriceRevision: Bool
}

public struct CommissionReport: Sendable, Equatable {
    public var execID: String
    public var commission: Decimal
    public var currency: String
    public var realizedPNL: Decimal?
    public var yield: Decimal?
    public var yieldRedemptionDate: Int?
}
