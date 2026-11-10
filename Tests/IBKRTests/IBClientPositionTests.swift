import Testing
@testable import IBKR

private func position(_ account: String = "DU1", _ conID: String, _ qty: String = "5") -> [String] {
    ["61", "3", account, conID, "AAPL", "STK", "", "0", "", "", "", "USD", "AAPL", "NMS", qty, "10"]
}

private func keys(_ set: [Position]) -> [String] { set.map { "\($0.account)/\($0.contract.conID)" } }

private func connect(_ client: IBClient, timeout: Duration = .seconds(10)) async throws {
    try await within2s { try await client.connect(clientID: 7, timeout: timeout) }
}

private func firstUpdate(_ stream: AsyncStream<[Position]>) async throws -> [Position] {
    try await within2s {
        for await set in stream { return set }
        throw TimedOut()
    }
}

private actor Gateways {
    private var list: [FakeGateway]
    init(_ list: [FakeGateway]) { self.list = list }
    func next() -> FakeGateway { list.removeFirst() }
}

@Test func syncedPositionsAreInSnapshot() async throws {
    let gateway = FakeGateway()
    gateway.onRequest = { $0[0] == "61" ? [position("DU1", "265598")] : [] }
    let client = IBClient(connector: gateway.connector)
    try await connect(client)
    #expect(keys(await client.positions().snapshot) == ["DU1/265598"])
}

@Test func connectWaitsForPositionEnd() async throws {
    let client = IBClient(connector: FakeGateway(answersPositions: false).connector)
    await #expect(throws: IBClientError.timeout) { try await connect(client, timeout: .milliseconds(300)) }
}

@Test func positionChangeIsPublishedAsAWholeSet() async throws {
    let gateway = FakeGateway()
    gateway.onRequest = { $0[0] == "61" ? [position("DU1", "1")] : [] }
    let client = IBClient(connector: gateway.connector)
    try await connect(client)
    let (snapshot, updates) = await client.positions()
    #expect(keys(snapshot) == ["DU1/1"])
    gateway.feed(position("DU1", "2"))
    #expect(keys(try await firstUpdate(updates)) == ["DU1/1", "DU1/2"])
}

@Test func reconnectReplacesPositionsWhole() async throws {
    let (one, two) = (FakeGateway(), FakeGateway())
    one.onRequest = { $0[0] == "61" ? [position("DU1", "1")] : [] }
    two.onRequest = { $0[0] == "61" ? [position("DU1", "2")] : [] }
    let gateways = Gateways([one, two])
    let client = IBClient(connector: { _, _, _ in await gateways.next() })
    try await connect(client)
    let (snapshot, updates) = await client.positions()
    #expect(keys(snapshot) == ["DU1/1"])
    await client.disconnect()
    try await connect(client)
    #expect(keys(try await firstUpdate(updates)) == ["DU1/2"])   // never both, never empty
    #expect(keys(await client.positions().snapshot) == ["DU1/2"])
}
