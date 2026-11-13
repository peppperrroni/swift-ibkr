import Foundation
import Testing
@testable import IBKR

// Order scenarios through the real IBClient against SimulatedBroker; every frame the broker emits must be in the
// oracle's corpus (Tests/IBKRTests/Oracle/corpus.json), so ib_async has decoded it.

/// AAPL as the recordings trade it.
private let aapl: Contract = { var c = Contract(symbol: "AAPL"); c.conID = 265598; return c }()

private func limit(_ action: OrderAction, _ quantity: Decimal, _ price: String) -> Order {
    Order(action: action, quantity: quantity, orderType: "LMT", limitPrice: d(price))
}

private func connected(_ broker: SimulatedBroker, clientID: Int) async throws -> IBClient {
    let client = IBClient(connector: broker.connector)
    try await within2s { try await client.connect(clientID: clientID) }
    return client
}

/// The first element matching `predicate`, failing after 2 s.
private func next<T: Sendable>(_ stream: AsyncStream<T>, _ predicate: @escaping @Sendable (T) -> Bool) async throws -> T {
    try await within2s {
        for await x in stream where predicate(x) { return x }
        throw TimedOut()
    }
}

/// The order's distinct statuses on `stream`, in order, up to and including `last`.
private func statuses(_ stream: AsyncStream<OrderSnapshot>, orderID: Int, until last: OrderStatus) async throws
    -> [OrderStatus] {
    try await within2s {
        var seen: [OrderStatus] = []
        for await s in stream where s.orderID == orderID && seen.last != s.status {
            seen.append(s.status)
            if s.status == last { return seen }
        }
        throw TimedOut()
    }
}

/// The latest snapshot of each order on `stream`, once `done` holds for them.
private func until(_ stream: AsyncStream<OrderSnapshot>, _ done: @escaping @Sendable ([Int: OrderSnapshot]) -> Bool)
    async throws -> [Int: OrderSnapshot] {
    try await within2s {
        var latest: [Int: OrderSnapshot] = [:]
        for await s in stream {
            latest[s.orderID] = s
            if done(latest) { return latest }
        }
        throw TimedOut()
    }
}

/// Place LMT BUY 100, fill 40 then 60: the client sees each status, the partial fill, both fills on the order, the
/// position, and the portfolio revalued at a new market price.
private func placePartialFill(_ client: IBClient, _ broker: SimulatedBroker, clientID: Int) async throws {
    let (_, orders) = await client.orders()
    let (_, fills) = await client.executions()
    let (_, positions) = await client.positions()
    let (_, portfolio) = await client.portfolio()
    let id = try await client.placeOrder(aapl, limit(.buy, 100, "187.25"))
    #expect(try await statuses(orders, orderID: id, until: .submitted) == [.pendingSubmit, .preSubmitted, .submitted])

    broker.fill(orderID: id, clientID: clientID, shares: 40, price: d("187.2"))
    let partial = try await next(orders) { $0.orderID == id && $0.filled == 40 }
    #expect(partial.remaining == 60 && partial.status == .submitted)
    let fill = try await next(fills) { _ in true }
    #expect(fill.execution.orderID == id && fill.execution.shares == 40 && fill.execution.price == d("187.2"))
    #expect(fill.commission.commission == 1)

    broker.fill(orderID: id, clientID: clientID, shares: 60, price: d("187.25"))
    let done = try await next(orders) { $0.orderID == id && $0.status == .filled }
    #expect(done.filled == 100 && done.remaining == 0)
    let both = try await next(orders) { $0.orderID == id && $0.fills.count == 2 }
    #expect(both.averageFillPrice == d("187.23") && both.lastFillPrice == d("187.25"))
    #expect(both.fills.map(\.execution.shares) == [40, 60] && both.fills.map(\.commission.commission) == [1, 1])
    #expect(both.permID > 0 && both.permID == broker.order(clientID: clientID, orderID: id)?.permID)
    #expect(both.fills.allSatisfy { $0.execution.permID == both.permID })
    let held = try await next(positions) { $0.first?.quantity == 100 }
    #expect(held.map(\.contract.conID) == [265598])
    #expect(broker.order(clientID: clientID, orderID: id)?.filled == 100)
    #expect(broker.position(account: "DU0000001", conID: 265598) == (100, d("187.25")))   // commissions included

    broker.setMarketPrice(conID: 265598, d("190"))
    let valued = try await next(portfolio) { $0.first?.marketPrice == d("190") }
    #expect(valued.map(\.quantity) == [100] && valued.map(\.averageCost) == [d("187.25")])
    #expect(valued.map(\.marketValue) == [19000] && valued.map(\.unrealizedPNL) == [275])
}

@Test func placedOrderGoesSubmittedPartialFilled() async throws {
    let broker = SimulatedBroker()
    let client = try await connected(broker, clientID: 7)
    try await placePartialFill(client, broker, clientID: 7)
    await expectInCorpus(broker.emitted, source: "sim/placedOrderGoesSubmittedPartialFilled")
}

/// The same lifecycle with the client on a real TCP socket: loopback, bridged to the broker's gateway.
@Test func placedOrderGoesSubmittedPartialFilledOverLoopback() async throws {
    let broker = SimulatedBroker()
    let listener = Listener()
    let pump = Task {
        let peer = await listener.acceptOffPool()
        listener.close()   // here, not in a defer: a throw must not free the fd while the accept thread still polls it
        guard let peer else { return }
        await bridge(peer, broker.newGateway()).value
    }
    let client = IBClient()
    try await within2s { try await client.connect(host: "127.0.0.1", port: listener.port, clientID: 7) }
    try await placePartialFill(client, broker, clientID: 7)
    await client.disconnect()
    try await within2s { await pump.value }
    await expectInCorpus(broker.emitted, source: "sim/placedOrderGoesSubmittedPartialFilledOverLoopback")
}

@Test func syncReplaysTheBook() async throws {
    let broker = SimulatedBroker()
    let first = try await connected(broker, clientID: 7)
    let (_, orders) = await first.orders()
    let working = try await first.placeOrder(aapl, limit(.buy, 100, "187.25"))
    _ = try await next(orders) { $0.orderID == working && $0.status == .submitted }
    let closing = try await first.placeOrder(aapl, limit(.sell, 10, "187.5"))
    _ = try await next(orders) { $0.orderID == closing && $0.status == .submitted }
    broker.fill(orderID: working, clientID: 7, shares: 40, price: d("187.2"))
    broker.fill(orderID: closing, clientID: 7, shares: 10, price: d("187.5"), commission: d("1.25"))
    _ = try await next(orders) { $0.orderID == closing && $0.status == .filled }

    let second = try await connected(broker, clientID: 8)
    let book = await second.orders().snapshot
    let open = book.first { $0.orderID == working }
    #expect(open?.clientID == 7 && open?.status == .submitted && open?.filled == 40 && open?.remaining == 60)
    let completed = book.first { $0.permID == broker.order(clientID: 7, orderID: closing)?.permID }
    #expect(completed?.status == .filled && completed?.filled == 10)
    let fills = await second.executions().snapshot
    #expect(fills.map(\.execution.shares) == [40, 10])
    #expect(fills.map(\.commission.commission) == [1, d("1.25")])
    // (187.5 - 187.225) × 10 - 1.25, the cost of the 40 bought including their commission of 1
    #expect(fills.last?.commission.realizedPNL == d("1.5"))
    let positions = await second.positions().snapshot
    #expect(positions.map(\.quantity) == [30] && positions.map(\.averageCost) == [d("187.225")])
    await expectInCorpus(broker.emitted, source: "sim/syncReplaysTheBook")
}

/// A modify re-sends the caller's own order from the snapshot (openOrder's echo, with its `?` placeholders and the
/// live `None` delta-neutral type, only updates the quantity, prices, type and orderRef) with a new limit; IB echoes
/// openOrder + orderStatus.
@Test func modifyKeepsTheOrderAndLogsModified() async throws {
    let broker = SimulatedBroker()
    let client = try await connected(broker, clientID: 7)
    let (_, orders) = await client.orders()
    let events = await client.orderEvents()
    let id = try await client.placeOrder(aapl, limit(.buy, 100, "187.25"))
    let working = try await next(orders) { $0.orderID == id && $0.status == .submitted }
    var changed = working.order
    changed.limitPrice = d("187.5")
    try await client.modifyOrder(id, working.contract, changed)
    guard case .modified(let modified) = try await next(events, { _ in true }) else {
        Issue.record("no .modified event"); return
    }
    #expect(modified.orderID == id && modified.order.limitPrice == d("187.5"))
    let acknowledged = try await next(orders) { $0.orderID == id && $0.log.last?.message == "Modified" }
    #expect(acknowledged.log.suffix(2).map(\.message) == ["Modify", "Modified"])
    #expect(acknowledged.status == .submitted && acknowledged.order.limitPrice == d("187.5"))
    #expect(acknowledged.permID == working.permID)
    let booked = broker.order(clientID: 7, orderID: id)
    #expect(booked?.limitPrice == d("187.5") && booked?.permID == working.permID && booked?.status == .submitted)
    await expectInCorpus(broker.emitted, source: "sim/modifyKeepsTheOrderAndLogsModified")
}

/// cancelOrder → openOrder + PendingCancel twice, Cancelled, then 202 with a bare reason, which leaves
/// `rejectReason` unset (DECISIONS' 202 row).
@Test func cancelFollowsTheRecordedSequence() async throws {
    let broker = SimulatedBroker()
    let client = try await connected(broker, clientID: 7)
    let (_, orders) = await client.orders()
    let events = await client.orderEvents()
    let id = try await client.placeOrder(aapl, limit(.buy, 100, "187.25"))
    _ = try await next(orders) { $0.orderID == id && $0.status == .submitted }
    try await client.cancelOrder(id)
    guard case .cancelRequested(let requested) = try await next(events, { _ in true }) else {
        Issue.record("no .cancelRequested event"); return
    }
    #expect(requested.status == .pendingCancel)
    let cancelled = try await next(orders) { $0.orderID == id && $0.log.last?.errorCode == 202 }
    #expect(cancelled.status == .cancelled && cancelled.rejectReason == nil)
    #expect(cancelled.log.suffix(3).map(\.status) == [.pendingCancel, .cancelled, .cancelled])
    #expect(cancelled.log.last?.message == "Order Canceled - reason:")
    #expect(broker.order(clientID: 7, orderID: id)?.status == .cancelled)
    await expectInCorpus(broker.emitted, source: "sim/cancelFollowsTheRecordedSequence")
}

/// IB refuses a new order with 201 before acknowledging it: the client ends it `.inactive` with IB's text.
@Test func rejectedOrderEndsInactive() async throws {
    let text = "Order rejected - reason:YOUR ORDER IS NOT ACCEPTED. IN ORDER TO OBTAIN THE DESIRED POSITION YOUR "
        + "EQUITY WITH LOAN VALUE [0.00 USD] MUST EXCEED THE INITIAL MARGIN [9362.50 USD]"
    let broker = SimulatedBroker()
    let client = try await connected(broker, clientID: 7)
    let (_, orders) = await client.orders()
    broker.reject(nextOrderWith: 201, text: text)
    let id = try await client.placeOrder(aapl, limit(.buy, 100, "187.25"))
    let rejected = try await next(orders) { $0.orderID == id && $0.status.isFinal }
    #expect(rejected.status == .inactive && rejected.rejectReason == text && rejected.permID == 0)
    #expect(rejected.log.last?.errorCode == 201)
    #expect(broker.order(clientID: 7, orderID: id) == nil)
    await expectInCorpus(broker.emitted, source: "sim/rejectedOrderEndsInactive")
}

/// A warning on a modification (105) leaves the order working at IB with its old terms; the client marks it
/// `.validationError`, still active, with IB's text (DECISIONS' warning row).
@Test func warnedModifyKeepsTheOrderLive() async throws {
    let text = "Order being modified does not match original order"
    let broker = SimulatedBroker()
    let client = try await connected(broker, clientID: 7)
    let (_, orders) = await client.orders()
    let id = try await client.placeOrder(aapl, limit(.buy, 100, "187.25"))
    let working = try await next(orders) { $0.orderID == id && $0.status == .submitted }
    broker.reject(nextOrderWith: 105, text: text)
    var changed = working.order
    changed.limitPrice = d("187.5")
    try await client.modifyOrder(id, working.contract, changed)
    let warned = try await next(orders) { $0.orderID == id && $0.log.last?.errorCode == 105 }
    #expect(warned.status == .validationError && warned.isActive && warned.rejectReason == text)
    let booked = broker.order(clientID: 7, orderID: id)
    #expect(booked?.limitPrice == d("187.25") && booked?.status == .submitted)
    await expectInCorpus(broker.emitted, source: "sim/warnedModifyKeepsTheOrderLive")
}

/// placeBracket: the legs sent with transmit off get no answer until the stop-loss transmits the group; the
/// children wait PreSubmitted under their parent, work once it fills, and the take-profit's fill cancels the stop.
@Test func bracketHoldsUntilTheLastLegAndCancelsTheSibling() async throws {
    let broker = SimulatedBroker()
    let client = try await connected(broker, clientID: 7)
    let (_, orders) = await client.orders()
    let ids = try await client.placeBracket(aapl, Order.bracket(.buy, quantity: 100, limitPrice: d("187.25"),
                                                          takeProfitPrice: 190, stopLossPrice: 185))
    let sent = try await until(orders) { s in
        s[ids.parent]?.status == .submitted && s[ids.takeProfit]?.status == .preSubmitted
            && s[ids.stopLoss]?.status == .preSubmitted
    }
    #expect(broker.answers.filter { $0.request.first == "3" }.map(\.replies.isEmpty) == [true, true, false])
    #expect(sent[ids.takeProfit]?.order.parentID == ids.parent && sent[ids.stopLoss]?.order.parentID == ids.parent)
    #expect(sent[ids.stopLoss]?.order.orderType == "STP" && sent[ids.stopLoss]?.order.auxPrice == 185)

    broker.fill(orderID: ids.parent, clientID: 7, shares: 100, price: d("187.25"))
    _ = try await until(orders) { s in
        s[ids.parent]?.status == .filled && s[ids.takeProfit]?.status == .submitted
            && s[ids.stopLoss]?.status == .submitted
    }
    broker.fill(orderID: ids.takeProfit, clientID: 7, shares: 100, price: 190)
    let done = try await until(orders) { s in
        s[ids.takeProfit]?.status == .filled && s[ids.stopLoss]?.status == .cancelled
    }
    #expect(done[ids.stopLoss]?.filled == 0 && done[ids.stopLoss]?.isActive == false)
    #expect(broker.order(clientID: 7, orderID: ids.stopLoss)?.status == .cancelled)
    #expect(broker.position(account: "DU0000001", conID: 265598).quantity == 0)
    await expectInCorpus(broker.emitted, source: "sim/bracketHoldsUntilTheLastLegAndCancelsTheSibling")
}

/// Two limits in one OCA group (type 1, cancel the rest): one fills, IB cancels the other.
@Test func ocaFillCancelsTheOthers() async throws {
    let broker = SimulatedBroker()
    let client = try await connected(broker, clientID: 7)
    let (_, orders) = await client.orders()
    let legs = Order.oneCancelsAll([limit(.buy, 100, "187"), limit(.buy, 100, "186")], group: "exit-1", type: 1)
    let first = try await client.placeOrder(aapl, legs[0])
    let second = try await client.placeOrder(aapl, legs[1])
    _ = try await until(orders) { s in s[first]?.status == .submitted && s[second]?.status == .submitted }
    broker.fill(orderID: first, clientID: 7, shares: 100, price: 187)
    let done = try await until(orders) { s in s[first]?.status == .filled && s[second]?.status == .cancelled }
    #expect(done[second]?.order.ocaGroup == "exit-1" && done[second]?.filled == 0)
    #expect(broker.order(clientID: 7, orderID: second)?.status == .cancelled)
    await expectInCorpus(broker.emitted, source: "sim/ocaFillCancelsTheOthers")
}

/// whatIfOrder: one openOrder with whatIf set and the margins; no orderStatus, nothing booked on either side.
@Test func whatIfReturnsMarginsAndBooksNothing() async throws {
    let broker = SimulatedBroker()
    let client = try await connected(broker, clientID: 7)
    let state = try await within2s { try await client.whatIfOrder(aapl, limit(.buy, 100, "187.25")) }
    // the broker's rule: 50 % / 25 % of the 18725 notional, equity 1,000,000 less the commission of 1
    #expect(state.initMarginBefore == 0 && state.maintMarginBefore == 0 && state.equityWithLoanBefore == 1_000_000)
    #expect(state.initMarginChange == d("9362.5") && state.maintMarginChange == d("4681.25"))
    #expect(state.equityWithLoanChange == -1 && state.equityWithLoanAfter == 999_999)
    #expect(state.initMarginAfter == d("9362.5") && state.maintMarginAfter == d("4681.25"))
    #expect(state.commission == 1 && state.commissionCurrency == "USD")
    #expect(await client.orders().snapshot.isEmpty)
    #expect(broker.bookedOrders.isEmpty && !broker.emitted.contains { $0.first == "3" })
    await expectInCorpus(broker.emitted, source: "sim/whatIfReturnsMarginsAndBooksNothing")
}
