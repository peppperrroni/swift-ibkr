import Foundation
import Testing
@testable import IBKR

/// The market-data and history requests (out 1, 2, 10, 11, 20, 25, 50, 51, 82, 83, 87-90, 96-98) from ib_async's
/// `Client` arguments; `nil` for another family's method.
func marketDataRequest(for c: EncodeCase) throws -> IBRequest? {
    var a = CaseArgs(c.args, c.name)
    let r: IBRequest
    switch c.method {
    case "reqMktData":
        let reqID = try a.int("reqId"), contract = try contract(from: a.value("contract"))
        let ticks = try a.text("genericTickList"), snapshot = try a.bool("snapshot")
        let regulatory = try a.bool("regulatorySnapshot")
        r = .marketData(requestID: reqID, contract: contract,
                        genericTicks: ticks.isEmpty ? [] : ticks.split(separator: ",", omittingEmptySubsequences: false)
                            .map { GenericTick(rawValue: String($0)) },
                        snapshot: snapshot, regulatorySnapshot: regulatory, options: try a.tagValues("mktDataOptions"))
    case "cancelMktData": r = .cancelMarketData(requestID: try a.int("reqId"))
    case "reqMktDepth":
        let reqID = try a.int("reqId"), contract = try contract(from: a.value("contract"))
        let rows = try a.int("numRows"), smart = try a.bool("isSmartDepth")
        r = .marketDepth(requestID: reqID, contract: contract, rows: rows, smart: smart,
                         options: try a.tagValues("mktDepthOptions"))
    case "cancelMktDepth": r = .cancelMarketDepth(requestID: try a.int("reqId"), smart: try a.bool("isSmartDepth"))
    case "reqHistoricalData":
        let reqID = try a.int("reqId"), contract = try contract(from: a.value("contract"))
        let end = try dateText(&a, "endDateTime", c), duration = try a.text("durationStr")
        let barSize = try a.text("barSizeSetting"), what = try a.text("whatToShow"), rth = try a.bool("useRTH")
        // swift-ibkr asks for epoch seconds (2) and SCHEDULE alone for text (1): another pair cannot be built
        let format = try a.int("formatDate")
        guard format == (what == "SCHEDULE" ? 1 : 2) else {
            throw CaseError("\(c.name): swift-ibkr sends formatDate 2, and 1 for SCHEDULE only; not \(format) for \(what)")
        }
        let keep = try a.bool("keepUpToDate")
        r = .historicalData(requestID: reqID, contract: contract, end: end, barSize: barSize, duration: duration,
                            rth: rth, whatToShow: what, keepUpToDate: keep, options: try optionalTagValues(&a, "chartOptions"))
    case "cancelHistoricalData": r = .cancelHistoricalData(requestID: try a.int("reqId"))
    case "reqRealTimeBars":
        let reqID = try a.int("reqId"), contract = try contract(from: a.value("contract"))
        guard try a.int("barSize") == 5 else { throw CaseError("\(c.name): swift-ibkr sends 5-second bars only") }
        let what = try a.text("whatToShow"), rth = try a.bool("useRTH")
        r = .realTimeBars(requestID: reqID, contract: contract, whatToShow: what, rth: rth,
                          options: try a.tagValues("realTimeBarsOptions"))
    case "cancelRealTimeBars": r = .cancelRealTimeBars(requestID: try a.int("reqId"))
    case "reqMktDepthExchanges": r = .depthExchanges
    case "reqSmartComponents": r = .smartComponents(requestID: try a.int("reqId"), bboExchange: try a.text("bboExchange"))
    case "reqHeadTimeStamp":
        let reqID = try a.int("reqId"), contract = try contract(from: a.value("contract"))
        let what = try a.text("whatToShow"), rth = try a.bool("useRTH")
        guard try a.int("formatDate") == 2 else { throw CaseError("\(c.name): swift-ibkr sends formatDate 2 only") }
        r = .headTimeStamp(requestID: reqID, contract: contract, whatToShow: what, rth: rth)
    case "cancelHeadTimeStamp": r = .cancelHeadTimeStamp(requestID: try a.int("reqId"))
    case "reqHistogramData":
        let reqID = try a.int("tickerId"), contract = try contract(from: a.value("contract"))
        r = .histogramData(requestID: reqID, contract: contract, rth: try a.bool("useRTH"),
                           period: try a.text("timePeriod"))
    case "cancelHistogramData": r = .cancelHistogramData(requestID: try a.int("tickerId"))
    case "reqHistoricalTicks":
        let reqID = try a.int("reqId"), contract = try contract(from: a.value("contract"))
        let start = try dateText(&a, "startDateTime", c), end = try dateText(&a, "endDateTime", c)
        let count = try a.int("numberOfTicks"), what = try a.text("whatToShow")
        let rth = try a.bool("useRth"), ignoreSize = try a.bool("ignoreSize")
        r = .historicalTicks(requestID: reqID, contract: contract, start: start, end: end, count: count,
                             whatToShow: what, rth: rth, ignoreSize: ignoreSize,
                             options: try a.tagValues("miscOptions"))
    case "reqTickByTickData":
        let reqID = try a.int("reqId"), contract = try contract(from: a.value("contract"))
        let raw = try a.text("tickType")
        guard let type = TickByTickType(rawValue: raw) else { throw CaseError("\(c.name): tickType \(raw)") }
        let count = try a.int("numberOfTicks")
        r = .tickByTick(requestID: reqID, contract: contract, type: type, count: count,
                        ignoreSize: try a.bool("ignoreSize"))
    case "cancelTickByTickData": r = .cancelTickByTick(requestID: try a.int("reqId"))
    default: return nil
    }
    try a.done()
    return r
}

/// A date argument as ib.py prepares it (`util.formatIBDatetime`, `yyyyMMdd HH:mm:ss UTC`; `""` for none). Text that
/// `IBDate` does not read back to the same text cannot be built.
func dateText(_ a: inout CaseArgs, _ key: String, _ c: EncodeCase) throws -> Date? {
    let text = try a.text(key)
    if text.isEmpty { return nil }
    guard let date = IBDate.parse(text), IBDate.format(date) == text else {
        throw CaseError("\(c.name).\(key): not a UTC date text: \(text)")
    }
    return date
}

/// ib.py passes `None` (reqHistoricalSchedule, ib.py:2386-2398) where swift-ibkr passes no options.
private func optionalTagValues(_ a: inout CaseArgs, _ key: String) throws -> [TagValue] {
    if case .null = try a.value(key) { return [] }
    return try a.tagValues(key)
}
