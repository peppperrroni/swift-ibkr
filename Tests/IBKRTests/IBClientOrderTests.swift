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
    await #expect(throws: IBClientError.notConnected) { try await client.send(.currentTime) }
    gateway.close()
    await #expect(throws: IBClientError.connectionClosed) { try await within2s { try await connecting.value } }
}

/// ib_async raises the id sequence past any order id it sees (wrapper.py:714-717), another client's included.
@Test func openOrderRaisesTheIDSequence() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    let (_, updates) = await client.orders()
    gateway.feed(Fixtures.openOrderFields(
        orderID: 500, permID: 900, clientID: 3, symbol: "AAPL", action: "BUY", quantity: "1", orderType: "LMT",
        limitPrice: "1", auxPrice: unset, tif: "DAY", parentID: "0", outsideRTH: "0", orderRef: "", status: "Submitted"))
    _ = try await next(updates) { $0.orderID == 500 }
    #expect(try await client.placeOrder(aapl, buy) >= 501)
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

/// ib_async keeps the caller's own order for a trade it placed and copies permId, totalQuantity, lmtPrice,
/// auxPrice, orderType and orderRef from openOrder (wrapper.py:687-693): a modify from the snapshot re-sends the
/// caller's values, not the gateway's echo (`right` `?`, deltaNeutralOpenClose `?`, clearingIntent `IB`, …).
@Test func modifyFromSnapshotResendsTheCallersOwnOrder() async throws {
    let echo = try #require(try recording("liveLimitOrderPlacesAndCancels").first { $0.first == "5" })
    let gateway = FakeGateway(nextValidID: 1)
    let client = IBClient(connector: gateway.connector)
    try await within2s { try await client.connect(clientID: 77) }
    let (_, updates) = await client.orders()
    var mine = buy
    mine.totalQuantity = 3; mine.orderType = "STP LMT"; mine.limitPrice = d("2"); mine.orderRef = "mine"
    #expect(try await client.placeOrder(aapl, mine) == 2)
    gateway.feed(echo)   // orderID 2, client 77, permID 610467324, 1 LMT @ 1, auxPrice 0, orderRef ""
    let s = try await next(updates) { $0.permID == 610467324 }
    var expected = mine
    expected.totalQuantity = 1; expected.orderType = "LMT"; expected.limitPrice = d("1"); expected.auxPrice = 0
    expected.orderRef = ""
    #expect(s.contract == aapl)
    #expect(s.order == expected)
    #expect(s.status == .preSubmitted)
    try await client.modifyOrder(2, s.contract, s.order)
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 2)
    let own = FieldReader(try IBRequest.placeOrder(orderID: 2, contract: aapl, order: expected).body()).fields
    #expect(sent[FakeGateway.syncFrames + 1] == own)
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

/// The gateway's stream stays open after the close, so the frame does reach `receive`: its generation guard drops it.
@Test func frameAfterDisconnectIsIgnored() async throws {
    let gateway = FakeGateway(staysOpenAfterClose: true)
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

/// The old gateway's last bytes arrive after a reconnect: `receive`'s generation guard keeps them out of the new
/// connection's frame reader, which would otherwise read the partial header as the start of the next frame.
@Test func staleChunkAfterReconnectIsIgnored() async throws {
    let (one, two) = (FakeGateway(staysOpenAfterClose: true), FakeGateway())
    let client = IBClient(connector: Gateways([one, two]).connector)
    try await within2s { try await client.connect(clientID: 7) }
    await client.disconnect()
    try await within2s { try await client.connect(clientID: 7) }
    let messages = await client.messages()
    one.feedRaw([0, 0, 0])   // a partial header from the old connection
    try await Task.sleep(for: .milliseconds(100))   // lets the old reader hand it over first
    two.feed(["49", "1", "1700000000"])
    let got = try await within2s { () async throws -> IBMessage in
        for await m in messages { return m }
        throw TimedOut()
    }
    #expect(got == .currentTime(1_700_000_000))
}

/// A consumer stop from the first connection that reaches the actor only after a reconnect reused its reqId. The
/// stop is the stream's termination hop (`stopped`) called with the old generation: a real one cannot be delayed
/// past a reconnect on purpose.
@Test func lateStopDoesNotCancelAReusedID() async throws {
    let (one, two) = (FakeGateway(nextValidID: 100), FakeGateway(nextValidID: 100))
    let client = IBClient(connector: Gateways([one, two]).connector)
    try await within2s { try await client.connect(clientID: 7) }
    let oldGeneration = await client.generation
    _ = try await client.marketData(aapl)
    let id = try await one.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames][2]
    await client.disconnect()
    try await within2s { try await client.connect(clientID: 7) }
    let second = try await client.marketData(aapl)
    #expect(try await two.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames][2] == id)   // reused
    await client.stopped(Int(id)!, oldGeneration)
    try await client.cancelOrder(1)   // a marker: whatever the stop sent has left before it
    #expect(!(try await two.waitForSent(FakeGateway.syncFrames + 2)).contains(["2", "2", id]))
    let (_, result) = take(1, second)
    two.feed(["2", "6", id, "0", "300"])
    #expect(try await within2s { try await result.value }.count == 1)
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

/// A bracket leg's snapshot keeps the `transmit` false `placeBracket` gave the parent, as ib_async's Trade keeps
/// the user's order: re-sent from the snapshot it is staged, not transmitted, unless the caller sets `transmit`.
@Test func bracketParentModifiedFromItsSnapshotKeepsTransmitOff() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    let (_, updates) = await client.orders()
    let ids = try await client.placeBracket(aapl, Order.bracket(.buy, quantity: 100, limitPrice: 180, takeProfitPrice: 190, stopLossPrice: 175))
    gateway.feed(Fixtures.openOrderFields(
        orderID: ids.parent, permID: 901, clientID: 7, symbol: "AAPL", action: "BUY", quantity: "100", orderType: "LMT",
        limitPrice: "180", auxPrice: unset, tif: "DAY", parentID: "0", outsideRTH: "0", orderRef: "", status: "PreSubmitted"))
    let s = try await next(updates) { $0.orderID == ids.parent && $0.permID == 901 }
    #expect(!s.order.transmit)
    try await client.modifyOrder(ids.parent, s.contract, s.order)
    var transmitted = s.order
    transmitted.transmit = true
    try await client.modifyOrder(ids.parent, s.contract, transmitted)
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 5)
    #expect(sent[FakeGateway.syncFrames + 3].prefix(2) == ["3", "101"] && sent[FakeGateway.syncFrames + 3][27] == "0")
    #expect(sent[FakeGateway.syncFrames + 4].prefix(2) == ["3", "101"] && sent[FakeGateway.syncFrames + 4][27] == "1")
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

@Test func placingANewOrderIsNoModifyEvent() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    let events = await client.orderEvents()
    let id = try await client.placeOrder(aapl, buy)
    try await client.cancelOrder(id)
    guard case .cancelRequested(let s) = try await first(events) else {
        Issue.record("the new order's placement yielded an event")
        return
    }
    #expect(s.orderID == id)
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
