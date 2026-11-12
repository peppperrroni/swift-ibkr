import Foundation

public struct OpenOrderMessage: Sendable, Equatable {
    public var orderID: Int
    public var clientID: Int
    public var permID: Int
    public var contract: Contract
    public var order: Order
    public var status: OrderStatus

    public init(orderID: Int, clientID: Int, permID: Int, contract: Contract, order: Order, status: OrderStatus) {
        self.orderID = orderID
        self.clientID = clientID
        self.permID = permID
        self.contract = contract
        self.order = order
        self.status = status
    }
}

/// `orderId` and `clientId` are not on the wire at version 178: the key is `permID`.
public struct CompletedOrderMessage: Sendable, Equatable {
    public var permID: Int
    public var contract: Contract
    public var order: Order
    public var status: OrderStatus
    public var completedTime: String
    public var completedStatus: String
    public var filledQuantity: Decimal

    public init(
        permID: Int,
        contract: Contract,
        order: Order,
        status: OrderStatus,
        completedTime: String,
        completedStatus: String,
        filledQuantity: Decimal
    ) {
        self.permID = permID
        self.contract = contract
        self.order = order
        self.status = status
        self.completedTime = completedTime
        self.completedStatus = completedStatus
        self.filledQuantity = filledQuantity
    }
}

/// Field order: docs/protocol-178.md, `openOrder (in 5)` and `completedOrder (in 101)`. Comments give
/// the base-case indices of the fields skipped.
extension IBDecoder {
    static func openOrder(_ r: inout FieldReader) throws -> OpenOrderMessage {
        let orderID = try r.int()
        var contract = try self.contract(&r)
        var o = try orderHead(&r)
        let clientID = try r.int(), permID = try r.int()
        o.outsideRTH = try r.bool(); o.hidden = try r.bool(); o.discretionaryAmt = try r.decimal()
        o.goodAfterTime = try r.string()
        try r.skip()  // 30 sharesAllocation
        o.faGroup = try r.string(); o.faMethod = try r.string(); o.faPercentage = try r.string()
        o.modelCode = try r.string(); o.goodTillDate = try r.string(); o.rule80A = try r.string()
        o.percentOffset = try r.optionalDecimal(); o.settlingFirm = try r.string(); o.shortSaleSlot = try r.int()
        o.designatedLocation = try r.string(); o.exemptCode = try r.int(); o.auctionStrategy = try r.int()
        o.startingPrice = try r.optionalDecimal(); o.stockRefPrice = try r.optionalDecimal()
        o.delta = try r.optionalDecimal(); o.stockRangeLower = try r.optionalDecimal()
        o.stockRangeUpper = try r.optionalDecimal(); o.displaySize = try r.int()
        o.blockOrder = try r.bool(); o.sweepToFill = try r.bool(); o.allOrNone = try r.bool()
        o.minQty = try r.optionalInt(); o.ocaType = try r.int()
        try r.skip(3)  // 54–56 eTradeOnly, firmQuoteOnly, nbboPriceCap
        o.parentID = try r.int()
        o.triggerMethod = try r.int(); o.volatility = try r.optionalDecimal(); o.volatilityType = try r.optionalInt()
        try deltaNeutral(&r, &o)
        if !o.deltaNeutralOrderType.isEmpty {
            o.deltaNeutralConID = try r.int(); o.deltaNeutralSettlingFirm = try r.string()
            o.deltaNeutralClearingAccount = try r.string(); o.deltaNeutralClearingIntent = try r.string()
            o.deltaNeutralOpenClose = try r.string(); o.deltaNeutralShortSale = try r.bool()
            o.deltaNeutralShortSaleSlot = try r.int(); o.deltaNeutralDesignatedLocation = try r.string()
        }
        o.continuousUpdate = try r.bool(); o.referencePriceType = try r.optionalInt()
        o.trailStopPrice = try r.optionalDecimal(); o.trailingPercent = try r.optionalDecimal()
        o.basisPoints = try r.optionalDecimal(); o.basisPointsType = try r.optionalInt()
        try comboThroughHedge(&r, &contract, &o)
        o.optOutSmartRouting = try r.bool()
        o.clearingAccount = try r.string(); o.clearingIntent = try r.string(); o.notHeld = try r.bool()
        try deltaNeutralContractAndAlgo(&r, &contract)
        o.solicited = try r.bool(); o.whatIf = try r.bool()
        let status = OrderStatus(rawValue: try r.string())
        try r.skip(14)  // 86–99 margins, commissions, warningText
        o.randomizeSize = try r.bool(); o.randomizePrice = try r.bool()
        try skipPegBenchThroughConditions(&r, orderType: o.orderType)
        o.adjustedOrderType = try r.string(); o.triggerPrice = try r.optionalDecimal()
        o.trailStopPrice = try r.optionalDecimal()  // again (65): this one wins, as in ib_async
        o.limitPriceOffset = try r.optionalDecimal(); o.adjustedStopPrice = try r.optionalDecimal()
        o.adjustedStopLimitPrice = try r.optionalDecimal(); o.adjustedTrailingAmount = try r.optionalDecimal()
        o.adjustableTrailingUnit = try r.int()
        o.softDollarTier = SoftDollarTier(name: try r.string(), value: try r.string(), displayName: try r.string())
        o.cashQty = try r.optionalDecimal()
        o.dontUseAutoPriceForHedge = try r.bool(); o.isOmsContainer = try r.bool()
        o.discretionaryUpToLimitPrice = try r.bool(); o.usePriceMgmtAlgo = try r.bool()
        o.duration = try r.optionalInt(); o.postToAts = try r.optionalInt(); o.autoCancelParent = try r.bool()
        try r.skip(5)  // 122–126 minTradeQty … midOffsetAtHalf
        return OpenOrderMessage(orderID: orderID, clientID: clientID, permID: permID, contract: contract, order: o,
                                status: status)
    }

    static func completedOrder(_ r: inout FieldReader) throws -> CompletedOrderMessage {
        var contract = try self.contract(&r)
        var o = try orderHead(&r)
        let permID = try r.int()
        o.outsideRTH = try r.bool(); o.hidden = try r.bool(); o.discretionaryAmt = try r.decimal()
        o.goodAfterTime = try r.string()
        o.faGroup = try r.string(); o.faMethod = try r.string(); o.faPercentage = try r.string()
        o.modelCode = try r.string(); o.goodTillDate = try r.string(); o.rule80A = try r.string()
        o.percentOffset = try r.optionalDecimal(); o.settlingFirm = try r.string(); o.shortSaleSlot = try r.int()
        o.designatedLocation = try r.string(); o.exemptCode = try r.int()
        o.startingPrice = try r.optionalDecimal(); o.stockRefPrice = try r.optionalDecimal()
        o.delta = try r.optionalDecimal(); o.stockRangeLower = try r.optionalDecimal()
        o.stockRangeUpper = try r.optionalDecimal(); o.displaySize = try r.int()
        o.sweepToFill = try r.bool(); o.allOrNone = try r.bool()
        o.minQty = try r.optionalInt(); o.ocaType = try r.int()
        o.triggerMethod = try r.int(); o.volatility = try r.optionalDecimal(); o.volatilityType = try r.optionalInt()
        try deltaNeutral(&r, &o)
        if !o.deltaNeutralOrderType.isEmpty {
            o.deltaNeutralConID = try r.int(); o.deltaNeutralShortSale = try r.bool()
            o.deltaNeutralShortSaleSlot = try r.int(); o.deltaNeutralDesignatedLocation = try r.string()
        }
        o.continuousUpdate = try r.bool(); o.referencePriceType = try r.optionalInt()
        o.trailStopPrice = try r.optionalDecimal(); o.trailingPercent = try r.optionalDecimal()
        try comboThroughHedge(&r, &contract, &o)
        o.clearingAccount = try r.string(); o.clearingIntent = try r.string(); o.notHeld = try r.bool()
        try deltaNeutralContractAndAlgo(&r, &contract)
        o.solicited = try r.bool()
        let status = OrderStatus(rawValue: try r.string())
        o.randomizeSize = try r.bool(); o.randomizePrice = try r.bool()
        try skipPegBenchThroughConditions(&r, orderType: o.orderType)
        o.trailStopPrice = try r.optionalDecimal()  // again (56): this one wins, as in ib_async
        o.limitPriceOffset = try r.optionalDecimal(); o.cashQty = try r.optionalDecimal()
        o.dontUseAutoPriceForHedge = try r.bool(); o.isOmsContainer = try r.bool()
        o.autoCancelDate = try r.string()
        let filledQuantity = try r.decimal()
        o.refFuturesConID = try r.optionalInt(); o.autoCancelParent = try r.bool(); o.shareholder = try r.string()
        o.imbalanceOnly = try r.bool(); o.routeMarketableToBbo = try r.bool(); o.parentPermID = try r.optionalInt()
        let completedTime = try r.string(), completedStatus = try r.string()
        try r.skip(5)  // 91–95 minTradeQty … midOffsetAtHalf
        return CompletedOrderMessage(permID: permID, contract: contract, order: o, status: status,
                                     completedTime: completedTime, completedStatus: completedStatus,
                                     filledQuantity: filledQuantity)
    }

    /// conId … tradingClass, 11 fields, no primaryExchange (also execDetails' layout).
    static func contract(_ r: inout FieldReader) throws -> Contract {
        var c = Contract(symbol: "")
        c.conID = try r.int(); c.symbol = try r.string(); c.secType = try r.string()
        c.lastTradeDateOrContractMonth = try r.string(); c.strike = try r.optionalDecimal()
        c.right = try r.string(); c.multiplier = try r.string(); c.exchange = try r.string()
        c.currency = try r.string(); c.localSymbol = try r.string(); c.tradingClass = try r.string()
        return c
    }

    /// action … orderRef, 11 fields. `transmit` is not on the wire and keeps the model default.
    private static func orderHead(_ r: inout FieldReader) throws -> Order {
        let at = r.index
        let a = try r.string()
        guard let action = OrderAction(rawValue: a) else { throw IBProtocolError.unexpectedValue(a, index: at) }
        var o = Order(action: action, quantity: try r.decimal(), orderType: try r.string(),
                      limitPrice: try r.optionalDecimal(), auxPrice: try r.optionalDecimal(), tif: try r.string())
        o.ocaGroup = try r.string(); o.account = try r.string()
        o.openClose = try r.string(); o.origin = try r.int(); o.orderRef = try r.string()
        return o
    }

    /// A repeat count; bounded by the fields left so `skip(n * size)` cannot overflow.
    private static func count(_ r: inout FieldReader) throws -> Int {
        let at = r.index
        let n = try r.int()
        guard n >= 0, n <= r.fields.count else { throw IBProtocolError.badNumber(String(n), index: at) }
        return n
    }

    /// deltaNeutralOrderType, deltaNeutralAuxPrice; the caller reads its own group when the type is set.
    private static func deltaNeutral(_ r: inout FieldReader, _ o: inout Order) throws {
        o.deltaNeutralOrderType = try r.string(); o.deltaNeutralAuxPrice = try r.optionalDecimal()
    }

    /// comboLegsDescrip through hedgeType (+ hedgeParam): combo legs, their prices, smart routing params, scale.
    private static func comboThroughHedge(_ r: inout FieldReader, _ c: inout Contract, _ o: inout Order) throws {
        c.comboLegsDescrip = try r.string()
        c.comboLegs = try (0..<count(&r)).map { _ in
            let conID = try r.int(), ratio = try r.int()
            let at = r.index
            let a = try r.string()
            guard let action = OrderAction(rawValue: a) else { throw IBProtocolError.unexpectedValue(a, index: at) }
            return ComboLeg(conID: conID, ratio: ratio, action: action, exchange: try r.string(), openClose: try r.int(),
                            shortSaleSlot: try r.int(), designatedLocation: try r.string(),
                            exemptCode: try r.optionalInt() ?? -1)
        }
        o.orderComboLegs = try (0..<count(&r)).map { _ in OrderComboLeg(price: try r.optionalDecimal()) }
        o.smartComboRoutingParams = try (0..<count(&r)).map { _ in TagValue(tag: try r.string(), value: try r.string()) }
        o.scaleInitLevelSize = try r.optionalInt(); o.scaleSubsLevelSize = try r.optionalInt()
        o.scalePriceIncrement = try r.optionalDecimal()
        if let increment = o.scalePriceIncrement, increment > 0 {
            o.scalePriceAdjustValue = try r.optionalDecimal(); o.scalePriceAdjustInterval = try r.optionalInt()
            o.scaleProfitOffset = try r.optionalDecimal(); o.scaleAutoReset = try r.bool()
            o.scaleInitPosition = try r.optionalInt(); o.scaleInitFillQty = try r.optionalInt()
            o.scaleRandomPercent = try r.bool()
        }
        o.hedgeType = try r.string()
        if !o.hedgeType.isEmpty { o.hedgeParam = try r.string() }
    }

    /// The delta-neutral contract, then algoStrategy; algo params are still skipped.
    private static func deltaNeutralContractAndAlgo(_ r: inout FieldReader, _ c: inout Contract) throws {
        if try r.bool() {
            c.deltaNeutralContract = DeltaNeutralContract(conID: try r.int(), delta: try r.decimal(), price: try r.decimal())
        }
        if try !r.string().isEmpty { try r.skip(2 * count(&r)) }  // algoStrategy set → tag/value pairs
    }

    /// PEG BENCH fields, conditions and their two flags.
    private static func skipPegBenchThroughConditions(_ r: inout FieldReader, orderType: String) throws {
        if orderType == "PEG BENCH" || orderType == "PEGBENCH" { try r.skip(5) }
        let n = try count(&r)
        for _ in 0..<n {
            let at = r.index
            let size = switch try r.int() {
            case 1: 7  // Price
            case 3, 4: 4  // Time, Margin
            case 5: 5  // Execution
            case 6, 7: 6  // Volume, PercentChange
            case let t: throw IBProtocolError.unexpectedValue(String(t), index: at)
            }
            try r.skip(size - 1)
        }
        if n > 0 { try r.skip(2) }  // conditionsIgnoreRth, conditionsCancelOrder
    }
}
