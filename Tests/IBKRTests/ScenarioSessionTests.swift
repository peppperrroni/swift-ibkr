import Foundation
import Testing
@testable import IBKR

// Account, session and fault scenarios through the real IBClient against SimulatedBroker; every frame the broker
// emits must be in the oracle's corpus (Tests/IBKRTests/Oracle/corpus.json), so ib_async has decoded it.

/// AAPL as the recordings trade it.
private let aapl: Contract = { var c = Contract(symbol: "AAPL"); c.conID = 265598; return c }()

private func limit(_ action: OrderAction, _ quantity: Decimal, _ price: String) -> Order {
    Order(action: action, quantity: quantity, orderType: "LMT", limitPrice: d(price))
}

private func connected(_ broker: SimulatedBroker, clientID: Int, reconnect: ReconnectPolicy? = nil) async throws
    -> IBClient {
    let client = IBClient(connector: broker.connector)
    try await within2s { try await client.connect(clientID: clientID, reconnect: reconnect) }
    return client
}

/// The first element matching `predicate`, failing after 2 s.
private func next<T: Sendable>(_ stream: AsyncStream<T>, _ predicate: @escaping @Sendable (T) -> Bool) async throws -> T {
    try await within2s {
        for await x in stream where predicate(x) { return x }
        throw TimedOut()
    }
}

/// The stream's first element; the consumer then stops.
private func first<T: Sendable>(_ stream: AsyncThrowingStream<T, any Error>) async throws -> T {
    let (reader, result) = take(1, stream)
    defer { reader.cancel() }
    guard let x = try await within2s({ try await result.value }).first else { throw TimedOut() }
    return x
}

/// Returns once `condition` holds of what the broker observed, failing after 2 s.
private func until(_ condition: @escaping @Sendable () -> Bool) async throws {
    try await within2s { while !condition() { try await Task.sleep(for: .milliseconds(5)) } }
}

/// BUY 100 in two fills, SELL 40: positions, the portfolio, both P&L requests, the fills and their commission reports
/// tell one story.
@Test func positionsPnlAndExecutionsAgreeAfterFills() async throws {
    let broker = SimulatedBroker()
    let client = try await connected(broker, clientID: 7)
    let (_, orders) = await client.orders()
    let (_, portfolio) = await client.portfolio()
    let buy = try await client.placeOrder(aapl, limit(.buy, 100, "187.25"))
    _ = try await next(orders) { $0.orderID == buy && $0.status == .submitted }
    broker.fill(orderID: buy, clientID: 7, shares: 40, price: d("187.2"))
    broker.fill(orderID: buy, clientID: 7, shares: 60, price: d("187.25"))
    let sell = try await client.placeOrder(aapl, limit(.sell, 40, "188"))
    _ = try await next(orders) { $0.orderID == sell && $0.status == .submitted }
    broker.fill(orderID: sell, clientID: 7, shares: 40, price: 188)
    // the portfolio update is the last frame of a fill: everything before it is in the client's state
    let valued = try await next(portfolio) { $0.first?.quantity == 60 }

    let fills = await client.executions().snapshot
    let signed = fills.map { $0.execution.side == "BOT" ? $0.execution.shares : -$0.execution.shares }.reduce(0, +)
    #expect(fills.count == 3 && signed == 60)
    #expect(await client.positions().snapshot.map(\.quantity) == [signed])
    #expect(valued.map(\.quantity) == [signed])
    let single = try await first(try await client.pnlSingle(account: "DU0000001", conID: 265598))
    #expect(single.position == signed)
    let account = try await first(try await client.pnl(account: "DU0000001"))
    let realized = fills.compactMap(\.commission.realizedPNL).reduce(0, +)
    // (188 - 187.25) × 40 - 1, the 100 bought costing 187.25 with their commissions
    #expect(realized == 29 && account.realized == realized && single.realized == realized)
    #expect(single.unrealized == valued.first?.unrealizedPNL && account.unrealized == single.unrealized)
    #expect(single.value == valued.first?.marketValue && single.daily == account.daily)
    #expect(broker.position(account: "DU0000001", conID: 265598) == (60, d("187.25")))
    await expectInCorpus(broker.emitted, source: "sim/positionsPnlAndExecutionsAgreeAfterFills")
}

/// A drop with an order working and a quote stream open: the stream ends, the state goes disconnected → connecting →
/// connected, and the sync brings back the order, the position and the fill booked during the outage; the part fill
/// the client saw before the drop is not counted twice.
@Test func reconnectMidStreamRecoversTheBook() async throws {
    let broker = SimulatedBroker()
    let client = try await connected(broker, clientID: 7, reconnect: ReconnectPolicy(delays: [.milliseconds(20)]))
    let (_, orders) = await client.orders()
    let id = try await client.placeOrder(aapl, limit(.buy, 100, "187.25"))
    _ = try await next(orders) { $0.orderID == id && $0.status == .submitted }
    broker.fill(orderID: id, clientID: 7, shares: 40, price: d("187.2"))
    _ = try await next(orders) { $0.orderID == id && $0.fills.count == 1 }
    let (_, quotes) = take(0, try await client.marketData(aapl))
    try await until { broker.openMarketData.count == 1 }
    let states = await client.states()

    // booked while connects are refused, so the policy's 20 ms cannot let the client back in first; an outage longer
    // than that only adds refused attempts, during which the client stays .connecting
    await broker.drop {
        try? await Task.sleep(for: .milliseconds(100))
        broker.fill(orderID: id, clientID: 7, shares: 60, price: d("187.25"))
    }
    await #expect(throws: IBClientError.connectionClosed) { try await within2s { try await quotes.value } }
    let seen = try await within2s {
        var seen: [ConnectionState] = []
        for await s in states {
            seen.append(s)
            if case .connected = s, seen.count > 1 { return seen }
        }
        throw TimedOut()
    }
    #expect(seen.dropFirst().dropLast() == [.disconnected(.connectionClosed), .connecting])

    let booked = try #require(broker.order(clientID: 7, orderID: id))
    let book = await client.orders().snapshot
    #expect(book.map(\.orderID) == [id] && book.map(\.permID) == [booked.permID])
    #expect(book.map(\.status) == [.filled] && book.map(\.filled) == [booked.filled])
    #expect(book.first?.fills.map(\.execution.shares) == [40, 60])
    let fills = await client.executions().snapshot
    #expect(fills.map(\.execution.shares) == [40, 60] && Set(fills.map(\.execution.permID)) == [booked.permID])
    let held = broker.position(account: "DU0000001", conID: 265598)
    let positions = await client.positions().snapshot
    #expect(positions.map(\.quantity) == [held.quantity] && positions.map(\.averageCost) == [held.averageCost])
    #expect(broker.openMarketData.isEmpty && broker.gateways.count == 2)   // nothing outside the sync is resent
    await expectInCorpus(broker.emitted, source: "sim/reconnectMidStreamRecoversTheBook")
    await client.disconnect()
}

/// Clients 1 and 2 on one broker each place order 1 and see only their own; client 0 binds no API client's order;
/// positions are the account's; reqAllOpenOrders and reqExecutions by clientId reach across clients.
@Test func twoClientsSeeTheirOwnOrdersAndOneBook() async throws {
    let broker = SimulatedBroker(nextOrderID: 0)   // the sync's reqExecutions takes 0, so each first order is 1
    let one = try await connected(broker, clientID: 1)
    let two = try await connected(broker, clientID: 2)
    let tws = try await connected(broker, clientID: 0)
    let (_, ordersOne) = await one.orders(), (_, ordersTwo) = await two.orders()
    let (_, positionsOne) = await one.positions(), (_, positionsTwo) = await two.positions()
    // one at a time: the broker numbers permIDs by arrival, and the corpus holds one numbering
    #expect(try await one.placeOrder(aapl, limit(.buy, 100, "187.25")) == 1)
    _ = try await next(ordersOne) { $0.orderID == 1 && $0.status == .submitted }
    #expect(try await two.placeOrder(aapl, limit(.buy, 50, "187.3")) == 1)
    _ = try await next(ordersTwo) { $0.orderID == 1 && $0.status == .submitted }
    #expect(await one.orders().snapshot.map(\.clientID) == [1])
    #expect(await two.orders().snapshot.map(\.clientID) == [2])
    // client 0's sync binds first (DECISIONS' reqAutoOpenOrders row); the others never send it
    let sent = try await (broker.gateways[0].waitForSent(0), broker.gateways[1].waitForSent(0),
                          broker.gateways[2].waitForSent(0))
    #expect(sent.2[1] == ["15", "1", "1"])
    #expect(!sent.0.contains { $0.first == "15" } && !sent.1.contains { $0.first == "15" })
    _ = try await within2s { try await tws.currentTime() }   // a round trip: whatever was fed before has been read
    #expect(await tws.orders().snapshot.isEmpty)

    for client in [one, two] {
        let all = try await within2s { try await client.fetchAllOpenOrders() }
        #expect(all.map(\.clientID).sorted() == [1, 2] && all.map(\.orderID) == [1, 1])
    }
    broker.fill(orderID: 1, clientID: 1, shares: 100, price: d("187.25"))
    broker.fill(orderID: 1, clientID: 2, shares: 50, price: d("187.3"))
    #expect(try await next(positionsOne) { $0.first?.quantity == 150 }.count == 1)
    #expect(try await next(positionsTwo) { $0.first?.quantity == 150 }.count == 1)
    _ = try await next(ordersTwo) { $0.orderID == 1 && $0.fills.count == 1 }   // 61 comes before the fill (as live)
    #expect(await one.executions().snapshot.map(\.execution.clientID) == [1])
    #expect(await two.executions().snapshot.map(\.execution.clientID) == [2])
    let theirs = try await within2s { try await one.executions(filter: ExecutionFilter(clientID: 2)) }
    #expect(theirs.map(\.execution.clientID) == [2] && theirs.map(\.execution.shares) == [50])
    await expectInCorpus(broker.emitted, source: "sim/twoClientsSeeTheirOwnOrdersAndOneBook")
}

/// A consumer that stops its quotes, P&L or ticker sends the cancel (2, 93, 2); the broker then feeds no tick.
@Test func stoppingAStreamSendsItsCancelAndTheBrokerStops() async throws {
    let broker = SimulatedBroker()
    let client = try await connected(broker, clientID: 7)
    let (quotesReader, quotes) = take(1, try await client.marketData(aapl))
    let (pnlReader, pnl) = take(1, try await client.pnl(account: "DU0000001"))
    let (tickerReader, tickers) = take(1, try await client.tickers(aapl))
    try await until { broker.openMarketData.count == 2 }
    let lines = broker.openMarketData
    broker.tick(conID: 265598, field: 4, price: d("187.5"))
    #expect(try await within2s { try await quotes.value } == [.price(.last, price: d("187.5"), size: 0)])
    #expect(try await within2s { try await tickers.value }.first?.last == d("187.5"))
    #expect(try await within2s { try await pnl.value }.count == 1)

    for reader in [quotesReader, pnlReader, tickerReader] { reader.cancel() }
    let pnlID = try #require(broker.answers.first { $0.request.first == "92" }?.request[1])
    let expected: Set = [["2", "2", "\(lines[0])"], ["2", "2", "\(lines[1])"], ["93", pnlID]]
    try await until { expected.isSubset(of: broker.answers.map(\.request)) }
    #expect(broker.openMarketData.isEmpty)
    let fed = broker.emitted.count
    broker.tick(conID: 265598, field: 4, price: 188)
    #expect(broker.emitted.count == fed)
    await expectInCorpus(broker.emitted, source: "sim/stoppingAStreamSendsItsCancelAndTheBrokerStops")
}

/// An injected IB error reaches the stream as its typed error, and delayed replies still answer.
@Test func faultsSurfaceTyped() async throws {
    let text = "No market data during competing live session"   // liveMarketData.json#10
    let broker = SimulatedBroker()
    let client = try await connected(broker, clientID: 7)
    broker.failNext("1", code: 10197, text: text)
    let (_, refused) = take(0, try await client.marketData(aapl))
    await #expect(throws: IBClientError.noMarketDataPermission(code: 10197, text: text)) {
        try await within2s { try await refused.value }
    }
    // a permission refusal still sends its cancel (DECISIONS: IB keeps that line open)
    let id = try #require(broker.answers.last { $0.request.first == "1" }?.request[2])
    try await until { broker.answers.contains { $0.request == ["2", "2", id] } }
    // on a P&L request's reqId the error ends that stream; with reqId -1 it ends the id-less one-shot waiting (R16)
    let invalid = "Error validating request.-'bN' : cause - Invalid account"
    broker.failNext("92", code: 322, text: invalid)
    let (_, pnl) = take(0, try await client.pnl(account: "DU0000002"))
    await #expect(throws: IBClientError.ib(code: 322, text: invalid)) { try await within2s { try await pnl.value } }
    let unknown = "No security definition has been found for the request"
    broker.failNext("94", code: 200, text: unknown)
    let (_, single) = take(0, try await client.pnlSingle(account: "DU0000001", conID: 1))
    await #expect(throws: IBClientError.ib(code: 200, text: unknown)) { try await within2s { try await single.value } }
    broker.failNext("49", code: 322, text: "Error processing request")
    await #expect(throws: IBClientError.ib(code: 322, text: "Error processing request")) {
        try await within2s { try await client.currentTime() }
    }

    broker.delayReplies(.milliseconds(30))
    let asked = ContinuousClock.now
    let time = try await within2s { try await client.currentTime() }
    #expect(ContinuousClock.now - asked >= .milliseconds(30))
    #expect(time == Date(timeIntervalSince1970: 1_794_321_000))
    await expectInCorpus(broker.emitted, source: "sim/faultsSurfaceTyped")
}

/// A request answered after its gateway closed feeds nothing, so `emitted` holds only frames a client read.
@Test func aClosedGatewayIsFedNoReply() {
    let broker = SimulatedBroker()
    let gateway = broker.newGateway()
    gateway.close()
    _ = gateway.onRequest?(["49", "1"])
    #expect(broker.answers.count == 1 && broker.emitted.isEmpty)
}
