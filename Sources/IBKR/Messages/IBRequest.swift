import Foundation

public enum IBRequest: Sendable, Equatable {
    case startAPI(clientID: Int, capabilities: String)
    case requestIDs
    case cancelOrder(orderID: Int, manualCancelTime: String)
    case exerciseOptions(requestID: Int, contract: Contract, action: ExerciseAction, quantity: Int, account: String, override: Bool)
    case openOrders
    case allOpenOrders
    case autoOpenOrders(Bool)
    case completedOrders(apiOnly: Bool)
    case executions(requestID: Int, filter: ExecutionFilter)
    case placeOrder(orderID: Int, contract: Contract, order: Order)
    case positions
    case accountSummary(requestID: Int, group: String, tags: [String])
    case cancelAccountSummary(requestID: Int)
    case pnlSingle(requestID: Int, account: String, modelCode: String, conID: Int)
    case cancelPnLSingle(requestID: Int)
    case accountUpdates(subscribe: Bool, account: String)
    case cancelPositions
    case positionsMulti(requestID: Int, account: String, modelCode: String)
    case cancelPositionsMulti(requestID: Int)
    case accountUpdatesMulti(requestID: Int, account: String, modelCode: String, ledgerAndNLV: Bool)
    case cancelAccountUpdatesMulti(requestID: Int)
    case pnl(requestID: Int, account: String, modelCode: String)
    case cancelPnL(requestID: Int)
    case contractDetails(requestID: Int, contract: Contract)
    case matchingSymbols(requestID: Int, pattern: String)
    case marketDataType(MarketDataType)
    case marketData(requestID: Int, contract: Contract, genericTicks: [GenericTick] = [], snapshot: Bool = false,
                    regulatorySnapshot: Bool = false)
    case cancelMarketData(requestID: Int)
    case historicalData(requestID: Int, contract: Contract, end: Date?, barSize: String, duration: String,
                        rth: Bool, whatToShow: String, keepUpToDate: Bool)
    case cancelHistoricalData(requestID: Int)
    case realTimeBars(requestID: Int, contract: Contract, whatToShow: String, rth: Bool)
    case cancelRealTimeBars(requestID: Int)
    case marketDepth(requestID: Int, contract: Contract, rows: Int, smart: Bool)
    case cancelMarketDepth(requestID: Int, smart: Bool)
    case tickByTick(requestID: Int, contract: Contract, type: TickByTickType)
    case cancelTickByTick(requestID: Int)
    case historicalTicks(requestID: Int, contract: Contract, start: Date?, end: Date?, count: Int, whatToShow: String,
                         rth: Bool, ignoreSize: Bool)
    case headTimeStamp(requestID: Int, contract: Contract, whatToShow: String, rth: Bool)
    case cancelHeadTimeStamp(requestID: Int)
    case histogramData(requestID: Int, contract: Contract, rth: Bool, period: String)
    case cancelHistogramData(requestID: Int)
    case currentTime
    case depthExchanges
    case smartComponents(requestID: Int, bboExchange: String)
    case secDefOptParams(requestID: Int, underlyingSymbol: String, futFopExchange: String, underlyingSecType: String,
                         underlyingConID: Int)
    case calculateImpliedVolatility(requestID: Int, contract: Contract, optionPrice: Decimal, underPrice: Decimal,
                                    options: [TagValue])
    case calculateOptionPrice(requestID: Int, contract: Contract, volatility: Decimal, underPrice: Decimal,
                              options: [TagValue])
    case cancelCalculateImpliedVolatility(requestID: Int)
    case cancelCalculateOptionPrice(requestID: Int)
    case marketRule(marketRuleID: Int)
    case familyCodes
    case softDollarTiers(requestID: Int)
    case scannerSubscription(requestID: Int, subscription: ScannerSubscription, options: [TagValue],
                             filterOptions: [TagValue])
    case cancelScannerSubscription(requestID: Int)
    case scannerParameters
    case newsProviders
    case newsBulletins(allMessages: Bool)
    case cancelNewsBulletins
    case newsArticle(requestID: Int, providerCode: String, articleID: String, options: [TagValue])
    case historicalNews(requestID: Int, conID: Int, providerCodes: [String], start: Date?, end: Date?,
                        totalResults: Int, options: [TagValue])
    case fundamentalData(requestID: Int, contract: Contract, reportType: String, options: [TagValue])
    case cancelFundamentalData(requestID: Int)
    case wshMetaData(requestID: Int)
    case cancelWshMetaData(requestID: Int)
    case wshEventData(requestID: Int, data: WshEventData)
    case cancelWshEventData(requestID: Int)
    case requestFA(FADataType)
    case replaceFA(requestID: Int, type: FADataType, xml: String)
    case queryDisplayGroups(requestID: Int)
    case subscribeToGroupEvents(requestID: Int, groupID: Int)
    case updateDisplayGroup(requestID: Int, contractInfo: String)
    case unsubscribeFromGroupEvents(requestID: Int)
    case verifyRequest(apiName: String, apiVersion: String)
    case verifyMessage(apiData: String)
    case verifyAndAuthRequest(apiName: String, apiVersion: String, opaqueISVKey: String)
    case verifyAndAuthMessage(apiData: String, xyzResponse: String)
    case managedAccounts
    case userInfo(requestID: Int)
    case serverLogLevel(ServerLogLevel)
    case globalCancel

    /// Fields only; the caller frames them. Field order is docs/protocol-178.md.
    func body() throws(IBEncodingError) -> [UInt8] {
        var w = FieldWriter()
        switch self {
        case .startAPI(let id, let caps):
            w.add(71); w.add(2); w.add(id); try w.add(caps)
        case .currentTime:
            w.add(49); w.add(1)
        case .depthExchanges:
            w.add(82)
        case .smartComponents(let reqID, let bbo):
            w.add(83); w.add(reqID); try w.add(bbo)
        case .secDefOptParams(let reqID, let symbol, let exchange, let secType, let conID):
            w.add(78); w.add(reqID); try w.add(symbol); try w.add(exchange); try w.add(secType); w.add(conID)
        case .calculateImpliedVolatility(let reqID, let c, let price, let under, let options):
            w.add(54); w.add(3); w.add(reqID); try Self.contract(&w, c)
            w.add(price); w.add(under); w.add(options.count); try w.add(Self.tagValues(options))
        case .calculateOptionPrice(let reqID, let c, let vol, let under, let options):
            w.add(55); w.add(3); w.add(reqID); try Self.contract(&w, c)
            w.add(vol); w.add(under); w.add(options.count); try w.add(Self.tagValues(options))
        case .cancelCalculateImpliedVolatility(let reqID):
            w.add(56); w.add(1); w.add(reqID)
        case .cancelCalculateOptionPrice(let reqID):
            w.add(57); w.add(1); w.add(reqID)
        case .marketRule(let id):
            w.add(91); w.add(id)
        case .familyCodes:
            w.add(80)
        case .softDollarTiers(let reqID):
            w.add(79); w.add(reqID)
        case .scannerSubscription(let reqID, let s, let options, let filterOptions):
            w.add(22); w.add(reqID); w.add(s.numberOfRows ?? -1)  // -1: IB's default row count
            try w.add(s.instrument); try w.add(s.locationCode); try w.add(s.scanCode)
            w.add(s.abovePrice); w.add(s.belowPrice); w.add(s.aboveVolume); w.add(s.marketCapAbove); w.add(s.marketCapBelow)
            try w.add(s.moodyRatingAbove); try w.add(s.moodyRatingBelow); try w.add(s.spRatingAbove)
            try w.add(s.spRatingBelow); try w.add(s.maturityDateAbove); try w.add(s.maturityDateBelow)
            w.add(s.couponRateAbove); w.add(s.couponRateBelow); w.add(s.excludeConvertible)
            w.add(s.averageOptionVolumeAbove); try w.add(s.scannerSettingPairs); try w.add(s.stockTypeFilter)
            try w.add(Self.tagValues(filterOptions)); try w.add(Self.tagValues(options))  // filter options go first
        case .cancelScannerSubscription(let reqID):
            w.add(23); w.add(1); w.add(reqID)
        case .scannerParameters:
            w.add(24); w.add(1)
        case .newsProviders:
            w.add(85)
        case .newsBulletins(let all):
            w.add(12); w.add(1); w.add(all)
        case .cancelNewsBulletins:
            w.add(13); w.add(1)
        case .newsArticle(let reqID, let provider, let article, let options):
            w.add(84); w.add(reqID); try w.add(provider); try w.add(article); try w.add(Self.tagValues(options))
        case .historicalNews(let reqID, let conID, let providers, let start, let end, let total, let options):
            w.add(86); w.add(reqID); w.add(conID); try w.add(providers.joined(separator: "+"))
            try w.add(start.map { Self.newsFormat.string(from: $0) } ?? ""); try w.add(end.map { Self.newsFormat.string(from: $0) } ?? "")
            w.add(total); try w.add(Self.tagValues(options))
        case .fundamentalData(let reqID, let c, let reportType, let options):
            // the contract block minus strike, right and multiplier, as ib_async sends it
            if c.secType == "BAG" { throw .unsupported("secType BAG") }
            w.add(52); w.add(2); w.add(reqID); w.add(c.conID); try w.add(c.symbol); try w.add(c.secType)
            try w.add(c.exchange); try w.add(c.primaryExchange); try w.add(c.currency); try w.add(c.localSymbol)
            try w.add(reportType); w.add(options.count); try w.add(Self.tagValues(options))
        case .cancelFundamentalData(let reqID):
            w.add(53); w.add(1); w.add(reqID)
        case .wshMetaData(let reqID):
            w.add(100); w.add(reqID)
        case .cancelWshMetaData(let reqID):
            w.add(101); w.add(reqID)
        case .wshEventData(let reqID, let d):
            // makeEmpty=False in ib_async: an unset conID or totalLimit is IB's UNSET_INTEGER, not empty
            w.add(102); w.add(reqID); w.add(d.conID ?? Int(Int32.max)); try w.addPayload(d.filter)
            w.add(d.fillWatchlist); w.add(d.fillPortfolio); w.add(d.fillCompetitors)
            try w.add(d.startDate); try w.add(d.endDate); w.add(d.totalLimit ?? Int(Int32.max))
        case .cancelWshEventData(let reqID):
            w.add(103); w.add(reqID)
        case .requestFA(let type):
            w.add(18); w.add(1); w.add(type.rawValue)
        case .replaceFA(let reqID, let type, let xml):
            w.add(19); w.add(1); w.add(type.rawValue); try w.addPayload(xml); w.add(reqID)   // reqId last, as ib_async
        case .queryDisplayGroups(let reqID):
            w.add(67); w.add(1); w.add(reqID)
        case .subscribeToGroupEvents(let reqID, let groupID):
            w.add(68); w.add(1); w.add(reqID); w.add(groupID)
        case .updateDisplayGroup(let reqID, let info):
            w.add(69); w.add(1); w.add(reqID); try w.add(info)
        case .unsubscribeFromGroupEvents(let reqID):
            w.add(70); w.add(1); w.add(reqID)
        case .verifyRequest(let name, let version):
            w.add(65); w.add(1); try w.add(name); try w.add(version)
        case .verifyMessage(let data):
            w.add(66); w.add(1); try w.add(data)
        case .verifyAndAuthRequest(let name, let version, let key):
            w.add(72); w.add(1); try w.add(name); try w.add(version); try w.add(key)
        case .verifyAndAuthMessage(let data, let response):
            w.add(73); w.add(1); try w.add(data); try w.add(response)
        case .managedAccounts:
            w.add(17); w.add(1)
        case .userInfo(let reqID):
            w.add(104); w.add(reqID)
        case .serverLogLevel(let level):
            w.add(14); w.add(1); w.add(level.rawValue)
        case .globalCancel:
            w.add(58); w.add(1)
        case .requestIDs:
            w.add(8); w.add(1); w.add(1)
        case .cancelOrder(let id, let t):
            w.add(4); w.add(1); w.add(id); try w.add(t)
        case .exerciseOptions(let id, let c, let action, let quantity, let account, let override):
            // the 12-field contract block minus primaryExchange, so it cannot reuse `contract`
            if c.secType == "BAG" { throw .unsupported("secType BAG") }
            w.add(21); w.add(2); w.add(id); w.add(c.conID); try w.add(c.symbol); try w.add(c.secType)
            try w.add(c.lastTradeDateOrContractMonth); w.addDouble(c.strike ?? 0); try w.add(c.right)
            try w.add(c.multiplier); try w.add(c.exchange); try w.add(c.currency); try w.add(c.localSymbol)
            try w.add(c.tradingClass); w.add(action.rawValue); w.add(quantity); try w.add(account); w.add(override)
        case .openOrders:
            w.add(5); w.add(1)
        case .allOpenOrders:
            w.add(16); w.add(1)
        case .autoOpenOrders(let bind):
            w.add(15); w.add(1); w.add(bind)
        case .completedOrders(let apiOnly):
            w.add(99); w.add(apiOnly)
        case .executions(let reqID, let f):
            w.add(7); w.add(3); w.add(reqID)
            w.add(f.clientID ?? 0)  // the table's default; an empty field is not what IB's client sends
            try w.add(f.account); try w.add(f.time); try w.add(f.symbol)
            try w.add(f.secType); try w.add(f.exchange); try w.add(f.side)
        case .placeOrder(let id, let c, let o):
            try Self.placeOrder(&w, id, c, o)
        case .positions:
            w.add(61); w.add(1)
        case .accountSummary(let reqID, let group, let tags):
            w.add(62); w.add(1); w.add(reqID); try w.add(group); try w.add(tags.joined(separator: ","))
        case .cancelAccountSummary(let reqID):
            w.add(63); w.add(1); w.add(reqID)
        case .pnlSingle(let reqID, let account, let modelCode, let conID):
            w.add(94); w.add(reqID); try w.add(account); try w.add(modelCode); w.add(conID)
        case .cancelPnLSingle(let reqID):
            w.add(95); w.add(reqID)
        case .accountUpdates(let subscribe, let account):
            w.add(6); w.add(2); w.add(subscribe); try w.add(account)
        case .cancelPositions:
            w.add(64); w.add(1)
        case .positionsMulti(let reqID, let account, let model):
            w.add(74); w.add(1); w.add(reqID); try w.add(account); try w.add(model)
        case .cancelPositionsMulti(let reqID):
            w.add(75); w.add(1); w.add(reqID)
        case .accountUpdatesMulti(let reqID, let account, let model, let ledger):
            w.add(76); w.add(1); w.add(reqID); try w.add(account); try w.add(model); w.add(ledger)
        case .cancelAccountUpdatesMulti(let reqID):
            w.add(77); w.add(1); w.add(reqID)
        case .pnl(let reqID, let account, let model):
            w.add(92); w.add(reqID); try w.add(account); try w.add(model)
        case .cancelPnL(let reqID):
            w.add(93); w.add(reqID)
        case .contractDetails(let reqID, let c):
            w.add(9); w.add(8); w.add(reqID); try Self.contract(&w, c)
            w.add(false); try w.add(c.secIDType); try w.add(c.secID); try w.add("")  // includeExpired, secIdType, secId, issuerId
        case .matchingSymbols(let reqID, let pattern):
            w.add(81); w.add(reqID); try w.add(pattern)
        case .marketDataType(let t):
            w.add(59); w.add(1); w.add(t.rawValue)
        case .marketData(let reqID, let c, let genericTicks, let snapshot, let regulatorySnapshot):
            w.add(1); w.add(11); w.add(reqID); try Self.contract(&w, c, allowBag: true)
            try Self.comboLegs(&w, c)
            if let dnc = c.deltaNeutralContract {
                w.add(true); w.add(dnc.conID); w.addDouble(dnc.delta); w.addDouble(dnc.price)
            } else {
                w.add(false)
            }
            try w.add(genericTicks.map(\.rawValue).joined(separator: ","))
            w.add(snapshot); w.add(regulatorySnapshot); try w.add("")  // options
        case .cancelMarketData(let reqID):
            w.add(2); w.add(2); w.add(reqID)
        case .historicalData(let reqID, let c, let end, let barSize, let duration, let rth, let what, let keep):
            w.add(20); w.add(reqID); try Self.contract(&w, c, allowBag: true); w.add(false)  // includeExpired
            try w.add(end.map { Self.endFormat.string(from: $0) } ?? "")
            try w.add(barSize); try w.add(duration); w.add(rth); try w.add(what)
            w.add(what == "SCHEDULE" ? 1 : 2)  // formatDate: epoch seconds, but SCHEDULE wants text
            try Self.comboLegs(&w, c)
            w.add(keep); try w.add("")  // keepUpToDate, chartOptions
        case .realTimeBars(let reqID, let c, let what, let rth):
            w.add(50); w.add(3); w.add(reqID); try Self.contract(&w, c)
            w.add(5); try w.add(what); w.add(rth); try w.add("")  // barSize (IB supports only 5), useRTH, options
        case .cancelRealTimeBars(let reqID):
            w.add(51); w.add(1); w.add(reqID)
        case .cancelHistoricalData(let reqID):
            w.add(25); w.add(1); w.add(reqID)
        case .marketDepth(let reqID, let c, let rows, let smart):
            w.add(10); w.add(5); w.add(reqID); try Self.contract(&w, c)
            w.add(rows); w.add(smart); try w.add("")  // numRows, isSmartDepth, options
        case .cancelMarketDepth(let reqID, let smart):
            w.add(11); w.add(1); w.add(reqID); w.add(smart)
        case .tickByTick(let reqID, let c, let type):
            w.add(97); w.add(reqID); try Self.contract(&w, c)
            try w.add(type.rawValue); w.add(0); w.add(false)  // numberOfTicks (unlimited), ignoreSize
        case .cancelTickByTick(let reqID):
            w.add(98); w.add(reqID)
        case .headTimeStamp(let reqID, let c, let what, let rth):
            w.add(87); w.add(reqID); try Self.contract(&w, c); w.add(false); w.add(rth); try w.add(what); w.add(2)  // includeExpired, useRTH, whatToShow, formatDate
        case .cancelHeadTimeStamp(let reqID):
            w.add(90); w.add(reqID)
        case .histogramData(let reqID, let c, let rth, let period):
            w.add(88); w.add(reqID); try Self.contract(&w, c); w.add(false); w.add(rth); try w.add(period)  // includeExpired, useRTH, timePeriod
        case .cancelHistogramData(let reqID):
            w.add(89); w.add(reqID)
        case .historicalTicks(let reqID, let c, let start, let end, let count, let what, let rth, let ignoreSize):
            w.add(96); w.add(reqID); try Self.contract(&w, c); w.add(false)  // includeExpired
            try w.add(start.map { Self.endFormat.string(from: $0) } ?? ""); try w.add(end.map { Self.endFormat.string(from: $0) } ?? "")
            w.add(count); try w.add(what); w.add(rth); w.add(ignoreSize); try w.add("")  // miscOptions
        }
        return w.body
    }

    /// ib_async's text for a news date (util.py formatIBDatetime), unlike the `-` form history requests use.
    private static let newsFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd HH:mm:ss 'UTC'"
        return f
    }()

    private static let endFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HH:mm:ss"
        return f
    }()

    /// A tag-value list as IB takes it: `tag=value;` per pair, with no separator.
    static func tagValues(_ list: [TagValue]) -> String { list.map { "\($0.tag)=\($0.value);" }.joined() }

    /// A `BAG`'s legs as a request sends them: the count, then conID, ratio, action and exchange per leg. Nothing for
    /// any other secType.
    static func comboLegs(_ w: inout FieldWriter, _ c: Contract) throws(IBEncodingError) {
        guard c.secType == "BAG" else { return }
        w.add(c.comboLegs.count)
        for l in c.comboLegs { w.add(l.conID); w.add(l.ratio); try w.add(l.action.rawValue); try w.add(l.exchange) }
    }

    /// The 12-field contract block every outgoing request shares (placeOrder rows 2-13). Only placeOrder,
    /// marketData and historicalData pass `allowBag: true` (they send a `BAG`'s legs), so every other request refuses one.
    static func contract(_ w: inout FieldWriter, _ c: Contract, allowBag: Bool = false) throws(IBEncodingError) {
        if c.secType == "BAG" && !allowBag { throw .unsupported("secType BAG") }
        w.add(c.conID); try w.add(c.symbol); try w.add(c.secType); try w.add(c.lastTradeDateOrContractMonth)
        w.addDouble(c.strike ?? 0)  // str(double), 0.0 by default
        try w.add(c.right); try w.add(c.multiplier); try w.add(c.exchange); try w.add(c.primaryExchange)
        try w.add(c.currency); try w.add(c.localSymbol); try w.add(c.tradingClass)
    }
}
