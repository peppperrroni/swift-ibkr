/// How much detail IB Gateway writes to its own log (`setServerLogLevel`).
public enum ServerLogLevel: Int, Sendable {
    /// IB's level 1.
    case system = 1
    /// IB's level 2.
    case error
    /// IB's level 3.
    case warning
    /// IB's level 4.
    case information
    /// IB's level 5, the most detail.
    case detail
}
