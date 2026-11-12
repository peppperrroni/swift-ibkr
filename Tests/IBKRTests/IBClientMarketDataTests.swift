import Foundation
import Testing
@testable import IBKR

private func connected(_ gateway: FakeGateway) async throws -> IBClient {
    let client = IBClient(connector: gateway.connector)
    try await within2s { try await client.connect(clientID: 7) }
    return client
}

@Test func marketDataYieldsTicks() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.marketData(Contract(symbol: "AAPL"))
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    let id = sent[FakeGateway.syncFrames][2]
    #expect(sent[FakeGateway.syncFrames][0] == "1")
    let (reader, result) = take(3, stream)
    gateway.feed(["1", "6", id, "1", "351.5", "200", "0"])
    gateway.feed(["2", "6", id, "0", "300"])
    gateway.feed(["58", "1", id, "1"])
    #expect(try await within2s { try await result.value } == [
        .price(.bid, price: d("351.5"), size: d("200")), .size(.bidSize, d("300")), .dataType(.realtime)])
    reader.cancel()   // the consumer stops
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 2)[FakeGateway.syncFrames + 1] == ["2", "2", id])
}

@Test func marketDataYieldsGreeksAndParameters() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.marketData(Contract(symbol: "AAPL"))
    let id = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames][2]
    let (_, result) = take(2, stream)
    gateway.feed(["21", id, "13", "1", "0.25", "0.55", "6.1", "0", "0.03", "0.12", "-0.05", "187.2"])
    gateway.feed(["81", id, "0.01", "9c0001", "3"])
    #expect(try await within2s { try await result.value } == [
        .optionComputation(TickField(rawValue: 13), OptionComputation(
            tickAttrib: 1, impliedVol: d("0.25"), delta: d("0.55"), optPrice: d("6.1"), pvDividend: 0, gamma: d("0.03"),
            vega: d("0.12"), theta: d("-0.05"), undPrice: d("187.2"))),
        .requestParameters(minTick: d("0.01"), bboExchange: "9c0001", snapshotPermissions: 3)])
}

@Test func marketDataSendsGenericTicks() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    _ = try await client.marketData(Contract(symbol: "AAPL"), genericTicks: [100, 101, 104])
    let f = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames]
    #expect(f[16] == "100,101,104" && f[17] == "0" && f[18] == "0")
}

@Test func snapshotEndsWithoutCancel() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.marketData(Contract(symbol: "AAPL"), snapshot: true, regulatorySnapshot: true)
    let f = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames]
    #expect(f[17] == "1" && f[18] == "1")
    let id = f[2]
    gateway.feed(["1", "6", id, "1", "351.5", "200", "0"])
    gateway.feed(["57", "1", id])
    let (_, result) = take(0, stream)
    #expect(try await within2s { try await result.value } == [.price(.bid, price: d("351.5"), size: d("200"))])
    try await Task.sleep(for: .milliseconds(50))
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1).count == FakeGateway.syncFrames + 1)
    #expect(await client.requestStreamCount == 0)
}

@Test func rerouteLeavesTheStreamOpen() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.marketData(Contract(symbol: "AAPL"))
    let id = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames][2]
    let (_, result) = take(1, stream)
    gateway.feed(["91", id, "12087792", "IDEALPRO"])
    gateway.feed(["1", "6", id, "1", "351.5", "200", "0"])
    #expect(try await within2s { try await result.value } == [.price(.bid, price: d("351.5"), size: d("200"))])
}

@Test func delayedNoticeKeepsTheStreamAndMapsFields() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    try await client.setMarketDataType(.delayed)
    let stream = try await client.marketData(Contract(symbol: "AAPL"))
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 2)
    #expect(sent[FakeGateway.syncFrames] == ["59", "1", "3"])
    let id = sent[FakeGateway.syncFrames + 1][2]
    let (_, result) = take(1, stream)
    gateway.feed(["4", "2", id, "10167", "Requested market data is not subscribed. Displaying delayed market data.", ""])
    gateway.feed(["1", "6", id, "66", "351.4", "100", "0"])
    let tick = try await within2s { try await result.value }
    #expect(tick == [.price(TickField(rawValue: 66), price: d("351.4"), size: d("100"))])
    guard case .price(let f, _, _)? = tick.first else { Issue.record("not a price"); return }
    #expect(f.live == .bid)
}

@Test func noPermissionIsTyped() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.marketData(Contract(symbol: "AAPL"))
    let id = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames][2]
    gateway.feed(["4", "2", id, "354", "Requested market data is not subscribed.", ""])
    let (_, result) = take(0, stream)
    await #expect(throws: IBClientError.noMarketDataPermission(code: 354, text: "Requested market data is not subscribed.")) {
        _ = try await within2s { try await result.value }
    }
    // IB keeps a refused subscription open, so the refusal sends the cancel.
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 2)[FakeGateway.syncFrames + 1] == ["2", "2", id])
}

@Test func otherFatalStaysIB() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.marketData(Contract(symbol: "AAPL"))
    let id = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames][2]
    gateway.feed(["4", "2", id, "200", "No security definition", ""])
    let (_, result) = take(0, stream)
    await #expect(throws: IBClientError.ib(code: 200, text: "No security definition")) {
        _ = try await within2s { try await result.value }
    }
    try await Task.sleep(for: .milliseconds(50))   // room for a wrong cancel
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1).count == FakeGateway.syncFrames + 1)
}

@Test func realTimeBarsStreamAndCancel() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.realTimeBars(Contract(symbol: "AAPL"), whatToShow: "MIDPOINT", rth: false)
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    let id = sent[FakeGateway.syncFrames][2]
    #expect(Array(sent[FakeGateway.syncFrames].suffix(4)) == ["5", "MIDPOINT", "0", ""])
    let (reader, result) = take(1, stream)
    gateway.feed(["50", "3", id, "1794321000", "351.0", "352.0", "350.5", "351.5", "1000", "351.2", "42"])
    #expect(try await within2s { try await result.value } == [
        Bar(time: Date(timeIntervalSince1970: 1794321000), open: d("351.0"), high: d("352.0"), low: d("350.5"),
            close: d("351.5"), volume: 1000, average: d("351.2"), count: 42)])
    reader.cancel()
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 2)[FakeGateway.syncFrames + 1] == ["51", "1", id])
}

@Test func realTimeBarsRefusalIsTyped() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.realTimeBars(Contract(symbol: "AAPL"))
    let id = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames][2]
    let text = "Invalid Real-time Query:No market data permissions for NYSE STK"
    gateway.feed(["4", "2", id, "420", text, ""])
    let (_, result) = take(0, stream)
    await #expect(throws: IBClientError.noMarketDataPermission(code: 420, text: text)) {
        _ = try await within2s { try await result.value }
    }
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 2)[FakeGateway.syncFrames + 1] == ["51", "1", id])
}

@Test func depthExchangesAnswers() async throws {
    let gateway = FakeGateway()
    gateway.onRequest = { $0 == ["82"] ? [["80", "2", "ISLAND", "STK", "NASDAQ", "Deep2", "1", "NYSE", "STK", "NYSE", "Deep", "2147483647"]] : [] }
    let client = try await connected(gateway)
    let got = try await within2s { try await client.depthExchanges() }
    #expect(got == [
        DepthMarketDataDescription(exchange: "ISLAND", secType: "STK", listingExchange: "NASDAQ", serviceDataType: "Deep2", aggGroup: 1),
        DepthMarketDataDescription(exchange: "NYSE", secType: "STK", listingExchange: "NYSE", serviceDataType: "Deep", aggGroup: nil)])
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames] == ["82"])
    #expect(await client.requestStreamCount == 0)
}

@Test func smartComponentsAnswers() async throws {
    let gateway = FakeGateway()
    gateway.onRequest = { $0.first == "83" ? [["82", $0[1], "1", "0", "NYSE", "N"]] : [] }
    let client = try await connected(gateway)
    let got = try await within2s { try await client.smartComponents("9c0001") }
    #expect(got == [SmartComponent(bitNumber: 0, exchange: "NYSE", exchangeLetter: "N")])
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames]
    #expect(sent.count == 3 && sent[0] == "83" && sent[2] == "9c0001")
}

@Test func smartComponentsFailsOnItsError() async throws {
    let gateway = FakeGateway()
    gateway.onRequest = { $0.first == "83" ? [["4", "2", $0[1], "200", "No security definition has been found for the request", ""]] : [] }
    let client = try await connected(gateway)
    await #expect(throws: IBClientError.ib(code: 200, text: "No security definition has been found for the request")) {
        _ = try await within2s { try await client.smartComponents("9c0001") }
    }
    #expect(await client.requestStreamCount == 0)
}

/// Forwards `stream` into `seen` until the stream ends or `reader` is cancelled, so the reader keeps the stream.
private func reading<T: Sendable>(_ stream: AsyncThrowingStream<T, any Error>)
    -> (reader: Task<Void, Never>, seen: AsyncThrowingStream<T, any Error>) {
    let (seen, out) = AsyncThrowingStream.makeStream(of: T.self, throwing: (any Error).self)
    let reader = Task { do { for try await t in stream { out.yield(t) }; out.finish() } catch { out.finish(throwing: error) } }
    return (reader, seen)
}

private func noStreamsLeft(_ client: IBClient) async throws {
    try await within2s { while await client.requestStreamCount != 0 { try await Task.sleep(for: .milliseconds(5)) } }
}

private let aapl = Contract(symbol: "AAPL")

@Test func tickersYieldWholeTickers() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.tickers(aapl)
    let f = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames]
    #expect(f[0] == "1" && f[16] == "")
    let id = f[2]
    gateway.feed(["1", "6", id, "1", "351.5", "200", "0"])
    gateway.feed(["2", "6", id, "0", "300"])
    let (reader, seen) = reading(stream)
    let ticker = try await within2s { try await seen.first { $0.bidSize == d("300") } }
    #expect(ticker?.bid == d("351.5"))
    reader.cancel()
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 2)[FakeGateway.syncFrames + 1] == ["2", "2", id])
}

@Test func tickersWithDepthCarryTheBookAndCancelBoth() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.tickers(aapl, depthRows: 5)
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 2)
    #expect(sent[FakeGateway.syncFrames][0] == "10" && sent[FakeGateway.syncFrames + 1][0] == "1")
    let (did, qid) = (sent[FakeGateway.syncFrames][2], sent[FakeGateway.syncFrames + 1][2])
    gateway.feed(["12", "1", did, "0", "0", "1", "351.5", "100"])
    gateway.feed(["1", "6", qid, "1", "351.5", "200", "0"])
    let (reader, seen) = reading(stream)
    let ticker = try await within2s { try await seen.first { $0.depth.bids.count == 1 && $0.bid != nil } }
    #expect(ticker != nil)
    reader.cancel()
    let cancels = try await gateway.waitForSent(FakeGateway.syncFrames + 4).suffix(2)
    #expect(Set(cancels) == [["2", "2", qid], ["11", "1", did, "1"]])
    #expect(await client.requestStreamCount == 0)
}

@Test func tickersEndWithTheirDepthRefusal() async throws {
    guard let frame = try recording("liveMarketData").first(where: { $0.first == "4" && $0.count > 3 && $0[3] == "2152" }) else {
        Issue.record("no 2152 frame"); return
    }
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.tickers(aapl, depthRows: 5)
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 2)
    let (did, qid) = (sent[FakeGateway.syncFrames][2], sent[FakeGateway.syncFrames + 1][2])
    gateway.feed(replacing(frame, [2: did]))
    await #expect(throws: IBClientError.noMarketDataPermission(code: 2152, text: frame[4])) {
        _ = try await within2s { try await stream.first { _ in false } }
    }
    let cancels = try await gateway.waitForSent(FakeGateway.syncFrames + 4).suffix(2)
    #expect(Set(cancels) == [["2", "2", qid], ["11", "1", did, "1"]])
    try await noStreamsLeft(client)
}

@Test func tickersRefuseABagBook() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    await #expect(throws: IBClientError.encoding(.unsupported("secType BAG"))) {
        _ = try await client.tickers(bagContract, depthRows: 5)
    }
    try await Task.sleep(for: .milliseconds(50))   // room for a wrong request or cancel
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames).count == FakeGateway.syncFrames)
    #expect(await client.requestStreamCount == 0)
}

@Test func tickersForReturnsSnapshotsInOrder() async throws {
    let gateway = FakeGateway()
    gateway.onRequest = { f in
        f.first == "1" ? [["1", "6", f[2], "1", f[4] == "AAPL" ? "351.5" : "420.1", "100", "0"], ["57", "1", f[2]]] : []
    }
    let client = try await connected(gateway)
    let got = try await within2s {
        try await client.tickers(for: [Contract(symbol: "AAPL"), Contract(symbol: "MSFT")])
    }
    #expect(got.map(\.contract.symbol) == ["AAPL", "MSFT"])
    #expect(got.map(\.bid) == [d("351.5"), d("420.1")])
    try await Task.sleep(for: .milliseconds(50))   // room for a wrong cancel
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 2).dropFirst(FakeGateway.syncFrames)
    #expect(sent.count == 2 && sent.allSatisfy { $0[0] == "1" && $0[17] == "1" && $0[18] == "0" })
    #expect(await client.requestStreamCount == 0)
}

@Test func tickersForFailsOnAnErrorAndCancelsTheRest() async throws {
    let gateway = FakeGateway()
    gateway.onRequest = { f in
        f.first == "1" && f[4] == "AAPL" ? [["4", "2", f[2], "200", "No security definition", ""]] : []
    }
    let client = try await connected(gateway)
    await #expect(throws: IBClientError.ib(code: 200, text: "No security definition")) {
        _ = try await within2s { try await client.tickers(for: [Contract(symbol: "AAPL"), Contract(symbol: "MSFT")]) }
    }
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 3)
    #expect(sent[FakeGateway.syncFrames + 2] == ["2", "2", sent[FakeGateway.syncFrames + 1][2]])
    try await noStreamsLeft(client)
}

@Test func tickersForStopsWhatItOpenedOnAnEncodingError() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    await #expect(throws: IBClientError.encoding(.nonASCII(field: "é"))) {
        _ = try await client.tickers(for: [Contract(symbol: "AAPL"), Contract(symbol: "é")])
    }
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 2)
    #expect(sent[FakeGateway.syncFrames + 1] == ["2", "2", sent[FakeGateway.syncFrames][2]])
    try await noStreamsLeft(client)
}

@Test func tickersForCancelledSendsEveryCancel() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let call = Task { try await client.tickers(for: [Contract(symbol: "AAPL"), Contract(symbol: "MSFT")]) }
    let opened = try await gateway.waitForSent(FakeGateway.syncFrames + 2).dropFirst(FakeGateway.syncFrames)
    call.cancel()
    await #expect(throws: IBClientError.cancelled) { _ = try await within2s { try await call.value } }
    let cancels = try await gateway.waitForSent(FakeGateway.syncFrames + 4).suffix(2)
    #expect(Set(cancels) == Set(opened.map { ["2", "2", $0[2]] }))
    try await noStreamsLeft(client)
}
