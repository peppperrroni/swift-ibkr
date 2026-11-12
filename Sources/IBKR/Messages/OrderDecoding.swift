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
        let contract = try self.contract(&r)
        var o = try orderHead(&r)
        let clientID = try r.int(), permID = try r.int()
        o.outsideRTH = try r.bool()
        try r.skip(26)  // 27–52 hidden … minQty
        o.ocaType = try r.int()
        try r.skip(3)  // 54–56 eTradeOnly, firmQuoteOnly, nbboPriceCap
        o.parentID = try r.int()
        try r.skip(3)  // 58–60 triggerMethod, volatility, volatilityType
        try skipDeltaNeutral(&r, extraFields: 8)
        try r.skip(6)  // 63–68 continuousUpdate … basisPointsType
        try skipComboThroughHedge(&r)
        try r.skip(4)  // 77–80 optOutSmartRouting, clearingAccount, clearingIntent, notHeld
        try skipDeltaNeutralContractAndAlgo(&r)
        try r.skip(2)  // 83–84 solicited, whatIf
        let status = OrderStatus(rawValue: try r.string())
        try r.skip(14)  // 86–99 margins, commissions, warningText
        try skipRandomizeThroughConditions(&r, orderType: o.orderType)
        try r.skip(24)  // 103–126 adjustedOrderType … midOffsetAtHalf
        return OpenOrderMessage(orderID: orderID, clientID: clientID, permID: permID, contract: contract, order: o,
                                status: status)
    }

    static func completedOrder(_ r: inout FieldReader) throws -> CompletedOrderMessage {
        let contract = try self.contract(&r)
        var o = try orderHead(&r)
        let permID = try r.int()
        o.outsideRTH = try r.bool()
        try r.skip(23)  // 25–47 hidden … minQty
        o.ocaType = try r.int()
        try r.skip(3)  // 49–51 triggerMethod, volatility, volatilityType
        try skipDeltaNeutral(&r, extraFields: 4)
        try r.skip(4)  // 54–57 continuousUpdate … trailingPercent
        try skipComboThroughHedge(&r)
        try r.skip(3)  // 66–68 clearingAccount, clearingIntent, notHeld
        try skipDeltaNeutralContractAndAlgo(&r)
        try r.skip()  // 71 solicited
        let status = OrderStatus(rawValue: try r.string())
        try skipRandomizeThroughConditions(&r, orderType: o.orderType)
        try r.skip(6)  // 76-81 trailStopPrice ... autoCancelDate
        let filledQuantity = try r.decimal()
        try r.skip(6)  // 83-88 refFuturesConId ... parentPermId
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
        try r.skip(2)  // openClose, origin
        o.orderRef = try r.string()
        return o
    }

    /// A repeat count; bounded by the fields left so `skip(n * size)` cannot overflow.
    private static func count(_ r: inout FieldReader) throws -> Int {
        let at = r.index
        let n = try r.int()
        guard n >= 0, n <= r.fields.count else { throw IBProtocolError.badNumber(String(n), index: at) }
        return n
    }

    /// deltaNeutralOrderType, deltaNeutralAuxPrice, then `extraFields` more when the type is set.
    private static func skipDeltaNeutral(_ r: inout FieldReader, extraFields: Int) throws {
        let type = try r.string()
        try r.skip()
        if !type.isEmpty { try r.skip(extraFields) }
    }

    /// comboLegsDescrip through hedgeType (+ hedgeParam): combo legs, their prices, smart routing params, scale.
    private static func skipComboThroughHedge(_ r: inout FieldReader) throws {
        try r.skip()  // comboLegsDescrip
        try r.skip(8 * count(&r))  // legs
        try r.skip(count(&r))  // order combo-leg prices
        try r.skip(2 * count(&r))  // smart combo routing tag/value pairs
        try r.skip(2)  // scaleInitLevelSize, scaleSubsLevelSize
        if let increment = try r.optionalDouble(), increment > 0 { try r.skip(7) }
        if try !r.string().isEmpty { try r.skip() }  // hedgeType set → hedgeParam
    }

    private static func skipDeltaNeutralContractAndAlgo(_ r: inout FieldReader) throws {
        if try r.bool() { try r.skip(3) }  // conId, delta, price
        if try !r.string().isEmpty { try r.skip(2 * count(&r)) }  // algoStrategy set → tag/value pairs
    }

    /// randomizeSize, randomizePrice, PEG BENCH fields, conditions and their two flags.
    private static func skipRandomizeThroughConditions(_ r: inout FieldReader, orderType: String) throws {
        try r.skip(2)
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
