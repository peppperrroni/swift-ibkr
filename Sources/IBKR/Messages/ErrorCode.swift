public enum ErrorKind: Sendable { case notice, orderCancelled, fatal }

public enum ErrorCode {
    /// An explicit table (docs/DECISIONS.md), not a range rule: 10167 is delayed data, 202 is a cancel.
    public static func kind(_ code: Int) -> ErrorKind {
        switch code {
        case 2100...2199, 10167, 399, 404, 161, 10147, 10148, 165, 1101, 1102, 317, 10090, 10091: .notice
        case 202: .orderCancelled
        default: .fatal
        }
    }

    /// IB refused a market-data request for want of a subscription. 162 is IB's catch-all for history (pacing,
    /// cancels), so it counts only when its text says permission.
    public static func isNoMarketDataPermission(code: Int, text: String) -> Bool {
        switch code {
        case 354, 10089, 10168, 10186, 10197: true
        case 162: text.localizedCaseInsensitiveContains("permission")
        default: false
        }
    }
}
