import Foundation

public enum IBDecoder {
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
            case 10: return try contractData(&r)
            case 52: try r.skip(); return .contractDataEnd(requestID: try r.int())
            case 79: return try symbolSamples(&r)
            case 1:
                try r.skip(); let id = try r.int(), f = TickField(rawValue: try r.int())
                let price = try r.optionalDecimal(), size = try r.optionalDecimal()
                try r.skip()  // attribMask
                return .tick(requestID: id, .price(f, price: price, size: size))
            case 2:
                try r.skip(); let id = try r.int(), f = TickField(rawValue: try r.int())
                return .tick(requestID: id, .size(f, try r.optionalDecimal()))
            case 45:
                try r.skip(); let id = try r.int(), f = TickField(rawValue: try r.int())
                return .tick(requestID: id, .generic(f, try r.decimal()))
            case 46:
                try r.skip(); let id = try r.int(), f = TickField(rawValue: try r.int())
                return .tick(requestID: id, .string(f, try r.string()))
            case 58:
                try r.skip(); let id = try r.int(), raw = try r.int()
                guard let t = MarketDataType(rawValue: raw) else { throw IBProtocolError.badNumber(String(raw), index: r.index - 1) }
                return .tick(requestID: id, .dataType(t))
            case 81:
                return .tickRequestParameters(requestID: try r.int(), minTick: try r.optionalDecimal(),
                                              bboExchange: try r.string(), snapshotPermissions: try r.int())
            case 59:
                try r.skip()
                return .commissionReport(CommissionReport(
                    execID: try r.string(), commission: try r.decimal(), currency: try r.string(),
                    realizedPNL: try r.optionalDecimal(), yield: try r.optionalDecimal(),
                    yieldRedemptionDate: try r.optionalInt()))
            case 61:
                try r.skip()
                return .position(Position(account: try r.string(), contract: try contract(&r),
                                          quantity: try r.decimal(), averageCost: try r.decimal()))
            case 62: return .positionEnd
            case 63:
                try r.skip()
                return .accountSummary(requestID: try r.int(), AccountValue(
                    account: try r.string(), tag: try r.string(), value: try r.string(), currency: try r.string()))
            case 64: try r.skip(); return .accountSummaryEnd(requestID: try r.int())
            case 95:
                return .pnlSingle(requestID: try r.int(), PnL(
                    position: try r.decimal(), daily: try r.optionalDecimal(), unrealized: try r.optionalDecimal(),
                    realized: try r.optionalDecimal(), value: try r.optionalDecimal()))
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

    private static func list(_ s: String) -> [String] { s.split(separator: ",").map(String.init) }

    private static func contractData(_ r: inout FieldReader) throws -> IBMessage {
        let requestID = try r.int()
        var c = Contract(symbol: try r.string())
        c.secType = try r.string(); c.lastTradeDateOrContractMonth = try r.string()  // lastTimes, kept whole
        c.strike = try r.optionalDecimal(); c.right = try r.string(); c.exchange = try r.string()
        c.currency = try r.string(); c.localSymbol = try r.string()
        let marketName = try r.string()
        c.tradingClass = try r.string(); c.conID = try r.int()
        let minTick = try r.decimal()
        c.multiplier = try r.string()
        let orderTypes = list(try r.string()), validExchanges = list(try r.string())
        let magnifier = try r.int()
        try r.skip()  // underConId
        let longName = try r.string()
        c.primaryExchange = try r.string()
        try r.skip(3)  // contractMonth, industry, category
        try r.skip()   // subcategory
        let tz = try r.string(), trading = try r.string(), liquid = try r.string()
        try r.skip(2)  // evRule, evMultiplier
        let secIDs = try r.int()
        guard secIDs >= 0, secIDs <= r.fields.count else { throw IBProtocolError.badNumber(String(secIDs), index: r.index - 1) }
        try r.skip(secIDs * 2 + 1)  // secIdList, aggGroup
        try r.skip(4)  // underSymbol, underSecType, marketRuleIds, realExpirationDate
        let stockType = try r.string()
        let details = ContractDetails(
            contract: c, marketName: marketName, minTick: minTick, priceMagnifier: magnifier, longName: longName,
            stockType: stockType, orderTypes: orderTypes, validExchanges: validExchanges, timeZoneID: tz,
            tradingHours: trading, liquidHours: liquid, minSize: try r.optionalDecimal(),
            sizeIncrement: try r.optionalDecimal(), suggestedSizeIncrement: try r.optionalDecimal())
        return .contractData(requestID: requestID, details)
    }

    private static func symbolSamples(_ r: inout FieldReader) throws -> IBMessage {
        let requestID = try r.int()
        let n = try r.int()
        var out: [ContractDescription] = []
        for _ in 0..<max(n, 0) {  // a short frame throws at the first missing field
            var c = Contract(symbol: "", exchange: "")
            c.conID = try r.int(); c.symbol = try r.string(); c.secType = try r.string()
            c.primaryExchange = try r.string(); c.currency = try r.string()
            let m = try r.int()
            var derivatives: [String] = []
            for _ in 0..<max(m, 0) { derivatives.append(try r.string()) }
            out.append(ContractDescription(contract: c, derivativeSecTypes: derivatives,
                                           description: try r.string(), issuerID: try r.string()))
        }
        return .symbolSamples(requestID: requestID, out)
    }
}
