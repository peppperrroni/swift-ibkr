public enum ErrorKind: Sendable { case notice, warning, orderCancelled, fatal }

extension ErrorKind {
    /// Warnings and fatals both fail the request they name; only a fatal also rejects an order.
    var failsRequest: Bool { self == .warning || self == .fatal }
}

public enum ErrorCode {
    /// An explicit table (docs/DECISIONS.md), not a range rule: 10167 is delayed data, 202 is a cancel.
    public static func kind(_ code: Int) -> ErrorKind {
        switch code {
        case 2100...2199, 10167, 399, 404, 161, 10147, 10148, 165, 1101, 1102, 317, 10090, 10091: .notice
        case 105, 321, 329, 434, 492: .warning   // ib_async's warning codes; 110 stays fatal
        case 202: .orderCancelled
        default: .fatal
        }
    }

    /// IB refused a market-data request for want of a subscription. 162 is IB's catch-all for history (pacing,
    /// cancels), so it counts only when its text says permission, or names a competing session from a different IP:
    /// IB's answer on a paper account without a data subscription even when no other session is open.
    public static func isNoMarketDataPermission(code: Int, text: String) -> Bool {
        switch code {
        case 354, 10089, 10168, 10186, 10197: true
        case 420: text.range(of: "permission", options: .caseInsensitive) != nil   // real-time bars refused
        case 162: text.range(of: "permission", options: .caseInsensitive) != nil
            || text.range(of: "different IP", options: .caseInsensitive) != nil
        case 10189: text.range(of: "permission", options: .caseInsensitive) != nil   // tick-by-tick's catch-all
        default: false
        }
    }

    /// Whether a 2152 refuses all depth: its text carries «Unknown market data permissions» and the part before it
    /// (what the login holds) names no `Depth:`. A 2152 without that phrase is not read as a refusal.
    static func grantsNoDepth(_ text: String) -> Bool {
        guard let marker = text.range(of: "Unknown market data permissions") else { return false }
        return !text[..<marker.lowerBound].contains("Depth:")
    }
}
