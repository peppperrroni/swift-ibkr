import Foundation
import Testing
@testable import IBKR

private let aapl = Contract(symbol: "AAPL")
private let buy = Order(action: .buy, quantity: 1, orderType: "LMT", limitPrice: d("1"))

private func connected(_ gateway: FakeGateway) async throws -> IBClient {
    let client = IBClient(connector: gateway.connector)
    try await within2s { try await client.connect(clientID: 7) }
    return client
}

@Test func currentTimeAsksAndDecodes() async throws {
    let gateway = FakeGateway()
    gateway.onRequest = { $0 == ["49", "1"] ? [["49", "1", "1700000000"]] : [] }
    let client = try await connected(gateway)
    let time = try await within2s { try await client.currentTime() }
    #expect(time == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames] == ["49", "1"])
}

@Test func managedAccountsAsks() async throws {
    let gateway = FakeGateway()
    gateway.onRequest = { $0 == ["17", "1"] ? [["15", "1", "DU1,DU2"]] : [] }
    let client = try await connected(gateway)
    #expect(try await within2s { try await client.managedAccounts() } == ["DU1", "DU2"])
}

@Test func nextOrderIDMergesIBsAnswer() async throws {
    let gateway = FakeGateway()
    gateway.onRequest = { $0 == ["8", "1", "1"] ? [["9", "1", "40"]] : [] }
    let client = try await connected(gateway)
    #expect(try await within2s { try await client.nextOrderID() } == 40)
    #expect(try await client.placeOrder(aapl, buy) == 40)
}

@Test func nextOrderIDKeepsALocalIDAboveIBsAnswer() async throws {
    let gateway = FakeGateway()   // connect used id 1 for the sync, so the next free id is 2
    gateway.onRequest = { $0 == ["8", "1", "1"] ? [["9", "1", "1"]] : [] }
    let client = try await connected(gateway)
    #expect(try await within2s { try await client.nextOrderID() } == 2)
}

@Test func userInfoAsksByReqId() async throws {
    let gateway = FakeGateway()
    gateway.onRequest = { $0.first == "104" ? [["107", $0[1], ""]] : [] }
    let client = try await connected(gateway)
    #expect(try await within2s { try await client.userInfo() } == "")

    gateway.onRequest = { $0.first == "104" ? [["4", "2", $0[1], "322", "Error processing request", ""]] : [] }
    do {
        _ = try await within2s { try await client.userInfo() }
        Issue.record("did not throw")
    } catch let e as IBClientError {
        #expect(e == .ib(code: 322, text: "Error processing request"))
    }
}

@Test func currentTimeEndsWithTheConnection() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let call = Task { try await client.currentTime() }
    _ = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    gateway.close()
    do {
        _ = try await within2s { try await call.value }
        Issue.record("did not throw")
    } catch let e as IBClientError {
        #expect(e == .connectionClosed)
    }
    #expect(await client.requestStreamCount == 0)
}

@Test func currentTimeHonoursCancellation() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let call = Task { try await client.currentTime() }
    _ = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    call.cancel()
    do {
        _ = try await within2s { try await call.value }
        Issue.record("did not throw")
    } catch let e as IBClientError {
        #expect(e == .cancelled)
    }
    for _ in 0..<100 where await client.requestStreamCount != 0 { try await Task.sleep(for: .milliseconds(10)) }   // the stop hops to the actor
    #expect(await client.requestStreamCount == 0)
}

@Test func twoCurrentTimeCallsTakeOneAnswerEach() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let one = Task { try await client.currentTime() }
    _ = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    let two = Task { try await client.currentTime() }
    _ = try await gateway.waitForSent(FakeGateway.syncFrames + 2)
    gateway.feed(["49", "1", "1700000000"])
    gateway.feed(["49", "1", "1700000001"])
    let a = try await within2s { try await one.value }, b = try await within2s { try await two.value }
    #expect(a != b)
}

@Test func settingsSendTheirFrames() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    try await client.setServerLogLevel(.detail)
    try await client.setAutoOpenOrders(true)
    try await client.cancelAllOrders()
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 3)
    #expect(Array(sent[FakeGateway.syncFrames...FakeGateway.syncFrames + 2]) == [["14", "1", "5"], ["15", "1", "1"], ["58", "1"]])
}

@Test func sessionCallsNeedAConnection() async throws {
    let client = IBClient(connector: FakeGateway().connector)
    func notConnected(_ call: () async throws -> some Any) async {
        do { _ = try await call(); Issue.record("did not throw") } catch { #expect(error as? IBClientError == .notConnected) }
    }
    await notConnected { try await client.currentTime() }
    await notConnected { try await client.managedAccounts() }
    await notConnected { try await client.nextOrderID() }
    await notConnected { try await client.userInfo() }
    await notConnected { try await client.setServerLogLevel(.error) }
    await notConnected { try await client.setAutoOpenOrders(false) }
    await notConnected { try await client.cancelAllOrders() }
}
