import Foundation
@testable import IBKR

/// in 1, 2, 12, 13, 21, 45, 46, 47, 50, 56, 57, 58, 81, 84, 91, 92, 99 under ib_async's wrapper names (the argument
/// names of `Wrapper`'s methods; the rerouteMktDataReq / rerouteMktDepthReq methods `Wrapper` lacks are `_1`, `_2`,
/// `_3`). Not mapped, because ib_async has no counterpart: tickPrice's mask (`TickAttrib`; ib_async's `priceSizeTick`
/// drops it, protocol-178 Disagreements 11, so the oracle cannot check it) and updateMktDepth's market maker (its
/// wrapper call has no such argument).
func marketDataCalls(id: Int, _ m: IBMessage) -> [OracleCall]? {
    func call(_ method: String, _ args: [String: String]) -> [OracleCall] { [OracleCall(method: method, args: args)] }
    switch m {
    case .tick(let reqId, let tick):
        let r = canon(reqId)
        switch tick {
        case .price(let f, let price, let size, _):
            return call("priceSizeTick", ["reqId": r, "tickType": canon(f.rawValue), "price": canon(price),
                                          "size": canon(size)])
        case .size(let f, let size):
            return call("tickSize", ["reqId": r, "tickType": canon(f.rawValue), "size": canon(size)])
        case .generic(let f, let value):
            return call("tickGeneric", ["reqId": r, "tickType": canon(f.rawValue), "value": canon(value)])
        case .string(let f, let value):
            return call("tickString", ["reqId": r, "tickType": canon(f.rawValue), "value": value])
        case .dataType(let t):
            return call("marketDataType", ["reqId": r, "marketDataId": canon(t.rawValue)])
        case .optionComputation(let f, let c):
            return call("tickOptionComputation", [
                "reqId": r, "tickType": canon(f.rawValue), "tickAttrib": canon(c.tickAttrib),
                "impliedVol": canon(c.impliedVol), "delta": canon(c.delta), "optPrice": canon(c.optPrice),
                "pvDividend": canon(c.pvDividend), "gamma": canon(c.gamma), "vega": canon(c.vega),
                "theta": canon(c.theta), "undPrice": canon(c.undPrice),
            ])
        case .efp(let f, let e):
            // ib_async's wrapper names the fifth value totalDividends; swift-ibkr's EFPData calls it impliedFuture
            return call("tickEFP", [
                "reqId": r, "tickType": canon(f.rawValue), "basisPoints": canon(e.basisPoints),
                "formattedBasisPoints": e.formattedBasisPoints, "totalDividends": canon(e.impliedFuture),
                "holdDays": canon(e.holdDays), "futureLastTradeDate": e.futureLastTradeDate,
                "dividendImpact": canon(e.dividendImpact), "dividendsToLastTradeDate": canon(e.dividendsToLastTradeDate),
            ])
        case .requestParameters(let minTick, let bbo, let snapshot):
            return call("tickReqParams", ["reqId": r, "minTick": canon(minTick), "bboExchange": bbo,
                                          "snapshotPermissions": canon(snapshot)])
        case .news(let n):
            return call("tickNews", ["_reqId": r, "timeStamp": canon(n.timeStamp), "providerCode": n.providerCode,
                                     "articleId": n.articleID, "headline": n.headline, "extraData": n.extraData])
        }
    case .depth(let reqId, let u):
        var a = ["reqId": canon(reqId), "position": canon(u.position), "operation": canon(u.operation.rawValue),
                 "side": canon(u.side.rawValue), "price": canon(u.price), "size": canon(u.size)]
        // no marketMaker for 12: not on its wire, nor an argument of ib_async's call (decoder.py:62, wrapper.py:1298)
        if id == 12 { return call("updateMktDepth", a) }
        a["marketMaker"] = u.marketMaker  // 13's isSmartDepth is read and dropped (DECISIONS: the `marketDepth` row)
        return call("updateMktDepthL2", a)
    case .realTimeBar(let reqId, let b):
        return call("realtimeBar", [
            "reqId": canon(reqId), "time": canon(b.time), "open_": canon(b.open), "high": canon(b.high),
            "low": canon(b.low), "close": canon(b.close), "volume": canon(b.volume), "wap": canon(b.average),
            "count": canon(b.count),
        ])
    case .tickByTick(let reqId, let t):
        let r = canon(reqId)
        switch t {
        case .trade(let time, let price, let size, let exchange, let conditions, let pastLimit, let unreported):
            // ib_async's tickType (1 Last, 2 AllLast) is not kept: both are `.trade` (DECISIONS: the `TickAttrib` row)
            return call("tickByTickAllLast", [
                "reqId": r, "time": canon(time), "price": canon(price), "size": canon(size),
                "tickAttribLast.pastLimit": canon(pastLimit), "tickAttribLast.unreported": canon(unreported),
                "exchange": exchange, "specialConditions": conditions,
            ])
        case .bidAsk(let time, let bid, let ask, let bidSize, let askSize, let bidPastLow, let askPastHigh):
            return call("tickByTickBidAsk", [
                "reqId": r, "time": canon(time), "bidPrice": canon(bid), "askPrice": canon(ask),
                "bidSize": canon(bidSize), "askSize": canon(askSize),
                "tickAttribBidAsk.bidPastLow": canon(bidPastLow), "tickAttribBidAsk.askPastHigh": canon(askPastHigh),
            ])
        case .midPoint(let time, let price):
            return call("tickByTickMidPoint", ["reqId": r, "time": canon(time), "midPoint": canon(price)])
        }
    case .tickSnapshotEnd(let reqId): return call("tickSnapshotEnd", ["reqId": canon(reqId)])
    case .deltaNeutralValidation(let reqId, let d):
        return call("deltaNeutralValidation", ["reqId": canon(reqId), "dnc.conId": canon(d.conID),
                                               "dnc.delta": canon(d.delta), "dnc.price": canon(d.price)])
    case .rerouteMarketData(let reqId, let conID, let exchange):
        return call("rerouteMktDataReq", ["_1": canon(reqId), "_2": canon(conID), "_3": exchange])
    case .rerouteMarketDepth(let reqId, let conID, let exchange):
        return call("rerouteMktDepthReq", ["_1": canon(reqId), "_2": canon(conID), "_3": exchange])
    default: return nil
    }
}
