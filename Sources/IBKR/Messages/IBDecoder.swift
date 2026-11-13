import Foundation

/// Turns one frame body into an `IBMessage` (incoming message ids per docs/protocol-178.md).
public enum IBDecoder {
    /// Never throws. A non-numeric message id is `.malformed` with id 0.
    public static func decode(_ body: [UInt8]) -> IBMessage { decode(body, gatewayTimeZone: nil) }

    /// `decode(_:)`, reading an execution time that names no zone in `gatewayTimeZone` (UTC when `nil`).
    static func decode(_ body: [UInt8], gatewayTimeZone: TimeZone?) -> IBMessage {
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
                return .error(IBErrorMessage(requestID: try r.int(), code: try r.int(),
                                             text: unescapeUnicode(try r.string()),
                                             advancedOrderRejectJSON: try r.string()))
            case 5: return .openOrder(try openOrder(&r))
            case 9: try r.skip(); return .nextValidID(try r.int())
            case 11: return try execDetails(&r, gatewayTimeZone)
            case 15:
                try r.skip()
                return .managedAccounts(try r.string().split(separator: ",").map(String.init))
            case 49: try r.skip(); return .currentTime(try r.int())
            case 107: return .userInfo(requestID: try r.int(), whiteBrandingID: try r.string())
            case 53: return .openOrderEnd
            case 55: try r.skip(); return .execDetailsEnd(requestID: try r.int())
            case 10: return try contractData(&r)
            case 18: return try bondContractData(&r)
            case 52: try r.skip(); return .contractDataEnd(requestID: try r.int())
            case 79: return try symbolSamples(&r)
            case 1:
                try r.skip(); let id = try r.int(), f = TickField(rawValue: try r.int())
                let price = try r.optionalDecimal(), size = try r.optionalDecimal()
                let attributes = TickAttrib(mask: try r.int())
                return .tick(requestID: id, .price(f, price: price, size: size, attributes: attributes))
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
                guard let t = MarketDataType(rawValue: raw) else {
                    throw IBProtocolError.badNumber(String(raw), index: r.index - 1)
                }
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
                let open = try r.decimal(), close = try r.decimal()
                let high = try r.decimal(), low = try r.decimal()   // O,C,H,L, as IB sends them
                let average = try r.optionalDecimal()
                return .historicalDataUpdate(requestID: id, Bar(
                    time: time, open: open, high: high, low: low, close: close, volume: try r.decimal(),
                    average: average, count: count))
            case 50:
                try r.skip(); let id = try r.int(), time = Date(timeIntervalSince1970: Double(try r.int()))
                return .realTimeBar(requestID: id, Bar(
                    time: time, open: try r.decimal(), high: try r.decimal(), low: try r.decimal(),
                    close: try r.decimal(),
                    volume: try r.decimal(), average: try r.optionalDecimal(), count: try r.int()))
            case 12:
                try r.skip(); let id = try r.int(), pos = try r.int(), op = try r.int(), side = try r.int()
                return .depth(requestID: id, try depthUpdate(pos, "", op, side, &r))
            case 13:
                try r.skip(); let id = try r.int(), pos = try r.int(), mm = try r.string()
                let op = try r.int(), side = try r.int()
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
                    let bid = try r.decimal(), ask = try r.decimal()
                    let bidSize = try r.decimal(), askSize = try r.decimal(), mask = try r.int()
                    return .tickByTick(requestID: id, .bidAsk(   // bit 0 bidPastLow here, askPastHigh in 97
                        time: time, bidPrice: bid, askPrice: ask, bidSize: bidSize, askSize: askSize,
                        bidPastLow: mask & 1 != 0, askPastHigh: mask & 2 != 0))
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
            case 80: return try depthExchanges(&r)
            case 82: return try smartComponents(&r)
            case 93: return try marketRule(&r)
            case 78: return try familyCodes(&r)
            case 77: return try softDollarTiers(&r)
            case 19: try r.skip(); return .scannerParameters(try r.string())
            case 20: return try scannerData(&r)
            case 85:
                return .newsProviders(try (0..<wireCount(&r)).map { _ in
                    NewsProvider(code: try r.string(), name: try r.string())
                })
            case 83:
                return .newsArticle(requestID: try r.int(),
                                    NewsArticle(articleType: try r.int(), articleText: try r.string()))
            case 86:
                return .historicalNews(requestID: try r.int(), HistoricalNews(
                    time: try r.string(), providerCode: try r.string(), articleID: try r.string(),
                    headline: try r.string()))
            case 14:
                try r.skip()
                return .newsBulletin(NewsBulletin(msgID: try r.int(), msgType: try r.int(), message: try r.string(),
                                                  origExchange: try r.string()))
            case 51: try r.skip(); return .fundamentalData(requestID: try r.int(), try r.string())
            case 104: return .wshMetaData(requestID: try r.int(), try r.string())
            case 105: return .wshEventData(requestID: try r.int(), try r.string())
            case 16:
                try r.skip()
                let raw = try r.int()
                guard let type = FADataType(rawValue: raw) else {
                    throw IBProtocolError.badNumber(String(raw), index: r.index - 1)
                }
                return .receiveFA(type: type, xml: try r.string())
            case 103: return .replaceFAEnd(requestID: try r.int(), try r.string())
            case 67: try r.skip(); return .displayGroupList(requestID: try r.int(), try r.string())
            case 68: try r.skip(); return .displayGroupUpdated(requestID: try r.int(), try r.string())
            case 65: try r.skip(); return .verifyMessageAPI(apiData: try r.string())
            case 66: try r.skip(); return .verifyCompleted(isSuccessful: try r.bool(), errorText: try r.string())
            case 69:
                try r.skip()
                return .verifyAndAuthMessageAPI(apiData: try r.string(), xyzChallenge: try r.string())
            case 70: try r.skip(); return .verifyAndAuthCompleted(isSuccessful: try r.bool(), errorText: try r.string())
            case 87: return .historicalNewsEnd(requestID: try r.int(), hasMore: try r.bool())
            case 75: return try optionChain(&r)
            case 76: return .securityDefinitionOptionParameterEnd(requestID: try r.int())
            case 96, 97, 98: return try historicalTicks(&r, id)
            case 106: return try historicalSchedule(&r)
            case 88: return .headTimeStamp(requestID: try r.int(), try barTime(&r))
            case 89: return try histogramData(&r)
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
                // this layout carries primaryExchange in the exchange slot
                c.primaryExchange = c.exchange; c.exchange = ""
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
                    daily: try r.optionalDecimal(), unrealized: try r.optionalDecimal(),
                    realized: try r.optionalDecimal()))
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

    private static func execDetails(_ r: inout FieldReader, _ zone: TimeZone?) throws -> IBMessage {
        let requestID = try r.int()
        let orderID = try r.int()
        let c = try contract(&r)
        let execID = try r.string(), time = try r.string(), account = try r.string(), exchange = try r.string()
        let side = try r.string(), shares = try r.decimal(), price = try r.decimal()
        let permID = try r.int(), clientID = try r.int(), liquidation = try r.int()
        let cumQty = try r.decimal(), avgPrice = try r.decimal(), orderRef = try r.string()
        let evRule = try r.string(), evMultiplier = try r.optionalDecimal(), modelCode = try r.string()
        let lastLiquidity = try r.int(), pending = try r.bool()
        return .execDetails(requestID: requestID, contract: c, execution: Execution(
            execID: execID, time: time, account: account, exchange: exchange, side: side, shares: shares,
            price: price, permID: permID, clientID: clientID, orderID: orderID, liquidation: liquidation,
            cumulativeQuantity: cumQty, averagePrice: avgPrice, orderRef: orderRef,
            lastLiquidity: lastLiquidity, pendingPriceRevision: pending, evRule: evRule, evMultiplier: evMultiplier,
            modelCode: modelCode,
            date: IBDate.parse(time, timeZone: zone ?? TimeZone(identifier: "UTC")!)))
    }

    /// scannerData (20): one whole scan, 16 fields per row.
    private static func scannerData(_ r: inout FieldReader) throws -> IBMessage {
        try r.skip()
        let id = try r.int()
        return .scannerData(requestID: id, try (0..<wireCount(&r)).map { _ in
            let rank = try r.int()
            var c = Contract(symbol: "")
            c.conID = try r.int(); c.symbol = try r.string(); c.secType = try r.string()
            c.lastTradeDateOrContractMonth = try r.string()
            c.strike = try r.optionalDecimal(); c.right = try r.string()
            c.exchange = try r.string(); c.currency = try r.string(); c.localSymbol = try r.string()
            let marketName = try r.string()
            c.tradingClass = try r.string()
            return ScanData(rank: rank, contract: c, marketName: marketName, distance: try r.string(),
                            benchmark: try r.string(), projection: try r.string(), legsStr: try r.string())
        })
    }

    private static func depthUpdate(_ pos: Int, _ mm: String, _ op: Int, _ side: Int,
                                    _ r: inout FieldReader) throws -> DepthUpdate {
        guard let o = DepthUpdate.Operation(rawValue: op) else {
            throw IBProtocolError.badNumber(String(op), index: r.index - 1)
        }
        guard let s = DepthUpdate.Side(rawValue: side) else {
            throw IBProtocolError.badNumber(String(side), index: r.index - 1)
        }
        return DepthUpdate(position: pos, marketMaker: mm, operation: o, side: s,
                           price: try r.decimal(), size: try r.decimal())
    }

    /// A repeat count off the wire: a negative one is a corrupt frame, not an empty list (and `0..<n` traps on it).
    static func wireCount(_ r: inout FieldReader) throws -> Int {
        let n = try r.int()
        guard n >= 0 else { throw IBProtocolError.badNumber(String(n), index: r.index - 1) }
        return n
    }

    /// 8 characters is a calendar day (checked first, as ib_async does: daily bars are dates under either
    /// formatDate); all digits is epoch seconds. Anything else, such as formatDate 1 text, is refused.
    static func barTime(_ r: inout FieldReader) throws -> Date {
        let s = try r.string()
        guard let date = barTime(s) else { throw IBProtocolError.unexpectedValue(s, index: r.index - 1) }
        return date
    }

    /// `barTime`'s rule on a string; `nil` where the reader throws.
    static func barTime(_ s: String) -> Date? {
        guard !s.isEmpty, s.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        if s.utf8.count == 8, let day = Int(s) {
            var c = DateComponents(); c.year = day / 10000; c.month = day / 100 % 100; c.day = day % 100
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
            return cal.date(from: c)
        }
        return Double(s).map { Date(timeIntervalSince1970: $0) }
    }

    private static func list(_ s: String) -> [String] { s.split(separator: ",").map(String.init) }

    /// ib_async's lastTimes split: on `-` when there is one, else on runs of whitespace.
    private static func splitLastTimes(_ s: String, into d: inout ContractDetails) -> String {
        let parts = s.contains("-") ? s.split(separator: "-", omittingEmptySubsequences: false)
                                    : s.split(whereSeparator: \.isWhitespace)
        if parts.count > 1 { d.lastTradeTime = String(parts[1]) }
        if parts.count > 2 { d.timeZoneID = String(parts[2]) }
        return parts.first.map(String.init) ?? ""
    }

    private static func marketRuleIDs(_ r: inout FieldReader) throws -> [Int] {
        let at = r.index
        return try list(try r.string()).map {
            guard let v = Int($0) else { throw IBProtocolError.badNumber($0, index: at) }
            return v
        }
    }

    /// The secId count and pairs, then aggGroup (shared by 10 and 18).
    private static func secIDsAndAggGroup(_ r: inout FieldReader, into d: inout ContractDetails) throws {
        let n = try r.int()
        guard n >= 0, n <= r.fields.count else { throw IBProtocolError.badNumber(String(n), index: r.index - 1) }
        for _ in 0..<n { d.secIDList.append(TagValue(tag: try r.string(), value: try r.string())) }
        d.aggGroup = try r.optionalInt()
    }

    private static func contractData(_ r: inout FieldReader) throws -> IBMessage {
        let requestID = try r.int()
        var c = Contract(symbol: try r.string())
        c.secType = try r.string(); let lastTimes = try r.string()
        c.strike = try r.optionalDecimal(); c.right = try r.string(); c.exchange = try r.string()
        c.currency = try r.string(); c.localSymbol = try r.string()
        let marketName = try r.string()
        c.tradingClass = try r.string(); c.conID = try r.int()
        let minTick = try r.decimal()
        c.multiplier = try r.string()
        let orderTypes = list(try r.string()), validExchanges = list(try r.string())
        let magnifier = try r.int()
        let underConID = try r.int()
        let longName = unescapeUnicode(try r.string())
        c.primaryExchange = try r.string()
        var d = ContractDetails(
            contract: c, marketName: marketName, minTick: minTick, priceMagnifier: magnifier, longName: longName,
            stockType: "", orderTypes: orderTypes, validExchanges: validExchanges, timeZoneID: "",
            tradingHours: "", liquidHours: "")
        d.underConID = underConID
        d.contractMonth = try r.string(); d.industry = try r.string(); d.category = try r.string()
        d.subcategory = try r.string()
        d.timeZoneID = try r.string(); d.tradingHours = try r.string(); d.liquidHours = try r.string()
        d.evRule = try r.string(); d.evMultiplier = try r.optionalDecimal()
        try secIDsAndAggGroup(&r, into: &d)
        d.underSymbol = try r.string(); d.underSecType = try r.string()
        d.marketRuleIDs = try marketRuleIDs(&r); d.realExpirationDate = try r.string()
        d.stockType = try r.string()
        d.minSize = try r.optionalDecimal(); d.sizeIncrement = try r.optionalDecimal()
        d.suggestedSizeIncrement = try r.optionalDecimal()
        d.contract.lastTradeDateOrContractMonth = splitLastTimes(lastTimes, into: &d)
        return .contractData(requestID: requestID, d)
    }

    /// Bond details (18) decode to the same `ContractDetails`; lastTimes part 0 is the maturity.
    private static func bondContractData(_ r: inout FieldReader) throws -> IBMessage {
        let requestID = try r.int()
        var c = Contract(symbol: try r.string(), secType: try r.string())
        var d = ContractDetails(
            contract: c, marketName: "", minTick: 0, priceMagnifier: 0, longName: "", stockType: "",
            timeZoneID: "", tradingHours: "", liquidHours: "")
        d.cusip = try r.string(); d.coupon = try r.optionalDecimal()
        let lastTimes = try r.string()
        d.issueDate = try r.string(); d.ratings = try r.string(); d.bondType = try r.string()
        d.couponType = try r.string()
        d.convertible = try r.bool(); d.callable = try r.bool(); d.putable = try r.bool()
        d.descAppend = try r.string()
        c.exchange = try r.string(); c.currency = try r.string()
        d.marketName = try r.string(); c.tradingClass = try r.string(); c.conID = try r.int()
        d.minTick = try r.decimal()
        d.orderTypes = list(try r.string()); d.validExchanges = list(try r.string())
        d.nextOptionDate = try r.string(); d.nextOptionType = try r.string()
        d.nextOptionPartial = try r.bool(); d.notes = try r.string(); d.longName = try r.string()
        d.evRule = try r.string(); d.evMultiplier = try r.optionalDecimal()
        try secIDsAndAggGroup(&r, into: &d)
        d.marketRuleIDs = try marketRuleIDs(&r)
        d.minSize = try r.optionalDecimal(); d.sizeIncrement = try r.optionalDecimal()
        d.suggestedSizeIncrement = try r.optionalDecimal()
        d.maturity = splitLastTimes(lastTimes, into: &d)
        d.contract = c
        return .contractData(requestID: requestID, d)
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
