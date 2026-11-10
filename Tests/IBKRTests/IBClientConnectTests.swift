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
    let sent = try await gateway.waitForSent(4)
    #expect(sent.map { $0[0] } == ["71", "16", "99", "7"])
    #expect(sent.first == ["71", "2", "7", ""])
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

/// Hands out one gateway per connect, in order.
private actor Gateways {
    private var list: [FakeGateway]
    init(_ list: [FakeGateway]) { self.list = list }
    func next() -> FakeGateway { list.removeFirst() }
}

@Test func disconnectReportsNoError() async throws {
    let (one, two) = (FakeGateway(), FakeGateway())
    let gateways = Gateways([one, two])
    let client = IBClient(connector: { _, _, _ in await gateways.next() })
    try await connect(client)
    await client.disconnect()
    #expect(try await first(client.states()) == .disconnected(nil))
    #expect(one.isClosed)

    try await connect(client)
    #expect(try await first(client.states()) == ready)
    #expect(try await two.waitForSent(4).count == 4)
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
