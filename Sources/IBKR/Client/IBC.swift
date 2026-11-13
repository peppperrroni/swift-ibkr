#if os(macOS) || os(Linux) || os(Windows)
import Foundation

#if os(Windows)
private let onWindows = true
#else
private let onWindows = false
#endif

/// A started TWS or IB Gateway (through IBC): its stdout, one line per element, and a way to stop it.
protocol LaunchedApp: Sendable {
    var lines: AsyncStream<String> { get }
    func terminate() async
}

/// Starts IBC's script with `arguments` (the script first); `windows` picks `cmd.exe /c` and `taskkill`.
typealias AppLauncher = @Sendable (_ arguments: [String], _ windows: Bool) throws -> any LaunchedApp

/// Starts and stops TWS or IB Gateway through an IBC install (https://github.com/IbcAlpha/IBC), as `ib_async`'s
/// `IBC`: each non-empty field becomes an argument of `ibcstart.sh`, or of `StartIBC.bat` on Windows. macOS, Linux
/// and Windows only. The command line holds `password` and `fixPassword`, so other local users can read them in
/// the process list, as with `ib_async`; IBC's own config file (`ibcIni`) keeps them off it.
public actor IBC {
    /// The major version of TWS or the Gateway to start (`1030`); 0 leaves it out.
    public nonisolated let twsVersion: Int
    /// Starts IB Gateway instead of TWS.
    public nonisolated let gateway: Bool
    /// `"live"` or `"paper"`; empty leaves IBC's config to decide.
    public nonisolated let tradingMode: String
    /// Where TWS or the Gateway is installed; empty for IBC's default.
    public nonisolated let twsPath: String
    /// Where TWS or the Gateway keeps its settings; empty for IBC's default. On Windows it goes on the command line
    /// as a bare value, as `ib_async` passes it.
    public nonisolated let twsSettingsPath: String
    /// Where IBC is installed: `/opt/ibc`, or `C:\IBC` on Windows, when given empty.
    public nonisolated let ibcPath: String
    /// IBC's config file; empty for IBC's default.
    public nonisolated let ibcIni: String
    /// The Java to run; empty for the one bundled with TWS or the Gateway.
    public nonisolated let javaPath: String
    /// The IB user name; empty to take it from IBC's config.
    public nonisolated let userID: String
    /// The IB password; empty to take it from IBC's config. It goes on the command line.
    public nonisolated let password: String
    /// The FIX user name; empty for none.
    public nonisolated let fixUserID: String
    /// The FIX password; empty for none. It goes on the command line.
    public nonisolated let fixPassword: String
    /// What IBC does when two-factor authentication times out (`"restart"` or `"exit"`); empty for IBC's default.
    public nonisolated let on2FATimeout: String
    /// The level at which IBC's stdout lines reach the log handler (`ib_async`'s `IbcLogLevel`).
    public nonisolated let logLevel: IBLogLevel

    private nonisolated let launcher: AppLauncher
    private var app: (any LaunchedApp)?
    private var monitor: Task<Void, Never>?

    /// Keeps the options; nothing starts until `start(logTo:)`.
    public init(twsVersion: Int = 0, gateway: Bool = false, tradingMode: String = "", twsPath: String = "",
                twsSettingsPath: String = "", ibcPath: String = "", ibcIni: String = "", javaPath: String = "",
                userID: String = "", password: String = "", fixUserID: String = "", fixPassword: String = "",
                on2FATimeout: String = "", logLevel: IBLogLevel = .debug) {
        self.init(twsVersion: twsVersion, gateway: gateway, tradingMode: tradingMode, twsPath: twsPath,
                  twsSettingsPath: twsSettingsPath, ibcPath: ibcPath, ibcIni: ibcIni, javaPath: javaPath,
                  userID: userID, password: password, fixUserID: fixUserID, fixPassword: fixPassword,
                  on2FATimeout: on2FATimeout, logLevel: logLevel, launcher: { try LaunchedProcess($0, windows: $1) })
    }

    init(twsVersion: Int = 0, gateway: Bool = false, tradingMode: String = "", twsPath: String = "",
         twsSettingsPath: String = "", ibcPath: String = "", ibcIni: String = "", javaPath: String = "",
         userID: String = "", password: String = "", fixUserID: String = "", fixPassword: String = "",
         on2FATimeout: String = "", logLevel: IBLogLevel = .debug, launcher: @escaping AppLauncher) {
        (self.twsVersion, self.gateway, self.tradingMode, self.twsPath) = (twsVersion, gateway, tradingMode, twsPath)
        (self.twsSettingsPath, self.ibcIni, self.javaPath) = (twsSettingsPath, ibcIni, javaPath)
        self.ibcPath = !ibcPath.isEmpty ? ibcPath : onWindows ? "C:\\IBC" : "/opt/ibc"
        (self.userID, self.password, self.fixUserID, self.fixPassword) = (userID, password, fixUserID, fixPassword)
        (self.on2FATimeout, self.logLevel, self.launcher) = (on2FATimeout, logLevel, launcher)
    }

    /// The command line, script first, in `ib_async`'s order (ibcontroller.py:129-160).
    nonisolated func arguments(windows: Bool) -> [String] {
        var a = [windows ? ibcPath + "\\scripts\\StartIBC.bat" : ibcPath + "/scripts/ibcstart.sh"]
        if twsVersion != 0 { a.append(String(twsVersion)) }
        if gateway { a.append(windows ? "/Gateway" : "--gateway") }
        let options = [(tradingMode, "--mode=", "/Mode:"), (twsPath, "--tws-path=", "/TwsPath:"),
                       (twsSettingsPath, "--tws-settings-path=", ""), (ibcPath, "--ibc-path=", "/IbcPath:"),
                       (ibcIni, "--ibc-ini=", "/Config:"), (javaPath, "--java-path=", "/JavaPath:"),
                       (userID, "--user=", "/User:"), (password, "--pw=", "/PW:"),
                       (fixUserID, "--fix-user=", "/FIXUser:"), (fixPassword, "--fix-pw=", "/FIXPW:"),
                       (on2FATimeout, "--on2fatimeout=", "/On2FATimeout:")]
        for (value, unix, win) in options where !value.isEmpty { a.append((windows ? win : unix) + value) }
        return a
    }

    /// Starts IBC, which starts TWS or the Gateway; does nothing while it runs. Each stdout line goes to `client`'s
    /// log handler at `logLevel`. Throws when the script cannot be started.
    public func start(logTo client: IBClient? = nil) async throws {
        guard app == nil else { return }
        let launched = try launcher(arguments(windows: onWindows), onWindows)
        app = launched
        let level = logLevel
        monitor = Task {
            for await line in launched.lines {
                client?.log(level, line.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    /// Stops what `start(logTo:)` started and waits for it to exit: `taskkill /F /T /PID` on Windows (the whole
    /// process tree), SIGTERM elsewhere. Does nothing when it is not running.
    public func terminate() async {
        guard let app else { return }
        self.app = nil   // before the wait, so a second call does nothing
        monitor?.cancel()
        monitor = nil
        await app.terminate()
    }
}

/// Carries a value to the one thread that uses it.
private struct Handoff<T>: @unchecked Sendable { let value: T }

/// IBC's script run by Foundation's `Process`, its stdout read on a thread of its own.
// @unchecked Sendable: `Process` is only asked for its pid, its state and to terminate, which it allows from any thread.
final class LaunchedProcess: LaunchedApp, @unchecked Sendable {
    let lines: AsyncStream<String>
    private let process = Process()
    private let exited: AsyncStream<Void>
    private let windows: Bool

    init(_ arguments: [String], windows: Bool) throws {
        self.windows = windows
        if windows {   // a .bat runs through the command interpreter
            let comSpec = ProcessInfo.processInfo.environment["ComSpec"] ?? "C:\\Windows\\System32\\cmd.exe"
            process.executableURL = URL(fileURLWithPath: comSpec)
            process.arguments = ["/c"] + arguments
        } else {
            process.executableURL = URL(fileURLWithPath: arguments[0])
            process.arguments = Array(arguments.dropFirst())
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        let (exited, done) = AsyncStream.makeStream(of: Void.self)
        self.exited = exited
        process.terminationHandler = { _ in done.finish() }
        let (lines, out) = AsyncStream.makeStream(of: String.self)
        self.lines = lines
        try process.run()
        let reader = Handoff(value: pipe.fileHandleForReading)   // FileHandle's Sendable varies by Foundation
        Thread.detachNewThread {
            let handle = reader.value
            var buffer = Data()
            while case let chunk = handle.availableData, !chunk.isEmpty {   // empty: end of file
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 10) {
                    out.yield(String(decoding: buffer[..<newline], as: UTF8.self))
                    buffer.removeSubrange(...newline)
                }
            }
            if !buffer.isEmpty { out.yield(String(decoding: buffer, as: UTF8.self)) }
            out.finish()
        }
    }

    func terminate() async {
        if windows {   // ib_async's `taskkill /F /T`: the .bat's Java child goes too
            let kill = Process()
            let root = ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:\\Windows"
            kill.executableURL = URL(fileURLWithPath: root + "\\System32\\taskkill.exe")
            kill.arguments = ["/F", "/T", "/PID", String(process.processIdentifier)]
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                kill.terminationHandler = { _ in done.resume() }
                do { try kill.run() } catch { kill.terminationHandler = nil; done.resume() }
            }
        } else if process.isRunning {
            process.terminate()
        }
        for await _ in exited {}
    }
}
#endif
