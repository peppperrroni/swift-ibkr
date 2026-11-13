import Foundation
@testable import IBKR

/// in 17, 88, 89, 90, 96, 97, 98, 106 under ib_async's wrapper names. A bar's `date` is the epoch seconds of
/// swift-ibkr's `Bar.time` (ib_async keeps IB's text, so a day bar differs: DECISIONS, the `Bar.time` row). 17 is one
/// `historicalData` call per bar, then `historicalDataEnd(reqId, _start, _end)`; swift-ibkr reads and drops the start
/// and end texts, so those two keys are absent on our side (Disagreements 18). ib_async's three historicalTicks
/// messages hold `NamedTuple`s, which the oracle's canonical form flattens by position: 96 `[0]` time, `[1]` price,
/// `[2]` size; 97 `[0]` time, `[1]` attributes, `[2]` priceBid, `[3]` priceAsk, `[4]` sizeBid, `[5]` sizeAsk; 98 `[0]`
/// time, `[1]` attributes, `[2]` price, `[3]` size, `[4]` exchange, `[5]` specialConditions. The `[i].#` keys are the
/// tuple widths (3, 6, 6), a property of ib_async's types. `.midPoint` has no size (DECISIONS: the midpoint size is
/// dropped), so 96's `[2]` is absent on our side.
func historyCalls(id: Int, _ m: IBMessage) -> [OracleCall]? {
    func call(_ method: String, _ args: [String: String]) -> OracleCall { OracleCall(method: method, args: args) }
    func barArgs(_ b: Bar) -> [String: String] {
        ["bar.date": canon(b.time), "bar.open": canon(b.open), "bar.high": canon(b.high), "bar.low": canon(b.low),
         "bar.close": canon(b.close), "bar.volume": canon(b.volume), "bar.average": canon(b.average),
         "bar.barCount": canon(b.count)]
    }
    switch m {
    case .historicalData(let reqId, let bars):
        return bars.map { b in call("historicalData", barArgs(b).merging(["reqId": canon(reqId)]) { a, _ in a }) }
            + [call("historicalDataEnd", ["reqId": canon(reqId)])]
    case .historicalDataUpdate(let reqId, let b):
        return [call("historicalDataUpdate", barArgs(b).merging(["reqId": canon(reqId)]) { a, _ in a })]
    case .headTimeStamp(let reqId, let date):
        return [call("headTimestamp", ["reqId": canon(reqId), "headTimestamp": canon(date)])]
    case .histogramData(let reqId, let items):
        var a = ["reqId": canon(reqId), "items.#": "\(items.count)"]
        for (i, item) in items.enumerated() {
            a["items[\(i)].price"] = canon(item.price)
            a["items[\(i)].count"] = canon(item.count)
        }
        return [call("histogramData", a)]
    case .historicalTicks(let reqId, let ticks, let done):
        var a = ["reqId": canon(reqId), "ticks.#": "\(ticks.count)", "done": canon(done)]
        for (i, tick) in ticks.enumerated() {
            let p = "ticks[\(i)]"
            switch (id, tick) {
            case (96, .midPoint(let time, let price)):
                a["\(p).#"] = "3"
                a["\(p)[0]"] = canon(time)
                a["\(p)[1]"] = canon(price)
            case (97, .bidAsk(let time, let bid, let ask, let bidSize, let askSize, let bidPastLow, let askPastHigh)):
                a["\(p).#"] = "6"
                a["\(p)[0]"] = canon(time)
                a["\(p)[1].askPastHigh"] = canon(askPastHigh)
                a["\(p)[1].bidPastLow"] = canon(bidPastLow)
                a["\(p)[2]"] = canon(bid)
                a["\(p)[3]"] = canon(ask)
                a["\(p)[4]"] = canon(bidSize)
                a["\(p)[5]"] = canon(askSize)
            case (98, .trade(let time, let price, let size, let exchange, let conditions, let pastLimit, let unreported)):
                a["\(p).#"] = "6"
                a["\(p)[0]"] = canon(time)
                a["\(p)[1].pastLimit"] = canon(pastLimit)
                a["\(p)[1].unreported"] = canon(unreported)
                a["\(p)[2]"] = canon(price)
                a["\(p)[3]"] = canon(size)
                a["\(p)[4]"] = exchange
                a["\(p)[5]"] = conditions
            default: a["\(p).#"] = "unexpected tick kind \(tick) in message \(id)"
            }
        }
        let method = ["96": "historicalTicks", "97": "historicalTicksBidAsk", "98": "historicalTicksLast"]["\(id)"]
        return method.map { [call($0, a)] }
    case .historicalSchedule(let reqId, let s):
        var a = ["reqId": canon(reqId), "startDateTime": s.startDateTime, "endDateTime": s.endDateTime,
                 "timeZone": s.timeZone, "sessions.#": "\(s.sessions.count)"]
        for (i, session) in s.sessions.enumerated() {
            a["sessions[\(i)].startDateTime"] = session.startDateTime
            a["sessions[\(i)].endDateTime"] = session.endDateTime
            a["sessions[\(i)].refDate"] = session.refDate
        }
        return [call("historicalSchedule", a)]
    default: return nil
    }
}
