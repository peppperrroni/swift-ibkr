import Foundation
import Testing
@testable import IBKR

/// Collects what a log handler sees.
final class LogLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [(IBLogLevel, String)] = []
    var handler: IBLogHandler { { level, text in self.lock.withLock { self.lines.append((level, text)) } } }
    var all: [(IBLogLevel, String)] { lock.withLock { lines } }
    func at(_ level: IBLogLevel) -> [String] { all.filter { $0.0 == level }.map(\.1) }
}

/// When each frame left, as the gateway saw it.
private final class SendTimes: @unchecked Sendable {
    private let lock = NSLock()
    private var times: [ContinuousClock.Instant] = []
    func add() { lock.withLock { times.append(.now) } }
    var all: [ContinuousClock.Instant] { lock.withLock { times } }
}

/// The idle times a stream yielded, with when each arrived.
private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(idle: Duration, at: ContinuousClock.Instant)] = []
    func add(_ idle: Duration) { lock.withLock { items.append((idle, .now)) } }
    var all: [(idle: Duration, at: ContinuousClock.Instant)] { lock.withLock { items } }
}

private func connect(_ gateway: FakeGateway, clientID: Int = 7, timeout: Duration = .seconds(10),
                     options: ConnectOptions = .init(), log: LogLines? = nil) async throws -> IBClient {
    let client = IBClient(connector: gateway.connector)
    if let log { client.setLogHandler(log.handler) }
    try await within2s { try await client.connect(clientID: clientID, timeout: timeout, options: options) }
    return client
}

/// Polls `condition` on the client for up to 2 s.
private func eventually(_ condition: @escaping @Sendable () async -> Bool) async throws {
    try await within2s { while await !condition() { try await Task.sleep(for: .milliseconds(5)) } }
}

@Suite struct ConnectOptionsTests {
    @Test func clientZeroAutoBindsInTheSync() async throws {
        let zero = FakeGateway()
        _ = try await connect(zero, clientID: 0)
        let sent = try await zero.waitForSent(FakeGateway.syncFrames + 1)
        #expect(sent.map { $0[0] } == ["71", "15", "16", "99", "7", "61", "6"])
        #expect(sent[1] == ["15", "1", "1"])

        let seven = FakeGateway()
        _ = try await connect(seven)
        #expect(try await seven.waitForSent(FakeGateway.syncFrames).map { $0[0] } == ["71", "16", "99", "7", "61", "6"])
    }

    @Test func readOnlyAndFetchGateTheSync() async throws {
        let readOnly = FakeGateway()
        _ = try await connect(readOnly, options: .init(readOnly: true))
        #expect(try await readOnly.waitForSent(4).map { $0[0] } == ["71", "7", "61", "6"])

        let nothing = FakeGateway()
        let client = try await connect(nothing, options: .init(fetch: []))
        #expect(await client.states().first { _ in true } == .connected(serverVersion: 178, accounts: ["DU1"]))
        try await Task.sleep(for: .milliseconds(50))
        #expect(try await nothing.waitForSent(1).map { $0[0] } == ["71"])

        let positions = FakeGateway()
        _ = try await connect(positions, options: .init(fetch: [.positions]))
        try await Task.sleep(for: .milliseconds(50))
        #expect(try await positions.waitForSent(2).map { $0[0] } == ["71", "61"])
    }

    @Test func accountOptionSubscribesThatAccount() async throws {
        let two = FakeGateway(accounts: "DU1,DU2")
        let client = try await connect(two, options: .init(account: "DU2"))
        let sent = try await two.waitForSent(8)
        #expect(sent.filter { $0[0] == "6" } == [["6", "2", "1", "DU2"]])
        #expect(sent.filter { $0[0] == "76" }.map { $0[3] } == ["DU1", "DU2"])
        _ = client

        let capped = FakeGateway(accounts: "DU1,DU2")
        _ = try await connect(capped, options: .init(account: "DU2", maxSyncedSubAccounts: 1))
        try await Task.sleep(for: .milliseconds(50))
        let cappedSent = try await capped.waitForSent(6)
        #expect(cappedSent.map { $0[0] } == ["71", "16", "99", "7", "61", "6"])
    }

    @Test func subAccountUpdatesAloneSyncTheSingleAccount() async throws {
        let one = FakeGateway()
        one.onRequest = { $0[0] == "76" ? [["74", "1", $0[2]]] : [] }   // the fake ends a 76 only with several
        _ = try await connect(one, options: .init(fetch: [.subAccountUpdates]))
        let sent = try await one.waitForSent(2)
        #expect(sent.map { $0[0] } == ["71", "76"])
        #expect(sent[1][3] == "DU1")
    }

    @Test func accountThatDoesNotEncodeFailsConnect() async throws {
        let gateway = FakeGateway(accounts: "DU1,DU2")
        let client = IBClient(connector: gateway.connector)
        await #expect(throws: IBClientError.encoding(.nonASCII(field: "DÜ2"))) {
            try await within2s { try await client.connect(clientID: 7, options: .init(account: "DÜ2")) }
        }
    }

    @Test func syncErrorsCanBeLogged() async throws {
        let failing: @Sendable ([String]) -> [[String]] = {
            $0[0] == "7" ? [["4", "2", $0[2], "322", "Error processing request", ""]] : []
        }
        let lenient = FakeGateway(answersExecutions: false)
        lenient.onRequest = failing
        let log = LogLines()
        _ = try await connect(lenient, options: .init(throwsOnSyncError: false), log: log)
        // IB's fatal error, then the sync giving the request up
        #expect(log.at(.error).count == 2)
        #expect(log.at(.error).filter { $0.hasPrefix("connect: sync request") }.count == 1)

        let warned = FakeGateway(answersExecutions: false)
        warned.onRequest = { $0[0] == "7" ? [["4", "2", $0[2], "321", "Error validating request", ""]] : [] }
        let warnLog = LogLines()
        _ = try await connect(warned, options: .init(throwsOnSyncError: false), log: warnLog)
        #expect(warnLog.at(.warning).count == 1)
        #expect(warnLog.at(.error).filter { $0.hasPrefix("connect: sync request") }.count == 1)

        let strict = FakeGateway(answersExecutions: false)
        strict.onRequest = failing
        await #expect(throws: IBClientError.ib(code: 322, text: "Error processing request")) {
            _ = try await connect(strict)
        }
    }

    @Test func syncDeadlineCanBeLogged() async throws {
        let log = LogLines()
        let silent = FakeGateway(answersPositions: false)
        _ = try await connect(silent, timeout: .milliseconds(200), options: .init(throwsOnSyncError: false), log: log)
        #expect(log.at(.error).count == 1)
    }

    @Test func optionalCapabilitiesGoInStartAPI() async throws {
        let gateway = FakeGateway()
        _ = try await connect(gateway, options: .init(optionalCapabilities: "+ABC"))
        #expect(try await gateway.waitForSent(1).first == ["71", "2", "7", "+ABC"])
    }

    @Test func throttleOptionsAreUsed() async throws {
        let gateway = FakeGateway()
        let times = SendTimes()
        gateway.onRequest = { _ in times.add(); return [] }
        _ = try await connect(gateway, options: .init(maxRequests: 1, requestsInterval: .milliseconds(50)))
        let t = times.all
        #expect(t[2] - t[0] >= .milliseconds(100))
    }

    @Test func connectionStatsCountBothWays() async throws {
        let gateway = FakeGateway()
        let client = try await connect(gateway)
        // ib_async counts the hello as a message sent (connection.py sendMsg) and the server's hello as one received
        try await eventually { (try? await client.connectionStats().messagesSent) == FakeGateway.syncFrames + 1 }
        let stats = try await client.connectionStats()
        #expect(stats.bytesSent > 0 && stats.bytesReceived > 0)
        #expect(stats.messagesReceived == 8)   // server hello, 9, 15, 53, 102, 55, 62, then the 54 that ends the sync
        await client.disconnect()
        await #expect(throws: IBClientError.notConnected) { try await client.connectionStats() }
    }

    @Test func connectionStatsDescription() {
        let stats = ConnectionStats(startTime: Date(), duration: .milliseconds(12_300), bytesReceived: 6_780_000,
                                    bytesSent: 1234, messagesReceived: 1200, messagesSent: 45)
        #expect(stats.description == "1.23 kB sent in 45 messages, 6.78 MB received in 1200 messages, session 12.3 s")
    }

    @Test func formatSIMatchesIbAsync() {
        #expect(formatSI(0) == "0 ")
        #expect(formatSI(999) == "999 ")
        #expect(formatSI(1234) == "1.23 k")
        #expect(formatSI(0.5) == "500 m")
        #expect(formatSI(0.0) == "0.00 ")
        #expect(formatSI(999_600) == "1.00 M")
        #expect(formatSI(12.3) == "12.3 ")
    }

    @Test func idleTimeoutsFireOncePerSilenceAndRearm() async throws {
        let gateway = FakeGateway()
        let client = try await connect(gateway)
        let seen = Seen()
        let reader = Task { for await idle in await client.idleTimeouts(after: .milliseconds(50)) { seen.add(idle) } }
        defer { reader.cancel() }
        try await eventually { seen.all.count == 1 }
        #expect(seen.all[0].idle >= .milliseconds(50))
        try await Task.sleep(for: .milliseconds(150))   // three more periods of silence: still one element
        #expect(seen.all.count == 1)
        let fed = ContinuousClock.now
        gateway.feed(["49", "1", "1700000000"])
        try await eventually { seen.all.count == 2 }
        #expect(seen.all[1].idle >= .milliseconds(50))
        #expect(seen.all[1].at - fed >= .milliseconds(50))
    }

    @Test func idleTimeoutsStopTheirTimerWithTheConsumer() async throws {
        let client = try await connect(FakeGateway())
        let reader = Task { for await _ in await client.idleTimeouts(after: .milliseconds(20)) {} }
        try await eventually { await client.activeIdleTimers == 1 }
        reader.cancel()
        try await eventually { await client.activeIdleTimers == 0 }
    }

    @Test func idleTimeoutsWithoutAPeriodFinishAtOnce() async throws {
        let client = try await connect(FakeGateway())
        let got = try await within2s {
            var n = 0
            for await _ in await client.idleTimeouts(after: .zero) { n += 1 }
            return n
        }
        #expect(got == 0)
        #expect(await client.activeIdleTimers == 0)
    }

    @Test func throttlingReportsStartAndEnd() async throws {
        let gateway = FakeGateway()
        let client = try await connect(gateway, options: .init(maxRequests: 1, requestsInterval: .milliseconds(20)))
        try await eventually { (try? await client.connectionStats().messagesSent) == FakeGateway.syncFrames + 1 }
        let events = await client.throttling()
        for _ in 0..<3 { try await client.setServerLogLevel(.detail) }
        let got = try await within2s {
            var seen: [Bool] = []
            for await e in events { seen.append(e); if seen.count == 3 { break } }
            return seen
        }
        #expect(got == [false, true, false])
    }

    @Test func endpointNamesTheConnection() async throws {
        let client = try await connect(FakeGateway())
        let e = try #require(await client.endpoint())
        #expect(e.host == "127.0.0.1" && e.port == 4002 && e.clientID == 7)
        await client.disconnect()
        #expect(await client.endpoint() == nil)
    }

    @Test func libraryVersionMatchesThePodspec() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let podspec = try String(contentsOf: root.appendingPathComponent("SwiftIBKR.podspec"), encoding: .utf8)
        #expect(podspec.contains("s.version      = '\(IBClient.libraryVersion)'"))
    }

    @Test func logHandlerSeesFramesAndOrders() async throws {
        let log = LogLines()
        let gateway = FakeGateway()
        let client = try await connect(gateway, log: log)
        let id = try await client.placeOrder(Contract(symbol: "AAPL"),
                                             Order(action: .buy, quantity: 1, orderType: "LMT", limitPrice: d("180")))
        let debug = log.at(.debug)
        #expect(debug.contains { $0.hasPrefix(">>> 71|2|7|") })
        #expect(debug.contains { $0.hasPrefix("<<< ") })
        #expect(log.at(.info).filter { $0.hasPrefix("placeOrder") } == ["placeOrder \(id): BUY 1 AAPL LMT 180"])
    }
}
