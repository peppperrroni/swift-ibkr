/// How `IBClient.connect(reconnect:)` gets a dropped connection back. Only a connection that reached `.connected`
/// and then ended with an error is retried; `disconnect()` stops it.
public struct ReconnectPolicy: Sendable, Equatable {
    /// The pause before attempt n is `delays[min(n-1, count-1)]`; empty: no pause.
    public var delays: [Duration]
    /// Attempts per drop; `nil`: until `disconnect()`.
    public var maxAttempts: Int?
    /// Silence on a connected socket before a reqCurrentTime probe; as long again with no frame ends the
    /// connection with `.timeout`. `nil`: no probe.
    public var probeAfter: Duration?

    public init(delays: [Duration] = [.seconds(1), .seconds(2), .seconds(5), .seconds(10), .seconds(30)],
                maxAttempts: Int? = nil, probeAfter: Duration? = .seconds(30)) {
        self.delays = delays
        self.maxAttempts = maxAttempts
        self.probeAfter = probeAfter
    }
}
