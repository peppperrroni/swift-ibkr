import Foundation

/// One trading session of a `HistoricalSchedule`; the times are IB's `yyyyMMdd-HH:mm:ss` text in the schedule's zone.
public struct HistoricalSession: Sendable, Equatable, Encodable {
    /// The session's start, `yyyyMMdd-HH:mm:ss`.
    public var startDateTime: String
    /// The session's end, `yyyyMMdd-HH:mm:ss`.
    public var endDateTime: String
    /// The trading day the session belongs to, `yyyyMMdd`.
    public var refDate: String

    /// Creates a session with every field given.
    public init(startDateTime: String, endDateTime: String, refDate: String) {
        self.startDateTime = startDateTime
        self.endDateTime = endDateTime
        self.refDate = refDate
    }
}

/// A contract's trading sessions over a span (historicalSchedule), as IB sends them: text, not `Date`s.
public struct HistoricalSchedule: Sendable, Equatable, Encodable {
    /// The schedule's start, `yyyyMMdd-HH:mm:ss`.
    public var startDateTime: String
    /// The schedule's end, `yyyyMMdd-HH:mm:ss`.
    public var endDateTime: String
    /// The time zone of the session times.
    public var timeZone: String
    /// The trading sessions in the span.
    public var sessions: [HistoricalSession]

    /// Creates a schedule with every field given.
    public init(startDateTime: String, endDateTime: String, timeZone: String, sessions: [HistoricalSession]) {
        self.startDateTime = startDateTime
        self.endDateTime = endDateTime
        self.timeZone = timeZone
        self.sessions = sessions
    }
}

extension BarList {
    /// Folds one keepUpToDate update in, as `ib_async`'s historicalDataUpdate (wrapper.py:923-942): a bar older than
    /// the last is dropped; a later one (or the first) is appended with `hasNewBar` `true`; one at the last bar's time
    /// replaces it with `hasNewBar` `false`, unless it is identical. Returns whether the list changed.
    public mutating func apply(_ bar: Bar) -> Bool {
        if let last = bars.last {
            if bar.time < last.time || bar == last { return false }
            if bar.time == last.time {
                bars[bars.count - 1] = bar
                hasNewBar = false
                return true
            }
        }
        bars.append(bar)
        hasNewBar = true
        return true
    }
}

/// One live bar subscription, `ib_async`'s `RealTimeBarList` or keepUpToDate `BarDataList`, as
/// `IBClient.liveBarSubscriptions()` and `IBClient.barUpdates()` report it.
public struct LiveBars: Sendable, Equatable, Encodable {
    /// The subscription's request id.
    public var requestID: Int
    /// The contract the bars are for.
    public var contract: Contract
    /// IB's bar size: `"5 secs"` for `realTimeBars`, the requested one (`"5 mins"`) for `liveHistoricalBars`.
    public var barSize: String
    /// What the bars show: `"TRADES"`, `"MIDPOINT"`, ...
    public var whatToShow: String
    /// Every bar so far, oldest first; it grows for as long as the subscription runs, as in `ib_async`.
    public var bars: [Bar]
    /// `true` when the last change added a bar, `false` when it replaced the forming one (or nothing came yet).
    public var hasNewBar: Bool

    /// Creates a subscription record with every field given.
    public init(requestID: Int, contract: Contract, barSize: String, whatToShow: String, bars: [Bar],
                hasNewBar: Bool) {
        self.requestID = requestID
        self.contract = contract
        self.barSize = barSize
        self.whatToShow = whatToShow
        self.bars = bars
        self.hasNewBar = hasNewBar
    }
}

/// One price bucket of a histogram (histogramData 89): how many trades happened at `price` over the requested period.
public struct HistogramData: Sendable, Equatable, Encodable {
    /// The bucket's price.
    public var price: Decimal
    /// The number of trades at `price`.
    public var count: Int

    /// Creates a bucket with every field given.
    public init(price: Decimal, count: Int) {
        self.price = price
        self.count = count
    }
}
