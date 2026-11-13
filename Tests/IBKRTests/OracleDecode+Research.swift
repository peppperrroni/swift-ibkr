import Foundation
@testable import IBKR

/// in 14, 16, 19, 20, 51, 65-70, 83, 85-87, 103-105 under ib_async's wrapper names. The nine methods `Wrapper` lacks
/// (65-70 and 103: verifyMessageAPI, verifyCompleted, displayGroupList, displayGroupUpdated, verifyAndAuthMessageAPI,
/// verifyAndAuthCompleted, replaceFAEnd) are recorded with positional names `_1`, `_2` (the recorder, plan decision 3),
/// so ib_async the library ignores them while the decoder's parse is still checked. `receiveFA`'s and
/// `historicalNewsEnd`'s first and last arguments are underscore-named in `Wrapper` (`_faDataType`, `_hasMore`).
func researchCalls(id: Int, _ m: IBMessage) -> [OracleCall]? {
    func call(_ method: String, _ args: [String: String]) -> [OracleCall] { [OracleCall(method: method, args: args)] }
    switch m {
    case .scannerParameters(let xml): return call("scannerParameters", ["xml": xml])
    case .scannerData(let reqId, let rows):
        // decoder.py:519-537 fills only the contract's identity and `marketName`; every other `ContractDetails` field
        // is the dataclass default (R9: the decoder never reads it, so the optional numbers map to ib_async's 0).
        let unread = ["minSize", "sizeIncrement", "suggestedSizeIncrement", "evMultiplier", "aggGroup"]
        let calls = rows.map { row -> OracleCall in
            let cd = ContractDetails(contract: row.contract, marketName: row.marketName, minTick: 0, priceMagnifier: 0,
                                     longName: "", stockType: "", timeZoneID: "", tradingHours: "", liquidHours: "")
            var a = contractDetailsArgs(cd, prefix: "contractDetails.")
            for k in unread { a["contractDetails.\(k)"] = "0" }
            a.merge(["reqId": canon(reqId), "rank": canon(row.rank), "distance": row.distance,
                     "benchmark": row.benchmark, "projection": row.projection, "legsStr": row.legsStr]) { a, _ in a }
            return OracleCall(method: "scannerData", args: a)
        }
        return calls + call("scannerDataEnd", ["reqId": canon(reqId)])
    case .newsProviders(let providers):
        var a = ["newsProviders.#": canon(providers.count)]
        for (i, p) in providers.enumerated() { a["newsProviders[\(i)].code"] = p.code; a["newsProviders[\(i)].name"] = p.name }
        return call("newsProviders", a)
    case .newsArticle(let reqId, let a):
        return call("newsArticle", ["reqId": canon(reqId), "articleType": canon(a.articleType), "articleText": a.articleText])
    case .historicalNews(let reqId, let n):
        return call("historicalNews", ["reqId": canon(reqId), "time": n.time, "providerCode": n.providerCode,
                                       "articleId": n.articleID, "headline": n.headline])
    case .historicalNewsEnd(let reqId, let hasMore):
        return call("historicalNewsEnd", ["reqId": canon(reqId), "_hasMore": canon(hasMore)])
    case .newsBulletin(let b):
        return call("updateNewsBulletin", ["msgId": canon(b.msgID), "msgType": canon(b.msgType), "message": b.message,
                                           "origExchange": b.origExchange])
    case .fundamentalData(let reqId, let data): return call("fundamentalData", ["reqId": canon(reqId), "data": data])
    case .wshMetaData(let reqId, let json): return call("wshMetaData", ["reqId": canon(reqId), "dataJson": json])
    case .wshEventData(let reqId, let json): return call("wshEventData", ["reqId": canon(reqId), "dataJson": json])
    case .receiveFA(let type, let xml): return call("receiveFA", ["_faDataType": canon(type.rawValue), "faXmlData": xml])
    case .replaceFAEnd(let reqId, let text): return call("replaceFAEnd", ["_1": canon(reqId), "_2": text])
    case .displayGroupList(let reqId, let groups): return call("displayGroupList", ["_1": canon(reqId), "_2": groups])
    case .displayGroupUpdated(let reqId, let contract):
        return call("displayGroupUpdated", ["_1": canon(reqId), "_2": contract])
    case .verifyMessageAPI(let data): return call("verifyMessageAPI", ["_1": data])
    case .verifyCompleted(let ok, let text): return call("verifyCompleted", ["_1": canon(ok), "_2": text])
    case .verifyAndAuthMessageAPI(let data, let challenge):
        return call("verifyAndAuthMessageAPI", ["_1": data, "_2": challenge])
    case .verifyAndAuthCompleted(let ok, let text): return call("verifyAndAuthCompleted", ["_1": canon(ok), "_2": text])
    default: return nil
    }
}
