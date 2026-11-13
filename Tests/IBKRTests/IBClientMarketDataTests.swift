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
    let messages = await client.messages()
    let stream = try await client.marketData(Contract(symbol: "AAPL"))
    let id = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames][2]
    let (_, result) = take(1, stream)
    gateway.feed(["91", id, "12087792", "IDEALPRO"])
    gateway.feed(["1", "6", id, "1", "351.5", "200", "0"])
    #expect(try await within2s { try await result.value } == [.price(.bid, price: d("351.5"), size: d("200"))])
    let reroute = try await within2s { await messages.first { if case .rerouteMarketData = $0 { true } else { false } } }
    #expect(reroute == .rerouteMarketData(requestID: Int(id)!, conID: 12087792, exchange: "IDEALPRO"))
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
    guard case .price(let f, _, _, _)? = tick.first else { Issue.record("not a price"); return }
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

/// Every request whose payload gained a field still ends (or throws) on its own IB error.
@Test func changedRequestsFailOnTheirError() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let text = "No security definition has been found"
    gateway.onRequest = { f in
        switch f[0] {
        case "1", "9", "10", "50": [ibError(f[2], "200", text)]   // the reqId follows a version
        case "20", "87", "88", "96", "97": [ibError(f[1], "200", text)]
        default: []
        }
    }
    let ib = IBClientError.ib(code: 200, text: text)
    let options = [TagValue(tag: "a", value: "1")]
    let c: Contract = { var c = Contract(symbol: "AAPL"); c.includeExpired = true; return c }()
    func drain<E: Sendable>(_ s: AsyncThrowingStream<E, any Error>) async throws {
        try await within2s { for try await _ in s {} }
    }
    await #expect(throws: ib) { try await drain(try await client.marketData(c, options: options)) }
    await #expect(throws: ib) {
        try await drain(try await client.historicalBars(c, duration: "1 D", barSize: "5 mins", keepUpToDate: true,
                                                        options: options))
    }
    await #expect(throws: ib) { try await drain(try await client.realTimeBars(c, options: options)) }
    await #expect(throws: ib) { try await drain(try await client.marketDepth(c, rows: 5, options: options)) }
    await #expect(throws: ib) { try await drain(try await client.tickByTick(c, .last, count: 10, ignoreSize: true)) }
    await #expect(throws: ib) { _ = try await within2s { try await client.historicalTicks(c, count: 10, options: options) } }
    await #expect(throws: ib) { _ = try await within2s { try await client.contractDetails(c) } }
    await #expect(throws: ib) { _ = try await within2s { try await client.headTimeStamp(c) } }
    await #expect(throws: ib) { _ = try await within2s { try await client.histogramData(c, period: "3 days") } }
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 9)
    #expect(sent[FakeGateway.syncFrames].last == "a=1;")
    #expect(sent[FakeGateway.syncFrames + 4].suffix(3) == ["Last", "10", "1"])
}

@Test func tickersSendTheirOptionsWithTheMarketDataRequestOnly() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.tickers(Contract(symbol: "AAPL"), depthRows: 5, options: [TagValue(tag: "a", value: "1")])
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 2)
    #expect(sent[FakeGateway.syncFrames].first == "10" && sent[FakeGateway.syncFrames].last == "")
    #expect(sent[FakeGateway.syncFrames + 1].first == "1" && sent[FakeGateway.syncFrames + 1].last == "a=1;")
    withExtendedLifetime(stream) {}
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

/// A `timeBars` consumer stopping stops `trades()`, then `tickers`, which sends IB's cancel.
@Test func stoppingTimeBarsCancelsTheTickersRequest() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.tickers(aapl)
    let id = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames][2]
    let (timer, ticking) = AsyncStream<Date>.makeStream()   // never fires and never ends by itself
    let reader = Task { for try await _ in stream.trades().timeBars(timer: timer) {} }
    gateway.feed(["1", "6", id, "4", "351.5", "200", "0"])
    try await Task.sleep(for: .milliseconds(50))
    reader.cancel()
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 2)[FakeGateway.syncFrames + 1] == ["2", "2", id])
    withExtendedLifetime(ticking) {}
}

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

@Test func tickersForAlreadyCancelledSendsNothing() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let call = Task { () async throws -> [Ticker] in
        withUnsafeCurrentTask { $0?.cancel() }
        return try await client.tickers(for: [Contract(symbol: "AAPL"), Contract(symbol: "MSFT")])
    }
    await #expect(throws: IBClientError.cancelled) { _ = try await within2s { try await call.value } }
    try await Task.sleep(for: .milliseconds(50))
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames).count == FakeGateway.syncFrames)
    #expect(await client.requestStreamCount == 0)
}

@Test func tickersForNeedsAConnection() async throws {
    let client = IBClient(connector: FakeGateway().connector)
    await #expect(throws: IBClientError.notConnected) { _ = try await client.tickers(for: []) }
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

@Test func tickersStampTimeAndResetPerUpdate() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.tickers(aapl)
    let id = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames][2]
    let (reader, seen) = reading(stream)
    gateway.feed(["1", "6", id, "1", "351.5", "200", "0"])
    let first = try #require(try await within2s { try await seen.first { _ in true } })
    gateway.feed(["2", "6", id, "0", "300"])   // fed after the first was read: one update per element
    let second = try #require(try await within2s { try await seen.first { _ in true } })
    #expect(first.ticks.map(\.field) == [.bid] && second.ticks.map(\.field) == [.bidSize])
    let (t1, t2) = (try #require(first.time), try #require(second.time))
    #expect(t2 >= t1 && second.ticks.first?.time == t2)
    reader.cancel()
}

@Test func tickersFoldTickByTickAndCancelIt() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.tickers(aapl, tickByTick: .bidAsk)
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 2)
    #expect(sent[FakeGateway.syncFrames][0] == "1" && sent[FakeGateway.syncFrames + 1][0] == "97")
    #expect(sent[FakeGateway.syncFrames + 1].suffix(3) == ["BidAsk", "0", "0"])
    let (qid, tid) = (sent[FakeGateway.syncFrames][2], sent[FakeGateway.syncFrames + 1][1])
    let (reader, seen) = reading(stream)
    gateway.feed(["99", tid, "3", "1794321000", "351.4", "351.6", "300", "200", "0"])
    let ticker = try await within2s { try await seen.first { _ in true } }
    #expect(ticker?.bid == d("351.4") && ticker?.ask == d("351.6") && ticker?.tickByTicks.count == 1)
    reader.cancel()
    let cancels = try await gateway.waitForSent(FakeGateway.syncFrames + 4).suffix(2)
    #expect(Set(cancels) == [["2", "2", qid], ["98", tid]])
    try await noStreamsLeft(client)
}

@Test func tickersStopWhatTheyOpenedWhenTickByTickIsRefused() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    await #expect(throws: IBClientError.encoding(.unsupported("secType BAG"))) {
        _ = try await client.tickers(bagContract, tickByTick: .last)
    }
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 2)
    #expect(sent[FakeGateway.syncFrames + 1] == ["2", "2", sent[FakeGateway.syncFrames][2]])
    try await noStreamsLeft(client)
}

@Test func tickersRecordDepthTicksAndReset() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.tickers(aapl, depthRows: 5)
    let did = try await gateway.waitForSent(FakeGateway.syncFrames + 2)[FakeGateway.syncFrames][2]
    let (reader, seen) = reading(stream)
    gateway.feed(["12", "1", did, "0", "0", "1", "351.5", "100"])
    let first = try #require(try await within2s { try await seen.first { _ in true } })
    #expect(first.domTicks.count == 1 && first.depth.bids.count == 1)
    gateway.feed(["4", "2", did, "317", "Market depth data has been RESET. Please empty deep book contents", ""])
    let reset = try #require(try await within2s { try await seen.first { _ in true } })
    #expect(reset.depth == DepthBook())
    // wrapper.py:1681: one delete per removed row, at position 0 with size 0
    let resetTime = try #require(reset.time)   // not nested in #expect: Swift 6.0 rejects a throwing #require there
    #expect(reset.domTicks == [DepthTick(time: resetTime, update: DepthUpdate(
        position: 0, marketMaker: "", operation: .delete, side: .bid, price: d("351.5"), size: 0))])
    reader.cancel()
}

/// Review Focus 1: whatever the consumer skips, the ticks of every update arrive exactly once, in order.
@Test func droppedTickerHandsOnItsTicks() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.tickers(aapl)
    let id = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames][2]
    for p in ["10", "11", "12"] { gateway.feed(["1", "6", id, "4", p, "1", "0"]) }
    gateway.feed(["1", "6", id, "9", "99", "0", "0"])   // the sentinel: a close
    try await Task.sleep(for: .milliseconds(50))   // room for the fold to run ahead, so the reader skips updates
    let ticks = try await within2s {
        var all: [TickData] = []
        for try await t in stream {
            all += t.ticks
            if t.close != nil { break }
        }
        return all
    }
    #expect(ticks.map(\.field) == [.last, .last, .last, .close])
    #expect(ticks.map(\.price) == [10, 11, 12, 99])
}

/// R6: 10225 (bust event) cancels and resends the same request, options included, under the same reqId, and the
/// stream goes on; a batch IB sends after the resend is ignored by `liveHistoricalBars`, as ib_async drops it.
@Test func bustEventResendsUnderTheSameID() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let c = Contract(symbol: "AAPL"), options = [TagValue(tag: "a", value: "1")]
    let realTime = try await client.realTimeBars(c, options: options)
    let live = try await client.liveHistoricalBars(c, duration: "1 D", barSize: "5 mins", options: options)
    let raw = try await client.historicalBars(c, duration: "1 D", barSize: "5 mins", keepUpToDate: true, options: options)
    let n = FakeGateway.syncFrames
    let requests = Array(try await gateway.waitForSent(n + 3)[n...])
    let ids = [requests[0][2], requests[1][1], requests[2][1]]
    let batch = { (id: String) in ["17", id, "", "", "1", "1794321000", "1", "2", "0", "1", "5", "1", "1"] }
    gateway.feed(batch(ids[1]))
    gateway.feed(batch(ids[2]))
    for (i, cancel) in ["51", "25", "25"].enumerated() {
        gateway.feed(ibError(ids[i], "10225", "Bust event occurred, current subscription is deactivated."))
        let sent = try await gateway.waitForSent(n + 5 + 2 * i)
        #expect(sent[n + 3 + 2 * i] == [cancel, "1", ids[i]])
        #expect(sent[n + 4 + 2 * i] == requests[i])
        #expect(requests[i].last == "a=1;")
    }
    gateway.feed(["50", "3", ids[0], "1794321005", "1", "2", "0", "1", "5", "1", "1"])
    for id in ids.suffix(2) {
        gateway.feed(["17", id, "", "", "1", "1794321300", "1", "2", "0", "1", "5", "1", "1"])   // after the resend
        gateway.feed(["90", id, "1", "1794321600", "1", "1", "2", "0", "1", "5"])
    }
    let (_, rtBars) = take(1, realTime)
    let (_, liveLists) = take(2, live)
    let (_, rawEvents) = take(3, raw)
    #expect(try await within2s { try await rtBars.value }.map(\.time) == [Date(timeIntervalSince1970: 1794321005)])
    let lists = try await within2s { try await liveLists.value }
    #expect(lists.map(\.bars.count) == [1, 2] && lists.map(\.hasNewBar) == [true, true])
    let events = try await within2s { try await rawEvents.value }   // the raw stream passes IB's new batch on
    guard events.count == 3, case .history = events[0], case .history = events[1], case .update = events[2] else {
        Issue.record("wrong sequence: \(events)"); return
    }
}

@Test func liveBarSubscriptionsAndBarUpdates() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let updates = await client.barUpdates()
    let aapl = Contract(symbol: "AAPL"), spy = Contract(symbol: "SPY")
    let realTime = try await client.realTimeBars(aapl, whatToShow: "MIDPOINT")
    let live = try await client.liveHistoricalBars(spy, duration: "1 D", barSize: "5 mins")
    let n = FakeGateway.syncFrames
    let sent = try await gateway.waitForSent(n + 2)
    let (rtID, liveID) = (Int(sent[n][2])!, Int(sent[n + 1][1])!)
    #expect(await client.liveBarSubscriptions() == [
        LiveBars(requestID: rtID, contract: aapl, barSize: "5 secs", whatToShow: "MIDPOINT", bars: [], hasNewBar: false),
        LiveBars(requestID: liveID, contract: spy, barSize: "5 mins", whatToShow: "TRADES", bars: [], hasNewBar: false)])
    gateway.feed(["17", "\(liveID)", "", "", "1", "1794321000", "1", "2", "0", "1", "5", "1", "1"])
    gateway.feed(["50", "3", "\(rtID)", "1794321005", "1", "2", "0", "1", "5", "1", "1"])
    gateway.feed(["90", "\(liveID)", "1", "1794321300", "1", "1", "2", "0", "1", "5"])
    let (rtReader, _) = take(0, realTime)
    let (_, liveLists) = take(2, live)
    _ = try await within2s { try await liveLists.value }
    let got = try await within2s {
        var got: [LiveBars] = []
        for await u in updates { got.append(u); if got.count == 2 { break } }
        return got
    }
    #expect(got.map(\.requestID) == [rtID, liveID])   // the batch itself is no update, as in ib_async
    #expect(got.map(\.bars.count) == [1, 2] && got.map(\.hasNewBar) == [true, true])
    #expect(await client.liveBarSubscriptions().map(\.bars.count) == [1, 2])
    rtReader.cancel()
    #expect(try await gateway.waitForSent(n + 3)[n + 2] == ["51", "1", "\(rtID)"])
    #expect(await client.liveBarSubscriptions().map(\.requestID) == [liveID])
    await client.disconnect()
    #expect(await client.liveBarSubscriptions().isEmpty)
    withExtendedLifetime(live) {}
}
