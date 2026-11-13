import Foundation
import Testing
@testable import IBKR

private func connected(_ gateway: FakeGateway) async throws -> IBClient {
    let client = IBClient(connector: gateway.connector)
    try await within2s { try await client.connect(clientID: 7) }
    return client
}

private func open(_ orderID: Int, _ permID: Int) -> [String] {
    Fixtures.openOrderFields(orderID: orderID, permID: permID, clientID: 7, symbol: "AAPL", action: "BUY", quantity: "100",
                             orderType: "LMT", limitPrice: "187.25", auxPrice: "1.7976931348623157E308", tif: "DAY",
                             parentID: "0", outsideRTH: "0", orderRef: "", status: "Submitted")
}

private let execID = "0000e0d5.6556b5f0.01.01"
private let exec = ["11", "-1", "12", "265598", "AAPL", "STK", "", "0", "", "", "SMART", "USD", "AAPL", "NMS",
                    execID, "20251109 10:00:00", "DU1", "ISLAND", "BOT", "100", "187.25", "918273001", "7", "0",
                    "100", "187.25", "", "", "", "", "1", "0"]
private let commission = ["59", "1", execID, "1.5", "USD", "1.7976931348623157E308", "1.7976931348623157E308", ""]

@Test func fetchOpenOrdersReturnsTheAnswer() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { $0 == ["5", "1"] || $0 == ["16", "1"] ? [open(12, 1001), open(13, 1002), ["53", "1"]] : [] }
    let mine = try await within2s { try await client.fetchOpenOrders() }
    #expect(mine.map(\.orderID) == [12, 13])
    #expect(mine.map(\.status) == [.submitted, .submitted])
    let all = try await within2s { try await client.fetchAllOpenOrders() }
    #expect(all.map(\.permID) == [1001, 1002])
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 2)
    #expect(Array(sent[FakeGateway.syncFrames...]) == [["5", "1"], ["16", "1"]])
    #expect(await client.requestStreamCount == 0)
}

@Test func completedOrdersReturnsTheAnswer() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in
        f == ["99", "1"] ? [Fixtures.completedOrderFields(
            orderID: 0, permID: 2001, clientID: 0, symbol: "AAPL", action: "BUY", quantity: "100", orderType: "LMT",
            limitPrice: "187.25", auxPrice: "1.7976931348623157E308", tif: "DAY", parentID: "0", outsideRTH: "0",
            orderRef: "", status: "Filled", filledQuantity: "100")] : []   // the gateway's default 102 follows
    }
    let done = try await within2s { try await client.completedOrders(apiOnly: true) }
    #expect(done.map(\.permID) == [2001])
    #expect(done.first?.status == .filled)
    #expect(await client.requestStreamCount == 0)
}

@Test func executionsWithFilterReturnsJoinedFills() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let unpaid = replacing(exec, [14: "0000e0d5.6556b5f0.01.02"])   // no commission report: left out
    gateway.onRequest = { f in
        f[0] == "7" ? [replacing(exec, [1: f[2]]), commission, replacing(unpaid, [1: f[2]])] : []   // then the default 55
    }
    let fills = try await within2s { try await client.executions(filter: ExecutionFilter(clientID: 7, symbol: "AAPL")) }
    #expect(fills.map(\.execution.execID) == [execID])
    #expect(fills.first?.commission.commission == d("1.5"))
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames]
    #expect(sent == ["7", "3", sent[2], "7", "", "", "AAPL", "", "", ""])
    #expect(await client.requestStreamCount == 0)
}

@Test func executionsFailOnTheirError() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in f[0] == "7" ? [ibError(f[2], "321", "Error validating request")] : [] }
    await #expect(throws: IBClientError.ib(code: 321, text: "Error validating request")) {
        _ = try await within2s { try await client.executions(filter: ExecutionFilter()) }
    }
    #expect(await client.requestStreamCount == 0)
}

/// R16: every id-less one-shot ends with IB's error when a fatal or warning error with reqId -1 arrives while it
/// waits. The error is fed ahead of the gateway's own answers (16 and 99 have defaults).
@Test func idlessOneShotsFailOnAMinusOneError() async throws {
    let calls: [@Sendable (IBClient) async throws -> Void] = [
        { _ = try await $0.currentTime() }, { _ = try await $0.managedAccounts() }, { _ = try await $0.nextOrderID() },
        { _ = try await $0.depthExchanges() }, { _ = try await $0.marketRule(26) }, { _ = try await $0.familyCodes() },
        { _ = try await $0.scannerParameters() }, { _ = try await $0.newsProviders() },
        { _ = try await $0.faData(.groups) }, { _ = try await $0.fetchOpenOrders() },
        { _ = try await $0.fetchAllOpenOrders() }, { _ = try await $0.completedOrders() }]
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { _ in [ibError("-1", "321", "Error validating request")] }
    for call in calls {
        await #expect(throws: IBClientError.ib(code: 321, text: "Error validating request")) {
            try await within2s { try await call(client) }
        }
    }
    #expect(await client.requestStreamCount == 0)
}
