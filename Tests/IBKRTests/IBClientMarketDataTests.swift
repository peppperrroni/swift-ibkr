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
