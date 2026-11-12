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
                return .error(IBErrorMessage(requestID: try r.int(), code: try r.int(), text: unescapeUnicode(try r.string()),
                                             advancedOrderRejectJSON: try r.string()))
            case 5: return .openOrder(try openOrder(&r))
            case 9: try r.skip(); return .nextValidID(try r.int())
            case 11: return try execDetails(&r)
            case 15:
                try r.skip()
                return .managedAccounts(try r.string().split(separator: ",").map(String.init))
            case 49: try r.skip(); return .currentTime(try r.int())
            case 107: return .userInfo(requestID: try r.int(), whiteBrandingID: try r.string())
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
            case 17:
                let id = try r.int(); try r.skip(2)  // startDate, endDate
                var bars: [Bar] = []
                for _ in 0..<(try wireCount(&r)) {
                    let time = try barTime(&r)
                    bars.append(Bar(time: time, open: try r.decimal(), high: try r.decimal(), low: try r.decimal(),
                                    close: try r.decimal(), volume: try r.decimal(), average: try r.optionalDecimal(),
                                    count: try r.int()))
                }
                return .historicalData(requestID: id, bars)
            case 90:
                let id = try r.int(), count = try r.int(), time = try barTime(&r)
                let open = try r.decimal(), close = try r.decimal(), high = try r.decimal(), low = try r.decimal()  // O,C,H,L
                let average = try r.optionalDecimal()
                return .historicalDataUpdate(requestID: id, Bar(
                    time: time, open: open, high: high, low: low, close: close, volume: try r.decimal(),
                    average: average, count: count))
            case 50:
                try r.skip(); let id = try r.int(), time = Date(timeIntervalSince1970: Double(try r.int()))
                return .realTimeBar(requestID: id, Bar(
                    time: time, open: try r.decimal(), high: try r.decimal(), low: try r.decimal(), close: try r.decimal(),
                    volume: try r.decimal(), average: try r.optionalDecimal(), count: try r.int()))
            case 12:
                try r.skip(); let id = try r.int(), pos = try r.int(), op = try r.int(), side = try r.int()
                return .depth(requestID: id, try depthUpdate(pos, "", op, side, &r))
            case 13:
                try r.skip(); let id = try r.int(), pos = try r.int(), mm = try r.string(), op = try r.int(), side = try r.int()
                let u = try depthUpdate(pos, mm, op, side, &r)
                _ = try r.bool()  // isSmartDepth
                return .depth(requestID: id, u)
            case 99:
                let id = try r.int(), type = try r.int(), time = Date(timeIntervalSince1970: Double(try r.int()))
                switch type {
                case 1, 2:
                    let price = try r.decimal(), size = try r.decimal(), mask = try r.int()
                    return .tickByTick(requestID: id, .trade(
                        time: time, price: price, size: size, exchange: try r.string(), conditions: try r.string(),
                        pastLimit: mask & 1 != 0, unreported: mask & 2 != 0))
                case 3:
                    let bid = try r.decimal(), ask = try r.decimal(), bidSize = try r.decimal(), askSize = try r.decimal()
                    try r.skip()  // attribMask
                    return .tickByTick(requestID: id, .bidAsk(time: time, bidPrice: bid, askPrice: ask, bidSize: bidSize, askSize: askSize))
                case 4: return .tickByTick(requestID: id, .midPoint(time: time, price: try r.decimal()))
                default: throw IBProtocolError.badNumber(String(type), index: r.index - 1)
                }
            case 57: try r.skip(); return .tickSnapshotEnd(requestID: try r.int())
            case 56:
                try r.skip()
                let id = try r.int()
                return .deltaNeutralValidation(requestID: id, DeltaNeutralContract(
                    conID: try r.int(), delta: try r.decimal(), price: try r.decimal()))
            case 91, 92:
                let reqID = try r.int(), conID = try r.int(), exchange = try r.string()
                return id == 91 ? .rerouteMarketData(requestID: reqID, conID: conID, exchange: exchange)
                    : .rerouteMarketDepth(requestID: reqID, conID: conID, exchange: exchange)
            case 81:
                let id = try r.int()
                return .tick(requestID: id, .requestParameters(
                    minTick: try r.optionalDecimal(), bboExchange: try r.string(), snapshotPermissions: try r.int()))
            case 21: return try optionComputation(&r)
            case 47: return try efp(&r)
            case 84: return try news(&r)
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
            case 6:
                try r.skip()
                let tag = try r.string(), value = try r.string(), currency = try r.string()
                return .accountValue(AccountValue(account: try r.string(), tag: tag, value: value, currency: currency))
            case 7:
                try r.skip()
                var c = try contract(&r)
                c.primaryExchange = c.exchange; c.exchange = ""  // this layout carries primaryExchange in the exchange slot
                let quantity = try r.decimal(), price = try r.decimal(), value = try r.decimal(), cost = try r.decimal()
                let unrealized = try r.optionalDecimal(), realized = try r.optionalDecimal()
                return .portfolioItem(PortfolioItem(
                    account: try r.string(), contract: c, quantity: quantity, marketPrice: price, marketValue: value,
                    averageCost: cost, unrealizedPNL: unrealized, realizedPNL: realized))
            case 8: try r.skip(); return .accountTime(try r.string())
            case 54: try r.skip(); return .accountDownloadEnd(account: try r.string())
            case 71:
                try r.skip()
                let reqID = try r.int(), account = try r.string(), c = try contract(&r)
                let quantity = try r.decimal(), cost = try r.decimal()
                return .positionMulti(requestID: reqID, Position(
                    account: account, contract: c, quantity: quantity, averageCost: cost, modelCode: try r.string()))
            case 72: try r.skip(); return .positionMultiEnd(requestID: try r.int())
            case 73:
                try r.skip()
                let reqID = try r.int(), account = try r.string(), model = try r.string()
                let tag = try r.string(), value = try r.string()
                return .accountUpdateMulti(requestID: reqID, AccountValue(
                    account: account, tag: tag, value: value, currency: try r.string(), modelCode: model))
            case 74: try r.skip(); return .accountUpdateMultiEnd(requestID: try r.int())
            case 94:
                return .pnl(requestID: try r.int(), AccountPnL(
                    daily: try r.optionalDecimal(), unrealized: try r.optionalDecimal(), realized: try r.optionalDecimal()))
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

    private static func depthUpdate(_ pos: Int, _ mm: String, _ op: Int, _ side: Int, _ r: inout FieldReader) throws -> DepthUpdate {
        guard let o = DepthUpdate.Operation(rawValue: op) else { throw IBProtocolError.badNumber(String(op), index: r.index - 1) }
        guard let s = DepthUpdate.Side(rawValue: side) else { throw IBProtocolError.badNumber(String(side), index: r.index - 1) }
        return DepthUpdate(position: pos, marketMaker: mm, operation: o, side: s, price: try r.decimal(), size: try r.decimal())
    }

    /// A repeat count off the wire: a negative one is a corrupt frame, not an empty list (and `0..<n` traps on it).
    private static func wireCount(_ r: inout FieldReader) throws -> Int {
        let n = try r.int()
        guard n >= 0 else { throw IBProtocolError.badNumber(String(n), index: r.index - 1) }
        return n
    }

    /// 8 characters is a calendar day (checked first, as ib_async does: daily bars are dates under either
    /// formatDate); all digits is epoch seconds. Anything else, such as formatDate 1 text, is refused.
    private static func barTime(_ r: inout FieldReader) throws -> Date {
        let s = try r.string(), at = r.index - 1
        guard !s.isEmpty, s.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            throw IBProtocolError.unexpectedValue(s, index: at)
        }
        if s.utf8.count == 8, let day = Int(s) {
            var c = DateComponents(); c.year = day / 10000; c.month = day / 100 % 100; c.day = day % 100
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
            guard let date = cal.date(from: c) else { throw IBProtocolError.unexpectedValue(s, index: at) }
            return date
        }
        guard let t = Double(s) else {
            throw IBProtocolError.unexpectedValue(s, index: at)
        }
        return Date(timeIntervalSince1970: t)
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
        let n = try wireCount(&r)
        var out: [ContractDescription] = []
        for _ in 0..<n {  // a short frame throws at the first missing field
            var c = Contract(symbol: "", exchange: "")
            c.conID = try r.int(); c.symbol = try r.string(); c.secType = try r.string()
            c.primaryExchange = try r.string(); c.currency = try r.string()
            let m = try wireCount(&r)
            var derivatives: [String] = []
            for _ in 0..<m { derivatives.append(try r.string()) }
            out.append(ContractDescription(contract: c, derivativeSecTypes: derivatives,
                                           description: try r.string(), issuerID: try r.string()))
        }
        return .symbolSamples(requestID: requestID, out)
    }
}

/// Error text arrives with JSON-style `\uXXXX` escapes. Anything that is not a well-formed escape stays literal.
func unescapeUnicode(_ s: String) -> String {
    guard s.contains("\\u") else { return s }
    let u = Array(s.unicodeScalars)
    func hex(_ i: Int) -> UInt32? {
        guard i + 6 <= u.count, u[i] == "\\", u[i + 1] == "u" else { return nil }
        var v: UInt32 = 0
        for k in 2..<6 { guard let d = Character(u[i + k]).hexDigitValue else { return nil }; v = v << 4 | UInt32(d) }
        return v
    }
    var out = String.UnicodeScalarView(), i = 0
    while i < u.count {
        if let v = hex(i) {
            if (0xD800..<0xDC00).contains(v), let lo = hex(i + 6), (0xDC00..<0xE000).contains(lo),
               let c = Unicode.Scalar(0x10000 + ((v - 0xD800) << 10) + (lo - 0xDC00)) {
                out.append(c); i += 12; continue
            }
            if let c = Unicode.Scalar(v) { out.append(c); i += 6; continue }
        }
        out.append(u[i]); i += 1
    }
    return String(out)
}
