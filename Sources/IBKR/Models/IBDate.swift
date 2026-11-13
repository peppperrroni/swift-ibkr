import Foundation

/// IB's date text, read and written as `ib_async`'s `util.formatIBDatetime` and `parseIBDatetime`. Locale and
/// time zones are fixed, so results do not depend on the machine.
public enum IBDate {
    /// `yyyyMMdd HH:mm:ss UTC`.
    public static func format(_ date: Date) -> String { newsFormat.string(from: date) }

    /// Reads `yyyyMMdd` (that day's start in `timeZone`), epoch seconds, `yyyyMMdd HH:mm:ss Zone` (in the zone
    /// named), and `yyyyMMdd  HH:mm:ss` or `yyyy-MM-dd HH:mm:ss.0` (in `timeZone`); anything else is `nil`.
    public static func parse(_ text: String, timeZone: TimeZone = TimeZone(identifier: "UTC")!) -> Date? {
        let s = Array(text.utf8)
        if s.count == 8 { return instant(s, [0, 4, 6], [4, 2, 2], in: timeZone) }
        if !s.isEmpty, s.allSatisfy({ $0 >= 48 && $0 <= 57 }) { return Int(text).map { Date(timeIntervalSince1970: Double($0)) } }
        if s.filter({ $0 == 32 }).count >= 2 && !text.contains("  ") {   // 20221125 10:00:00 Europe/Amsterdam
            let parts = text.split(separator: " ", maxSplits: 2).map(String.init)
            guard parts.count == 3, let zone = TimeZone(identifier: parts[2]) else { return nil }
            return dateTime(parts[0] + parts[1], zone)
        }
        return dateTime(text.filter { $0 != " " && $0 != "-" }, timeZone)
    }

    /// The first 16 characters read as `yyyyMMddHH:mm:ss` in `zone`.
    private static func dateTime(_ text: String, _ zone: TimeZone) -> Date? {
        let compact = Array(String(text.prefix(16)).utf8)
        return compact.count == 16 && compact[10] == 58 && compact[13] == 58
            ? instant(compact, [0, 4, 6, 8, 11, 14], [4, 2, 2, 2, 2, 2], in: zone) : nil
    }

    /// The instant of the digit runs of `s` (at `starts`, `lengths` long) as year, month, day, then hour, minute and
    /// second when given, in `zone`; `nil` for a non-digit or a date that does not exist.
    static func instant(_ s: [UInt8], _ starts: [Int], _ lengths: [Int], in zone: TimeZone) -> Date? {
        var v: [Int] = []
        for (i, n) in zip(starts, lengths) {
            let run = s[i..<(i + n)]
            guard run.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
            v.append(run.reduce(0) { $0 * 10 + Int($1 - 48) })
        }
        return instant(year: v[0], month: v[1], day: v[2], hour: v.count > 3 ? v[3] : 0,
                       minute: v.count > 4 ? v[4] : 0, second: v.count > 5 ? v[5] : 0, in: zone)
    }

    static func instant(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int, in zone: TimeZone) -> Date? {
        guard hour < 24, minute < 60, second < 60 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let date = calendar.date(from: parts) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)   // Feb 30 rolls over: refuse it
        return back.year == year && back.month == month && back.day == day ? date : nil
    }

    /// The news date text, `yyyyMMdd HH:mm:ss UTC`. Never mutated after creation.
    static let newsFormat: DateFormatter = formatter("yyyyMMdd HH:mm:ss 'UTC'")

    /// The history end text, `yyyyMMdd-HH:mm:ss` in UTC. Never mutated after creation.
    static let endFormat: DateFormatter = formatter("yyyyMMdd-HH:mm:ss")

    private static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = pattern
        return f
    }
}
