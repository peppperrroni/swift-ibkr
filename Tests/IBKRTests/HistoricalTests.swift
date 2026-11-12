import Foundation
import Testing
@testable import IBKR

private let aapl = ["0", "AAPL", "STK", "", "0.0", "", "", "SMART", "", "USD", "", ""]

private func connected(_ gateway: FakeGateway) async throws -> IBClient {
    let client = IBClient(connector: gateway.connector)
    try await within2s { try await client.connect(clientID: 7) }
    return client
}

private let batch = ["17", "9", "20261110  09:30:00", "20261110  16:00:00", "2",
    "1794321000", "351.0", "352.0", "350.5", "351.5", "1000", "351.2", "42",
    "20261110", "350.0", "353.0", "349.0", "352.5", "90000", "351.9", "8000"]

private let scheduleFrame = ["106", "9", "20261106-09:30:00", "20261112-16:00:00", "US/Eastern", "2",
    "20261111-09:30:00", "20261111-16:00:00", "20261111", "20261112-09:30:00", "20261112-16:00:00", "20261112"]
private let expectedSchedule = HistoricalSchedule(
    startDateTime: "20261106-09:30:00", endDateTime: "20261112-16:00:00", timeZone: "US/Eastern",
    sessions: [HistoricalSession(startDateTime: "20261111-09:30:00", endDateTime: "20261111-16:00:00", refDate: "20261111"),
               HistoricalSession(startDateTime: "20261112-09:30:00", endDateTime: "20261112-16:00:00", refDate: "20261112")])

@Suite struct HistoricalCodecTests {
    @Test func historicalRequestEncodes() throws {
        let end = Date(timeIntervalSince1970: 1794344400)   // 2026-11-10 21:00:00 UTC
        let c = Contract(symbol: "AAPL")
        #expect(try IBRequest.historicalData(requestID: 9, contract: c, end: end, barSize: "5 mins", duration: "1 D",
                                             rth: true, whatToShow: "TRADES", keepUpToDate: false).body()
            == body(["20", "9"] + aapl + ["0", "20261110-21:00:00", "5 mins", "1 D", "1", "TRADES", "2", "0", ""]))
        #expect(try IBRequest.historicalData(requestID: 9, contract: c, end: nil, barSize: "5 mins", duration: "1 D",
                                             rth: false, whatToShow: "MIDPOINT", keepUpToDate: true).body()
            == body(["20", "9"] + aapl + ["0", "", "5 mins", "1 D", "0", "MIDPOINT", "2", "1", ""]))
        #expect(try IBRequest.cancelHistoricalData(requestID: 9).body() == body("25", "1", "9"))
    }

    @Test func historicalBagSendsLegs() throws {
        #expect(try IBRequest.historicalData(requestID: 9, contract: bagContract, end: nil, barSize: "1 day", duration: "5 D",
                                             rth: true, whatToShow: "TRADES", keepUpToDate: false).body()
            == body(["20", "9"] + bagBlock + ["0", "", "1 day", "5 D", "1", "TRADES", "2"] + bagLegs + ["0", ""]))
    }

    @Test func scheduleSendsFormatDateOne() throws {
        #expect(try IBRequest.historicalData(requestID: 9, contract: Contract(symbol: "AAPL"), end: nil, barSize: "1 day",
                                             duration: "5 D", rth: true, whatToShow: "SCHEDULE", keepUpToDate: false).body()
            == body(["20", "9"] + aapl + ["0", "", "1 day", "5 D", "1", "SCHEDULE", "1", "0", ""]))
    }

    @Test func historicalScheduleDecodes() {
        guard case .historicalSchedule(9, let s) = IBDecoder.decode(body(scheduleFrame)) else { Issue.record("not 106"); return }
        #expect(s == expectedSchedule)
        var f = scheduleFrame; f[5] = "-1"
        guard case .malformed = IBDecoder.decode(body(f)) else { Issue.record("not malformed"); return }
    }

    @Test func historicalDataDecodes() {
        guard case .historicalData(let id, let bars) = IBDecoder.decode(body(batch)) else { Issue.record("not 17"); return }
        #expect(id == 9 && bars.count == 2)
        #expect(bars[0].time == Date(timeIntervalSince1970: 1794321000))
        #expect(bars[0].open == d("351.0") && bars[0].high == d("352.0") && bars[0].low == d("350.5"))
        #expect(bars[0].close == d("351.5") && bars[0].volume == 1000 && bars[0].average == d("351.2") && bars[0].count == 42)
        #expect(bars[1].time == Date(timeIntervalSince1970: 1794268800))   // 2026-11-10 00:00 UTC
    }

    @Test func historicalUpdateDecodes() {
        let m = IBDecoder.decode(body("90", "9", "42", "1794321300", "351.5", "351.7", "351.9", "351.4", "351.6", "300"))
        guard case .historicalDataUpdate(9, let bar) = m else { Issue.record("not 90"); return }
        #expect(bar.open == d("351.5") && bar.close == d("351.7") && bar.high == d("351.9") && bar.low == d("351.4"))
        #expect(bar.count == 42 && bar.volume == 300 && bar.average == d("351.6"))
    }

    @Test func negativeBarCountIsMalformed() {
        var f = batch; f[4] = "-1"
        guard case .malformed = IBDecoder.decode(body(f)) else { Issue.record("not malformed"); return }
    }

    @Test func signedDayTimeIsMalformed() {
        var f = batch; f[5] = "-1234567"
        guard case .malformed = IBDecoder.decode(body(f)) else { Issue.record("not malformed"); return }
    }

    @Test func badBarTimeIsMalformed() {
        var f = batch; f[5] = "yesterday"
        guard case .malformed = IBDecoder.decode(body(f)) else { Issue.record("not malformed"); return }
    }
    @Test func historicalTicksRequestEncodes() throws {
        #expect(try IBRequest.historicalTicks(requestID: 7, contract: Contract(symbol: "AAPL"),
                                              start: Date(timeIntervalSince1970: 1794321000), end: nil, count: 100,
                                              whatToShow: "TRADES", rth: true, ignoreSize: false).body()
            == body(["96", "7"] + aapl + ["0", "20261110-14:30:00", "", "100", "TRADES", "1", "0", ""]))
    }

    @Test func historicalTicksDecode() {
        let t = Date(timeIntervalSince1970: 1794321000)
        #expect(IBDecoder.decode(body("96", "7", "2", "1794321000", "0", "351.5", "0", "1794321001", "0", "351.55", "0", "1"))
            == .historicalTicks(requestID: 7, [.midPoint(time: t, price: d("351.5")), .midPoint(time: t + 1, price: d("351.55"))], done: true))
        #expect(IBDecoder.decode(body("97", "7", "1", "1794321000", "3", "351.5", "351.6", "100", "200", "1"))
            == .historicalTicks(requestID: 7, [.bidAsk(time: t, bidPrice: d("351.5"), askPrice: d("351.6"), bidSize: 100, askSize: 200)], done: true))
        #expect(IBDecoder.decode(body("98", "7", "1", "1794321000", "2", "351.5", "100", "ISLAND", "T", "0"))
            == .historicalTicks(requestID: 7, [.trade(time: t, price: d("351.5"), size: 100, exchange: "ISLAND", conditions: "T", pastLimit: false, unreported: true)], done: false))
        guard case .malformed = IBDecoder.decode(body("98", "7", "-1", "0")) else { Issue.record("not malformed"); return }
    }
}

@Test func historyWithoutUpdatesEndsWithoutCancel() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.historicalBars(Contract(symbol: "AAPL"), duration: "1 D", barSize: "5 mins")
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    #expect(sent[FakeGateway.syncFrames][0] == "20")
    var f = batch; f[1] = sent[FakeGateway.syncFrames][1]
    gateway.feed(f)
    let (_, result) = take(0, stream)
    let events = try await within2s { try await result.value }
    guard events.count == 1, case .history(let bars) = events[0] else { Issue.record("expected one history"); return }
    #expect(bars.count == 2)
    try await Task.sleep(for: .milliseconds(50))   // room for a wrong cancel
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1).count == FakeGateway.syncFrames + 1)
    #expect(await client.requestStreamCount == 0)
}

@Test func keepUpToDateStreamsUpdatesAndCancels() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.historicalBars(Contract(symbol: "AAPL"), duration: "1 D", barSize: "5 mins",
                                                 keepUpToDate: true)
    let id = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames][1]
    var f = batch; f[1] = id
    gateway.feed(f)
    gateway.feed(["90", id, "42", "1794321300", "351.5", "351.7", "351.9", "351.4", "351.6", "300"])
    gateway.feed(["90", id, "43", "1794321300", "351.5", "351.8", "351.9", "351.4", "351.6", "310"])
    let (reader, result) = take(3, stream)
    let events = try await within2s { try await result.value }
    guard case .history = events[0], case .update(let a) = events[1], case .update(let b) = events[2] else {
        Issue.record("wrong sequence: \(events)"); return
    }
    #expect(a.close == d("351.7") && b.close == d("351.8"))
    reader.cancel()
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 2)[FakeGateway.syncFrames + 1] == ["25", "1", id])
}

@Test func historyPermissionErrorIsTyped() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.historicalBars(Contract(symbol: "AAPL"), duration: "1 D", barSize: "5 mins")
    let id = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames][1]
    let text = "Historical Market Data Service error message:No market data permissions for NASDAQ STK"
    gateway.feed(["4", "2", id, "162", text, ""])
    let (_, result) = take(0, stream)
    await #expect(throws: IBClientError.noMarketDataPermission(code: 162, text: text)) {
        _ = try await within2s { try await result.value }
    }
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 2)[FakeGateway.syncFrames + 1] == ["25", "1", id])
}

@Test func historicalScheduleAnswers() async throws {
    let gateway = FakeGateway()
    gateway.onRequest = { f in
        guard f.first == "20" else { return [] }
        var r = scheduleFrame; r[1] = f[1]; return [r]
    }
    let client = try await connected(gateway)
    let got = try await within2s { try await client.historicalSchedule(Contract(symbol: "AAPL"), days: 5) }
    #expect(got == expectedSchedule)
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames]
    #expect(Array(sent[15...22]) == ["", "1 day", "5 D", "1", "SCHEDULE", "1", "0", ""])
    try await Task.sleep(for: .milliseconds(50))   // room for a wrong cancel
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1).count == FakeGateway.syncFrames + 1)
    #expect(await client.requestStreamCount == 0)
}

@Test func historicalScheduleRefusalIsTyped() async throws {
    let text = "Historical Market Data Service error message:No market data permissions for NYSE STK"
    let gateway = FakeGateway()
    gateway.onRequest = { $0.first == "20" ? [["4", "2", $0[1], "162", text, ""]] : [] }
    let client = try await connected(gateway)
    await #expect(throws: IBClientError.noMarketDataPermission(code: 162, text: text)) {
        _ = try await within2s { try await client.historicalSchedule(Contract(symbol: "AAPL"), days: 5) }
    }
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 2)
    #expect(Array(sent[FakeGateway.syncFrames + 1].prefix(2)) == ["25", "1"])
    #expect(await client.requestStreamCount == 0)
}

@Test func historicalBarsRefuseScheduleBeforeSending() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    await #expect(throws: IBClientError.encoding(.unsupported("whatToShow SCHEDULE"))) {
        _ = try await client.historicalBars(Contract(symbol: "AAPL"), duration: "5 D", barSize: "1 day", whatToShow: "SCHEDULE")
    }
    try await Task.sleep(for: .milliseconds(50))
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames).count == FakeGateway.syncFrames)
    #expect(await client.requestStreamCount == 0)
}

@Test func historicalTicksCollectUntilDone() async throws {
    let gateway = FakeGateway()
    gateway.onRequest = { f in
        guard f.first == "96" else { return [] }
        return [["98", f[1], "1", "1794321000", "0", "351.5", "100", "ISLAND", "", "0"],
                ["98", f[1], "1", "1794321001", "2", "351.6", "50", "NYSE", "T", "1"]]
    }
    let client = try await connected(gateway)
    let t = Date(timeIntervalSince1970: 1794321000)
    let got = try await within2s { try await client.historicalTicks(Contract(symbol: "AAPL"), start: t, count: 2) }
    #expect(got == [.trade(time: t, price: d("351.5"), size: 100, exchange: "ISLAND", conditions: "", pastLimit: false, unreported: false),
                    .trade(time: t + 1, price: d("351.6"), size: 50, exchange: "NYSE", conditions: "T", pastLimit: false, unreported: true)])
    try await Task.sleep(for: .milliseconds(50))   // room for a wrong cancel
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1).count == FakeGateway.syncFrames + 1)
    #expect(await client.requestStreamCount == 0)
}

@Test func historicalTicksFailsOnItsError() async throws {
    let gateway = FakeGateway()
    gateway.onRequest = { f in
        f.first == "96" ? [["4", "2", f[1], "162", "Historical Market Data Service error message:HMDS query returned no data", ""]] : []
    }
    let client = try await connected(gateway)
    await #expect(throws: IBClientError.ib(code: 162, text: "Historical Market Data Service error message:HMDS query returned no data")) {
        _ = try await within2s { try await client.historicalTicks(Contract(symbol: "AAPL"), count: 2) }
    }
    try await Task.sleep(for: .milliseconds(50))
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1).count == FakeGateway.syncFrames + 1)
    #expect(await client.requestStreamCount == 0)
}
