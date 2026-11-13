import Foundation

/// IB's openOrder message (in 5): an order as IB holds it, with the margin and commission it works out.
public struct OpenOrderMessage: Sendable, Equatable, Encodable {
    /// The order's id on this API; `0` for a manual order.
    public var orderID: Int
    /// The client id the order belongs to.
    public var clientID: Int
    /// IB's permanent id for the order.
    public var permID: Int
    /// The order's contract.
    public var contract: Contract
    /// The order as IB reports it.
    public var order: Order
    /// The order's status.
    public var status: OrderStatus
    /// The margin and commission IB works out for the order.
    public var state: OrderState

    /// A message with these values; `state` defaults to an empty one.
    public init(orderID: Int, clientID: Int, permID: Int, contract: Contract, order: Order, status: OrderStatus,
                state: OrderState = OrderState()) {
        self.orderID = orderID
        self.clientID = clientID
        self.permID = permID
        self.contract = contract
        self.order = order
        self.status = status
        self.state = state
    }
}

/// IB's completedOrder message (in 101): an order that finished, as `reqCompletedOrders` returns it.
/// `orderId` and `clientId` are not on the wire at version 178: the key is `permID`.
public struct CompletedOrderMessage: Sendable, Equatable, Encodable {
    /// IB's permanent id for the order.
    public var permID: Int
    /// The order's contract.
    public var contract: Contract
    /// The order as IB reports it.
    public var order: Order
    /// The order's status.
    public var status: OrderStatus
    /// When the order finished, as IB's text.
    public var completedTime: String
    /// IB's text for how the order finished.
    public var completedStatus: String
    /// Shares or contracts filled.
    public var filledQuantity: Decimal

    /// A message with these values.
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
        o.designatedLocation = try r.string(); o.exemptCode = try r.optionalInt() ?? -1; o.auctionStrategy = try r.int()
        o.startingPrice = try r.optionalDecimal(); o.stockRefPrice = try r.optionalDecimal()
        o.delta = try r.optionalDecimal(); o.stockRangeLower = try r.optionalDecimal()
        o.stockRangeUpper = try r.optionalDecimal(); o.displaySize = try r.int()
        o.blockOrder = try r.bool(); o.sweepToFill = try r.bool(); o.allOrNone = try r.bool()
        o.minQty = try r.optionalInt(); o.ocaType = try r.int()
        o.eTradeOnly = try r.string() == "1" ? true : nil  // 54–56 (decoder.py:948-950)
        o.firmQuoteOnly = try r.string() == "1" ? true : nil
        o.nbboPriceCap = try r.optionalDecimal()
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
        try deltaNeutralContractAndAlgo(&r, &contract, &o)
        o.solicited = try r.bool(); o.whatIf = try r.bool()
        let status = OrderStatus(rawValue: try r.string())
        // unparseable → nil: ib_async keeps margins as strings, IB's format is unconfirmed
        func margin() -> Decimal? { try? r.optionalDecimal() }
        let state = OrderState(
            initMarginBefore: margin(), maintMarginBefore: margin(), equityWithLoanBefore: margin(),
            initMarginChange: margin(), maintMarginChange: margin(), equityWithLoanChange: margin(),
            initMarginAfter: margin(), maintMarginAfter: margin(), equityWithLoanAfter: margin(),
            commission: try r.optionalDecimal(),
            minCommission: try r.optionalDecimal(), maxCommission: try r.optionalDecimal(),
            commissionCurrency: try r.string(), warningText: try r.string())
        o.randomizeSize = try r.bool(); o.randomizePrice = try r.bool()
        try pegBenchThroughConditions(&r, &o)
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
        try tail(&r, &o)
        return OpenOrderMessage(orderID: orderID, clientID: clientID, permID: permID, contract: contract, order: o,
                                status: status, state: state)
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
        o.designatedLocation = try r.string(); o.exemptCode = try r.optionalInt() ?? -1
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
        try deltaNeutralContractAndAlgo(&r, &contract, &o)
        o.solicited = try r.bool()
        let status = OrderStatus(rawValue: try r.string())
        o.randomizeSize = try r.bool(); o.randomizePrice = try r.bool()
        try pegBenchThroughConditions(&r, &o)
        o.trailStopPrice = try r.optionalDecimal()  // again (56): this one wins, as in ib_async
        o.limitPriceOffset = try r.optionalDecimal(); o.cashQty = try r.optionalDecimal()
        o.dontUseAutoPriceForHedge = try r.bool(); o.isOmsContainer = try r.bool()
        o.autoCancelDate = try r.string()
        let filledQuantity = try r.decimal()
        o.refFuturesConID = try r.optionalInt(); o.autoCancelParent = try r.bool(); o.shareholder = try r.string()
        o.imbalanceOnly = try r.bool(); o.routeMarketableToBbo = try r.bool(); o.parentPermID = try r.optionalInt()
        let completedTime = try r.string(), completedStatus = try r.string()
        try tail(&r, &o)
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

    /// A repeat count; bounded by the fields left so a corrupt count fails fast.
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
            return ComboLeg(conID: conID, ratio: ratio, action: action, exchange: try r.string(),
                            openClose: try r.int(), shortSaleSlot: try r.int(), designatedLocation: try r.string(),
                            exemptCode: try r.optionalInt() ?? -1)
        }
        o.orderComboLegs = try (0..<count(&r)).map { _ in OrderComboLeg(price: try r.optionalDecimal()) }
        o.smartComboRoutingParams = try (0..<count(&r)).map { _ in
            TagValue(tag: try r.string(), value: try r.string())
        }
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

    /// The delta-neutral contract, then algoStrategy and its params.
    private static func deltaNeutralContractAndAlgo(_ r: inout FieldReader, _ c: inout Contract,
                                                    _ o: inout Order) throws {
        if try r.bool() {
            c.deltaNeutralContract = DeltaNeutralContract(conID: try r.int(), delta: try r.decimal(),
                                                          price: try r.decimal())
        }
        o.algoStrategy = try r.string()
        if !o.algoStrategy.isEmpty {
            o.algoParams = try (0..<count(&r)).map { _ in TagValue(tag: try r.string(), value: try r.string()) }
        }
    }

    /// PEG BENCH fields, conditions and their two flags.
    private static func pegBenchThroughConditions(_ r: inout FieldReader, _ o: inout Order) throws {
        if o.orderType == "PEG BENCH" || o.orderType == "PEGBENCH" {
            o.referenceContractID = try r.int(); o.isPeggedChangeAmountDecrease = try r.bool()
            o.peggedChangeAmount = try r.decimal(); o.referenceChangeAmount = try r.decimal()
            o.referenceExchangeID = try r.string()
        }
        o.conditions = try (0..<count(&r)).map { _ in try condition(&r) }
        if !o.conditions.isEmpty { o.conditionsIgnoreRTH = try r.bool(); o.conditionsCancelOrder = try r.bool() }
    }

    /// One condition element; an unknown type or conjunction throws.
    private static func condition(_ r: inout FieldReader) throws -> OrderCondition {
        let typeAt = r.index
        let type = try r.int()
        let at = r.index
        let j = try r.string()
        guard let conjunction = OrderCondition.Conjunction(rawValue: j) else {
            throw IBProtocolError.unexpectedValue(j, index: at)
        }
        switch type {
        case 1:
            let isMore = try r.bool(), price = try r.decimal(), conID = try r.int(), exchange = try r.string()
            return .price(conID: conID, exchange: exchange, isMore: isMore, price: price, triggerMethod: try r.int(),
                          conjunction: conjunction)
        case 3: return .time(isMore: try r.bool(), time: try r.string(), conjunction: conjunction)
        case 4: return .margin(isMore: try r.bool(), percent: try r.int(), conjunction: conjunction)
        case 5:
            return .execution(secType: try r.string(), exchange: try r.string(), symbol: try r.string(),
                              conjunction: conjunction)
        case 6:
            let isMore = try r.bool(), volume = try r.int()
            return .volume(conID: try r.int(), exchange: try r.string(), isMore: isMore, volume: volume,
                           conjunction: conjunction)
        case 7:
            let isMore = try r.bool(), changePercent = try r.decimal()
            return .percentChange(conID: try r.int(), exchange: try r.string(), isMore: isMore,
                                  changePercent: changePercent, conjunction: conjunction)
        default: throw IBProtocolError.unexpectedValue(String(type), index: typeAt)
        }
    }

    /// minTradeQty, minCompeteSize, competeAgainstBestOffset (`Infinite` is `upToMid`), midOffsetAtWhole,
    /// midOffsetAtHalf.
    private static func tail(_ r: inout FieldReader, _ o: inout Order) throws {
        o.minTradeQty = try r.optionalInt(); o.minCompeteSize = try r.optionalInt()
        let at = r.index
        if try r.string() == "Infinite" {
            o.competeAgainstBestOffset = .upToMid
        } else {
            r.index = at
            o.competeAgainstBestOffset = try r.optionalDecimal().map(CompeteOffset.offset)
        }
        o.midOffsetAtWhole = try r.optionalDecimal(); o.midOffsetAtHalf = try r.optionalDecimal()
    }
}
