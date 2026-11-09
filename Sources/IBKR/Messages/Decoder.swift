import Foundation

public enum Decoder {
    /// Never throws. A non-numeric message id is `.malformed` with id 0.
    public static func decode(_ body: [UInt8]) -> IBMessage {
        var r = FieldReader(body)
        let fields = r.fields
        guard let first = fields.first, let id = Int(first) else {
            return .malformed(id: 0, fields: fields, reason: "message id is not a number")
        }
        r.index = 1
        do {
            switch id {
            case 3: return .orderStatus(try orderStatus(&r))
            case 4:
                try r.skip()
                return .error(IBErrorMessage(requestID: try r.int(), code: try r.int(), text: try r.string(),
                                             advancedOrderRejectJSON: try r.string()))
            case 5: return .openOrder(try openOrder(&r))
            case 9: try r.skip(); return .nextValidID(try r.int())
            case 11: return try execDetails(&r)
            case 15:
                try r.skip()
                return .managedAccounts(try r.string().split(separator: ",").map(String.init))
            case 49: try r.skip(); return .currentTime(try r.int())
            case 53: return .openOrderEnd
            case 55: try r.skip(); return .execDetailsEnd(requestID: try r.int())
            case 59:
                try r.skip()
                return .commissionReport(CommissionReport(
                    execID: try r.string(), commission: try r.decimal(), currency: try r.string(),
                    realizedPNL: try r.optionalDecimal(), yield: try r.optionalDecimal(),
                    yieldRedemptionDate: try r.optionalInt()))
            case 100: return .orderBound(permID: try r.int(), clientID: try r.int(), orderID: try r.int())
            case 101: return .completedOrder(try completedOrder(&r))
            case 102: return .completedOrdersEnd
            default: return .unknown(id: id, fields: fields)
            }
        } catch {
            return .malformed(id: id, fields: fields, reason: "\(error)")
        }
    }

    private static func orderStatus(_ r: inout FieldReader) throws -> OrderStatusMessage {
        OrderStatusMessage(
            orderID: try r.int(), status: OrderStatus(rawValue: try r.string()), filled: try r.decimal(),
            remaining: try r.decimal(), averageFillPrice: try r.optionalDecimal(), permID: try r.int(),
            parentID: try r.int(), lastFillPrice: try r.optionalDecimal(), clientID: try r.int(),
            whyHeld: try r.string(), marketCapPrice: try r.optionalDecimal())
    }

    private static func execDetails(_ r: inout FieldReader) throws -> IBMessage {
        let requestID = try r.int()
        let orderID = try r.int()
        let c = try contract(&r)
        let execID = try r.string(), time = try r.string(), account = try r.string(), exchange = try r.string()
        let side = try r.string(), shares = try r.decimal(), price = try r.decimal()
        let permID = try r.int(), clientID = try r.int(), liquidation = try r.int()
        let cumQty = try r.decimal(), avgPrice = try r.decimal(), orderRef = try r.string()
        try r.skip(3)  // evRule, evMultiplier, modelCode
        let lastLiquidity = try r.int(), pending = try r.bool()
        return .execDetails(requestID: requestID, contract: c, execution: Execution(
            execID: execID, time: time, account: account, exchange: exchange, side: side, shares: shares,
            price: price, permID: permID, clientID: clientID, orderID: orderID, liquidation: liquidation,
            cumulativeQuantity: cumQty, averagePrice: avgPrice, orderRef: orderRef,
            lastLiquidity: lastLiquidity, pendingPriceRevision: pending))
    }
}
