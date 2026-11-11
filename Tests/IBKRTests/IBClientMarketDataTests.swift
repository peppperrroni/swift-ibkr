import Testing
@testable import IBKR

private func connected(_ gateway: FakeGateway) async throws -> IBClient {
    let client = IBClient(connector: gateway.connector)
    try await within2s { try await client.connect(clientID: 7) }
    return client
}

/// Reads `count` ticks, or until the stream throws. The reader keeps the stream until cancelled, so a test
/// that wants the consumer to stop cancels `.reader`.
private func take(_ count: Int, _ stream: AsyncThrowingStream<Tick, any Error>)
    -> (reader: Task<Void, Never>, result: Task<[Tick], any Error>) {
    let (seen, out) = AsyncThrowingStream.makeStream(of: Tick.self, throwing: (any Error).self)
    let reader = Task {
        do { for try await t in stream { out.yield(t) }; out.finish() } catch { out.finish(throwing: error) }
    }
    let result = Task {
        var got: [Tick] = []
        if count > 0 { for try await t in seen { got.append(t); if got.count == count { break } } }
        else { for try await t in seen { got.append(t) } }
        return got
    }
    return (reader, result)
}

@Test func marketDataYieldsTicks() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.marketData(Contract(symbol: "AAPL"))
    let sent = try await gateway.waitForSent(6)
    let id = sent[5][2]
    #expect(sent[5][0] == "1")
    let (reader, result) = take(3, stream)
    gateway.feed(["1", "6", id, "1", "351.5", "200", "0"])
    gateway.feed(["2", "6", id, "0", "300"])
    gateway.feed(["58", "1", id, "1"])
    #expect(try await within2s { try await result.value } == [
        .price(.bid, price: d("351.5"), size: d("200")), .size(.bidSize, d("300")), .dataType(.realtime)])
    reader.cancel()   // the consumer stops
    #expect(try await gateway.waitForSent(7)[6] == ["2", "2", id])
}

@Test func delayedNoticeKeepsTheStreamAndMapsFields() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    try await client.setMarketDataType(.delayed)
    let stream = try await client.marketData(Contract(symbol: "AAPL"))
    let sent = try await gateway.waitForSent(7)
    #expect(sent[5] == ["59", "1", "3"])
    let id = sent[6][2]
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
    let id = try await gateway.waitForSent(6)[5][2]
    gateway.feed(["4", "2", id, "354", "Requested market data is not subscribed.", ""])
    let (_, result) = take(0, stream)
    await #expect(throws: IBClientError.noMarketDataPermission(code: 354, text: "Requested market data is not subscribed.")) {
        _ = try await within2s { try await result.value }
    }
}

@Test func otherFatalStaysIB() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.marketData(Contract(symbol: "AAPL"))
    let id = try await gateway.waitForSent(6)[5][2]
    gateway.feed(["4", "2", id, "200", "No security definition", ""])
    let (_, result) = take(0, stream)
    await #expect(throws: IBClientError.ib(code: 200, text: "No security definition")) {
        _ = try await within2s { try await result.value }
    }
}
