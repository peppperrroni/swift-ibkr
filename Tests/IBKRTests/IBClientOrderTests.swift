import Foundation
import Testing
@testable import IBKR

private let aapl = Contract(symbol: "AAPL")
private let buy = Order(action: .buy, quantity: 1, orderType: "LMT", limitPrice: d("1"))
private let opt: Contract = {
    var c = Contract(symbol: "AAPL", secType: "OPT")
    c.conID = 12345; c.lastTradeDateOrContractMonth = "20261218"; c.strike = d("150"); c.right = "C"
    c.multiplier = "100"; c.localSymbol = "AAPL  261218C00150000"; c.tradingClass = "AAPL"
    return c
}()
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

/// The first element matching `predicate`, failing after 2 s.
private func next<T: Sendable>(_ stream: AsyncStream<T>, _ predicate: @escaping @Sendable (T) -> Bool) async throws -> T {
    try await within2s {
        for await x in stream where predicate(x) { return x }
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
    await #expect(throws: IBClientError.notConnected) { try await client.exerciseOptions(opt, action: .exercise, quantity: 1, account: "DU1") }
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
    await #expect(throws: IBClientError.connectionClosed) { try await within2s { try await connecting.value } }
}

@Test func placeOrderPublishesWholeOrderOnAck() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    let (_, updates) = await client.orders()
    #expect(try await client.placeOrder(aapl, buy) == 101)
    gateway.feed(["3", "101", "Submitted", "0", "1", "0", "555", "0", "0", "7", "", "0"])
    let s = try await next(updates) { $0.status == .submitted }
    #expect(s.orderID == 101 && s.status == .submitted)
    #expect(s.contract.symbol == "AAPL" && s.order.limitPrice == d("1"))
}

@Test func cancelRightAfterPlaceKeepsOrder() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    let id = try await client.placeOrder(aapl, buy)
    try await client.cancelOrder(id)
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 2)
    #expect(Array(sent[FakeGateway.syncFrames].prefix(2)) == ["3", "101"])
    #expect(sent[FakeGateway.syncFrames + 1] == ["4", "1", "101", ""])
}

@Test func modifyResendsPlaceOrderWithSameID() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    let id = try await client.placeOrder(aapl, buy)
    var changed = buy
    changed.limitPrice = d("2")
    try await client.modifyOrder(id, aapl, changed)
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 2)
    #expect(Array(sent[FakeGateway.syncFrames + 1].prefix(2)) == ["3", "101"] && sent[FakeGateway.syncFrames + 1][19] == "2" && sent[FakeGateway.syncFrames][19] == "1")
}

@Test func encodingErrorThrowsAndSendsNothing() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    var bad = buy
    bad.orderRef = "Купить"
    await #expect(throws: IBClientError.encoding(.nonASCII(field: "Купить"))) { try await client.placeOrder(aapl, bad) }
    try await client.cancelOrder(1)   // the next frame out is this one
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    #expect(sent.count == FakeGateway.syncFrames + 1 && sent[FakeGateway.syncFrames][0] == "4")
}

@Test func errorRejectsOwnPendingOrder() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    let (_, updates) = await client.orders()
    let id = try await client.placeOrder(aapl, buy)
    gateway.feed(["4", "2", "\(id)", "201", "Order rejected", ""])
    _ = try await next(updates) { $0.status == .inactive }
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
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 50, timeout: .seconds(3))   // + 50 cancels
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

@Test func exerciseOptionsSendsItsFrame() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    let id = try await client.exerciseOptions(opt, action: .lapse, quantity: 1, account: "DU1", override: true)
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    #expect(sent[FakeGateway.syncFrames] == ["21", "2", "\(id)", "12345", "AAPL", "OPT", "20261218", "150.0", "C", "100", "SMART", "USD",
                                             "AAPL  261218C00150000", "AAPL", "2", "1", "DU1", "1"])
}

@Test func cancelOrderSendsTheManualCancelTime() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    try await client.cancelOrder(101, manualCancelOrderTime: "20261112-15:00:00")
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    #expect(sent[FakeGateway.syncFrames] == ["4", "1", "101", "20261112-15:00:00"])
}

@Test func orderBoundRebindsAManualOrder() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    let (_, updates) = await client.orders()
    gateway.feed(Fixtures.openOrderFields(
        orderID: 0, permID: 5555, clientID: 0, symbol: "AAPL", action: "BUY", quantity: "1", orderType: "LMT",
        limitPrice: "1", auxPrice: unset, tif: "DAY", parentID: "0", outsideRTH: "0", orderRef: "", status: "Submitted"))
    gateway.feed(["100", "5555", "7", "41"])
    gateway.feed(["3", "41", "Filled", "1", "0", "1", "5555", "0", "1", "7", "", "0"])
    let last = try await within2s {
        var last: OrderSnapshot?
        for await s in updates { last = s; if s.orderID == 41 && s.status == .filled { return s } }
        throw TimedOut()
    }
    #expect(last.orderID == 41 && last.status == .filled)
    #expect(await client.orders().snapshot.count == 1)
}

@Test func placeBracketLinksAndTransmitsLast() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    let ids = try await client.placeBracket(aapl, Order.bracket(.buy, quantity: 100, limitPrice: 180, takeProfitPrice: 190, stopLossPrice: 175))
    #expect(ids == (101, 102, 103))
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 3)
    let legs = Array(sent[FakeGateway.syncFrames...])
    #expect(legs.map { Array($0.prefix(2)) } == [["3", "101"], ["3", "102"], ["3", "103"]])
    #expect(legs.map { $0[28] } == ["0", "101", "101"])
    #expect(legs.map { $0[27] } == ["0", "0", "1"])
}

@Test func placeBracketSendsNothingWhenALegFailsToEncode() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    var b = Order.bracket(.buy, quantity: 100, limitPrice: 180, takeProfitPrice: 190, stopLossPrice: 175)
    b.stopLoss.orderRef = "Стоп"
    await #expect(throws: IBClientError.encoding(.nonASCII(field: "Стоп"))) { try await client.placeBracket(aapl, b) }
    try await client.cancelOrder(1)
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    #expect(sent.count == FakeGateway.syncFrames + 1 && sent[FakeGateway.syncFrames][0] == "4")
    #expect(await client.orders().snapshot.isEmpty)
}

@Test func placeBracketRefusesWhatIfAndSendsNothing() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    var b = Order.bracket(.buy, quantity: 100, limitPrice: 180, takeProfitPrice: 190, stopLossPrice: 175)
    b.takeProfit.whatIf = true
    await #expect(throws: IBClientError.encoding(.unsupported("whatIf"))) { try await client.placeBracket(aapl, b) }
    try await client.cancelOrder(1)
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    #expect(sent.count == FakeGateway.syncFrames + 1 && sent[FakeGateway.syncFrames][0] == "4")
    #expect(await client.orders().snapshot.isEmpty)
}

private func submitted(_ id: Int) -> [String] { ["3", "\(id)", "Submitted", "0", "1", "0", "555", "0", "0", "7", "", "0"] }

private func snapshot(of event: OrderEvent) -> OrderSnapshot {
    switch event { case .modified(let s), .cancelRequested(let s): s }
}

@Test func placeOrderPublishesPendingSubmitAtOnce() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    let (_, updates) = await client.orders()
    let id = try await client.placeOrder(aapl, buy)
    let local = try await first(updates)   // before the gateway has answered anything
    #expect(local.orderID == id && local.clientID == 7 && local.status == .pendingSubmit && local.order == buy)
    #expect(local.log.map(\.status) == [.pendingSubmit] && local.log.first?.message == "")
    #expect(await client.orders().snapshot == [local])
    gateway.feed(Fixtures.openOrderFields(
        orderID: id, permID: 555, clientID: 7, symbol: "AAPL", action: "BUY", quantity: "1", orderType: "LMT",
        limitPrice: "1", auxPrice: unset, tif: "DAY", parentID: "0", outsideRTH: "0", orderRef: "",
        status: "PreSubmitted"))
    gateway.feed(submitted(id))
    let acked = try await next(updates) { $0.status == .submitted }
    #expect(acked.permID == 555 && acked.log.map(\.status) == [.pendingSubmit, .preSubmitted, .submitted])
    #expect(await client.orders().snapshot.count == 1)
}

@Test func modifyLogsAndClearsRejectReason() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    let (_, updates) = await client.orders()
    let events = await client.orderEvents()
    let id = try await client.placeOrder(aapl, buy)
    gateway.feed(submitted(id))
    gateway.feed(ibError("\(id)", "110", "The price does not conform to the minimum price variation"))
    let rejected = try await next(updates) { $0.rejectReason != nil }
    #expect(rejected.status == .submitted && rejected.log.last?.errorCode == 110)
    var changed = buy
    changed.limitPrice = d("2")
    try await client.modifyOrder(id, aapl, changed)
    let m = try await next(updates) { $0.log.last?.message == "Modify" }
    #expect(m.rejectReason == nil && m.status == .submitted && m.order.limitPrice == d("2"))
    #expect(try await first(events) == .modified(m))
    gateway.feed(submitted(id))
    let a = try await next(updates) { $0.log.last?.message == "Modified" }
    #expect(a.rejectReason == nil && a.log.map(\.message) == ["", "", "The price does not conform to the minimum price variation", "Modify", "Modified"])
}

@Test func cancelBeforeAcknowledgementEndsCancelled() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    let (_, updates) = await client.orders()
    let events = await client.orderEvents()
    let id = try await client.placeOrder(aapl, buy)
    try await client.cancelOrder(id)
    #expect(await client.orders().snapshot.first?.status == .pendingCancel)
    #expect(snapshot(of: try await first(events)).status == .pendingCancel)
    gateway.feed(ibError("\(id)", "202", "Order Canceled - reason:"))
    let c = try await next(updates) { $0.status == .cancelled }
    #expect(c.log.map(\.status) == [.pendingSubmit, .pendingCancel, .cancelled])

    var held = buy
    held.transmit = false
    let other = try await client.placeOrder(aapl, held)
    try await client.cancelOrder(other)
    let e = try await next(events) { snapshot(of: $0).orderID == other }
    guard case .cancelRequested(let s) = e else { Issue.record("not a cancel: \(e)"); return }
    #expect(s.status == .cancelled && s.log.map(\.status) == [.pendingSubmit, .cancelled])
}

@Test func warningSetsValidationError() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    let (_, updates) = await client.orders()
    let id = try await client.placeOrder(aapl, buy)
    gateway.feed(ibError("\(id)", "321", "Error validating request"))
    let s = try await next(updates) { $0.status == .validationError }
    #expect(s.rejectReason == "Error validating request" && s.isActive && s.isWorking)
    #expect(s.log.last?.message == "Error validating request" && s.log.last?.errorCode == 321)
}

@Test func fillsJoinTheirOrder() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    let (_, updates) = await client.orders()
    let id = try await client.placeOrder(aapl, buy)
    let execID = "0000e0d5.6556b5f0.01.01"
    gateway.feed(["11", "-1", "\(id)", "265598", "AAPL", "STK", "", "0", "", "", "SMART", "USD", "AAPL", "NMS",
                  execID, "20251109 10:00:00", "DU1", "ISLAND", "BOT", "100", "187.25", "918273001", "7", "0",
                  "100", "187.25", "", "", "", "", "1", "0"])
    gateway.feed(["59", "1", execID, "1.5", "USD", unset, unset, ""])
    let s = try await next(updates) { !$0.fills.isEmpty }
    #expect(s.fills.count == 1 && s.fills.first?.execution.execID == execID)
    #expect(s.log.last?.message == "Fill 100@187.25")
}

@Test func bracketPublishesThreeLocalSnapshots() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    let (_, updates) = await client.orders()
    let ids = try await client.placeBracket(aapl, Order.bracket(.buy, quantity: 100, limitPrice: 180,
                                                                takeProfitPrice: 190, stopLossPrice: 175))
    let got = try await within2s {
        var all: [OrderSnapshot] = []
        for await s in updates { all.append(s); if all.count == 3 { return all } }
        throw TimedOut()
    }
    #expect(got.map(\.orderID) == [ids.parent, ids.takeProfit, ids.stopLoss])
    #expect(got.allSatisfy { $0.status == .pendingSubmit && $0.log.count == 1 })
    #expect(got.map(\.order.transmit) == [false, false, true])
    #expect(got.map(\.order.parentID) == [0, ids.parent, ids.parent])
}
