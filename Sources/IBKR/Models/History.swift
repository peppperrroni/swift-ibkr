import Foundation

/// One trading session of a `HistoricalSchedule`; the times are IB's `yyyyMMdd-HH:mm:ss` text in the schedule's zone.
public struct HistoricalSession: Sendable, Equatable {
    public var startDateTime: String
    public var endDateTime: String
    public var refDate: String

    public init(startDateTime: String, endDateTime: String, refDate: String) {
        self.startDateTime = startDateTime
        self.endDateTime = endDateTime
        self.refDate = refDate
    }
}

/// A contract's trading sessions over a span (historicalSchedule), as IB sends them: text, not `Date`s.
public struct HistoricalSchedule: Sendable, Equatable {
    public var startDateTime: String
    public var endDateTime: String
    public var timeZone: String
    public var sessions: [HistoricalSession]

    public init(startDateTime: String, endDateTime: String, timeZone: String, sessions: [HistoricalSession]) {
        self.startDateTime = startDateTime
        self.endDateTime = endDateTime
        self.timeZone = timeZone
        self.sessions = sessions
    }
}

/// One price bucket of a histogram: how many trades happened at `price` over the requested period.
public struct HistogramData: Sendable, Equatable {
    public var price: Decimal
    public var count: Int

    public init(price: Decimal, count: Int) {
        self.price = price
        self.count = count
    }
}
