import Foundation
import Testing
@testable import IBKR

private func connected(_ gateway: FakeGateway) async throws -> IBClient {
    let client = IBClient(connector: gateway.connector)
    try await within2s { try await client.connect(clientID: 7) }
    return client
}

/// Waits (at most 2 s) until `check` holds.
private func eventually(_ check: @escaping @Sendable () async -> Bool) async throws {
    try await within2s { while await !check() { try await Task.sleep(for: .milliseconds(5)) } }
}

private func contract(_ symbol: String, _ conID: Int) -> Contract {
    var c = Contract(symbol: symbol)
    c.conID = conID
    return c
}

private let aapl = contract("AAPL", 265598), spy = contract("SPY", 756733)

private func conIDOnly(_ conID: Int) -> Contract { contract("", conID) }

private func newsTick(_ id: String, _ headline: String) -> [String] {
    ["84", id, "1794321000000", "BRFG", "BRFG$12345", headline, ""]
}

@Test func tickerRegistryFollowsOpenStreams() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let a = try await client.tickers(aapl)
    let s = try await client.tickers(spy)
    let n = FakeGateway.syncFrames
    let sent = try await gateway.waitForSent(n + 2)
    let (aid, sid) = (sent[n][2], sent[n + 1][2])
    #expect(await client.activeTickers().map(\.contract) == [aapl, spy])   // listed from the request, as ib_async
    #expect(await client.ticker(for: conIDOnly(265598))?.bid == nil)
    gateway.feed(["1", "6", aid, "1", "351.5", "200", "0"])
    let (aReader, aSeen) = take(1, a)
    _ = try await within2s { try await aSeen.value }
    #expect(await client.ticker(for: conIDOnly(265598))?.bid == d("351.5"))   // by conID, as contract.py's __eq__
    #expect(await client.ticker(for: aapl)?.contract == aapl)
    #expect(await client.ticker(for: conIDOnly(1)) == nil)
    #expect(await client.activeTickers().count == 2)
    aReader.cancel()   // the consumer stops: the entry goes
    try await eventually { await client.activeTickers().map(\.contract) == [spy] }
    gateway.feed(ibError(sid, "200", "No security definition has been found for the request"))   // an IB error
    try await eventually { await client.activeTickers().isEmpty }
    let b = try await client.tickers(aapl)
    #expect(await client.activeTickers().count == 1)
    await client.disconnect()   // the connection ends
    #expect(await client.activeTickers().isEmpty)
    withExtendedLifetime((s, b)) {}
}

@Test func pendingTickersYieldEachUpdate() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let pending = await client.pendingTickers()
    let other = await client.pendingTickers()   // fresh per call: each gets every update
    let stream = try await client.tickers(aapl)
    let n = FakeGateway.syncFrames
    let id = try await gateway.waitForSent(n + 1)[n][2]
    gateway.feed(["1", "6", id, "1", "351.5", "200", "0"])
    gateway.feed(["2", "6", id, "0", "300"])
    for updates in [pending, other] {
        let got = try await within2s {
            var got: [[Ticker]] = []
            for await u in updates { got.append(u); if got.count == 2 { break } }
            return got
        }
        #expect(got.map(\.count) == [1, 1])   // one fold step each: the ticker it changed
        #expect(got.map { $0[0].bid } == [d("351.5"), d("351.5")])
        #expect(got.map { $0[0].bidSize } == [d("200"), d("300")])
        #expect(got.map { $0[0].ticks.count } == [1, 1])
    }
    withExtendedLifetime(stream) {}
}

@Test func pnlValuesFilterByAccount() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let one = try await client.pnl(account: "DU1")
    let two = try await client.pnl(account: "DU2", modelCode: "M1")
    let n = FakeGateway.syncFrames
    let sent = try await gateway.waitForSent(n + 2)
    let (id1, id2) = (sent[n][1], sent[n + 1][1])
    gateway.feed(["94", id1, "1.5", "5", "0"])
    gateway.feed(["94", id2, "2.5", "6", "1"])
    let (r1, v1) = take(1, one), (r2, v2) = take(1, two)
    let streamed = try await within2s { try await v1.value + v2.value }
    #expect(streamed.map(\.account) == ["DU1", "DU2"] && streamed.map(\.modelCode) == ["", "M1"])
    #expect(await client.pnlValues(account: "DU1")
            == [AccountPnL(daily: d("1.5"), unrealized: d("5"), realized: d("0"), account: "DU1")])
    #expect(await client.pnlValues().map(\.account) == ["DU1", "DU2"])
    #expect(await client.pnlValues(modelCode: "M1").map(\.account) == ["DU2"])
    #expect(await client.pnlValues(account: "DU1", modelCode: "M1").isEmpty)
    gateway.feed(["94", id1, "3.5", "5", "0"])   // the latest value replaces the last
    try await eventually { await client.pnlValues(account: "DU1").first?.daily == d("3.5") }
    gateway.feed(ibError(id2, "322", "Error processing request"))   // an IB error drops the subscription
    try await eventually { await client.pnlValues().map(\.account) == ["DU1"] }
    r1.cancel()   // the consumer stops
    try await eventually { await client.pnlValues().isEmpty }
    r2.cancel()
}

@Test func pnlSingleValuesCarryTheirConID() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let a = try await client.pnlSingle(account: "DU1", conID: 265598)
    let s = try await client.pnlSingle(account: "DU1", conID: 756733, modelCode: "M1")
    let n = FakeGateway.syncFrames
    let sent = try await gateway.waitForSent(n + 2)
    gateway.feed(["95", sent[n][1], "100", "1", "5", "0", "18725"])
    gateway.feed(["95", sent[n + 1][1], "10", "2", "6", "0", "4000"])
    let (_, va) = take(1, a), (_, vs) = take(1, s)
    let streamed = try await within2s { try await va.value + vs.value }
    #expect(streamed.map(\.conID) == [265598, 756733] && streamed.map(\.modelCode) == ["", "M1"])
    #expect(await client.pnlSingleValues(conID: 265598) == [
        PnL(position: 100, daily: 1, unrealized: 5, realized: 0, value: 18725, account: "DU1", conID: 265598)])
    #expect(await client.pnlSingleValues(account: "DU1").map(\.conID) == [265598, 756733])
    #expect(await client.pnlSingleValues(modelCode: "M1").map(\.conID) == [756733])
    #expect(await client.pnlSingleValues(account: "DU2").isEmpty)
    await client.disconnect()   // the connection ends: no subscription is open
    #expect(await client.pnlSingleValues().isEmpty)
}

@Test func newsTicksCollectAcrossSubscriptions() async throws {
    let (one, two) = (FakeGateway(), FakeGateway())
    let client = IBClient(connector: Gateways([one, two]).connector)
    try await within2s { try await client.connect(clientID: 7) }
    let first = try await client.marketData(aapl, genericTicks: ["mdoff", "292:BRFG"])
    let second = try await client.marketData(spy, genericTicks: ["mdoff", "292:BRFG"])
    let n = FakeGateway.syncFrames
    let sent = try await one.waitForSent(n + 2)
    one.feed(newsTick(sent[n][2], "Apple headline"))
    let (_, seen) = take(1, first)
    _ = try await within2s { try await seen.value }
    let (snapshot, updates) = await client.newsTicks()
    #expect(snapshot.map(\.headline) == ["Apple headline"])
    one.feed(newsTick(sent[n + 1][2], "SPY headline"))
    one.feed(newsTick("999", "No subscription"))   // any reqId, as ib_async's tickNews
    let got = try await within2s {
        var got: [NewsTick] = []
        for await t in updates { got.append(t); if got.count == 2 { break } }
        return got
    }
    #expect(got.map(\.headline) == ["SPY headline", "No subscription"])
    #expect(await client.newsTicks().snapshot.count == 3)
    one.feed(["14", "1", "3", "1", "Exchange halted", "NYSE"])
    try await eventually { await client.receivedBulletins().count == 1 }
    await client.disconnect()
    #expect(await client.newsTicks().snapshot.count == 3)   // kept until the next manual connect
    #expect(await client.receivedBulletins().count == 1)
    try await within2s { try await client.connect(clientID: 7) }
    #expect(await client.newsTicks().snapshot.isEmpty)
    #expect(await client.receivedBulletins().isEmpty)
    withExtendedLifetime(second) {}
}

@Test func bulletinsAreKeptByID() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.feed(["14", "1", "3", "1", "Exchange halted", "NYSE"])
    gateway.feed(["14", "1", "4", "1", "Other news", "ARCA"])
    gateway.feed(["14", "1", "3", "3", "Exchange trades again", "NYSE"])   // same msgID: last wins, first place kept
    try await eventually { await client.receivedBulletins().first?.msgType == 3 }
    #expect(await client.receivedBulletins() == [
        NewsBulletin(msgID: 3, msgType: 3, message: "Exchange trades again", origExchange: "NYSE"),
        NewsBulletin(msgID: 4, msgType: 1, message: "Other news", origExchange: "ARCA")])
}

/// A fold step that loses the race with the connection's end must not list its ticker again.
@Test func aFoldStepAfterTheEndDoesNotRelistTheTicker() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.tickers(aapl)
    let key = await client.tickerKey
    await client.disconnect()
    await client.recordTicker(key, Ticker(contract: aapl))
    #expect(await client.activeTickers().isEmpty)
    withExtendedLifetime(stream) {}
}

/// R27: a policy reconnect keeps the news ticks and bulletins; only a manual `connect` clears them.
@Test func newsSurvivesAPolicyReconnect() async throws {
    let (one, two) = (FakeGateway(), FakeGateway())
    let client = IBClient(connector: Gateways([one, two]).connector)
    try await within2s {
        try await client.connect(clientID: 7, reconnect: ReconnectPolicy(delays: [.milliseconds(10)], probeAfter: nil))
    }
    one.feed(newsTick("999", "Kept"))
    one.feed(["14", "1", "3", "1", "Exchange halted", "NYSE"])
    try await eventually { await client.receivedBulletins().count == 1 }
    try await eventually { await client.newsTicks().snapshot.count == 1 }
    let states = await client.states()
    one.close()
    try await within2s {
        var connects = 0
        for await s in states {
            if case .connected = s { connects += 1 }
            if connects == 2 { return }   // the current state, then the reconnect
        }
        throw TimedOut()
    }
    #expect(await client.newsTicks().snapshot.map(\.headline) == ["Kept"])
    #expect(await client.receivedBulletins().map(\.msgID) == [3])
    await client.disconnect()
}
