import Foundation
import Testing
@testable import IBKR

// Encode cross-check (C4): each encode.json case built as an IBRequest by the per-family OracleEncode+<Family>.swift
// files, and its body compared field by field, as exact strings, with what ib_async 2.1.0's Client sent.

/// Every ib_async `Client` method that sends, with the out id it sends (client.py:443-1183): one per `IBRequest` case.
let ibAsyncRequestIDs: [String: Int] = [
    "reqMktData": 1, "cancelMktData": 2, "placeOrder": 3, "cancelOrder": 4, "reqOpenOrders": 5,
    "reqAccountUpdates": 6, "reqExecutions": 7, "reqIds": 8, "reqContractDetails": 9, "reqMktDepth": 10,
    "cancelMktDepth": 11, "reqNewsBulletins": 12, "cancelNewsBulletins": 13, "setServerLogLevel": 14,
    "reqAutoOpenOrders": 15, "reqAllOpenOrders": 16, "reqManagedAccts": 17, "requestFA": 18, "replaceFA": 19,
    "reqHistoricalData": 20, "exerciseOptions": 21, "reqScannerSubscription": 22, "cancelScannerSubscription": 23,
    "reqScannerParameters": 24, "cancelHistoricalData": 25, "reqCurrentTime": 49, "reqRealTimeBars": 50,
    "cancelRealTimeBars": 51, "reqFundamentalData": 52, "cancelFundamentalData": 53,
    "calculateImpliedVolatility": 54, "calculateOptionPrice": 55, "cancelCalculateImpliedVolatility": 56,
    "cancelCalculateOptionPrice": 57, "reqGlobalCancel": 58, "reqMarketDataType": 59, "reqPositions": 61,
    "reqAccountSummary": 62, "cancelAccountSummary": 63, "cancelPositions": 64, "verifyRequest": 65,
    "verifyMessage": 66, "queryDisplayGroups": 67, "subscribeToGroupEvents": 68, "updateDisplayGroup": 69,
    "unsubscribeFromGroupEvents": 70, "startApi": 71, "verifyAndAuthRequest": 72, "verifyAndAuthMessage": 73,
    "reqPositionsMulti": 74, "cancelPositionsMulti": 75, "reqAccountUpdatesMulti": 76,
    "cancelAccountUpdatesMulti": 77, "reqSecDefOptParams": 78, "reqSoftDollarTiers": 79, "reqFamilyCodes": 80,
    "reqMatchingSymbols": 81, "reqMktDepthExchanges": 82, "reqSmartComponents": 83, "reqNewsArticle": 84,
    "reqNewsProviders": 85, "reqHistoricalNews": 86, "reqHeadTimeStamp": 87, "reqHistogramData": 88,
    "cancelHistogramData": 89, "cancelHeadTimeStamp": 90, "reqMarketRule": 91, "reqPnL": 92, "cancelPnL": 93,
    "reqPnLSingle": 94, "cancelPnLSingle": 95, "reqHistoricalTicks": 96, "reqTickByTickData": 97,
    "cancelTickByTickData": 98, "reqCompletedOrders": 99, "reqWshMetaData": 100, "cancelWshMetaData": 101,
    "reqWshEventData": 102, "cancelWshEventData": 103, "reqUserInfo": 104,
]

/// The ib_async `Client` method that sends what `r` is (plan decision 11): exhaustive, so a new `IBRequest` case
/// does not compile until it is mapped.
func ibAsyncMethod(_ r: IBRequest) -> String {
    switch r {
    case .startAPI: "startApi"
    case .requestIDs: "reqIds"
    case .cancelOrder: "cancelOrder"
    case .exerciseOptions: "exerciseOptions"
    case .openOrders: "reqOpenOrders"
    case .allOpenOrders: "reqAllOpenOrders"
    case .autoOpenOrders: "reqAutoOpenOrders"
    case .completedOrders: "reqCompletedOrders"
    case .executions: "reqExecutions"
    case .placeOrder: "placeOrder"
    case .positions: "reqPositions"
    case .accountSummary: "reqAccountSummary"
    case .cancelAccountSummary: "cancelAccountSummary"
    case .pnlSingle: "reqPnLSingle"
    case .cancelPnLSingle: "cancelPnLSingle"
    case .accountUpdates: "reqAccountUpdates"
    case .cancelPositions: "cancelPositions"
    case .positionsMulti: "reqPositionsMulti"
    case .cancelPositionsMulti: "cancelPositionsMulti"
    case .accountUpdatesMulti: "reqAccountUpdatesMulti"
    case .cancelAccountUpdatesMulti: "cancelAccountUpdatesMulti"
    case .pnl: "reqPnL"
    case .cancelPnL: "cancelPnL"
    case .contractDetails: "reqContractDetails"
    case .matchingSymbols: "reqMatchingSymbols"
    case .marketDataType: "reqMarketDataType"
    case .marketData: "reqMktData"
    case .cancelMarketData: "cancelMktData"
    case .historicalData: "reqHistoricalData"
    case .cancelHistoricalData: "cancelHistoricalData"
    case .realTimeBars: "reqRealTimeBars"
    case .cancelRealTimeBars: "cancelRealTimeBars"
    case .marketDepth: "reqMktDepth"
    case .cancelMarketDepth: "cancelMktDepth"
    case .tickByTick: "reqTickByTickData"
    case .cancelTickByTick: "cancelTickByTickData"
    case .historicalTicks: "reqHistoricalTicks"
    case .headTimeStamp: "reqHeadTimeStamp"
    case .cancelHeadTimeStamp: "cancelHeadTimeStamp"
    case .histogramData: "reqHistogramData"
    case .cancelHistogramData: "cancelHistogramData"
    case .currentTime: "reqCurrentTime"
    case .depthExchanges: "reqMktDepthExchanges"
    case .smartComponents: "reqSmartComponents"
    case .secDefOptParams: "reqSecDefOptParams"
    case .calculateImpliedVolatility: "calculateImpliedVolatility"
    case .calculateOptionPrice: "calculateOptionPrice"
    case .cancelCalculateImpliedVolatility: "cancelCalculateImpliedVolatility"
    case .cancelCalculateOptionPrice: "cancelCalculateOptionPrice"
    case .marketRule: "reqMarketRule"
    case .familyCodes: "reqFamilyCodes"
    case .softDollarTiers: "reqSoftDollarTiers"
    case .scannerSubscription: "reqScannerSubscription"
    case .cancelScannerSubscription: "cancelScannerSubscription"
    case .scannerParameters: "reqScannerParameters"
    case .newsProviders: "reqNewsProviders"
    case .newsBulletins: "reqNewsBulletins"
    case .cancelNewsBulletins: "cancelNewsBulletins"
    case .newsArticle: "reqNewsArticle"
    case .historicalNews: "reqHistoricalNews"
    case .fundamentalData: "reqFundamentalData"
    case .cancelFundamentalData: "cancelFundamentalData"
    case .wshMetaData: "reqWshMetaData"
    case .cancelWshMetaData: "cancelWshMetaData"
    case .wshEventData: "reqWshEventData"
    case .cancelWshEventData: "cancelWshEventData"
    case .requestFA: "requestFA"
    case .replaceFA: "replaceFA"
    case .queryDisplayGroups: "queryDisplayGroups"
    case .subscribeToGroupEvents: "subscribeToGroupEvents"
    case .updateDisplayGroup: "updateDisplayGroup"
    case .unsubscribeFromGroupEvents: "unsubscribeFromGroupEvents"
    case .verifyRequest: "verifyRequest"
    case .verifyMessage: "verifyMessage"
    case .verifyAndAuthRequest: "verifyAndAuthRequest"
    case .verifyAndAuthMessage: "verifyAndAuthMessage"
    case .managedAccounts: "reqManagedAccts"
    case .userInfo: "reqUserInfo"
    case .serverLogLevel: "setServerLogLevel"
    case .globalCancel: "reqGlobalCancel"
    }
}

/// The `IBRequest` for a case, from the first family that maps its method (each returns `nil` for another family's).
func request(for c: EncodeCase) throws -> IBRequest {
    let families: [(EncodeCase) throws -> IBRequest?] = [sessionRequest, placeOrderRequest, marketDataRequest, referenceRequest]
    for family in families { if let r = try family(c) { return r } }
    throw CaseError("no family maps \(c.method)")
}

@Test func everyRequestKindHasACase() throws {
    let file: OracleEncodeFile = try oracleFile("encode.json")
    #expect(ibAsyncRequestIDs.count == 80)
    #expect(Set(ibAsyncRequestIDs.values).count == 80)
    let methods = Set(file.cases.map(\.method))
    #expect(methods == Set(ibAsyncRequestIDs.keys), "a method has no case, or a case names no method")
    for c in file.cases {
        #expect(c.fields.first == ibAsyncRequestIDs[c.method].map(String.init), "\(c.name): out id")
    }
}

@Test func ibAsyncEncodesLikeSwiftIBKR() throws {
    let file: OracleEncodeFile = try oracleFile("encode.json")
    let allow: [AllowEntry] = try oracleFile("allowlist.json")
    var used: Set<Int> = []
    for c in file.cases {
        let built: IBRequest
        do { built = try request(for: c) } catch { Issue.record("\(c.name): \(error)"); continue }
        #expect(ibAsyncMethod(built) == c.method, "\(c.name)")
        let scope = "out \(c.fields.first ?? "?")"
        var mismatches: [Mismatch] = []
        do {
            let ours = FieldReader(try built.body()).fields
            // placeOrder's fields by protocol-178 name (P7), every other request's by index
            var names = ours.indices.map(String.init)
            if case .placeOrder(_, let contract, let order) = built {
                names = placeOrderFieldNames(contract, order)
                if names.count != ours.count { Issue.record("\(c.name): \(names.count) names for \(ours.count) fields") }
            }
            if ours.count != c.fields.count {
                mismatches.append(Mismatch(name: c.name, scope: scope, field: "#count", ours: "\(ours.count): \(ours)",
                                           theirs: "\(c.fields.count): \(c.fields)"))
            }
            // the common prefix is compared even when the counts differ (R23)
            for (i, (a, b)) in zip(ours, c.fields).enumerated() where a != b {
                let field = i < names.count ? names[i] : "\(i)"
                mismatches.append(Mismatch(name: c.name, scope: scope, field: field, ours: a, theirs: b))
            }
        } catch {
            mismatches = [Mismatch(name: c.name, scope: scope, field: "#error", ours: "\(error)", theirs: "sent")]
        }
        for m in unallowed(mismatches, allow: allow, used: &used) { Issue.record("\(m)") }
    }
    for (i, e) in allow.enumerated() where e.scope.hasPrefix("out ") && !used.contains(i) {
        Issue.record("allowlist entry \(e.scope) \(e.field) (\(e.frames ?? "*")) accepts no mismatch: remove it")
    }
}

/// P7: an encode entry names one case and a field by index, `#count` (with its `pair`, R23) or `#error`; placeOrder
/// alone names a field by protocol-178 name or globs its cases.
@Test func encodeAllowlistEntriesAreNarrow() throws {
    let docs = try oracleDocs()
    let cite = "protocol-178 Disagreements 8"
    let good = [
        AllowEntry(scope: "out 4", field: "3", frames: "cancelOrder/set", cite: cite),
        AllowEntry(scope: "out 4", field: "#count", frames: "cancelOrder/set", pair: ["3: []", "4: []"], cite: cite),
        AllowEntry(scope: "out 3", field: "displaySize", frames: "placeOrder/modify/*", pair: ["0", ""], cite: cite),
        AllowEntry(scope: "out 3", field: "31", frames: "placeOrder/limit", cite: cite),
    ]
    for e in good { #expect(allowlistProblems([e], decisions: docs.decisions, protocol178: docs.protocol178).isEmpty, "\(e)") }
    let bad = [
        AllowEntry(scope: "out 4", field: "orderId", frames: "cancelOrder/set", cite: cite),
        AllowEntry(scope: "out 4", field: "3", cite: cite),
        AllowEntry(scope: "out 4", field: "3", frames: "cancelOrder/*", cite: cite),
        AllowEntry(scope: "out 4", field: "#calls", frames: "cancelOrder/set", cite: cite),
        AllowEntry(scope: "out 4", field: "#count", frames: "cancelOrder/set", cite: cite),
        AllowEntry(scope: "out 3", field: "#count", frames: "placeOrder/limit", cite: cite),
        AllowEntry(scope: "out 3", field: "31", cite: cite),
    ]
    for e in bad { #expect(allowlistProblems([e], decisions: docs.decisions, protocol178: docs.protocol178).count == 1, "\(e)") }
}

/// R23: the 80 strings `ibAsyncMethod` returns are distinct and are exactly the methods of `ibAsyncRequestIDs`, so a
/// wrong string fails before its family is mapped. Read from this file's switch: an `IBRequest` with associated values
/// cannot be enumerated.
@Test func ibAsyncMethodStringsAreDistinct() throws {
    let source = try String(contentsOf: URL(fileURLWithPath: #filePath), encoding: .utf8)
    let body = try #require(source.components(separatedBy: "func ibAsyncMethod(").dropFirst().first?
        .components(separatedBy: "\n}").first)
    let strings = body.split(whereSeparator: \.isNewline).compactMap { line -> String? in
        guard line.contains("case ."), let quote = line.firstIndex(of: "\"") else { return nil }
        return String(line[line.index(after: quote)...].prefix { $0 != "\"" })
    }
    #expect(strings.count == 80)
    #expect(Set(strings).count == strings.count, "a method string repeats")
    #expect(Set(strings) == Set(ibAsyncRequestIDs.keys))
}
