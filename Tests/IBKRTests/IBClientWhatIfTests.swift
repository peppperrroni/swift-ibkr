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

/// A what-if openOrder for `orderID`, its margins empty unless `initMarginChange` is given.
private func whatIfOpen(_ orderID: Int, initMarginChange: String = "") -> [String] {
    var f = Fixtures.openOrderFields(
        orderID: orderID, permID: 0, clientID: 7, symbol: "AAPL", action: "BUY", quantity: "1", orderType: "LMT",
        limitPrice: "1", auxPrice: unset, tif: "DAY", parentID: "0", outsideRTH: "0", orderRef: "", status: "PreSubmitted")
    f[84] = "1"
    f[89] = initMarginChange
    return f
}

/// Answers every placeOrder with `reply(orderID)`.
private func answering(_ reply: @escaping @Sendable (String) -> [[String]]) -> FakeGateway {
    let gateway = FakeGateway(nextValidID: 100)
    gateway.onRequest = { f in f[0] == "3" ? reply(f[1]) : [] }
    return gateway
}

@Test func whatIfOrderReturnsTheState() async throws {
    let gateway = answering { id in [whatIfOpen(Int(id)!), whatIfOpen(Int(id)!, initMarginChange: "250.5")] }
    let client = try await connected(gateway)
    let state = try await within2s { try await client.whatIfOrder(aapl, buy) }
    #expect(state.initMarginChange == d("250.5"))
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    #expect(sent[FakeGateway.syncFrames][0] == "3" && sent[FakeGateway.syncFrames][84] == "1")
    #expect(await client.orders().snapshot.isEmpty)
    #expect(await client.requestStreamCount == 0)
}

@Test func whatIfOrderFailsOnItsError() async throws {
    let gateway = answering { id in [["4", "2", id, "201", "Order rejected - reason:Insufficient margin", ""]] }
    let client = try await connected(gateway)
    await #expect(throws: IBClientError.ib(code: 201, text: "Order rejected - reason:Insufficient margin")) {
        try await within2s { try await client.whatIfOrder(aapl, buy) }
    }
    #expect(await client.orders().snapshot.isEmpty)
    #expect(await client.requestStreamCount == 0)
}

@Test func whatIfOrderEndsWithTheConnection() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    let pending = Task { try await client.whatIfOrder(aapl, buy) }
    _ = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    gateway.close()
    await #expect(throws: IBClientError.connectionClosed) { try await within2s { try await pending.value } }
}

@Test func placeOrderRefusesWhatIf() async throws {
    let gateway = FakeGateway(nextValidID: 100)
    let client = try await connected(gateway)
    var whatIf = buy
    whatIf.whatIf = true
    await #expect(throws: IBClientError.encoding(.unsupported("whatIf"))) { try await client.placeOrder(aapl, whatIf) }
    await #expect(throws: IBClientError.encoding(.unsupported("whatIf"))) { try await client.modifyOrder(1, aapl, whatIf) }
    try await client.cancelOrder(1)   // the next frame out is this one
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    #expect(sent.count == FakeGateway.syncFrames + 1 && sent[FakeGateway.syncFrames][0] == "4")
}

@Test func whatIfOrderNeedsAConnection() async throws {
    let client = IBClient(connector: FakeGateway().connector)
    await #expect(throws: IBClientError.notConnected) { try await client.whatIfOrder(aapl, buy) }
}
