import Foundation

/// One trading session of a `HistoricalSchedule`; the times are IB's `yyyyMMdd-HH:mm:ss` text in the schedule's zone.
public struct HistoricalSession: Sendable, Equatable {
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
public struct HistoricalSchedule: Sendable, Equatable {
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

/// One price bucket of a histogram (histogramData 89): how many trades happened at `price` over the requested period.
public struct HistogramData: Sendable, Equatable {
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
