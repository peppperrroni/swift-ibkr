public enum IBClientError: Error, Equatable, Sendable {
    case notConnected, alreadyConnected, timeout, connectionClosed
    case transport(String)
    case protocolError(IBProtocolError)
    case encoding(IBEncodingError)
    case ib(code: Int, text: String)
    /// A market-data request refused for want of a subscription (`ErrorCode.isNoMarketDataPermission`).
    case noMarketDataPermission(code: Int, text: String)
    /// The calling task was cancelled while `connect` or a one-shot request waited.
    case cancelled
    /// A subscription IB allows once per connection is already open.
    case alreadySubscribed
}
