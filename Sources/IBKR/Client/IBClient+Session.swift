import Foundation

extension IBClient {
    /// This library's version, kept equal to the podspec's `s.version` (`ib_async`'s `__version__`).
    public static let libraryVersion = "1.0.0"

    /// The traffic of the current connection so far. Throws `.notConnected` unless connected.
    public func connectionStats() throws(IBClientError) -> ConnectionStats {
        try requireConnected()
        var s = stats
        s.duration = .now - startedAt
        return s
    }

    /// Where the client connects, from `connect` on until it is disconnected; `nil` when disconnected.
    public func endpoint() -> (host: String, port: Int, clientID: Int)? {
        if case .disconnected = state { return nil }
        return (address.host, address.port, clientID)
    }

    /// A fresh stream on every call, of the idle time each time `after` passes with no incoming frame while connected
    /// (`ib_async`'s `setTimeout` and `timeoutEvent`); it fires once, and the next frame arms it again. The connection
    /// is left alone. Stopping the stream stops its timer.
    public func idleTimeouts(after: Duration) -> AsyncStream<Duration> {
        let (stream, out) = AsyncStream.makeStream(of: Duration.self)
        let timer = Task.detached { [weak self] in
            var reported: ContinuousClock.Instant?   // the last frame already reported idle
            while !Task.isCancelled {
                guard let (connected, last) = await self?.idleClock() else { break }
                var wake = ContinuousClock.now + after
                if connected, last != reported {
                    let idle = ContinuousClock.now - last
                    if idle >= after { out.yield(idle); reported = last } else { wake = last + after }
                }
                try? await Task.sleep(until: wake)
            }
            out.finish()
        }
        out.onTermination = { _ in timer.cancel() }
        return stream
    }

    /// Whether connected, and when the last chunk came in.
    private func idleClock() -> (Bool, ContinuousClock.Instant) {
        if case .connected = state { (true, lastFrame) } else { (false, lastFrame) }
    }

    /// A fresh stream on every call: the current state first, then `true` when the writer starts waiting on the
    /// throttle and `false` when everything queued is written (`ib_async`'s `throttleStart` and `throttleEnd`).
    public func throttling() -> AsyncStream<Bool> {
        throttleSubscribers.stream(first: isThrottling) { [weak self] id in
            Task { await self?.unsubscribe(throttling: id) }
        }
    }

    /// Sends the client's log lines to `handler`, or to nowhere for `nil` (the default; nothing is formatted then).
    /// `.debug`: every frame, `>>> ` out (at queueing) and `<<< ` in, fields joined by `|`. `.info`: state changes,
    /// `placeOrder`, `modifyOrder`, `cancelOrder` (`"placeOrder 12: BUY 1 AAPL LMT 180"`) and fills. `.warning`:
    /// IB's warning codes. `.error`: IB's fatal errors and sync requests given up under
    /// `ConnectOptions.throwsOnSyncError` `false`. The handler runs synchronously, on the client's actor for its
    /// own lines. Works without an actor hop.
    public nonisolated func setLogHandler(_ handler: IBLogHandler?) { logBox.handler = handler }

    /// Writes one line to the log handler; `text` is built only when one is set.
    nonisolated func log(_ level: IBLogLevel, _ text: @autoclosure () -> String) {
        if let handler = logBox.handler { handler(level, text()) }
    }
}
