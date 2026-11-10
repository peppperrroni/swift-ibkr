public enum ErrorKind: Sendable { case notice, orderCancelled, fatal }

public enum ErrorCode {
    /// An explicit table (docs/DECISIONS.md), not a range rule: 10167 is delayed data, 202 is a cancel.
    public static func kind(_ code: Int) -> ErrorKind {
        switch code {
        case 2100...2199, 10167, 399, 404, 161, 10147, 10148, 165, 1101, 1102: .notice
        case 202: .orderCancelled
        default: .fatal
        }
    }
}
