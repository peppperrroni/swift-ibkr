import Testing
@testable import IBKR

private func item(_ account: String = "DU1", _ conID: String) -> [String] {
    ["7", "8", conID, "AAPL", "STK", "", "0.0", "", "", "NASDAQ", "USD", "AAPL", "NMS", "5", "187.25", "936.25",
     "180.5", "33.75", "1.7976931348623157E308", account]
}

private func value(_ v: String = "100", _ account: String = "DU1") -> [String] {
    ["6", "2", "NetLiquidation", v, "USD", account]
}

private func netLiq(_ v: String = "100", _ account: String = "DU1") -> AccountValue {
    AccountValue(account: account, tag: "NetLiquidation", value: v, currency: "USD")
}

private func keys(_ set: [PortfolioItem]) -> [String] { set.map { "\($0.account)/\($0.contract.conID)" } }

private func connect(_ client: IBClient, timeout: Duration = .seconds(10)) async throws {
    try await within2s { try await client.connect(clientID: 7, timeout: timeout) }
}

/// The first `count` updates of `stream`, within 2 s.
private func next<T: Sendable>(_ count: Int, _ stream: AsyncStream<T>) async throws -> [T] {
    try await within2s {
        var got: [T] = []
        for await x in stream {
            got.append(x)
            if got.count == count { return got }
        }
        throw TimedOut()
    }
}

@Test func connectSyncsTheSingleAccount() async throws {
    let gateway = FakeGateway()
    gateway.onRequest = { $0[0] == "6" ? [value(), item("DU1", "265598")] : [] }
    let client = IBClient(connector: gateway.connector)
    try await connect(client)
    #expect(await client.accountValues().snapshot == [netLiq()])
    guard case .portfolioItem(let want) = IBDecoder.decode(body(item("DU1", "265598"))) else {
        Issue.record("the item does not decode"); return
    }
    #expect(await client.portfolio().snapshot == [want])
}

@Test func connectWaitsForAccountDownloadEnd() async throws {
    let client = IBClient(connector: FakeGateway(answersAccountUpdates: false).connector)
    await #expect(throws: IBClientError.timeout) { try await connect(client, timeout: .milliseconds(300)) }
}

@Test func severalAccountsSyncThroughMulti() async throws {
    let gateway = FakeGateway(accounts: "DU1,DU2")
    gateway.onRequest = { r in r[0] == "76" ? [["73", "1", r[2], r[3], "", "NetLiquidation", "100", "USD"]] : [] }
    let client = IBClient(connector: gateway.connector)
    try await connect(client)
    let sent = try await gateway.waitForSent(7)
    #expect(Array(sent[5...]) == [["76", "1", "2", "DU1", "", "0"], ["76", "1", "3", "DU2", "", "0"]])
    #expect(!sent.contains { $0[0] == "6" })
    #expect(await client.accountValues().snapshot == [netLiq("100", "DU1"), netLiq("100", "DU2")])
    #expect(await client.portfolio().snapshot.isEmpty)
}

@Test func multiUpdateForAnotherRequestDoesNotReachAccountValues() async throws {
    let gateway = FakeGateway(accounts: "DU1,DU2")
    let client = IBClient(connector: gateway.connector)
    try await connect(client)
    let (_, updates) = await client.accountValues()
    gateway.feed(["73", "1", "99", "DU3", "", "NetLiquidation", "1", "USD"])   // not one of the sync's reqIds
    gateway.feed(value("7"))
    #expect(try await next(1, updates) == [netLiq("7")])
    #expect(await client.accountValues().snapshot == [netLiq("7")])
}

@Test func fatalErrorOnAccountSyncFailsConnect() async throws {
    let gateway = FakeGateway(accounts: "DU1,DU2")
    gateway.onRequest = { r in
        r[0] == "76" && r[3] == "DU2" ? [["4", "2", r[2], "322", "Error processing request", ""]] : []
    }
    let client = IBClient(connector: gateway.connector)
    await #expect(throws: IBClientError.ib(code: 322, text: "Error processing request")) { try await connect(client) }
}

@Test func portfolioChangeIsPublishedAsAWholeSet() async throws {
    let gateway = FakeGateway()
    gateway.onRequest = { $0[0] == "6" ? [item("DU1", "1")] : [] }
    let client = IBClient(connector: gateway.connector)
    try await connect(client)
    let (snapshot, updates) = await client.portfolio()
    #expect(keys(snapshot) == ["DU1/1"])
    gateway.feed(item("DU1", "2"))
    #expect(try await next(1, updates).map(keys) == [["DU1/1", "DU1/2"]])
}

@Test func accountValueChangeIsPublishedOnce() async throws {
    let gateway = FakeGateway()
    let client = IBClient(connector: gateway.connector)
    try await connect(client)
    let (_, updates) = await client.accountValues()
    gateway.feed(value("100"))
    gateway.feed(value("100"))
    gateway.feed(value("200"))
    #expect(try await next(2, updates) == [netLiq("100"), netLiq("200")])
}

@Test func reconnectReplacesPortfolioWhole() async throws {
    let (one, two) = (FakeGateway(), FakeGateway())
    one.onRequest = { $0[0] == "6" ? [item("DU1", "1")] : [] }
    two.onRequest = { $0[0] == "6" ? [item("DU1", "2")] : [] }
    let gateways = Gateways([one, two])
    let client = IBClient(connector: gateways.connector)
    try await connect(client)
    let (snapshot, updates) = await client.portfolio()
    #expect(keys(snapshot) == ["DU1/1"])
    await client.disconnect()
    try await connect(client)
    #expect(try await next(1, updates).map(keys) == [["DU1/2"]])   // never both, never empty
    #expect(keys(await client.portfolio().snapshot) == ["DU1/2"])
}
