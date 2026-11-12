import Testing
@testable import IBKR

private func connected(_ gateway: FakeGateway) async throws -> IBClient {
    let client = IBClient(connector: gateway.connector)
    try await within2s { try await client.connect(clientID: 7) }
    return client
}

/// A 40-field contractData (10) frame for `symbol` under reqId `id`.
private func details(_ id: String, _ symbol: String, conID: String, secType: String = "STK", lastTimes: String = "",
                     exchange: String = "SMART") -> [String] {
    ["10", id, symbol, secType, lastTimes, "0", "", exchange, "USD", symbol, "NMS", "NMS", conID, "0.01", "", "LMT",
     "SMART", "1", "0", symbol, "NASDAQ", "", "", "", "", "US/Eastern", "", "", "", "", "0"] + Array(repeating: "", count: 9)
}

@Test func qualifyContractsReturnsEachOutcomeInOrder() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in
        guard f[0] == "9" else { return [] }
        switch f[4] {
        case "AAPL": return [details(f[2], "AAPL", conID: "265598", exchange: "NASDAQ"), ["52", "1", f[2]]]
        case "ZZZZ": return [ibError(f[2], "200", "No security definition has been found for the request")]
        case "ES": return [details(f[2], "ES", conID: "1", secType: "FUT", lastTimes: "20261218"),
                           details(f[2], "ES", conID: "2", secType: "FUT", lastTimes: "20270319"), ["52", "1", f[2]]]
        default: return []
        }
    }
    let got = try await within2s {
        try await client.qualifyContracts([.stock("AAPL", exchange: "SMART", currency: "USD"),
                                           .stock("ZZZZ", exchange: "SMART", currency: "USD"),
                                           .future("ES", exchange: "CME")])
    }
    try #require(got.count == 3)
    guard case .qualified(let c) = got[0] else { Issue.record("\(got[0])"); return }
    #expect(c.conID == 265598)
    #expect(c.exchange == "SMART")
    #expect(c.primaryExchange == "NASDAQ")
    #expect(got[1] == .notFound)
    guard case .ambiguous(let list) = got[2] else { Issue.record("\(got[2])"); return }
    #expect(list.map(\.conID) == [1, 2])
    #expect(await client.requestStreamCount == 0)
}

@Test func qualifyContractsPicksTheRequestedSecType() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in
        guard f[0] == "9" else { return [] }
        return [details(f[2], "ES", conID: "7", secType: "FOP", lastTimes: "20261218 15:00 US/Central", exchange: "CME"),
                details(f[2], "ES", conID: "8", secType: "OPT", lastTimes: "20261218", exchange: "CME"),
                ["52", "1", f[2]]]
    }
    let got = try await within2s {
        try await client.qualifyContracts([.futuresOption("ES", lastTradeDateOrContractMonth: "20261218", strike: 6000,
                                                          right: "C", exchange: "CME")])
    }
    try #require(got.count == 1)
    guard case .qualified(let c) = got[0] else { Issue.record("\(got[0])"); return }
    #expect(c.conID == 7)
    #expect(c.exchange == "CME")
    #expect(c.lastTradeDateOrContractMonth == "20261218")
}

/// ib_async keeps only the filtered list even when it is empty, so nothing is offered as a candidate.
@Test func qualifyContractsKeepsNoCandidateWhenTheSecTypeMatchesNone() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in
        guard f[0] == "9" else { return [] }
        return [details(f[2], "ES", conID: "8", secType: "OPT", lastTimes: "20261218", exchange: "CME"),
                details(f[2], "ES", conID: "9", secType: "OPT", lastTimes: "20261218", exchange: "CME"),
                ["52", "1", f[2]]]
    }
    let got = try await within2s {
        try await client.qualifyContracts([.futuresOption("ES", lastTradeDateOrContractMonth: "20261218", strike: 6000,
                                                          right: "C", exchange: "CME")])
    }
    #expect(got == [.ambiguous([])])
}

@Test func qualifyContractsThrowsAnyOtherError() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in
        guard f[0] == "9", f[4] == "AAPL" else { return [] }
        return [ibError(f[2], "321", "Error validating request")]
    }
    await #expect(throws: IBClientError.ib(code: 321, text: "Error validating request")) {
        try await within2s { try await client.qualifyContracts([.stock("AAPL"), .stock("MSFT")]) }
    }
    try await within2s { while await client.requestStreamCount != 0 { try await Task.sleep(for: .milliseconds(5)) } }
    try await Task.sleep(for: .milliseconds(50))   // room for a wrong cancel
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 2).count == FakeGateway.syncFrames + 2)
}

@Test func qualifyContractsRefusesABagBeforeSending() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    await #expect(throws: IBClientError.encoding(.unsupported("secType BAG"))) {
        try await client.qualifyContracts([.stock("AAPL"), bagContract])
    }
    try await Task.sleep(for: .milliseconds(50))   // room for a wrong send
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames).count == FakeGateway.syncFrames)
}
