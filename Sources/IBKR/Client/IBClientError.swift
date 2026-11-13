/// Why a client call or stream failed.
public enum IBClientError: Error, Equatable, Sendable {
    /// A call was made while the client is not connected.
    case notConnected
    /// `connect` was called while connected, connecting or reconnecting.
    case alreadyConnected
    /// `connect` ran out of its timeout, the reconnect probe heard nothing, or an id-less one-shot heard nothing
    /// within `ConnectOptions.idlessRequestTimeout`.
    case timeout
    /// The peer closed or reset the connection, a write hit a closed transport, a newer `connect` superseded this
    /// one, or the connection's end finished the streams still open.
    case connectionClosed
    /// The socket failed; the text is the underlying error's.
    case transport(String)
    /// IB sent bytes the library could not read.
    case protocolError(IBProtocolError)
    /// The request could not be encoded.
    case encoding(IBEncodingError)
    /// IB answered the request with this error code and text.
    case ib(code: Int, text: String)
    /// A market-data request refused for want of a subscription (`ErrorCode.isNoMarketDataPermission`).
    case noMarketDataPermission(code: Int, text: String)
    /// The calling task was cancelled while `connect` or a one-shot request waited.
    case cancelled
    /// A subscription IB allows once per connection is already open.
    case alreadySubscribed
}
