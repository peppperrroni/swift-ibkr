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

@Test func scannerDataCancelledSendsItsCancel() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let call = Task { try await client.scannerData(top) }
    let id = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames][1]
    call.cancel()
    await #expect(throws: IBClientError.cancelled) { try await call.value }
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 2)[FakeGateway.syncFrames + 1] == ["23", "1", id])
    #expect(await client.requestStreamCount == 0)
}

@Test func scannerParametersAnswer() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in f == ["24", "1"] ? [["19", "1", "<xml/>"]] : [] }
    #expect(try await within2s { try await client.scannerParameters() } == "<xml/>")
    #expect(await client.requestStreamCount == 0)
}

@Test func newsProvidersAnswer() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in
        f == ["85"] ? [["85", "2", "BRFG", "Briefing.com General Market Columns", "DJNL", "Dow Jones Newsletters"]] : []
    }
    let providers = try await within2s { try await client.newsProviders() }
    #expect(providers == [NewsProvider(code: "BRFG", name: "Briefing.com General Market Columns"),
                          NewsProvider(code: "DJNL", name: "Dow Jones Newsletters")])
    #expect(await client.requestStreamCount == 0)
}

@Test func newsArticleAnswers() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in f[0] == "84" ? [["83", f[1], "0", "Apple beats estimates"]] : [] }
    let article = try await within2s { try await client.newsArticle(providerCode: "BRFG", articleID: "BRFG$12345") }
    #expect(article == NewsArticle(articleType: 0, articleText: "Apple beats estimates"))
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    #expect(sent[FakeGateway.syncFrames] == ["84", sent[FakeGateway.syncFrames][1], "BRFG", "BRFG$12345", ""])
    #expect(await client.requestStreamCount == 0)
}

@Test func newsArticleFailsOnItsError() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let text = "Failed to request news article: No data available"
    gateway.onRequest = { f in f[0] == "84" ? [ibError(f[1], "10172", text)] : [] }
    await #expect(throws: IBClientError.ib(code: 10172, text: text)) {
        _ = try await within2s { try await client.newsArticle(providerCode: "BRFG", articleID: "X") }
    }
    #expect(await client.requestStreamCount == 0)
}

@Test func historicalNewsCollectsUntilEnd() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in
        f[0] == "86" ? [["86", f[1], "2026-11-10 14:30:00.0", "BRFG", "A1", "First"],
                        ["86", f[1], "2026-11-10 14:20:00.0", "BRFG", "A2", "Second"], ["87", f[1], "0"]] : []
    }
    let news = try await within2s { try await client.historicalNews(conID: 265598, providerCodes: ["BRFG"], totalResults: 10) }
    #expect(news.map(\.articleID) == ["A1", "A2"])
    #expect(news.map(\.headline) == ["First", "Second"])
    try await Task.sleep(for: .milliseconds(50))   // room for a wrong cancel: IB has none
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1).count == FakeGateway.syncFrames + 1)
    #expect(await client.requestStreamCount == 0)
}

private let halted = ["14", "1", "3", "1", "Exchange halted", "NYSE"]
private let haltedBulletin = NewsBulletin(msgID: 3, msgType: 1, message: "Exchange halted", origExchange: "NYSE")

@Test func newsBulletinsStreamAndCancel() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let bulletins = try await client.newsBulletins()
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames] == ["12", "1", "0"])
    let (seen, signal) = AsyncStream.makeStream(of: NewsBulletin.self)
    let reader = Task { do { for try await b in bulletins { signal.yield(b) } } catch {} }
    gateway.feed(halted)
    #expect(try await within2s { await seen.first { _ in true } } == haltedBulletin)
    reader.cancel()
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 2)[FakeGateway.syncFrames + 1] == ["13", "1"])
    try await Task.sleep(for: .milliseconds(50))   // room for a wrong second 13
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 2).filter { $0[0] == "13" }.count == 1)
    #expect(await client.requestStreamCount == 0)
}

/// Review Focus 5: IB holds one bulletin subscription per connection, so a second stream is refused, not shared.
@Test func aSecondNewsBulletinsStreamIsRefused() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let first = try await client.newsBulletins()
    await #expect(throws: IBClientError.alreadySubscribed) { _ = try await client.newsBulletins() }
    try await Task.sleep(for: .milliseconds(50))   // room for a wrong second 12
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1).filter { $0[0] == "12" }.count == 1)
    let reader = Task { do { for try await _ in first {} } catch {} }
    reader.cancel()
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 2)[FakeGateway.syncFrames + 1] == ["13", "1"])
    _ = try await client.newsBulletins(allMessages: true)
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 3)[FakeGateway.syncFrames + 2] == ["12", "1", "1"])
}

@Test func newsBulletinsEndWithTheConnection() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let bulletins = try await client.newsBulletins()
    _ = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    gateway.close()
    await #expect(throws: IBClientError.connectionClosed) { try await within2s { for try await _ in bulletins {} } }
}

@Test func newsTicksArriveThroughMarketData() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let ticks = try await client.marketData(Contract(symbol: "BRFG:BRFG_ALL", secType: "NEWS", exchange: "BRFG"),
                                            genericTicks: ["mdoff", "292"])
    let f = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames]
    #expect(f[16] == "mdoff,292")
    gateway.feed(["84", f[2], "1794321000000", "BRFG", "BRFG$12345", "Apple headline", "A:800015:L:en"])
    #expect(try await within2s { try await ticks.first { _ in true } }
            == .news(NewsTick(timeStamp: 1794321000000, providerCode: "BRFG", articleID: "BRFG$12345",
                              headline: "Apple headline", extraData: "A:800015:L:en")))
}

@Test func historicalNewsFailsOnItsError() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let text = "Failed to request historical news:Unknown provider codes"
    gateway.onRequest = { f in f[0] == "86" ? [ibError(f[1], "10187", text)] : [] }
    await #expect(throws: IBClientError.ib(code: 10187, text: text)) {
        _ = try await within2s { try await client.historicalNews(conID: 265598, providerCodes: ["NOPE"], totalResults: 10) }
    }
    #expect(await client.requestStreamCount == 0)
}

private let reportSnapshot = "<ReportSnapshot/>"

@Test func fundamentalDataAnswers() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in f[0] == "52" ? [["51", "1", f[2], reportSnapshot]] : [] }
    #expect(try await within2s { try await client.fundamentalData(Contract(symbol: "AAPL"), reportType: "ReportSnapshot") }
            == reportSnapshot)
    try await Task.sleep(for: .milliseconds(50))   // room for a wrong cancel: the answer ends it
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1).contains { $0[0] == "53" } == false)
    #expect(await client.requestStreamCount == 0)
}

@Test func fundamentalDataFailsOnItsError() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let text = "We are sorry, but fundamentals data for the security specified is not available."
    gateway.onRequest = { f in f[0] == "52" ? [ibError(f[2], "430", text)] : [] }
    await #expect(throws: IBClientError.ib(code: 430, text: text)) {
        _ = try await within2s { try await client.fundamentalData(Contract(symbol: "AAPL"), reportType: "ReportSnapshot") }
    }
    #expect(await client.requestStreamCount == 0)
}

@Test func fundamentalDataCancelledSendsItsCancel() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let call = Task { try await client.fundamentalData(Contract(symbol: "AAPL"), reportType: "ReportSnapshot") }
    let id = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames][2]
    call.cancel()
    await #expect(throws: IBClientError.cancelled) { try await call.value }
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 2)[FakeGateway.syncFrames + 1] == ["53", "1", id])
}

/// R7, as ib_async's getWshMetaDataAsync: the answered request stays open until the next call cancels it.
@Test func wshMetaDataHoldsItsRequestUntilTheNextCall() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in f[0] == "100" ? [["104", f[1], "{\"m\":1}"]] : [] }
    #expect(try await within2s { try await client.wshMetaData() } == "{\"m\":1}")
    try await Task.sleep(for: .milliseconds(50))   // room for a wrong cancel
    let first = try await gateway.waitForSent(FakeGateway.syncFrames + 1)
    #expect(first.count == FakeGateway.syncFrames + 1)
    let id1 = first[FakeGateway.syncFrames][1]
    #expect(await client.requestStreamCount == 0)
    #expect(try await within2s { try await client.wshMetaData() } == "{\"m\":1}")
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 3)
    #expect(sent[FakeGateway.syncFrames + 1] == ["101", id1])
    #expect(sent[FakeGateway.syncFrames + 2][0] == "100")
    #expect(sent[FakeGateway.syncFrames + 2][1] != id1)
}

@Test func wshMetaDataFailsOnItsError() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in f[0] == "100" ? [ibError(f[1], "321", "Error validating request")] : [] }
    await #expect(throws: IBClientError.ib(code: 321, text: "Error validating request")) {
        _ = try await within2s { try await client.wshMetaData() }
    }
    try await Task.sleep(for: .milliseconds(50))   // room for a wrong cancel
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1).contains { $0[0] == "101" } == false)
    #expect(await client.requestStreamCount == 0)
    // nothing is held after an error, so a later call sends no 101 either
    gateway.onRequest = { f in f[0] == "100" ? [["104", f[1], "{\"m\":1}"]] : [] }
    #expect(try await within2s { try await client.wshMetaData() } == "{\"m\":1}")
    try await Task.sleep(for: .milliseconds(50))
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 2)
    #expect(sent.count == FakeGateway.syncFrames + 2)
    #expect(sent.contains { $0[0] == "101" } == false)
}

@Test func wshMetaRequestEndsWithTheConnection() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in f[0] == "100" ? [["104", f[1], "{\"m\":1}"]] : [] }
    _ = try await within2s { try await client.wshMetaData() }
    #expect(await client.wshMetaRequestID != nil)
    gateway.close()
    try await within2s { while await client.wshMetaRequestID != nil { try await Task.sleep(for: .milliseconds(5)) } }
}

@Test func wshMetaDataCancelledSendsItsCancel() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let call = Task { try await client.wshMetaData() }
    let id = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames][1]
    call.cancel()
    await #expect(throws: IBClientError.cancelled) { try await call.value }
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 2)[FakeGateway.syncFrames + 1] == ["101", id])
    #expect(await client.wshMetaRequestID == nil)
}

@Test func wshEventDataAnswersThenCancels() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in f[0] == "102" ? [["105", f[1], "{\"m\":1}"]] : [] }
    #expect(try await within2s { try await client.wshEventData(WshEventData(conID: 8314)) } == "{\"m\":1}")
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 2)
    #expect(sent[FakeGateway.syncFrames + 1] == ["103", sent[FakeGateway.syncFrames][1]])
    #expect(await client.requestStreamCount == 0)
}

@Test func wshEventDataFailsOnItsError() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in f[0] == "102" ? [ibError(f[1], "321", "Error validating request")] : [] }
    await #expect(throws: IBClientError.ib(code: 321, text: "Error validating request")) {
        _ = try await within2s { try await client.wshEventData(WshEventData(conID: 8314)) }
    }
    try await Task.sleep(for: .milliseconds(50))   // room for a wrong cancel
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1).contains { $0[0] == "103" } == false)
    #expect(await client.requestStreamCount == 0)
}

@Test func wshEventDataCancelledSendsItsCancel() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let call = Task { try await client.wshEventData(WshEventData(conID: 8314)) }
    let id = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames][1]
    call.cancel()
    await #expect(throws: IBClientError.cancelled) { try await call.value }
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 2)[FakeGateway.syncFrames + 1] == ["103", id])
    #expect(await client.requestStreamCount == 0)
}

/// 16 carries no reqId: each faData call takes only the answer of its own type, whatever the order.
@Test func faDataAnswersByType() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let a = Task { try await client.faData(.groups) }
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames] == ["18", "1", "1"])
    let b = Task { try await client.faData(.aliases) }
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 2)[FakeGateway.syncFrames + 1] == ["18", "1", "3"])
    gateway.feed(["16", "1", "3", "<aliases/>"])
    gateway.feed(["16", "1", "1", "<groups/>"])
    #expect(try await within2s { try await a.value } == "<groups/>")
    #expect(try await within2s { try await b.value } == "<aliases/>")
    #expect(await client.requestStreamCount == 0)
}

@Test func replaceFAAnswers() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in f[0] == "19" ? [["103", f[4], "done"]] : [] }
    #expect(try await within2s { try await client.replaceFA(.aliases, xml: "<ListOfAccountAliases/>") } == "done")
    #expect(await client.requestStreamCount == 0)
}

@Test func replaceFAFailsOnItsError() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in f[0] == "19" ? [ibError(f[4], "321", "Error validating request")] : [] }
    await #expect(throws: IBClientError.ib(code: 321, text: "Error validating request")) {
        _ = try await within2s { try await client.replaceFA(.aliases, xml: "<ListOfAccountAliases/>") }
    }
    #expect(await client.requestStreamCount == 0)
}

@Test func displayGroupsAnswer() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in f[0] == "67" ? [["67", "1", f[2], "1|2|3"]] : [] }
    #expect(try await within2s { try await client.displayGroups() } == "1|2|3")
    #expect(await client.requestStreamCount == 0)
}

@Test func displayGroupsFailOnTheirError() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    gateway.onRequest = { f in f[0] == "67" ? [ibError(f[2], "321", "Error validating request")] : [] }
    await #expect(throws: IBClientError.ib(code: 321, text: "Error validating request")) {
        _ = try await within2s { try await client.displayGroups() }
    }
    #expect(await client.requestStreamCount == 0)
}

/// Review Focus 4: updateDisplayGroup sends under the stream's own reqId, and stopping the stream sends 70 for it.
@Test func displayGroupUpdatesStreamUpdateAndCancel() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let (rid, updates) = try await client.displayGroupUpdates(1)
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames] == ["68", "1", "\(rid)", "1"])
    let (reader, result) = take(1, updates)
    gateway.feed(["68", "1", "\(rid)", "265598@SMART"])
    #expect(try await within2s { try await result.value } == ["265598@SMART"])
    try await client.updateDisplayGroup(rid, contractInfo: "8314@SMART")
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 2)[FakeGateway.syncFrames + 1]
            == ["69", "1", "\(rid)", "8314@SMART"])
    reader.cancel()
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 3)[FakeGateway.syncFrames + 2] == ["70", "1", "\(rid)"])
    #expect(await client.requestStreamCount == 0)
}

@Test func displayGroupUpdatesEndOnTheirError() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let (rid, updates) = try await client.displayGroupUpdates(1)
    gateway.feed(ibError("\(rid)", "321", "Error validating request"))
    await #expect(throws: IBClientError.ib(code: 321, text: "Error validating request")) {
        try await within2s { for try await _ in updates {} }
    }
    try await Task.sleep(for: .milliseconds(50))   // room for a wrong cancel
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1).contains { $0[0] == "70" } == false)
    #expect(await client.requestStreamCount == 0)
}

/// The verify calls only send; IB's answers reach messages() and nothing else.
@Test func verifyCallsSendAndAnswersReachMessages() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let messages = await client.messages()
    try await client.verifyRequest(apiName: "app", apiVersion: "1.0")
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames] == ["65", "1", "app", "1.0"])
    gateway.feed(["65", "1", "d"])
    let got = try await within2s { await messages.first { if case .verifyMessageAPI = $0 { true } else { false } } }
    #expect(got == .verifyMessageAPI(apiData: "d"))
    try await client.verifyAndAuthMessage("d", xyzResponse: "r")
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 2)[FakeGateway.syncFrames + 1] == ["73", "1", "d", "r"])
    try await client.verifyMessage("m")
    try await client.verifyAndAuthRequest(apiName: "app", apiVersion: "1.0", opaqueISVKey: "k")
    let sent = try await gateway.waitForSent(FakeGateway.syncFrames + 4)
    #expect(Array(sent[(FakeGateway.syncFrames + 2)...]) == [["66", "1", "m"], ["72", "1", "app", "1.0", "k"]])
    #expect(await client.requestStreamCount == 0)
}
