import Foundation

/// One trading or liquid session of a contract (`ib_async`'s `TradingSession`).
public struct TradingSession: Sendable, Equatable, Encodable {
    /// When the session opens.
    public var start: Date
    /// When the session closes.
    public var end: Date

    /// Creates a session from its two instants.
    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

extension ContractDetails {
    /// `tradingHours` as sessions, read in `timeZoneID`; `CLOSED` days are left out, and an unknown zone gives `[]`.
    public var tradingSessions: [TradingSession] { Self.sessions(tradingHours, timeZoneID) }

    /// `liquidHours` as sessions, read in `timeZoneID`; `CLOSED` days are left out, and an unknown zone gives `[]`.
    public var liquidSessions: [TradingSession] { Self.sessions(liquidHours, timeZoneID) }

    private static func sessions(_ text: String, _ zoneID: String) -> [TradingSession] {
        guard let zone = TimeZone(identifier: zoneID) else { return [] }
        return text.split(separator: ";").compactMap { part in
            let ends = part.split(separator: "-").map { instant(Array($0.utf8), zone) }
            guard !part.contains("CLOSED"), ends.count == 2, let start = ends[0], let end = ends[1] else { return nil }
            return TradingSession(start: start, end: end)
        }
    }

    /// `yyyyMMdd:HHmm` in `zone`.
    private static func instant(_ s: [UInt8], _ zone: TimeZone) -> Date? {
        s.count == 13 && s[8] == 58 ? IBDate.instant(s, [0, 4, 6, 9, 11], [4, 2, 2, 2, 2], in: zone) : nil
    }
}
