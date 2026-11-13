import Foundation

/// One execution (execDetails, in 11); `ib_async`'s `Execution`.
public struct Execution: Sendable, Equatable, Encodable {
    /// IB's execution id; a correction reuses it up to the last `.`-segment.
    public var execID: String
    /// IB's raw text, in two formats that a consumer parses (see KNOWN-GAPS).
    public var time: String
    /// The account id that traded.
    public var account: String
    /// The exchange that executed it (the contract's `exchange` is a separate field).
    public var exchange: String
    /// `BOT` or `SLD`.
    public var side: String  // BOT / SLD
    /// The quantity of this execution.
    public var shares: Decimal
    /// The price of this execution.
    public var price: Decimal
    /// IB's permanent order id.
    public var permID: Int
    /// The client id that placed the order.
    public var clientID: Int
    /// The order id, in the placing client's numbering.
    public var orderID: Int
    /// execDetails' `liquidation` field, passed through.
    public var liquidation: Int
    /// execDetails' `cumQty`: the order's cumulative filled quantity.
    public var cumulativeQuantity: Decimal
    /// execDetails' `avgPrice`: the order's average fill price.
    public var averagePrice: Decimal
    /// The order's `orderRef` text; empty for none.
    public var orderRef: String
    /// execDetails' `lastLiquidity` field, passed through.
    public var lastLiquidity: Int
    /// execDetails' `pendingPriceRevision` flag.
    public var pendingPriceRevision: Bool
    /// IB's EV rule text, with `evMultiplier`; empty when none.
    public var evRule: String
    /// IB's EV multiplier; `nil` when none.
    public var evMultiplier: Decimal?
    /// The order's model code; empty when none.
    public var modelCode: String

    /// Creates an execution with every field given.
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
        pendingPriceRevision: Bool,
        evRule: String = "",
        evMultiplier: Decimal? = nil,
        modelCode: String = ""
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
        self.evRule = evRule
        self.evMultiplier = evMultiplier
        self.modelCode = modelCode
    }
}

/// The commission of one execution (commissionReport, in 59); `ib_async`'s `CommissionReport`.
public struct CommissionReport: Sendable, Equatable, Encodable {
    /// The execution it belongs to.
    public var execID: String
    /// The commission charged, in `currency`.
    public var commission: Decimal
    /// The currency of `commission`.
    public var currency: String
    /// `nil` when IB sent its unset value.
    public var realizedPNL: Decimal?
    /// commissionReport's `yield`; `nil` when IB sent its unset value.
    public var yield: Decimal?
    /// commissionReport's `yieldRedemptionDate`; `nil` when IB sent an empty field or its unset value.
    public var yieldRedemptionDate: Int?

    /// Creates a commission report with every field given.
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
