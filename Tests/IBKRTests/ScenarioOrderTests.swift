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

/// Place LMT BUY 100, fill 40 then 60: the client sees each status, the partial fill and the position.
private func placePartialFill(_ client: IBClient, _ broker: SimulatedBroker, clientID: Int) async throws {
    let (_, orders) = await client.orders()
    let (_, fills) = await client.executions()
    let (_, positions) = await client.positions()
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
    let held = try await next(positions) { $0.first?.quantity == 100 }
    #expect(held.map(\.contract.conID) == [265598])
    #expect(broker.order(clientID: clientID, orderID: id)?.filled == 100)
    #expect(broker.position(account: "DU0000001", conID: 265598).quantity == 100)
}

@Test func placedOrderGoesSubmittedPartialFilled() async throws {
    let broker = SimulatedBroker()
    let client = try await connected(broker, clientID: 7)
    try await placePartialFill(client, broker, clientID: 7)
    expectInCorpus(broker.emitted, source: "sim/placedOrderGoesSubmittedPartialFilled")
}

/// The same lifecycle with the client on a real TCP socket: loopback, bridged to the broker's gateway.
@Test func placedOrderGoesSubmittedPartialFilledOverLoopback() async throws {
    let broker = SimulatedBroker()
    let listener = Listener()
    let pump = Task { bridge(await listener.acceptOffPool(), broker.newGateway()) }
    let client = IBClient()
    try await within2s { try await client.connect(host: "127.0.0.1", port: listener.port, clientID: 7) }
    try await placePartialFill(client, broker, clientID: 7)
    await client.disconnect()
    try await within2s { await pump.value.value }
    expectInCorpus(broker.emitted, source: "sim/placedOrderGoesSubmittedPartialFilledOverLoopback")
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
    expectInCorpus(broker.emitted, source: "sim/syncReplaysTheBook")
}
