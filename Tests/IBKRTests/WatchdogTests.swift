#if os(macOS) || os(Linux) || os(Windows)
import Foundation
import Testing
@testable import IBKR

/// Records every launch and termination; each launched app emits `lines` and then waits to be terminated.
// @unchecked Sendable: the mutable state sits behind `lock`.
private final class FakeLauncher: @unchecked Sendable {
    private let lock = NSLock()
    private var _launches: [[String]] = []
    private var _terminations = 0
    let lines: [String]
    init(lines: [String] = []) { self.lines = lines }

    var launches: [[String]] { lock.withLock { _launches } }
    var terminations: Int { lock.withLock { _terminations } }

    var launcher: AppLauncher {
        { arguments, _ in
            self.lock.withLock { self._launches.append(arguments) }
            return FakeApp(lines: self.lines) { self.lock.withLock { self._terminations += 1 } }
        }
    }

    /// Waits up to 2 s for `count` launches.
    func waitForLaunches(_ count: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while launches.count < count {
            guard ContinuousClock.now < deadline else { throw TimedOut() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private struct FakeApp: LaunchedApp {
    let lines: AsyncStream<String>
    let onTerminate: @Sendable () -> Void
    init(lines: [String], onTerminate: @escaping @Sendable () -> Void) {
        let (stream, out) = AsyncStream.makeStream(of: String.self)
        for line in lines { out.yield(line) }   // left open, as a running app's stdout
        self.lines = stream
        self.onTerminate = onTerminate
    }
    func terminate() async { onTerminate() }
}

/// Collects a `Watchdog`'s events from before `start()` on.
// @unchecked Sendable: `all` sits behind `lock`.
private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [WatchdogEvent] = []
    private var reader: Task<Void, Never>?

    init(_ watchdog: Watchdog) async {
        let stream = await watchdog.events()
        reader = Task { [weak self] in for await e in stream { self?.record(e) } }
    }
    deinit { reader?.cancel() }

    private func record(_ e: WatchdogEvent) { lock.withLock { all.append(e) } }

    var events: [WatchdogEvent] { lock.withLock { all } }

    /// The first `count` events, once there are that many, within 2 s.
    func first(_ count: Int) async throws -> [WatchdogEvent] {
        let deadline = ContinuousClock.now + .seconds(2)
        while events.count < count {
            guard ContinuousClock.now < deadline else { throw TimedOut() }
            try await Task.sleep(for: .milliseconds(5))
        }
        return Array(events.prefix(count))
    }
}

private func ibc(_ launcher: FakeLauncher) -> IBC { IBC(gateway: true, launcher: launcher.launcher) }

private func watchdog(_ launcher: FakeLauncher, _ client: IBClient, appTimeout: Duration = .seconds(60),
                      appStartupTime: Duration = .milliseconds(5), probeContract: Contract? = nil) -> Watchdog {
    Watchdog(controller: ibc(launcher), client: client, appStartupTime: appStartupTime, appTimeout: appTimeout,
             retryDelay: .milliseconds(5), probeContract: probeContract, probeTimeout: .milliseconds(300))
}

@Test func ibcArgumentsMatchIbAsync() async {
    let unix = IBC(twsVersion: 1030, gateway: true, tradingMode: "paper", ibcPath: "/opt/ibc", userID: "u", password: "p")
    #expect(unix.arguments(windows: false)
            == ["/opt/ibc/scripts/ibcstart.sh", "1030", "--gateway", "--mode=paper", "--ibc-path=/opt/ibc", "--user=u", "--pw=p"])
    let windows = IBC(twsVersion: 1030, gateway: true, tradingMode: "paper", ibcPath: "C:\\IBC", userID: "u", password: "p")
    #expect(windows.arguments(windows: true)
            == ["C:\\IBC\\scripts\\StartIBC.bat", "1030", "/Gateway", "/Mode:paper", "/IbcPath:C:\\IBC", "/User:u", "/PW:p"])
    let all = IBC(twsVersion: 1, gateway: false, tradingMode: "m", twsPath: "t", twsSettingsPath: "s", ibcPath: "i",
                  ibcIni: "c", javaPath: "j", userID: "u", password: "p", fixUserID: "fu", fixPassword: "fp",
                  on2FATimeout: "restart")
    #expect(all.arguments(windows: false) == ["i/scripts/ibcstart.sh", "1", "--mode=m", "--tws-path=t",
                                              "--tws-settings-path=s", "--ibc-path=i", "--ibc-ini=c", "--java-path=j",
                                              "--user=u", "--pw=p", "--fix-user=fu", "--fix-pw=fp",
                                              "--on2fatimeout=restart"])
    #expect(all.arguments(windows: true) == ["i\\scripts\\StartIBC.bat", "1", "/Mode:m", "/TwsPath:t", "s",
                                             "/IbcPath:i", "/Config:c", "/JavaPath:j", "/User:u", "/PW:p",
                                             "/FIXUser:fu", "/FIXPW:fp", "/On2FATimeout:restart"])
    #if os(Windows)
    #expect(IBC().ibcPath == "C:\\IBC")
    #else
    #expect(IBC().ibcPath == "/opt/ibc")
    #endif
    #expect(IBC().logLevel == .debug)
}

@Test func ibcLinesGoToTheLogHandler() async throws {
    let launcher = FakeLauncher(lines: ["IBC 3.18 starting", "  Gateway up  \r"])
    let client = IBClient()
    let seen = FakeLog()
    client.setLogHandler { level, line in seen.append(level, line) }
    let controller = ibc(launcher)
    try await controller.start(logTo: client)
    #expect(try await seen.first(2) == [FakeLog.Line(.debug, "IBC 3.18 starting"), FakeLog.Line(.debug, "Gateway up")])
    await controller.terminate()
}

@Test func ibcTerminateIsIdempotent() async throws {
    let launcher = FakeLauncher()
    let controller = ibc(launcher)
    await controller.terminate()   // not running: nothing
    try await controller.start()
    try await controller.start()   // running: nothing
    await controller.terminate()
    await controller.terminate()
    #expect(launcher.launches.count == 1)
    #expect(launcher.terminations == 1)
    try await controller.start()   // terminated: starts again
    #expect(launcher.launches.count == 2)
    await controller.terminate()
}

@Test func ibcLaunchFailureThrows() async throws {
    struct NoScript: Error {}
    let controller = IBC(launcher: { _, _ in throw NoScript() })
    await #expect(throws: NoScript.self) { try await controller.start() }
    await controller.terminate()   // nothing launched: nothing to do
}

/// The real launcher on a stand-in script: its stdout comes line by line, and terminate ends it (taskkill on Windows).
@Test func launchedProcessReadsLinesAndTerminates() async throws {
    #if os(Windows)
    let script = FileManager.default.temporaryDirectory.appendingPathComponent("ibkr-\(UUID().uuidString).bat")
    try "@echo off\r\necho hello\r\nping -n 30 127.0.0.1 >nul\r\n".write(to: script, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: script) }
    let app = try LaunchedProcess([script.path], windows: true)
    #else
    let app = try LaunchedProcess(["/bin/sh", "-c", "echo hello; exec sleep 30"], windows: false)
    #endif
    let first = try await within2s { () async -> String? in
        for await line in app.lines { return line.trimmingCharacters(in: .whitespacesAndNewlines) }
        return nil
    }
    #expect(first == "hello")
    try await within2s { await app.terminate() }
}

@Test func watchdogStartsConnectsAndStops() async throws {
    let launcher = FakeLauncher()
    let gateways = Gateways([FakeGateway()])
    let client = IBClient(connector: gateways.connector)
    let dog = watchdog(launcher, client)
    let log = await EventLog(dog)
    try await dog.start()
    #expect(try await log.first(2) == [.starting, .started])
    #expect(await client.endpoint()?.clientID == 1)
    await dog.stop()
    #expect(try await log.first(4) == [.starting, .started, .stopping, .stopped])
    #expect(launcher.launches.count == 1)
    #expect(launcher.terminations == 1)
    #expect(await client.state == .disconnected(nil))
    try await Task.sleep(for: .milliseconds(100))
    #expect(launcher.launches.count == 1)   // the loop is gone
    #expect(log.events.count == 4)
}

@Test func hardTimeoutRestartsTheApp() async throws {
    let launcher = FakeLauncher()
    let second = FakeGateway()
    second.onRequest = { $0 == ["49", "1"] ? [["49", "1", "1700000000"]] : [] }
    let gateways = Gateways([FakeGateway(), second])   // the first never answers the time probe
    let client = IBClient(connector: gateways.connector)
    let dog = watchdog(launcher, client, appTimeout: .milliseconds(100))
    let log = await EventLog(dog)
    try await dog.start()
    // P3: as ib_async, `.starting` only comes from start(); a restart round goes straight to `.started`
    #expect(try await log.first(6) == [.starting, .started, .softTimeout, .hardTimeout, .stopped, .started])
    #expect(try await log.first(7)[6] == .softTimeout)   // the second app answers: no hard timeout follows
    #expect(launcher.launches.count == 2)
    #expect(launcher.terminations == 1)
    await dog.stop()
    #expect(launcher.terminations == 2)
    #expect(!log.events.dropFirst(6).contains(.hardTimeout))
    // no idle timer, messages or states consumer outlives its round
    try await within2s {
        while await client.activeIdleTimers + client.messageSubscriberCount + client.stateSubscriberCount > 0 {
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

@Test func probeContractUsesTheHistoryProbe() async throws {
    let launcher = FakeLauncher()
    let first = FakeGateway(), second = FakeGateway()
    first.onRequest = { $0.first == "20" ? [["17", $0[1], "", "", "0"]] : [] }   // an empty batch fails the probe
    second.onRequest = { f in
        f.first == "20" ? [["17", f[1], "", "", "1", "1794321300", "1", "2", "0", "1", "5", "1", "1"]] : []
    }
    let client = IBClient(connector: Gateways([first, second]).connector)
    let dog = watchdog(launcher, client, appTimeout: .milliseconds(100), probeContract: .forex("EURUSD"))
    let log = await EventLog(dog)
    try await dog.start()
    #expect(try await log.first(6) == [.starting, .started, .softTimeout, .hardTimeout, .stopped, .started])
    let sent = try await first.waitForSent(FakeGateway.syncFrames + 1)
    let probe = sent[FakeGateway.syncFrames]
    #expect(probe.first == "20")
    #expect(Array(probe.suffix(8)) == ["", "5 secs", "30 S", "0", "MIDPOINT", "2", "0", ""])
    #expect(try await log.first(8).suffix(2) == [.softTimeout, .softTimeout])   // a bar keeps the second app up
    await dog.stop()
    #expect(!log.events.dropFirst(6).contains(.hardTimeout))
}

@Test func error1100Restarts() async throws {
    let launcher = FakeLauncher()
    let first = FakeGateway()
    let client = IBClient(connector: Gateways([first, FakeGateway()]).connector)
    let dog = watchdog(launcher, client)
    let log = await EventLog(dog)
    try await dog.start()
    #expect(try await log.first(2) == [.starting, .started])
    first.feed(ibError("-1", "1100", "Connectivity between IB and Trader Workstation has been lost."))
    #expect(try await log.first(4) == [.starting, .started, .stopped, .started])
    #expect(launcher.launches.count == 2)
    await dog.stop()
    #expect(launcher.terminations == 2)
}

@Test func disconnectRestarts() async throws {
    let launcher = FakeLauncher()
    let first = FakeGateway()
    let client = IBClient(connector: Gateways([first, FakeGateway()]).connector)
    let dog = watchdog(launcher, client)
    let log = await EventLog(dog)
    try await dog.start()
    #expect(try await log.first(2) == [.starting, .started])
    first.close()
    #expect(try await log.first(4) == [.starting, .started, .stopped, .started])
    await dog.stop()
}

@Test func startOnAConnectedClientThrows() async throws {
    let client = IBClient(connector: FakeGateway().connector)
    try await within2s { try await client.connect(clientID: 1) }
    let launcher = FakeLauncher()
    let dog = watchdog(launcher, client)
    await #expect(throws: IBClientError.alreadyConnected) { try await dog.start() }
    #expect(launcher.launches.isEmpty)
}

/// Review Focus 4: a stop while the app starts up ends the round once and starts nothing more.
@Test func stopDuringStartupTerminatesOnce() async throws {
    let launcher = FakeLauncher()
    let client = IBClient(connector: Gateways([FakeGateway(), FakeGateway()]).connector)
    let dog = watchdog(launcher, client, appStartupTime: .seconds(60))
    let log = await EventLog(dog)
    try await dog.start()
    try await launcher.waitForLaunches(1)
    await dog.stop()
    #expect(try await log.first(3) == [.starting, .stopping, .stopped])
    #expect(launcher.terminations == 1)
    try await Task.sleep(for: .milliseconds(200))
    #expect(launcher.launches.count == 1)
    #expect(log.events.count == 3)
}

/// Collects log lines.
// @unchecked Sendable: `lines` sits behind `lock`.
private final class FakeLog: @unchecked Sendable {
    struct Line: Equatable { let level: IBLogLevel, text: String; init(_ l: IBLogLevel, _ t: String) { (level, text) = (l, t) } }
    private let lock = NSLock()
    private var lines: [Line] = []
    func append(_ level: IBLogLevel, _ text: String) { lock.withLock { lines.append(Line(level, text)) } }
    func first(_ count: Int) async throws -> [Line] {
        let deadline = ContinuousClock.now + .seconds(2)
        while lock.withLock({ lines.count }) < count {
            guard ContinuousClock.now < deadline else { throw TimedOut() }
            try await Task.sleep(for: .milliseconds(5))
        }
        return lock.withLock { Array(lines.prefix(count)) }
    }
}
#endif
