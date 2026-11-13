import Foundation
import Testing
@testable import IBKR

/// The first element of `stream` that `match` accepts, within 2 s.
private func first<T: Sendable>(_ stream: AsyncStream<T>,
                                where match: @escaping @Sendable (T) -> Bool = { _ in true }) async throws -> T {
    try await within2s {
        for await x in stream where match(x) { return x }
        throw TimedOut()   // the stream ended first
    }
}

private func isDisconnected(_ s: ConnectionState) -> Bool {
    if case .disconnected = s { true } else { false }
}

private func connect(_ client: IBClient, timeout: Duration = .seconds(10)) async throws {
    try await within2s { try await client.connect(clientID: 7, timeout: timeout) }
}

private func connected(_ gateway: FakeGateway) async throws -> IBClient {
    let client = IBClient(connector: gateway.connector)
    try await connect(client)
    return client
}

private let ready = ConnectionState.connected(serverVersion: 178, accounts: ["DU1"])

@Test func connectReachesConnectedAfterSync() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    #expect(try await first(client.states()) == ready)
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames)
    #expect(sent.map { $0[0] } == ["71", "16", "99", "7", "61", "6"])
    #expect(sent.first == ["71", "2", "7", ""])
    #expect(sent[5] == ["6", "2", "1", "DU1"])
}

@Test func connectRejectsOtherServerVersion() async throws {
    let gateway = FakeGateway(serverVersion: "176")
    let client = IBClient(connector: gateway.connector)
    let error = IBClientError.protocolError(.unsupportedServerVersion(176))
    await #expect(throws: error) { try await connect(client) }
    #expect(try await first(client.states()) == .disconnected(error))
    #expect(gateway.isClosed)
}

@Test func connectTimesOut() async throws {
    let gateway = FakeGateway(answersStartAPI: false)
    let client = IBClient(connector: gateway.connector)
    await #expect(throws: IBClientError.timeout) { try await connect(client, timeout: .milliseconds(300)) }
    #expect(try await first(client.states()) == .disconnected(.timeout))
    #expect(gateway.isClosed)
}

@Test func connectFailsWithIBError() async throws {
    let text = "Unable to connect as the client id is already in use."
    let gateway = FakeGateway()
    gateway.onRequest = { $0[0] == "71" ? [["4", "2", "-1", "326", text, ""]] : [] }
    let client = IBClient(connector: gateway.connector)
    let connecting = Task { try await connect(client) }
    _ = try await gateway.waitForSent(1)
    gateway.close()   // IB closes right behind the error
    await #expect(throws: IBClientError.ib(code: 326, text: text)) { try await connecting.value }
    #expect(try await first(client.states()) == .disconnected(.ib(code: 326, text: text)))
}

@Test func connectTwiceThrows() async throws {
    let client = try await connected(FakeGateway())
    await #expect(throws: IBClientError.alreadyConnected) { try await connect(client) }
    #expect(try await first(client.states()) == ready)
}

@Test func peerCloseReportsDisconnected() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let states = await client.states()
    gateway.close()
    #expect(try await first(states, where: isDisconnected) == .disconnected(.connectionClosed))
}

@Test func disconnectReportsNoError() async throws {
    let (one, two) = (FakeGateway(), FakeGateway())
    let gateways = Gateways([one, two])
    let client = IBClient(connector: gateways.connector)
    try await connect(client)
    await client.disconnect()
    #expect(try await first(client.states()) == .disconnected(nil))
    try await one.waitUntilClosed()
    #expect(one.isClosed)

    try await connect(client)
    #expect(try await first(client.states()) == ready)
    #expect(try await two.waitForSent(FakeGateway.syncFrames).count == FakeGateway.syncFrames)
}

@Test func cleanDisconnectSendsCancelPositionsThenCloses() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    await client.disconnect()
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1).last == ["64", "1"])
    try await gateway.waitUntilClosed()
}

@Test func queuedFramesLeaveBeforeTheClose() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    _ = try await client.placeOrder(Contract(symbol: "AAPL"),
                                    Order(action: .buy, quantity: 1, orderType: "LMT", limitPrice: d("1")))
    await client.disconnect()
    try await gateway.waitUntilClosed()
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 2)
    #expect(sent.suffix(2).map { $0[0] } == ["3", "64"])
    #expect(sent.last == ["64", "1"])
}

@Test func peerCloseSendsNoCancelPositions() async throws {
    let gateway = FakeGateway()
    _ = try await connected(gateway)
    gateway.close()
    try await Task.sleep(for: .milliseconds(100))
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames).count == FakeGateway.syncFrames)
    #expect(gateway.writesAfterClose == 0)
}

@Test func disconnectWhileConnectingSendsNoCancelPositions() async throws {
    let gateway = FakeGateway(answersStartAPI: false)
    let client = IBClient(connector: gateway.connector)
    let connecting = Task { try await connect(client) }
    _ = try await gateway.waitForSent(1)
    await client.disconnect()
    await #expect(throws: IBClientError.connectionClosed) { try await connecting.value }
    #expect(gateway.isClosed)
    #expect(!(try await gateway.waitForSent(1)).contains { $0[0] == "64" })
}

@Test func connectHonoursCancellation() async throws {
    let (one, two) = (FakeGateway(answersStartAPI: false), FakeGateway())
    let gateways = Gateways([one, two])
    let client = IBClient(connector: gateways.connector)
    let connecting = Task { try await client.connect(clientID: 7) }   // outside within2s: a task inside it would not receive this cancel
    _ = try await one.waitForSent(1)
    connecting.cancel()
    await #expect(throws: IBClientError.cancelled) { try await within2s { try await connecting.value } }
    #expect(try await first(client.states()) == .disconnected(.cancelled))
    #expect(one.isClosed)

    try await connect(client)
    #expect(try await first(client.states()) == ready)
}

@Test func cancelWhileTheConnectorWaits() async throws {
    let client = IBClient(connector: { _, _, _ in
        try await Task.sleep(for: .seconds(5))
        return FakeGateway()
    })
    let connecting = Task { try await client.connect(clientID: 7) }
    _ = try await first(client.states()) { $0 == .connecting }
    connecting.cancel()
    await #expect(throws: IBClientError.cancelled) { try await within2s { try await connecting.value } }
    #expect(try await first(client.states()) == .disconnected(.cancelled))
}

@Test func reconnectDoesNotRepublishFills() async throws {
    let id = "0000e0d5.6556b5f0.01.01"
    let exec = ["11", "-1", "12", "265598", "AAPL", "STK", "", "0", "", "", "SMART", "USD", "AAPL", "NMS",
                id, "20251109 10:00:00", "DU1", "ISLAND", "BOT", "100", "187.25", "918273001", "7", "0",
                "100", "187.25", "", "", "", "", "1", "0"]
    let commission = ["59", "1", id, "1.5", "USD", "1.7976931348623157E308", "1.7976931348623157E308", ""]
    let (one, two) = (FakeGateway(), FakeGateway())
    let order = Fixtures.openOrderFields(
        orderID: 12, permID: 918273001, clientID: 7, symbol: "AAPL", action: "BUY", quantity: "100", orderType: "LMT",
        limitPrice: "187.25", auxPrice: "1.7976931348623157E308", tif: "DAY", parentID: "0", outsideRTH: "0",
        orderRef: "", status: "Submitted")
    two.onRequest = { $0[0] == "7" ? [exec, commission] : $0[0] == "16" ? [order] : [] }   // the sync replays both
    let gateways = Gateways([one, two])
    let client = IBClient(connector: gateways.connector)
    try await connect(client)
    let (_, updates) = await client.executions()
    one.feed(exec)
    one.feed(commission)
    _ = try await first(updates)

    await client.disconnect()
    try await connect(client)
    let got = Task { () -> Fill? in
        for await f in updates { return f }
        return nil
    }
    try await Task.sleep(for: .milliseconds(300))
    got.cancel()
    #expect(await got.value == nil)
    #expect(await client.executions().snapshot.count == 1)
    #expect(await client.orders().snapshot.first?.fills.count == 1, "the replayed fill still joins the fresh tracker's order")
}

@Test func fatalErrorOnSyncRequestFailsConnect() async throws {
    let gateway = FakeGateway()
    gateway.onRequest = { $0[0] == "7" ? [["4", "2", $0[2], "321", "Error validating request", ""]] : [] }
    let client = IBClient(connector: gateway.connector)
    let error = IBClientError.ib(code: 321, text: "Error validating request")
    await #expect(throws: error) { try await connect(client) }
    #expect(try await first(client.states()) == .disconnected(error))
    #expect(gateway.isClosed)
}

@Test func malformedFrameReachesMessages() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let messages = await client.messages()
    gateway.feed(["5", "x"])
    let message = try await first(messages)
    guard case .malformed(id: 5, _, _) = message else { Issue.record("got \(message)"); return }
    #expect(try await first(client.states()) == ready)
}

@Test func chunkedFramesAreReassembled() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let messages = await client.messages()
    for byte in Frame.encode(body("49", "1", "1700000000")) + Frame.encode(body("9", "1", "50")) {
        gateway.feedRaw([byte])
    }
    let got = try await within2s {
        var it = messages.makeAsyncIterator()
        return [await it.next(), await it.next()]
    }
    #expect(got == [.currentTime(1_700_000_000), .nextValidID(50)])
}

@Test func oversizedFrameDisconnects() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let states = await client.states()
    gateway.feedRaw([0x01, 0, 0, 0])
    #expect(try await first(states, where: isDisconnected) == .disconnected(.protocolError(.frameTooLong(16_777_216))))
    #expect(gateway.isClosed)
}

@Test func liveFillTimeIsTheArrivalAndTheGatewayZoneReadsTheText() async throws {
    let id = "0000e0d5.6556b5f0.01.01"
    let exec = ["11", "-1", "12", "265598", "AAPL", "STK", "", "0", "", "", "SMART", "USD", "AAPL", "NMS",
                id, "20251109-10:00:00", "DU1", "ISLAND", "BOT", "100", "187.25", "918273001", "7", "0",
                "100", "187.25", "", "", "", "", "1", "0"]
    let gateway = FakeGateway()
    let client = IBClient(connector: gateway.connector)
    try await within2s {
        try await client.connect(clientID: 7, options: ConnectOptions(gatewayTimeZone: TimeZone(identifier: "US/Eastern")))
    }
    let (_, updates) = await client.executions()
    gateway.feed(exec)
    gateway.feed(["59", "1", id, "1.5", "USD", "1.7976931348623157E308", "1.7976931348623157E308", ""])
    let fill = try await first(updates)
    let time = try #require(fill.time)
    #expect(abs(time.timeIntervalSinceNow) < 2)
    #expect(fill.execution.date == Date(timeIntervalSince1970: 1_762_682_400 + 5 * 3600))   // read as Eastern
}
