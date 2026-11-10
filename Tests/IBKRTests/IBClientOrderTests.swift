import Foundation
import Testing
@testable import IBKR

private let aapl = Contract(symbol: "AAPL")
private let buy = Order(action: .buy, quantity: 1, orderType: "LMT", limitPrice: d("1"))
private let unset = "1.7976931348623157E308"

private func connected(_ gateway: FakeGateway) async throws -> IBClient {
    let client = IBClient(connector: gateway.connector)
    try await within2s { try await client.connect(clientID: 7) }
    return client
}

private func first<T: Sendable>(_ stream: AsyncStream<T>) async throws -> T {
    try await within2s {
        for await x in stream { return x }
        throw TimedOut()
    }
}

/// Polls until `condition` holds, failing after 2 s.
private func until(_ condition: @escaping @Sendable () async -> Bool) async throws {
    try await within2s {
        while !(await condition()) { try await Task.sleep(for: .milliseconds(5)) }
    }
}

@Test func requestsAndOrdersShareOneSequence() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    let sync = try await gateway.waitForSent(4).first { $0[0] == "7" }
    #expect(sync?[2] == "100")
    #expect(try await client.placeOrder(aapl, buy) == 101)
    #expect(try await client.placeOrder(aapl, buy) == 102)
}

@Test func laterNextValidIDNeverLowersTheCounter() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    let messages = await client.messages()
    gateway.feed(["9", "1", "5"])
    _ = try await first(messages)
    #expect(try await client.placeOrder(aapl, buy) == 101)
}

@Test func requestBeforeConnectThrows() async throws {
    let client = IBClient(connector: FakeGateway().connector)
    await #expect(throws: IBClientError.notConnected) { try await client.placeOrder(aapl, buy) }
    await #expect(throws: IBClientError.notConnected) { try await client.cancelOrder(1) }
}

@Test func orderMethodsNeedConnectedState() async throws {
    let gateway = FakeGateway(answersStartAPI: false)
    let client = IBClient(connector: gateway.connector)
    let connecting = Task { try await client.connect(clientID: 7) }
    _ = try await gateway.waitForSent(1)   // startAPI is out, the state is still .connecting
    await #expect(throws: IBClientError.notConnected) { try await client.placeOrder(aapl, buy) }
    await #expect(throws: IBClientError.notConnected) { try await client.modifyOrder(1, aapl, buy) }
    await #expect(throws: IBClientError.notConnected) { try await client.cancelOrder(1) }
    gateway.close()
    _ = try? await connecting.value
}

@Test func placeOrderPublishesWholeOrderOnAck() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    let (_, updates) = await client.orders()
    #expect(try await client.placeOrder(aapl, buy) == 101)
    gateway.feed(["3", "101", "Submitted", "0", "1", "0", "555", "0", "0", "7", "", "0"])
    let s = try await first(updates)
    #expect(s.orderID == 101 && s.status == .submitted)
    #expect(s.contract.symbol == "AAPL" && s.order.limitPrice == d("1"))
}

@Test func cancelRightAfterPlaceKeepsOrder() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    let id = try await client.placeOrder(aapl, buy)
    try await client.cancelOrder(id)
    let sent = try await gateway.waitForSent(6)
    #expect(Array(sent[4].prefix(2)) == ["3", "101"])
    #expect(sent[5] == ["4", "1", "101", ""])
}

@Test func modifyResendsPlaceOrderWithSameID() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    let id = try await client.placeOrder(aapl, buy)
    var changed = buy
    changed.limitPrice = d("2")
    try await client.modifyOrder(id, aapl, changed)
    let sent = try await gateway.waitForSent(6)
    #expect(Array(sent[5].prefix(2)) == ["3", "101"] && sent[5][19] == "2" && sent[4][19] == "1")
}

@Test func encodingErrorThrowsAndSendsNothing() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    var bad = buy
    bad.orderRef = "Купить"
    await #expect(throws: IBClientError.encoding(.nonASCII(field: "Купить"))) { try await client.placeOrder(aapl, bad) }
    try await client.cancelOrder(1)   // the next frame out is this one
    let sent = try await gateway.waitForSent(5)
    #expect(sent.count == 5 && sent[4][0] == "4")
}

@Test func errorRejectsOwnPendingOrder() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    let (_, updates) = await client.orders()
    let id = try await client.placeOrder(aapl, buy)
    gateway.feed(["4", "2", "\(id)", "201", "Order rejected", ""])
    _ = try await first(updates)
    let s = await client.orders().snapshot.first { $0.orderID == 101 }
    #expect(s?.status == .inactive && s?.rejectReason == "Order rejected")
}

@Test func syncedOrdersAreInSnapshot() async throws {
    let gateway = FakeGateway()
    gateway.onRequest = { fields in
        fields[0] == "16" ? [Fixtures.openOrderFields(
            orderID: 3, permID: 900, clientID: 7, symbol: "AAPL", action: "BUY", quantity: "1", orderType: "LMT",
            limitPrice: "1", auxPrice: unset, tif: "DAY", parentID: "0", outsideRTH: "0", orderRef: "",
            status: "Submitted")] : []
    }
    let client = try await connected(gateway)
    #expect(await client.orders().snapshot.count == 1)
}

@Test func fillPublishedWhenBothHalvesArrive() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let (_, updates) = await client.executions()
    let id = "0000e0d5.6556b5f0.01.01"
    gateway.feed(["11", "-1", "12", "265598", "AAPL", "STK", "", "0", "", "", "SMART", "USD", "AAPL", "NMS",
                  id, "20251109 10:00:00", "DU1", "ISLAND", "BOT", "100", "187.25", "918273001", "7", "0",
                  "100", "187.25", "", "", "", "", "1", "0"])
    gateway.feed(["59", "1", id, "1.5", "USD", unset, unset, ""])
    let fill = try await first(updates)
    #expect(fill.execution.execID == id && fill.commission.commission == d("1.5"))
}

@Test func burstIsThrottledNotDropped() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    for i in 1...50 { try await client.cancelOrder(i) }
    let sent = try await gateway.waitForSent(54, timeout: .seconds(3))   // 4 sync frames + 50 cancels
    #expect(sent.filter { $0[0] == "4" }.map { $0[2] } == (1...50).map(String.init))
}

@Test func droppedOrdersStreamIsRemoved() async throws {
    let client = try await connected(FakeGateway())
    let consumer = Task { for await _ in await client.orders().updates {} }
    try await until { await client.orderSubscriberCount == 1 }
    consumer.cancel()
    try await until { await client.orderSubscriberCount == 0 }
}

@Test func frameAfterDisconnectIsIgnored() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let messages = await client.messages()
    await client.disconnect()
    gateway.feed(["49", "1", "1700000000"])
    let got = Task { () -> IBMessage? in
        for await m in messages { return m }
        return nil
    }
    try await Task.sleep(for: .milliseconds(300))
    got.cancel()
    #expect(await got.value == nil)
    var it = await client.states().makeAsyncIterator()
    #expect(await it.next() == .disconnected(nil))
}
