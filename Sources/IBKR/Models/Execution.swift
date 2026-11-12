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

    public init(
        execID: String,
        time: String,
        account: String,
        exchange: String,
        side: String,
        shares: Decimal,
        price: Decimal,
        permID: Int,
        clientID: Int,
        orderID: Int,
        liquidation: Int,
        cumulativeQuantity: Decimal,
        averagePrice: Decimal,
        orderRef: String,
        lastLiquidity: Int,
        pendingPriceRevision: Bool
    ) {
        self.execID = execID
        self.time = time
        self.account = account
        self.exchange = exchange
        self.side = side
        self.shares = shares
        self.price = price
        self.permID = permID
        self.clientID = clientID
        self.orderID = orderID
        self.liquidation = liquidation
        self.cumulativeQuantity = cumulativeQuantity
        self.averagePrice = averagePrice
        self.orderRef = orderRef
        self.lastLiquidity = lastLiquidity
        self.pendingPriceRevision = pendingPriceRevision
    }
}

public struct CommissionReport: Sendable, Equatable {
    public var execID: String
    public var commission: Decimal
    public var currency: String
    public var realizedPNL: Decimal?
    public var yield: Decimal?
    public var yieldRedemptionDate: Int?

    public init(
        execID: String,
        commission: Decimal,
        currency: String,
        realizedPNL: Decimal? = nil,
        yield: Decimal? = nil,
        yieldRedemptionDate: Int? = nil
    ) {
        self.execID = execID
        self.commission = commission
        self.currency = currency
        self.realizedPNL = realizedPNL
        self.yield = yield
        self.yieldRedemptionDate = yieldRedemptionDate
    }
}
