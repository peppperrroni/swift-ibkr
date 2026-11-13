import Foundation

extension IBClient {
    /// IB's history of `contract` kept up to date (keepUpToDate, `end` empty, as IB requires), folded as `ib_async`'s
    /// `BarDataList` is: the first batch with `hasNewBar` `true`, then the whole list after each update that changes
    /// it (`BarList.apply`). IB's 10225 (bust event) cancels and resends the same request under the same reqId and the
    /// stream goes on; the batch IB answers the resend with is ignored, as `ib_async` drops it. Ends like
    /// `historicalBars`; stopping it sends the cancel. While open it is listed by `liveBarSubscriptions()` and each
    /// change goes to `barUpdates()`. `whatToShow` "SCHEDULE" is refused; `options` are IB's chart options.
    public func liveHistoricalBars(
        _ contract: Contract, duration: String, barSize: String, whatToShow: String = "TRADES", rth: Bool = true,
        options: [TagValue] = []
    ) throws(IBClientError) -> AsyncThrowingStream<BarList, any Error> {
        try requireConnected()
        if whatToShow == "SCHEDULE" { throw .encoding(.unsupported("whatToShow SCHEDULE")) }
        let id = nextRequestID()
        var started = false
        let stream = try openStream(.historicalData(requestID: id, contract: contract, end: nil, barSize: barSize,
                                                    duration: duration, rth: rth, whatToShow: whatToShow,
                                                    keepUpToDate: true, options: options),
                                    id: id, cancel: .cancelHistoricalData(requestID: id), resendOn: 10225) {
            (message, out: AsyncThrowingStream<BarList, any Error>.Continuation) in
            switch message {
            case .historicalData(_, let bars) where !started:
                started = true
                self.liveBars[id]?.bars = bars
                self.liveBars[id]?.hasNewBar = true
                out.yield(BarList(bars: bars, hasNewBar: true))
            case .historicalDataUpdate(_, let bar) where started:   // ib_async drops an update before the batch
                if let list = self.foldLiveBar(id, bar) { out.yield(list) }
            default: break
            }
            return false
        }
        liveBars[id] = LiveBars(requestID: id, contract: contract, barSize: barSize, whatToShow: whatToShow, bars: [],
                                hasNewBar: false)
        return stream
    }

    /// The open `realTimeBars` and `liveHistoricalBars` subscriptions with their bars so far, by request id
    /// (`ib_async`'s `realtimeBars()`). A subscription leaves when its stream ends, however it ends.
    public func liveBarSubscriptions() -> [LiveBars] {
        liveBars.values.sorted { $0.requestID < $1.requestID }
    }

    /// A fresh stream on every call, of every change of any live bar subscription from now on (`ib_async`'s
    /// `barUpdateEvent`): each real-time bar, and each `liveHistoricalBars` update that changes its list, but not the
    /// first batch. Unbounded, like `messages()`.
    public func barUpdates() -> AsyncStream<LiveBars> {
        barUpdateSubscribers.stream { [weak self] id in Task { await self?.unsubscribe(barUpdate: id) } }
    }

    /// Folds `bar` into live subscription `id`, by `BarList.apply` or, with `append`, as a new bar (real-time bars,
    /// as `ib_async` appends them), and publishes the change on `barUpdates()`. `nil` when nothing changed.
    /// shortcut: copies the bar list once per update (O(bars)), as the bar builders do; keep the bars in a class if a
    /// day of 5-second bars ever shows up in a profile.
    func foldLiveBar(_ id: Int, _ bar: Bar, append: Bool = false) -> BarList? {
        guard var live = liveBars[id] else { return nil }
        var list = BarList(bars: live.bars, hasNewBar: live.hasNewBar)
        if append { list.bars.append(bar); list.hasNewBar = true } else if !list.apply(bar) { return nil }
        (live.bars, live.hasNewBar) = (list.bars, list.hasNewBar)
        liveBars[id] = live
        barUpdateSubscribers.yield(live)
        return list
    }

    func unsubscribe(barUpdate id: Int) { barUpdateSubscribers.remove(id) }
}
