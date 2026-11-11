public enum IBClientError: Error, Equatable, Sendable {
    case notConnected, alreadyConnected, timeout, connectionClosed
    case transport(String)
    case protocolError(IBProtocolError)
    case encoding(IBEncodingError)
    case ib(code: Int, text: String)
    /// The calling task was cancelled while a one-shot request waited.
    case cancelled
}
