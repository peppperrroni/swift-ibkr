import Testing
@testable import IBKR

private let policy = ReconnectPolicy(delays: [.milliseconds(10)], probeAfter: nil)
private let ready = ConnectionState.connected(serverVersion: 178, accounts: ["DU1"])

/// The next `count` states of `states`, within 2 s.
private func next(_ count: Int, _ states: AsyncStream<ConnectionState>) async throws -> [ConnectionState] {
    try await within2s {
        var got: [ConnectionState] = []
        for await s in states { got.append(s); if got.count == count { return got } }
        throw TimedOut()   // the stream ended first
    }
}

private func connect(_ client: IBClient, _ policy: ReconnectPolicy) async throws {
    try await within2s { try await client.connect(clientID: 7, reconnect: policy) }
}

@Test func dropReconnectsAndKeepsSubscribers() async throws {
    let (one, two) = (FakeGateway(), FakeGateway())
    let gateways = Gateways([one, two])
    let client = IBClient(connector: gateways.connector)
    try await connect(client, policy)
    let states = await client.states()
    let (_, updates) = await client.positions()
    one.close()
    #expect(try await next(4, states) == [ready, .disconnected(.connectionClosed), .connecting, ready])
    #expect(try await two.waitForSent(FakeGateway.syncFrames).map { $0[0] } == ["71", "16", "99", "7", "61", "6"])

    two.feed(["61", "3", "DU1", "265598", "AAPL", "STK", "", "0", "", "", "", "USD", "AAPL", "NMS", "5", "10"])
    let set = try await within2s {
        for await set in updates where !set.isEmpty { return set }
        throw TimedOut()
    }
    #expect(set.map(\.contract.conID) == [265598])
}

@Test func ordersSurviveTheReconnectWindow() async throws {
    let order = Fixtures.openOrderFields(
        orderID: 3, permID: 900, clientID: 7, symbol: "AAPL", action: "BUY", quantity: "1", orderType: "LMT",
        limitPrice: "1", auxPrice: "1.7976931348623157E308", tif: "DAY", parentID: "0", outsideRTH: "0", orderRef: "",
        status: "Submitted")
    let (one, two) = (FakeGateway(), FakeGateway())
    for g in [one, two] { g.onRequest = { $0[0] == "16" ? [order] : [] } }
    let gateways = Gateways([one, nil, two])   // the first attempt is refused
    let client = IBClient(connector: gateways.connector)
    try await connect(client, ReconnectPolicy(delays: [.milliseconds(10), .milliseconds(300)], probeAfter: nil))
    let states = await client.states()
    one.close()
    try await within2s { while await gateways.connects < 2 { try await Task.sleep(for: .milliseconds(5)) } }
    #expect(try await next(1, client.states()) == [.connecting])   // in the pause after the refused attempt
    #expect(await client.orders().snapshot.map(\.orderID) == [3])
    #expect(try await next(4, states) == [ready, .disconnected(.connectionClosed), .connecting, ready])
    #expect(await client.orders().snapshot.map(\.orderID) == [3])
}

@Test func requestStreamsEndAndAreNotReplayed() async throws {
    let (one, two) = (FakeGateway(), FakeGateway())
    let gateways = Gateways([one, two])
    let client = IBClient(connector: gateways.connector)
    try await connect(client, policy)
    let states = await client.states()
    let (_, summary) = take(0, try await client.accountSummary(tags: ["NetLiquidation"]))
    try await client.setMarketDataType(.delayed)
    _ = try await one.waitForSent(FakeGateway.syncFrames + 2)
    one.close()
    await #expect(throws: IBClientError.connectionClosed) { try await within2s { try await summary.value } }
    #expect(try await next(4, states).last == ready)
    try await Task.sleep(for: .milliseconds(100))
    let sent = try await two.waitForSent(FakeGateway.syncFrames)
    #expect(!sent.contains { $0[0] == "62" || $0[0] == "59" })
}

@Test func reconnectGivesUpAfterMaxAttempts() async throws {
    let one = FakeGateway()
    let gateways = Gateways([one])
    let client = IBClient(connector: gateways.connector)
    try await connect(client, ReconnectPolicy(delays: [.milliseconds(10)], maxAttempts: 2, probeAfter: nil))
    let states = await client.states()
    one.close()
    #expect(try await next(4, states)
            == [ready, .disconnected(.connectionClosed), .connecting, .disconnected(.transport("refused"))])
    try await Task.sleep(for: .milliseconds(100))
    #expect(await gateways.connects == 3)
}

@Test func disconnectStopsReconnecting() async throws {
    let one = FakeGateway()
    let gateways = Gateways([one])
    let client = IBClient(connector: gateways.connector)
    try await connect(client, ReconnectPolicy(delays: [.seconds(1)], probeAfter: nil))
    let states = await client.states()
    one.close()
    #expect(try await next(3, states) == [ready, .disconnected(.connectionClosed), .connecting])
    await #expect(throws: IBClientError.alreadyConnected) { try await connect(client, policy) }
    await client.disconnect()
    #expect(try await next(1, states) == [.disconnected(nil)])
    try await Task.sleep(for: .milliseconds(1200))   // past the 1 s pause: an attempt not cancelled would count
    #expect(await gateways.connects == 1)
    #expect(try await next(1, client.states()) == [.disconnected(nil)])
}

@Test func manualDisconnectDoesNotReconnect() async throws {
    let gateways = Gateways([FakeGateway(), FakeGateway()])
    let client = IBClient(connector: gateways.connector)
    try await connect(client, policy)
    await client.disconnect()
    try await Task.sleep(for: .milliseconds(100))
    #expect(await gateways.connects == 1)
}

@Test func firstConnectFailureIsNotRetried() async throws {
    let gateways = Gateways([])
    let client = IBClient(connector: gateways.connector)
    await #expect(throws: IBClientError.transport("refused")) { try await connect(client, policy) }
    try await Task.sleep(for: .milliseconds(100))
    #expect(await gateways.connects == 1)
}

@Test func silentConnectionIsProbedThenDropped() async throws {
    let (one, two) = (FakeGateway(), FakeGateway())
    let gateways = Gateways([one, two])
    let client = IBClient(connector: gateways.connector)
    try await connect(client, ReconnectPolicy(delays: [.milliseconds(10)], probeAfter: .milliseconds(100)))
    let states = await client.states()
    #expect(try await next(4, states) == [ready, .disconnected(.timeout), .connecting, ready])
    #expect(try await one.waitForSent(FakeGateway.syncFrames + 1).last == ["49", "1"])
    #expect(one.isClosed)
}

@Test func answeredProbeKeepsTheConnection() async throws {
    let one = FakeGateway()
    one.onRequest = { $0 == ["49", "1"] ? [["49", "1", "1700000000"]] : [] }
    let gateways = Gateways([one])
    let client = IBClient(connector: gateways.connector)
    try await connect(client, ReconnectPolicy(delays: [.milliseconds(10)], probeAfter: .milliseconds(50)))
    try await Task.sleep(for: .milliseconds(400))
    #expect(try await next(1, client.states()) == [ready])
    #expect(!one.isClosed)
    #expect(try await one.waitForSent(1).filter { $0 == ["49", "1"] }.count >= 2)
}
