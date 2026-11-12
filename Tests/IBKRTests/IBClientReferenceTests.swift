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

private func chainFrame(_ id: String, _ exchange: String) -> [String] {
    ["75", id, exchange, "265598", "AAPL", "100", "2", "20261218", "20270115", "3", "190", "195", "200"]
}

@Test func optionChainsCollectUntilEnd() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in
        guard f[0] == "78" else { return [] }
        return [chainFrame(f[1], "SMART"), chainFrame(f[1], "CBOE"), ["76", f[1]]]
    }
    var base = Contract.stock("AAPL", exchange: "SMART", currency: "USD")
    base.conID = 265598
    let u = base
    let chains = try await within2s { try await client.optionChains(for: u) }
    #expect(chains.map(\.exchange) == ["SMART", "CBOE"])
    #expect(chains[0].strikes == [190, 195, 200])
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    #expect(sent[FakeGateway.syncFrames].dropFirst(2) == ["AAPL", "", "STK", "265598"])
    #expect(sent[FakeGateway.syncFrames].first == "78")
    try await Task.sleep(for: .milliseconds(50))   // room for a wrong cancel
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1).count == FakeGateway.syncFrames + 1)
    #expect(await client.requestStreamCount == 0)
}

@Test func optionChainsFailOnTheirError() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in
        guard f[0] == "78" else { return [] }
        return [ibError(f[1], "200", "No security definition has been found for the request")]
    }
    await #expect(throws: IBClientError.ib(code: 200, text: "No security definition has been found for the request")) {
        try await within2s { try await client.optionChains(for: .stock("AAPL")) }
    }
}

private let comp = OptionComputation(tickAttrib: 1, impliedVol: d("0.25"), delta: d("0.55"), optPrice: d("6.1"),
                                     pvDividend: 0, gamma: d("0.03"), vega: d("0.12"), theta: d("-0.05"),
                                     undPrice: d("187.2"))

/// A tickOptionComputation (21) frame of field 53 (custom option computation) under reqId `id`.
private func t21(_ id: String, _ iv: String) -> [String] {
    ["21", id, "53", "1", iv, "0.55", "6.1", "0", "0.03", "0.12", "-0.05", "187.2"]
}

@Test func calculateImpliedVolatilityAnswersThenCancels() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in f[0] == "54" ? [t21(f[2], "0.25")] : [] }
    let got = try await within2s {
        try await client.calculateImpliedVolatility(aaplCall, optionPrice: d("6.1"), underPrice: d("187.2"))
    }
    #expect(got == comp)
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 2)
    let f = sent[FakeGateway.syncFrames]
    #expect(Array(f[15...18]) == ["6.1", "187.2", "0", ""])
    #expect(sent[FakeGateway.syncFrames + 1] == ["56", "1", f[2]])
    #expect(await client.requestStreamCount == 0)
}

@Test func calculateOptionPriceRefusedForPermissionSendsItsCancel() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in f[0] == "55" ? [ibError(f[2], "354", "Requested market data is not subscribed.")] : [] }
    await #expect(throws: IBClientError.noMarketDataPermission(code: 354, text: "Requested market data is not subscribed.")) {
        _ = try await within2s {
            try await client.calculateOptionPrice(aaplCall, volatility: d("0.25"), underPrice: d("187.2"))
        }
    }
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 2)
    #expect(sent[FakeGateway.syncFrames + 1] == ["57", "1", sent[FakeGateway.syncFrames][2]])
}

@Test func calculateFailsOnItsErrorWithoutCancel() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in
        f[0] == "54" ? [ibError(f[2], "200", "No security definition has been found for the request")] : []
    }
    await #expect(throws: IBClientError.ib(code: 200, text: "No security definition has been found for the request")) {
        _ = try await within2s {
            try await client.calculateImpliedVolatility(aaplCall, optionPrice: d("6.1"), underPrice: d("187.2"))
        }
    }
    try await Task.sleep(for: .milliseconds(50))   // room for a wrong cancel
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1).count == FakeGateway.syncFrames + 1)
    #expect(await client.requestStreamCount == 0)
}

/// Review Focus 2: a quote stream's 21 never answers a calculation, and the calculation's 21 never reaches the quotes.
@Test func calculationTakesOnlyItsOwnTick() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let quotes = try await client.marketData(Contract(symbol: "AAPL"))
    let q = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames][2]
    let calc = Task {
        try await client.calculateImpliedVolatility(aaplCall, optionPrice: d("6.1"), underPrice: d("187.2"))
    }
    let c = try await gateway.waitForSent(FakeGateway.syncFrames + 2)[FakeGateway.syncFrames + 1][2]
    gateway.feed(t21(q, "0.25"))
    gateway.feed(t21(c, "0.3"))
    let got = try await within2s { try await calc.value }
    #expect(got.impliedVol == d("0.3"))
    gateway.feed(["1", "6", q, "1", "351.5", "200", "0"])
    let (_, result) = take(2, quotes)
    #expect(try await within2s { try await result.value }
        == [.optionComputation(TickField(rawValue: 53), comp), .price(.bid, price: d("351.5"), size: d("200"))])
}
