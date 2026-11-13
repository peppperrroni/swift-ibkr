import Foundation
import Testing
@testable import IBKR

private let eastern = TimeZone(identifier: "US/Eastern")!

/// 2026-11-10 00:00:00 UTC plus `h`:`m`:`s`, built without any formatter.
private func utcDate(_ h: Int, _ m: Int = 0, _ s: Int = 0) -> Date {
    Date(timeIntervalSince1970: 1_794_268_800 + Double(h * 3600 + m * 60 + s))
}

@Test func formatMatchesIbAsync() {
    #expect(IBDate.format(utcDate(21)) == "20261110 21:00:00 UTC")
}

@Test func parseReadsEveryIbForm() {
    #expect(IBDate.parse("20261110") == utcDate(0))
    #expect(IBDate.parse("20261110", timeZone: eastern) == utcDate(5))
    #expect(IBDate.parse("1794344400") == Date(timeIntervalSince1970: 1_794_344_400))
    #expect(IBDate.parse("20261110 16:00:00 US/Eastern") == utcDate(21))
    #expect(IBDate.parse("20261110  16:00:00") == utcDate(16))
    #expect(IBDate.parse("20261110  16:00:00", timeZone: eastern) == utcDate(21))
    #expect(IBDate.parse("2026-11-10 16:00:00.0") == utcDate(16))
    #expect(IBDate.parse("20261110-16:00:00") == utcDate(16))
    #expect(IBDate.parse("noon") == nil)
    #expect(IBDate.parse("") == nil)
    #expect(IBDate.parse("20261110 16:00:00 Nowhere/Land") == nil)
    #expect(IBDate.parse("20261340") == nil)
}

@Test func executionDateReadsBothLiveFormats() throws {
    func date(_ time: String, _ zone: TimeZone? = nil) throws -> Date? {
        let fields = ["11", "-1", "12", "265598", "AAPL", "STK", "", "0", "", "", "SMART", "USD", "AAPL", "NMS",
                      "e1", time, "DU1", "ISLAND", "BOT", "100", "187.25", "918273001", "7", "0",
                      "100", "187.25", "", "", "", "", "1", "0"]
        guard case .execDetails(_, _, let e) = IBDecoder.decode(fields.flatMap { Array($0.utf8) + [0] },
                                                                gatewayTimeZone: zone) else { throw TimedOut() }
        #expect(e.time == time)   // the raw string stays
        return e.date
    }
    let live = try date("20261110-11:56:31"), reply = try date("20261110 06:56:31 US/Eastern")
    #expect(live != nil && live == reply)
    let shifted = try #require(try date("20261110-11:56:31", eastern))
    #expect(shifted.timeIntervalSince(try #require(live)) == 5 * 3600)
    #expect(try date("20261110 06:56:31 US/Eastern", eastern) == reply)   // a named zone beats the gateway's
}


@Test func waitUntilReturnsAtTheDate() async throws {
    let target = Date().addingTimeInterval(0.1)
    try await IBClient.wait(until: target)
    #expect(Date() >= target)
    try await IBClient.wait(until: Date().addingTimeInterval(-5))   // the past returns at once
}

@Test func greeksAddSubtractAndScale() {
    let a = OptionComputation(tickAttrib: 3, impliedVol: 0.5, delta: 0.25, optPrice: 2, pvDividend: 9, gamma: nil,
                              vega: 1, theta: -1, undPrice: 100)
    let b = OptionComputation(tickAttrib: 4, impliedVol: 0.25, delta: nil, optPrice: 1, pvDividend: 8, gamma: nil,
                              vega: 2, theta: -2, undPrice: 200)
    #expect(a + b == OptionComputation(tickAttrib: 0, impliedVol: 0.75, delta: 0.25, optPrice: 3, pvDividend: nil,
                                       gamma: 0, vega: 3, theta: -3, undPrice: 100))
    let difference = a - b
    #expect(difference.delta == 0.25 && difference.vega == -1 && difference.gamma == 0 && difference.undPrice == 100)
    let scaled = a * 2
    #expect(scaled.impliedVol == 1 && scaled.theta == -2 && scaled.gamma == 0 && scaled.tickAttrib == 0)
}

@Test func forexPair() {
    #expect(Contract.forex("EURUSD").pair == "EURUSD")
}

@Test func tradingSessionsParseAndSkipClosed() {
    var d = ContractDetails(contract: Contract(symbol: "AAPL"), marketName: "", minTick: 0.01, priceMagnifier: 1,
                            longName: "", stockType: "", timeZoneID: "US/Eastern",
                            tradingHours: "20261110:0930-20261110:1600;20261111:CLOSED",
                            liquidHours: "20261110:0930-20261110:1600;20261111:CLOSED")
    #expect(d.tradingSessions == [TradingSession(start: utcDate(14, 30), end: utcDate(21))])
    #expect(d.liquidSessions.count == 1)
    d.timeZoneID = "Nowhere/Land"
    #expect(d.tradingSessions == [])
    d.timeZoneID = ""; d.tradingHours = ""
    #expect(d.tradingSessions == [])
}

@Test func liveFillTimeIsArrivalReplayIsExecution() {
    var t = ExecutionTracker()
    let when = Date(timeIntervalSince1970: 1_794_300_000)
    let e = Execution(execID: "e.01.01", time: "20261110 06:56:31", account: "DU1", exchange: "X", side: "BOT",
                      shares: 1, price: 2, permID: 3, clientID: 4, orderID: 5, liquidation: 0, cumulativeQuantity: 1,
                      averagePrice: 2, orderRef: "", lastLiquidity: 0, pendingPriceRevision: false,
                      date: utcDate(6, 56, 31))
    let report = CommissionReport(execID: "e.01.01", commission: 1, currency: "USD")
    _ = t.apply(.execDetails(requestID: -1, contract: Contract(symbol: "AAPL"), execution: e), receivedAt: when)
    #expect(t.apply(.commissionReport(report)).first?.time == when)
    var replay = ExecutionTracker()
    _ = replay.apply(.execDetails(requestID: 7, contract: Contract(symbol: "AAPL"), execution: e))
    #expect(replay.apply(.commissionReport(report)).first?.time == utcDate(6, 56, 31))
}

@Test func timeRangeSkipsPastPointsAndYieldsEach() async throws {
    let start = Date().addingTimeInterval(-1), end = Date().addingTimeInterval(0.3)
    var points: [Date] = []
    for await t in IBClient.timeRange(from: start, to: end, every: .milliseconds(50)) {
        #expect(Date() >= t)
        points.append(t)
    }
    #expect(!points.isEmpty && points.count <= 8 && points == points.sorted())
    #expect(points.allSatisfy { $0 >= start.addingTimeInterval(1 - 0.001) && $0 <= end })   // none of the past
    for (a, b) in zip(points, points.dropFirst()) { #expect(abs(b.timeIntervalSince(a) - 0.05) < 0.001) }
}

@Test func aStoppedConsumerEndsTimeRange() async {
    var n = 0
    for await _ in IBClient.timeRange(from: Date(), to: Date().addingTimeInterval(60), every: .milliseconds(20)) {
        n += 1
        break
    }
    #expect(n == 1)   // the loop returned at once instead of waiting a minute
}

@Test func cancellingWaitThrows() async {
    let task = Task { try await IBClient.wait(until: Date().addingTimeInterval(10)) }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
}

@Test func zoneFormNeedsAFullTime() {
    #expect(IBDate.parse("20261110 16 US/Eastern") == nil)
    #expect(IBDate.parse("1234 5678 UTC") == nil)
}
