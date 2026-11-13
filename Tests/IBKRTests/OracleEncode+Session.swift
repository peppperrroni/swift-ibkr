import Foundation
import Testing
@testable import IBKR

/// The session, account and order-side requests (out 4-8, 14-17, 21, 49, 58, 59, 61-64, 71, 74-77, 92-95, 99, 104)
/// from ib_async's `Client` arguments; `nil` for another family's method.
func sessionRequest(for c: EncodeCase) throws -> IBRequest? {
    var a = CaseArgs(c.args, c.name)
    let r: IBRequest
    switch c.method {
    case "startApi":  // client.py:1017 sends the Client's attributes, not arguments (P15)
        var client = try CaseArgs(a.value("_client"), type: nil, "\(c.name)._client")
        let clientID = try client.int("clientId")
        r = .startAPI(clientID: clientID, capabilities: try client.text("optCapab"))
        try client.done()
    case "reqIds":  // swift-ibkr always asks for one id (IB ignores the count); any other count cannot be built
        guard try a.int("numIds") == 1 else { throw CaseError("\(c.name): swift-ibkr sends numIds 1 only") }
        r = .requestIDs
    case "reqCurrentTime": r = .currentTime
    case "reqManagedAccts": r = .managedAccounts
    case "reqUserInfo": r = .userInfo(requestID: try a.int("reqId"))
    case "setServerLogLevel": r = .serverLogLevel(try enumValue(ServerLogLevel.self, a.int("logLevel"), c))
    case "reqMarketDataType": r = .marketDataType(try enumValue(MarketDataType.self, a.int("marketDataType"), c))
    case "reqPositions": r = .positions
    case "cancelPositions": r = .cancelPositions
    case "reqAccountSummary":
        let reqID = try a.int("reqId"), group = try a.text("groupName"), tags = try a.text("tags")
        let list = tags.isEmpty ? [] : tags.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        r = .accountSummary(requestID: reqID, group: group, tags: list)
    case "cancelAccountSummary": r = .cancelAccountSummary(requestID: try a.int("reqId"))
    case "reqPnLSingle":
        let reqID = try a.int("reqId"), account = try a.text("account"), model = try a.text("modelCode")
        r = .pnlSingle(requestID: reqID, account: account, modelCode: model, conID: try a.int("conid"))
    case "cancelPnLSingle": r = .cancelPnLSingle(requestID: try a.int("reqId"))
    case "reqAccountUpdates":
        let subscribe = try a.bool("subscribe")
        r = .accountUpdates(subscribe: subscribe, account: try a.text("acctCode"))
    case "reqPositionsMulti":
        let reqID = try a.int("reqId"), account = try a.text("account")
        r = .positionsMulti(requestID: reqID, account: account, modelCode: try a.text("modelCode"))
    case "cancelPositionsMulti": r = .cancelPositionsMulti(requestID: try a.int("reqId"))
    case "reqAccountUpdatesMulti":
        let reqID = try a.int("reqId"), account = try a.text("account"), model = try a.text("modelCode")
        r = .accountUpdatesMulti(requestID: reqID, account: account, modelCode: model,
                                 ledgerAndNLV: try a.bool("ledgerAndNLV"))
    case "cancelAccountUpdatesMulti": r = .cancelAccountUpdatesMulti(requestID: try a.int("reqId"))
    case "reqPnL":
        let reqID = try a.int("reqId"), account = try a.text("account")
        r = .pnl(requestID: reqID, account: account, modelCode: try a.text("modelCode"))
    case "cancelPnL": r = .cancelPnL(requestID: try a.int("reqId"))
    case "cancelOrder":
        let id = try a.int("orderId")
        r = .cancelOrder(orderID: id, manualCancelTime: try a.text("manualCancelOrderTime"))
    case "exerciseOptions":  // ib.py:1805 passes exerciseAction and override as ints
        let reqID = try a.int("reqId"), option = try contract(from: a.value("contract"))
        let action = try enumValue(ExerciseAction.self, a.int("exerciseAction"), c)
        let quantity = try a.int("exerciseQuantity"), account = try a.text("account")
        r = .exerciseOptions(requestID: reqID, contract: option, action: action, quantity: quantity,
                             account: account, override: try a.flag("override"))
    case "reqGlobalCancel": r = .globalCancel
    case "reqOpenOrders": r = .openOrders
    case "reqAllOpenOrders": r = .allOpenOrders
    case "reqAutoOpenOrders": r = .autoOpenOrders(try a.bool("bAutoBind"))
    case "reqCompletedOrders": r = .completedOrders(apiOnly: try a.bool("apiOnly"))
    case "reqExecutions":
        let reqID = try a.int("reqId")
        var f = try CaseArgs(a.value("execFilter"), type: "ExecutionFilter", "\(c.name).execFilter")
        let clientID = try f.int("clientId")
        var filter = ExecutionFilter(clientID: clientID == 0 ? nil : clientID)  // 0, ib_async's default, is our nil
        filter.account = try f.text("acctCode")
        filter.time = try f.text("time")
        filter.symbol = try f.text("symbol")
        filter.secType = try f.text("secType")
        filter.exchange = try f.text("exchange")
        filter.side = try f.text("side")
        try f.done()
        r = .executions(requestID: reqID, filter: filter)
    default: return nil
    }
    try a.done()
    return r
}

private func enumValue<T: RawRepresentable>(_: T.Type, _ raw: T.RawValue, _ c: EncodeCase) throws -> T {
    guard let v = T(rawValue: raw) else { throw CaseError("\(c.name): \(raw) is not a \(T.self)") }
    return v
}

/// The tag string ib.py:2247-2258 joins, which reqAccountSummary/set passes, is swift-ibkr's default tag list.
@Test func defaultAccountSummaryTagsAreIbAsyncs() async throws {
    let file: OracleEncodeFile = try await oracleEncode()
    let c = try #require(file.cases.first { $0.name == "reqAccountSummary/set" })
    guard case .text(let tags)? = c.args["tags"] else { Issue.record("no tags"); return }
    #expect(tags == IBClient.defaultAccountSummaryTags.joined(separator: ","))
}
