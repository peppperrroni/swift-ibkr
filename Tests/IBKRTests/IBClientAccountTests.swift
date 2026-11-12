import Testing
@testable import IBKR

private let tags = ["NetLiquidation", "BuyingPower"]

private func connected(_ gateway: FakeGateway) async throws -> IBClient {
    let client = IBClient(connector: gateway.connector)
    try await within2s { try await client.connect(clientID: 7) }
    return client
}

/// The first `count` elements; the stream is released afterwards, which is the consumer stopping.
private func take<T: Sendable>(_ count: Int, _ stream: AsyncThrowingStream<T, any Error>) async throws -> [T] {
    try await within2s {
        var got: [T] = []
        for try await x in stream {
            got.append(x)
            if got.count == count { return got }
        }
        throw TimedOut()
    }
}

/// Reads the stream to its end and returns what it threw.
private func ending<T: Sendable>(_ stream: AsyncThrowingStream<T, any Error>) async throws -> IBClientError? {
    try await within2s {
        do { for try await _ in stream {} } catch { return error as? IBClientError }
        return nil
    }
}

private func value(_ id: String, _ tag: String, _ value: String, account: String = "DU1") -> [String] {
    ["63", "1", id, account, tag, value, "USD"]
}

private func end(_ id: String) -> [String] { ["64", "1", id] }

private func pnl(_ id: String, _ daily: String) -> [String] { ["95", id, "100", daily, "5", "0", "18725"] }

private func pairs(_ set: [AccountValue]) -> [String] { set.map { "\($0.account)/\($0.tag)=\($0.value)" } }

/// The reqId of the request the client sent last.
private func lastRequestID(_ gateway: FakeGateway, _ count: Int, at index: Int) async throws -> String {
    try await gateway.waitForSent(count)[count - 1][index]
}

@Test func accountSummaryYieldsTheSetAtEnd() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.accountSummary(tags: tags)
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    let id = sent[FakeGateway.syncFrames][2]
    #expect(sent[FakeGateway.syncFrames] == ["62", "1", id, "All", "NetLiquidation,BuyingPower"])
    gateway.feed(value(id, "NetLiquidation", "100000"))
    gateway.feed(value(id, "BuyingPower", "400000"))
    gateway.feed(end(id))
    let first = try await take(1, stream)[0]
    #expect(pairs(first) == ["DU1/BuyingPower=400000", "DU1/NetLiquidation=100000"])
    #expect(first[0].currency == "USD")
}

@Test func accountSummaryYieldsChangesAfterEndButNoRepeats() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.accountSummary(tags: ["NetLiquidation"])
    let id = try await lastRequestID(gateway, FakeGateway.syncFrames + 1, at: 2)
    gateway.feed(value(id, "NetLiquidation", "100"))
    gateway.feed(end(id))
    gateway.feed(value(id, "NetLiquidation", "101"))
    gateway.feed(end(id))   // the set is unchanged: nothing
    gateway.feed(value(id, "NetLiquidation", "102"))
    #expect(try await take(3, stream).map(pairs)
            == [["DU1/NetLiquidation=100"], ["DU1/NetLiquidation=101"], ["DU1/NetLiquidation=102"]])
}

@Test func accountSummaryErrorEndsOnlyItsStream() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let one = try await client.accountSummary(tags: tags)
    let two = try await client.accountSummary(tags: tags)
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 2)
    let (id1, id2) = (sent[FakeGateway.syncFrames][2], sent[FakeGateway.syncFrames + 1][2])
    let text = "Maximum number of account summary requests exceeded"
    gateway.feed(["4", "2", id1, "322", text, ""])
    gateway.feed(value(id2, "NetLiquidation", "100"))
    gateway.feed(end(id2))
    #expect(try await ending(one) == .ib(code: 322, text: text))
    #expect(pairs(try await take(1, two)[0]) == ["DU1/NetLiquidation=100"])
    #expect(!(try await gateway.waitForSent(FakeGateway.syncFrames + 2)).contains { $0 == ["63", "1", id1] })
}

@Test func noticeDoesNotEndAStream() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.accountSummary(tags: ["NetLiquidation"])
    let id = try await lastRequestID(gateway, FakeGateway.syncFrames + 1, at: 2)
    gateway.feed(["4", "2", id, "2104", "Market data farm connection is OK:usfarm", ""])
    gateway.feed(value(id, "NetLiquidation", "100"))
    gateway.feed(end(id))
    #expect(pairs(try await take(1, stream)[0]) == ["DU1/NetLiquidation=100"])
}

@Test func stoppingAStreamSendsItsCancel() async throws {
    let gateway = FakeGateway()
    gateway.onRequest = { r in   // answered at once, so the test never holds the stream past `take`
        switch r[0] {
        case "62": [value(r[2], "NetLiquidation", "100"), end(r[2])]
        case "94": [pnl(r[1], "1")]
        default: []
        }
    }
    let client = try await connected(gateway)
    let messages = await client.messages()

    _ = try await take(1, client.accountSummary(tags: ["NetLiquidation"]))
    let id = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames][2]
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 2)[FakeGateway.syncFrames + 1] == ["63", "1", id])

    _ = try await take(1, client.pnlSingle(account: "DU1", conID: 265598))
    let pid = try await gateway.waitForSent(FakeGateway.syncFrames + 3)[FakeGateway.syncFrames + 2][1]
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 4)[FakeGateway.syncFrames + 3] == ["95", pid])
    #expect(await client.requestStreamCount == 0)

    gateway.feed(value(id, "NetLiquidation", "101"))   // late, for the stopped reqIds
    gateway.feed(pnl(pid, "2"))
    try await within2s {
        var seen = 0
        for await m in messages {
            if case .accountSummary(let r, _) = m, "\(r)" == id { seen += 1 }
            if case .pnlSingle(let r, let v) = m, "\(r)" == pid, v.daily == d("2") { seen += 1 }
            if seen == 2 { return }
        }
    }
    #expect(await client.requestStreamCount == 0)
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 4).count == FakeGateway.syncFrames + 4)
}

@Test func pnlSingleYieldsEachUpdate() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.pnlSingle(account: "DU1", conID: 265598)
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    let id = sent[FakeGateway.syncFrames][1]
    #expect(sent[FakeGateway.syncFrames] == ["94", id, "DU1", "", "265598"])
    gateway.feed(pnl(id, "1.5"))
    gateway.feed(["95", id, "100", "2.5", "1.7976931348623157E308", "0", "18725"])
    let updates = try await take(2, stream)
    #expect(updates.map(\.daily) == [d("1.5"), d("2.5")])
    #expect(updates[0].position == d("100") && updates[0].unrealized == d("5") && updates[1].unrealized == nil)
}

@Test(arguments: [true, false])
func disconnectEndsRequestStreams(peerCloses: Bool) async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let summary = try await client.accountSummary(tags: ["NetLiquidation"])
    let p = try await client.pnlSingle(account: "DU1", conID: 265598)
    _ = try await gateway.waitForSent(FakeGateway.syncFrames + 2)
    if peerCloses { gateway.close() } else { await client.disconnect() }
    #expect(try await ending(summary) == .connectionClosed)
    #expect(try await ending(p) == .connectionClosed)
    #expect(await client.requestStreamCount == 0)
    try await Task.sleep(for: .milliseconds(50))   // room for a wrong cancel from the streams' termination
    let after = try await gateway.waitForSent(FakeGateway.syncFrames + 2).dropFirst(FakeGateway.syncFrames + 2)
    #expect(Array(after) == (peerCloses ? [] : [["64", "1"]]))   // a clean disconnect sends cancelPositions only
    #expect(gateway.writesAfterClose == 0)
}

@Test func requestStreamsNeedAConnection() async throws {
    let client = IBClient(connector: FakeGateway().connector)
    await #expect(throws: IBClientError.notConnected) { try await client.accountSummary(tags: tags) }
    await #expect(throws: IBClientError.notConnected) { try await client.pnlSingle(account: "DU1", conID: 1) }
    await #expect(throws: IBClientError.notConnected) { try await client.accountUpdatesMulti(account: "DU1") }
    await #expect(throws: IBClientError.notConnected) { try await client.positionsMulti(account: "DU1") }
    await #expect(throws: IBClientError.notConnected) { try await client.pnl(account: "DU1") }
    #expect(await client.requestStreamCount == 0)
}

@Test func badTagRegistersNothing() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    await #expect(throws: IBClientError.encoding(.nonASCII(field: "Чистая"))) {
        try await client.accountSummary(tags: ["Чистая"])
    }
    #expect(await client.requestStreamCount == 0)
    try await client.cancelOrder(1)   // the next frame out is this one
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    #expect(sent.count == FakeGateway.syncFrames + 1 && sent[FakeGateway.syncFrames][0] == "4")
}

@Test func warningEndsARequestStream() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.accountSummary(tags: ["NetLiquidation"])
    let id = try await lastRequestID(gateway, FakeGateway.syncFrames + 1, at: 2)
    gateway.feed(["4", "2", id, "321", "Error validating request", ""])
    #expect(try await ending(stream) == .ib(code: 321, text: "Error validating request"))
}

private func multiValue(_ id: String, _ tag: String, _ value: String, model: String = "") -> [String] {
    ["73", "1", id, "DU1", model, tag, value, "USD"]
}

private func multiPosition(_ id: String, _ conID: String, _ quantity: String) -> [String] {
    ["71", "1", id, "DU1", conID, "AAPL", "STK", "", "0", "", "", "SMART", "USD", "AAPL", "NMS", quantity, "10", ""]
}

private func accountPnL(_ id: String, _ daily: String, realized: String = "0") -> [String] {
    ["94", id, daily, "5", realized]
}

@Test func accountUpdatesMultiYieldsTheSetAtEnd() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.accountUpdatesMulti(account: "DU1")
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    let id = sent[FakeGateway.syncFrames][2]
    #expect(sent[FakeGateway.syncFrames] == ["76", "1", id, "DU1", "", "0"])
    gateway.feed(multiValue(id, "NetLiquidation", "100"))
    gateway.feed(multiValue(id, "BuyingPower", "400"))
    gateway.feed(["74", "1", id])
    #expect(pairs(try await take(1, stream)[0]) == ["DU1/BuyingPower=400", "DU1/NetLiquidation=100"])
}

@Test func positionsMultiYieldsTheSetAtEndAndDropsZero() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.positionsMulti(account: "DU1")
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    let id = sent[FakeGateway.syncFrames][2]
    #expect(sent[FakeGateway.syncFrames] == ["74", "1", id, "DU1", ""])
    gateway.feed(multiPosition(id, "1", "5"))
    gateway.feed(multiPosition(id, "2", "7"))
    gateway.feed(["72", "1", id])
    gateway.feed(multiPosition(id, "1", "0"))
    let sets = try await take(2, stream)
    #expect(sets[0].map(\.contract.conID) == [1, 2])
    #expect(sets[1].map(\.contract.conID) == [2])
}

@Test func pnlYieldsEachUpdate() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.pnl(account: "DU1")
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    let id = sent[FakeGateway.syncFrames][1]
    #expect(sent[FakeGateway.syncFrames] == ["92", id, "DU1", ""])
    gateway.feed(accountPnL(id, "1.5"))
    gateway.feed(accountPnL(id, "2.5", realized: "1.7976931348623157E308"))
    let updates = try await take(2, stream)
    #expect(updates.map(\.daily) == [d("1.5"), d("2.5")])
    #expect(updates[0].realized == d("0") && updates[1].realized == nil)
}

@Test func stoppingMultiStreamsSendsTheirCancels() async throws {
    let gateway = FakeGateway()
    gateway.onRequest = { r in
        switch r[0] {
        case "76": [multiValue(r[2], "NetLiquidation", "1"), ["74", "1", r[2]]]
        case "74" where r.count == 5: [multiPosition(r[2], "1", "5"), ["72", "1", r[2]]]
        case "92": [accountPnL(r[1], "1")]
        default: []
        }
    }
    let client = try await connected(gateway)
    let n = FakeGateway.syncFrames
    _ = try await take(1, client.accountUpdatesMulti(account: "DU1"))
    let a = try await gateway.waitForSent(n + 1)[n][2]
    #expect(try await gateway.waitForSent(n + 2)[n + 1] == ["77", "1", a])
    _ = try await take(1, client.positionsMulti(account: "DU1"))
    let p = try await gateway.waitForSent(n + 3)[n + 2][2]
    #expect(try await gateway.waitForSent(n + 4)[n + 3] == ["75", "1", p])
    _ = try await take(1, client.pnl(account: "DU1"))
    let q = try await gateway.waitForSent(n + 5)[n + 4][1]
    #expect(try await gateway.waitForSent(n + 6)[n + 5] == ["93", q])
    #expect(await client.requestStreamCount == 0)
}

@Test func accountPnLErrorEndsItsStream() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.pnl(account: "DU1")
    let id = try await lastRequestID(gateway, FakeGateway.syncFrames + 1, at: 1)
    gateway.feed(["4", "2", id, "322", "Error processing request", ""])
    #expect(try await ending(stream) == .ib(code: 322, text: "Error processing request"))
}

@Test func consumerMultiStreamDoesNotTouchAccountValues() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.accountUpdatesMulti(account: "DU1", modelCode: "M1")
    let id = try await lastRequestID(gateway, FakeGateway.syncFrames + 1, at: 2)
    gateway.feed(multiValue(id, "NetLiquidation", "100", model: "M1"))
    gateway.feed(["74", "1", id])
    #expect(try await take(1, stream)[0].map(\.modelCode) == ["M1"])
    #expect(await client.accountValues().snapshot.allSatisfy { $0.modelCode != "M1" })
}
