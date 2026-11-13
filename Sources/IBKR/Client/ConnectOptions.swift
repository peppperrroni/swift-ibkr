import Foundation

/// `ib_async`'s connect options in one value, passed as `connect(…, options:)` and reused by every reconnect
/// attempt.
public struct ConnectOptions: Sendable, Equatable, Encodable {
    /// Skips the open and completed orders in the sync (`ib_async`'s `readonly`), for a read-only API login.
    public var readOnly: Bool
    /// The account whose reqAccountUpdates (portfolio and values) the sync sends; `nil` is the only account when
    /// there is one, and none when there are several. One that is not ASCII fails `connect` with `.encoding`.
    public var account: String?
    /// Which sync requests `connect` sends (`ib_async`'s `fetchFields`).
    public var fetch: StartupFetch
    /// With more managed accounts than this, the sync sends no per-account reqAccountUpdatesMulti
    /// (`ib_async`'s `MaxSyncedSubAccounts`).
    public var maxSyncedSubAccounts: Int
    /// `true`: a sync request that fails or is still due at the deadline fails `connect`. `false`: it is logged at
    /// `.error` and `connect` succeeds without it (`ib_async`'s `raiseSyncErrors`, whose default is `false`).
    public var throwsOnSyncError: Bool
    /// At most this many requests leave per `requestsInterval`; 0 turns the throttle off.
    public var maxRequests: Int
    /// The throttle's sliding window.
    public var requestsInterval: Duration
    /// Appended to the handshake's version range after one space, e.g. `"+PACEAPI"`; `""` for none.
    public var connectOptions: String
    /// startApi's optional capabilities field.
    public var optionalCapabilities: String
    /// How long an id-less one-shot (`currentTime()`, `faData(_:)`, `fetchOpenOrders()`, ...) waits for its answer
    /// before it throws `.timeout`; `nil` waits without bound. IB cannot address an error to these requests, so any
    /// fatal or warning error with reqId -1 also ends every one waiting, and an answer that comes after its waiter
    /// gave up goes to the next call of the same kind.
    public var idlessRequestTimeout: Duration?
    /// The zone of an `Execution.time` that names none (IB's live format); `nil` reads it as UTC (`ib_async`'s
    /// `TimezoneTWS`, whose default is the local zone).
    public var gatewayTimeZone: TimeZone?

    /// Creates options; every default is today's behaviour.
    public init(readOnly: Bool = false, account: String? = nil, fetch: StartupFetch = .all,
                maxSyncedSubAccounts: Int = 50, throwsOnSyncError: Bool = true, maxRequests: Int = 45,
                requestsInterval: Duration = .seconds(1), connectOptions: String = "",
                optionalCapabilities: String = "", idlessRequestTimeout: Duration? = .seconds(10),
                gatewayTimeZone: TimeZone? = nil) {
        self.readOnly = readOnly
        self.account = account
        self.fetch = fetch
        self.maxSyncedSubAccounts = maxSyncedSubAccounts
        self.throwsOnSyncError = throwsOnSyncError
        self.maxRequests = maxRequests
        self.requestsInterval = requestsInterval
        self.connectOptions = connectOptions
        self.optionalCapabilities = optionalCapabilities
        self.idlessRequestTimeout = idlessRequestTimeout
        self.gatewayTimeZone = gatewayTimeZone
    }
}

/// The requests the connect-time sync may send (`ib_async`'s `StartupFetch`).
public struct StartupFetch: OptionSet, Sendable, Encodable {
    /// The bit set.
    public let rawValue: Int
    /// Creates a set from its bits.
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// reqPositions.
    public static let positions = StartupFetch(rawValue: 1 << 0)
    /// reqAllOpenOrders.
    public static let ordersOpen = StartupFetch(rawValue: 1 << 1)
    /// reqCompletedOrders.
    public static let ordersComplete = StartupFetch(rawValue: 1 << 2)
    /// reqAccountUpdates for `ConnectOptions.account`.
    public static let accountUpdates = StartupFetch(rawValue: 1 << 3)
    /// reqAccountUpdatesMulti per account: with several, or for a single account whose reqAccountUpdates is left out.
    public static let subAccountUpdates = StartupFetch(rawValue: 1 << 4)
    /// reqExecutions.
    public static let executions = StartupFetch(rawValue: 1 << 5)
    /// Every request.
    public static let all: StartupFetch = [.positions, .ordersOpen, .ordersComplete, .accountUpdates,
                                           .subAccountUpdates, .executions]
    /// No request: `connect` returns after the handshake. Where a `StartupFetch?` is expected, `.none` means
    /// `Optional.none`: write `StartupFetch.none` or `[]`.
    public static let none: StartupFetch = []
}

/// Traffic counts of the current connection (`ib_async`'s `ConnectionStats`). Both hellos count as messages.
public struct ConnectionStats: Sendable, Equatable, Encodable, CustomStringConvertible {
    /// When the connection started.
    public var startTime: Date
    /// How long it has been up.
    public var duration: Duration
    /// Bytes read from the socket.
    public var bytesReceived: Int
    /// Bytes written to the socket.
    public var bytesSent: Int
    /// Frames received.
    public var messagesReceived: Int
    /// Frames written.
    public var messagesSent: Int

    /// Creates stats with every field given.
    public init(startTime: Date, duration: Duration, bytesReceived: Int, bytesSent: Int, messagesReceived: Int,
                messagesSent: Int) {
        self.startTime = startTime
        self.duration = duration
        self.bytesReceived = bytesReceived
        self.bytesSent = bytesSent
        self.messagesReceived = messagesReceived
        self.messagesSent = messagesSent
    }

    /// `"1.23 kB sent in 45 messages, 6.78 MB received in 1200 messages, session 12.3 s"`, as `ib_async` logs it.
    public var description: String {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return "\(formatSI(bytesSent))B sent in \(messagesSent) messages, "
            + "\(formatSI(bytesReceived))B received in \(messagesReceived) messages, session \(formatSI(seconds))s"
    }
}

/// How much a log line matters.
public enum IBLogLevel: Int, Sendable, Comparable, Encodable {
    /// Every frame each way, `>>> ` out and `<<< ` in, fields joined by `|`.
    case debug
    /// Connection state changes, placed, modified and cancelled orders, and fills.
    case info
    /// IB's warning codes.
    case warning
    /// IB's fatal errors, and sync requests given up under `throwsOnSyncError = false`.
    case error

    /// Orders by severity.
    public static func < (a: IBLogLevel, b: IBLogLevel) -> Bool { a.rawValue < b.rawValue }
}

/// Receives the client's log lines. It runs synchronously where the line is written, on the client's actor or
/// its caller, so it must be quick.
public typealias IBLogHandler = @Sendable (IBLogLevel, String) -> Void

/// The log handler, readable without an actor hop.
final class LogBox: @unchecked Sendable {   // `handler` sits behind `lock`
    private let lock = NSLock()
    private var _handler: IBLogHandler?
    var handler: IBLogHandler? {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }
}

/// `n` with three significant digits and an SI prefix, as `ib_async`'s `util.formatSI`: an integer below 1000 as
/// is (`"999 "`).
func formatSI(_ n: Int) -> String {
    n < 0 ? "-" + formatSI(-n) : n < 1000 ? "\(n) " : formatSI(Double(n))
}

/// `n` with three significant digits and an SI prefix (`0.5` is `"500 m"`); below 1e-22, `"0.00 "`.
func formatSI(_ n: Double) -> String {
    if n < 0 { return "-" + formatSI(-n) }
    if n < 1e-22 { return "0.00 " }
    let log = Int((log10(n)).rounded(.down))
    var i = Int((Double(log) / 3).rounded(.down)), j = log - 3 * i   // Python's floor divmod
    var value = ""
    for _ in 0..<2 {
        value = String(format: "%.\(2 - j)f", n * pow(10, Double(-3 * i)))
        if value != "1000" { break }
        (i, j) = (i + 1, 0)
    }
    let prefixes = Array("yzafpnum kMGTPEZY")
    return value + " " + (i != 0 ? String(prefixes[i + 8]) : "")
}
