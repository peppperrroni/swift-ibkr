import Foundation

public enum IBRequest: Sendable, Equatable {
    case startAPI(clientID: Int, capabilities: String)
    case requestIDs
    case cancelOrder(orderID: Int, manualCancelTime: String)
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
    case contractDetails(requestID: Int, contract: Contract)
    case matchingSymbols(requestID: Int, pattern: String)
    case marketDataType(MarketDataType)
    case marketData(requestID: Int, contract: Contract)
    case cancelMarketData(requestID: Int)
    case historicalData(requestID: Int, contract: Contract, end: Date?, barSize: String, duration: String,
                        rth: Bool, whatToShow: String, keepUpToDate: Bool)
    case cancelHistoricalData(requestID: Int)
    case marketDepth(requestID: Int, contract: Contract, rows: Int, smart: Bool)
    case cancelMarketDepth(requestID: Int, smart: Bool)
    case tickByTick(requestID: Int, contract: Contract, type: TickByTickType)
    case cancelTickByTick(requestID: Int)

    /// Fields only; the caller frames them. Field order is docs/protocol-178.md.
    func body() throws(IBEncodingError) -> [UInt8] {
        var w = FieldWriter()
        switch self {
        case .startAPI(let id, let caps):
            w.add(71); w.add(2); w.add(id); try w.add(caps)
        case .requestIDs:
            w.add(8); w.add(1); w.add(1)
        case .cancelOrder(let id, let t):
            w.add(4); w.add(1); w.add(id); try w.add(t)
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
        case .contractDetails(let reqID, let c):
            w.add(9); w.add(8); w.add(reqID); try Self.contract(&w, c)
            w.add(false); try w.add(""); try w.add(""); try w.add("")  // includeExpired, secIdType, secId, issuerId
        case .matchingSymbols(let reqID, let pattern):
            w.add(81); w.add(reqID); try w.add(pattern)
        case .marketDataType(let t):
            w.add(59); w.add(1); w.add(t.rawValue)
        case .marketData(let reqID, let c):
            w.add(1); w.add(11); w.add(reqID); try Self.contract(&w, c)
            w.add(false); try w.add(""); w.add(false); w.add(false); try w.add("")  // delta-neutral, genericTickList, snapshot, regulatorySnapshot, options
        case .cancelMarketData(let reqID):
            w.add(2); w.add(2); w.add(reqID)
        case .historicalData(let reqID, let c, let end, let barSize, let duration, let rth, let what, let keep):
            w.add(20); w.add(reqID); try Self.contract(&w, c); w.add(false)  // includeExpired
            try w.add(end.map { Self.endFormat.string(from: $0) } ?? "")
            try w.add(barSize); try w.add(duration); w.add(rth); try w.add(what)
            w.add(2); w.add(keep); try w.add("")  // formatDate (epoch seconds), keepUpToDate, chartOptions
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
        }
        return w.body
    }

    private static let endFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HH:mm:ss"
        return f
    }()

    /// The 12-field contract block every outgoing request shares (placeOrder rows 2-13).
    private static func contract(_ w: inout FieldWriter, _ c: Contract) throws(IBEncodingError) {
        if c.secType == "BAG" { throw .unsupported("secType BAG") }
        w.add(c.conID); try w.add(c.symbol); try w.add(c.secType); try w.add(c.lastTradeDateOrContractMonth)
        w.add(((c.strike ?? 0) as NSDecimalNumber).doubleValue)  // str(double), 0.0 by default
        try w.add(c.right); try w.add(c.multiplier); try w.add(c.exchange); try w.add(c.primaryExchange)
        try w.add(c.currency); try w.add(c.localSymbol); try w.add(c.tradingClass)
    }

    /// The base case of the table: plain order, no BAG / delta-neutral / scale / hedge / algo / PEG / conditions.
    /// Every unmodelled field carries the table's default; row numbers are the table's.
    private static func placeOrder(_ w: inout FieldWriter, _ id: Int, _ c: Contract, _ o: Order) throws(IBEncodingError) {
        // Table conditions that add fields this encoder does not emit; refuse rather than misalign.
        if c.exchange == "IBKRATS" { throw .unsupported("exchange IBKRATS") }
        if ["PEG BENCH", "PEGBENCH", "PEG BEST", "PEGBEST", "PEG MID", "PEGMID"].contains(o.orderType) {
            throw .unsupported("orderType \(o.orderType)")
        }
        func raw(_ values: String...) throws(IBEncodingError) { for v in values { try w.add(v) } }
        w.add(3); w.add(id)
        try contract(&w, c)
        try raw("", "")                                           // 14-15 secIdType, secId
        try w.add(o.action.rawValue); w.add(o.totalQuantity); try w.add(o.orderType)
        w.add(o.limitPrice); w.add(o.auxPrice)
        try w.add(o.tif); try w.add(o.ocaGroup); try w.add(o.account)
        try raw("O", "0"); try w.add(o.orderRef)                  // 24-26 openClose, origin, orderRef
        w.add(o.transmit); w.add(o.parentID)
        try raw("0", "0", "0", "0"); w.add(o.outsideRTH); try raw("0")  // 29-34
        try raw("", "0.0", "", "", "", "", "", "")                // 35-42
        try raw("0", "", "-1"); w.add(o.ocaType)                  // 43-46
        try raw("", "", "0", "", "", "0", "0", "")                // 47-54
        try raw("0", "", "", "", "", "")                          // 55-60
        try raw("0", "", "", "", "")                              // 61-65
        try raw("0", "", "", "", "", "", "", "")                  // 66-73
        try raw("", "", "")                                       // 74-76
        try raw("0", "", "", "0", "0")                            // 77-81
        try raw("", "", "0", "", "0", "0", "0")                   // 82-88
        try raw("0")                                              // 89 conditionsCount
        try raw("", "", "", "", "", "", "0", "", "", "")          // 90-99
        try raw("", "", "", "", "")                               // 100-104
        try raw("0", "0", "0", "0")                               // 105-108
        try raw("", "", "0", "", "")                              // 109-113
    }
}
