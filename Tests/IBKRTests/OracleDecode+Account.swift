import Foundation
@testable import IBKR

/// Every ib_async `Contract` dataclass field under `prefix`, as the canonical flatten of a Contract names them
/// (`contract.conId`, `contract.comboLegs.#`, `contract.comboLegs[0].conId`, …). `description` is ib_async's free-text
/// field, never on the wire and not modelled here, so it maps to the `""` ib_async's decoder leaves in it.
func contractArgs(_ c: Contract, prefix: String) -> [String: String] {
    var a: [String: String] = [
        "conId": canon(c.conID), "symbol": c.symbol, "secType": c.secType,
        "lastTradeDateOrContractMonth": c.lastTradeDateOrContractMonth, "strike": canon(c.strike), "right": c.right,
        "multiplier": c.multiplier, "exchange": c.exchange, "primaryExchange": c.primaryExchange,
        "currency": c.currency, "localSymbol": c.localSymbol, "tradingClass": c.tradingClass,
        "includeExpired": canon(c.includeExpired), "secIdType": c.secIDType, "secId": c.secID, "description": "",
        "issuerId": c.issuerID, "comboLegsDescrip": c.comboLegsDescrip, "comboLegs.#": canon(c.comboLegs.count),
        "deltaNeutralContract": "",
    ]
    for (i, l) in c.comboLegs.enumerated() {
        a["comboLegs[\(i)].conId"] = canon(l.conID); a["comboLegs[\(i)].ratio"] = canon(l.ratio)
        a["comboLegs[\(i)].action"] = l.action.rawValue; a["comboLegs[\(i)].exchange"] = l.exchange
        a["comboLegs[\(i)].openClose"] = canon(l.openClose); a["comboLegs[\(i)].shortSaleSlot"] = canon(l.shortSaleSlot)
        a["comboLegs[\(i)].designatedLocation"] = l.designatedLocation
        a["comboLegs[\(i)].exemptCode"] = canon(l.exemptCode)
    }
    if let d = c.deltaNeutralContract {
        a["deltaNeutralContract"] = nil
        a["deltaNeutralContract.conId"] = canon(d.conID); a["deltaNeutralContract.delta"] = canon(d.delta)
        a["deltaNeutralContract.price"] = canon(d.price)
    }
    return Dictionary(uniqueKeysWithValues: a.map { (prefix + $0.key, $0.value) })
}

/// in 6, 7, 8, 54, 61, 62, 63, 64, 71, 72, 73, 74, 94, 95 under ib_async's wrapper names. The stage-14 fields
/// (`account`, `modelCode`, `conID` of the P&L messages) are set by the streams, not the decoder, so they are not mapped.
func accountCalls(id: Int, _ m: IBMessage) -> [OracleCall]? {
    func call(_ method: String, _ args: [String: String] = [:]) -> [OracleCall] {
        [OracleCall(method: method, args: args)]
    }
    switch m {
    case .accountValue(let v):
        return call("updateAccountValue", ["tag": v.tag, "val": v.value, "currency": v.currency, "account": v.account])
    case .portfolioItem(let p):
        return call("updatePortfolio", contractArgs(p.contract, prefix: "contract.").merging([
            "posSize": canon(p.quantity), "marketPrice": canon(p.marketPrice), "marketValue": canon(p.marketValue),
            "averageCost": canon(p.averageCost), "unrealizedPNL": canon(p.unrealizedPNL),
            "realizedPNL": canon(p.realizedPNL), "account": p.account,
        ]) { a, _ in a })
    case .accountTime(let t): return call("updateAccountTime", ["timestamp": t])
    case .accountDownloadEnd(let account): return call("accountDownloadEnd", ["_account": account])
    case .position(let p):
        return call("position", contractArgs(p.contract, prefix: "contract.").merging([
            "account": p.account, "posSize": canon(p.quantity), "avgCost": canon(p.averageCost),
        ]) { a, _ in a })
    case .positionEnd: return call("positionEnd")
    case .accountSummary(let reqId, let v):
        return call("accountSummary", ["_reqId": canon(reqId), "account": v.account, "tag": v.tag, "value": v.value,
                                       "currency": v.currency])
    case .accountSummaryEnd(let reqId): return call("accountSummaryEnd", ["reqId": canon(reqId)])
    case .positionMulti(let reqId, let p):
        return call("positionMulti", contractArgs(p.contract, prefix: "contract.").merging([
            "reqId": canon(reqId), "account": p.account, "modelCode": p.modelCode, "pos": canon(p.quantity),
            "avgCost": canon(p.averageCost),
        ]) { a, _ in a })
    case .positionMultiEnd(let reqId): return call("positionMultiEnd", ["reqId": canon(reqId)])
    case .accountUpdateMulti(let reqId, let v):
        return call("accountUpdateMulti", ["reqId": canon(reqId), "account": v.account, "modelCode": v.modelCode,
                                           "tag": v.tag, "val": v.value, "currency": v.currency])
    case .accountUpdateMultiEnd(let reqId): return call("accountUpdateMultiEnd", ["reqId": canon(reqId)])
    case .pnl(let reqId, let p):
        return call("pnl", ["reqId": canon(reqId), "dailyPnL": canon(p.daily), "unrealizedPnL": canon(p.unrealized),
                            "realizedPnL": canon(p.realized)])
    case .pnlSingle(let reqId, let p):
        return call("pnlSingle", ["reqId": canon(reqId), "pos": canon(p.position), "dailyPnL": canon(p.daily),
                                  "unrealizedPnL": canon(p.unrealized), "realizedPnL": canon(p.realized),
                                  "value": canon(p.value)])
    default: return nil
    }
}
