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
}

@Test func historyWithoutUpdatesEndsWithoutCancel() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.historicalBars(Contract(symbol: "AAPL"), duration: "1 D", barSize: "5 mins")
    let sent = try await gateway.waitForSent(6)
    #expect(sent[5][0] == "20")
    var f = batch; f[1] = sent[5][1]
    gateway.feed(f)
    let (_, result) = take(0, stream)
    let events = try await within2s { try await result.value }
    guard events.count == 1, case .history(let bars) = events[0] else { Issue.record("expected one history"); return }
    #expect(bars.count == 2)
    #expect(try await gateway.waitForSent(6).allSatisfy { $0.first != "25" })
    #expect(await client.requestStreamCount == 0)
}

@Test func keepUpToDateStreamsUpdatesAndCancels() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.historicalBars(Contract(symbol: "AAPL"), duration: "1 D", barSize: "5 mins",
                                                 keepUpToDate: true)
    let id = try await gateway.waitForSent(6)[5][1]
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
    #expect(try await gateway.waitForSent(7)[6] == ["25", "1", id])
}

@Test func historyPermissionErrorIsTyped() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.historicalBars(Contract(symbol: "AAPL"), duration: "1 D", barSize: "5 mins")
    let id = try await gateway.waitForSent(6)[5][1]
    let text = "Historical Market Data Service error message:No market data permissions for NASDAQ STK"
    gateway.feed(["4", "2", id, "162", text, ""])
    let (_, result) = take(0, stream)
    await #expect(throws: IBClientError.noMarketDataPermission(code: 162, text: text)) {
        _ = try await within2s { try await result.value }
    }
}
