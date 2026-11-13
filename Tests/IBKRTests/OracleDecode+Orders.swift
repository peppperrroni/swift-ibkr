import Foundation
@testable import IBKR

/// ib_async's `Execution` fields under `prefix`; `time` is `Execution.date` (a zone-less text is UTC on both sides:
/// the generator sets `TimezoneTWS = "UTC"`, ours has no `gatewayTimeZone`).
func executionArgs(_ e: Execution, prefix: String) -> [String: String] {
    let a: [String: String] = [
        "execId": e.execID, "time": canon(e.date), "acctNumber": e.account, "exchange": e.exchange, "side": e.side,
        "shares": canon(e.shares), "price": canon(e.price), "permId": canon(e.permID), "clientId": canon(e.clientID),
        "orderId": canon(e.orderID), "liquidation": canon(e.liquidation), "cumQty": canon(e.cumulativeQuantity),
        "avgPrice": canon(e.averagePrice), "orderRef": e.orderRef, "evRule": e.evRule,
        "evMultiplier": canon(e.evMultiplier), "modelCode": e.modelCode, "lastLiquidity": canon(e.lastLiquidity),
        "pendingPriceRevision": canon(e.pendingPriceRevision),
    ]
    return Dictionary(uniqueKeysWithValues: a.map { (prefix + $0.key, $0.value) })
}

/// in 3, 11, 53, 55, 59, 100, 102 under ib_async's wrapper names.
func orderCalls(id: Int, _ m: IBMessage) -> [OracleCall]? {
    func call(_ method: String, _ args: [String: String] = [:]) -> [OracleCall] {
        [OracleCall(method: method, args: args)]
    }
    switch m {
    case .orderStatus(let s):
        return call("orderStatus", [
            "orderId": canon(s.orderID), "status": s.status.rawValue, "filled": canon(s.filled),
            "remaining": canon(s.remaining), "avgFillPrice": canon(s.averageFillPrice), "permId": canon(s.permID),
            "parentId": canon(s.parentID), "lastFillPrice": canon(s.lastFillPrice), "clientId": canon(s.clientID),
            "whyHeld": s.whyHeld, "mktCapPrice": canon(s.marketCapPrice),
        ])
    case .execDetails(let reqId, let contract, let execution):
        return call("execDetails", contractArgs(contract, prefix: "contract.")
            .merging(executionArgs(execution, prefix: "execution.")) { a, _ in a }
            .merging(["reqId": canon(reqId)]) { a, _ in a })
    case .execDetailsEnd(let reqId): return call("execDetailsEnd", ["reqId": canon(reqId)])
    case .commissionReport(let c):
        return call("commissionReport", [
            "commissionReport.execId": c.execID, "commissionReport.commission": canon(c.commission),
            "commissionReport.currency": c.currency, "commissionReport.realizedPNL": canon(c.realizedPNL),
            "commissionReport.yield_": canon(c.yield), "commissionReport.yieldRedemptionDate": canon(c.yieldRedemptionDate),
        ])
    case .orderBound(let permID, let clientID, let orderID):
        return call("orderBound", ["reqId": canon(permID), "apiClientId": canon(clientID), "apiOrderId": canon(orderID)])
    case .openOrderEnd: return call("openOrderEnd")
    case .completedOrdersEnd: return call("completedOrdersEnd")
    default: return nil
    }
}
