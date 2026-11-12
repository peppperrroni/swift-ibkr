import Testing
@testable import IBKR

private func connected(_ gateway: FakeGateway) async throws -> IBClient {
    let client = IBClient(connector: gateway.connector)
    try await within2s { try await client.connect(clientID: 7) }
    return client
}

private func contractData(_ id: String, conID: String) -> [String] {
    ["10", id, "AAPL", "STK", "", "0.0", "?", "SMART", "USD", "AAPL", "NMS", "NMS", conID, "0.01", "",
     "LMT,MKT", "SMART,NASDAQ", "1", "0", "APPLE INC", "NASDAQ", "", "Technology", "Computers", "Computers",
     "US/Eastern", "20261110:0400-20261110:2000", "20261110:0930-20261110:1600",
     "", "0", "0", "1", "", "", "26,26", "", "COMMON", "1", "1", "1"]
}

@Test func contractDetailsCollectsUntilEnd() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let result = Task<[ContractDetails], any Error> { try await client.contractDetails(Contract(symbol: "AAPL")) }
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    let id = sent[FakeGateway.syncFrames][2]
    #expect(sent[FakeGateway.syncFrames][0...1] == ["9", "8"])
    gateway.feed(contractData(id, conID: "265598"))
    gateway.feed(contractData(id, conID: "265599"))
    gateway.feed(["52", "1", id])
    let got = try await within2s { try await result.value }
    #expect(got.map(\.contract.conID) == [265598, 265599])
    #expect(await client.requestStreamCount == 0)
}

@Test func matchingSymbolsReturnsTheSamples() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let result = Task<[ContractDescription], any Error> { try await client.matchingSymbols("AAP") }
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    let id = sent[FakeGateway.syncFrames][1]
    #expect(sent[FakeGateway.syncFrames] == ["81", id, "AAP"])
    gateway.feed(["79", id, "1", "265598", "AAPL", "STK", "NASDAQ", "USD", "1", "OPT", "APPLE INC", ""])
    let got = try await within2s { try await result.value }
    #expect(got.map(\.contract.symbol) == ["AAPL"])
    try await Task.sleep(for: .milliseconds(50))   // room for a wrong cancel
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1).count == FakeGateway.syncFrames + 1)
    #expect(await client.requestStreamCount == 0)
}

@Test func noSecurityDefinitionThrows() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let result = Task<[ContractDetails], any Error> { try await client.contractDetails(Contract(symbol: "ZZZZ")) }
    let id = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames][2]
    let text = "No security definition has been found for the request"
    gateway.feed(["4", "2", id, "200", text, ""])
    await #expect(throws: IBClientError.ib(code: 200, text: text)) { try await within2s { try await result.value } }
}

@Test func lookupThrowsWhenTheConnectionEnds() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let result = Task<[ContractDescription], any Error> { try await client.matchingSymbols("AAP") }
    _ = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    gateway.close()
    await #expect(throws: IBClientError.connectionClosed) { try await within2s { try await result.value } }
}

@Test func cancelledLookupThrowsCancelled() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let task = Task<IBClientError?, Never> {
        do { _ = try await client.contractDetails(Contract(symbol: "AAPL")); return nil } catch { return error as? IBClientError }
    }
    _ = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    task.cancel()
    #expect(try await within2s { await task.value } == .cancelled)
    try await within2s { while await client.requestStreamCount != 0 { try await Task.sleep(for: .milliseconds(5)) } }
    try await Task.sleep(for: .milliseconds(50))   // room for a wrong cancel
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1).count == FakeGateway.syncFrames + 1)
}

@Test func lookupsNeedAConnection() async throws {
    let client = IBClient(connector: FakeGateway().connector)
    await #expect(throws: IBClientError.notConnected) { try await client.contractDetails(Contract(symbol: "AAPL")) }
    await #expect(throws: IBClientError.notConnected) { try await client.matchingSymbols("AAP") }
}
