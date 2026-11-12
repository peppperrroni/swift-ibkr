import Testing
@testable import IBKR

private func connected(_ gateway: FakeGateway) async throws -> IBClient {
    let client = IBClient(connector: gateway.connector)
    try await within2s { try await client.connect(clientID: 7) }
    return client
}

private let top = ScannerSubscription(instrument: "STK", locationCode: "STK.US.MAJOR", scanCode: "TOP_PERC_GAIN")
private let cancelled = "Historical Market Data Service error message:API scanner subscription cancelled: 1"

/// Review Focus 3: each message 20 is one whole scan, the stream never ends itself, and stopping it sends 23.
@Test func scannerSubscriptionStreamsWholeScansAndCancels() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let scans = try await client.scannerSubscription(top)
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    let f = sent[FakeGateway.syncFrames]
    #expect(Array(f[0...5]) == ["22", f[1], "-1", "STK", "STK.US.MAJOR", "TOP_PERC_GAIN"])
    let id = f[1]
    let (sawOneRow, signal) = AsyncStream.makeStream(of: Void.self)
    // the newest-only buffer may drop the first scan, so read until the one-row scan and keep the stream open
    let reader = Task {
        do { for try await s in scans where s.count == 1 { signal.yield() } } catch {}
    }
    gateway.feed(scan(id))
    gateway.feed(["20", "3", id, "1"] + scan(id)[4...19])
    try await within2s { for await _ in sawOneRow { return } }
    #expect(await client.requestStreamCount == 1)
    reader.cancel()
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 2)[FakeGateway.syncFrames + 1] == ["23", "1", id])
    #expect(await client.requestStreamCount == 0)
}

@Test func scannerSubscriptionEndsOnItsError() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in f[0] == "22" ? [ibError(f[1], "162", cancelled)] : [] }
    let scans = try await client.scannerSubscription(top)
    await #expect(throws: IBClientError.ib(code: 162, text: cancelled)) {
        try await within2s { for try await _ in scans {} }
    }
    try await Task.sleep(for: .milliseconds(50))   // room for a wrong cancel
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1).count == FakeGateway.syncFrames + 1)
    #expect(await client.requestStreamCount == 0)
}

/// Review Focus 3: the one-shot returns the first scan, then sends 23 as ib_async's reqScannerDataAsync does.
@Test func scannerDataReturnsTheFirstScanThenCancels() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in f[0] == "22" ? [scan(f[1])] : [] }
    let rows = try await within2s { try await client.scannerData(top) }
    #expect(rows.map(\.contract.symbol) == ["AAPL", "MSFT"])
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 2)
    #expect(sent[FakeGateway.syncFrames + 1] == ["23", "1", sent[FakeGateway.syncFrames][1]])
    #expect(await client.requestStreamCount == 0)
}

/// Review Focus 3: IB's error ends the one-shot, and IB has already dropped the subscription, so no 23 follows.
@Test func scannerDataFailsOnItsErrorWithoutCancel() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in f[0] == "22" ? [ibError(f[1], "162", cancelled)] : [] }
    await #expect(throws: IBClientError.ib(code: 162, text: cancelled)) {
        _ = try await within2s { try await client.scannerData(top) }
    }
    try await Task.sleep(for: .milliseconds(50))   // room for a wrong cancel
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1).count == FakeGateway.syncFrames + 1)
    #expect(await client.requestStreamCount == 0)
}

@Test func scannerParametersAnswer() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in f == ["24", "1"] ? [["19", "1", "<xml/>"]] : [] }
    #expect(try await within2s { try await client.scannerParameters() } == "<xml/>")
    #expect(await client.requestStreamCount == 0)
}
