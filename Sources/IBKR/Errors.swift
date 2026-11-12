/// IB sent bytes the library cannot read.
public enum IBProtocolError: Error, Equatable, Sendable {
    /// A frame announced a length above 0xFFFFFF bytes.
    case frameTooLong(Int)
    /// A message ended before the field at this index.
    case missingField(index: Int)
    /// The text is not a number, or a count or code is out of range, at this field index.
    case badNumber(String, index: Int)
    /// The text is not a valid value of its field (a date or an order action, say) at this field index.
    case unexpectedValue(String, index: Int)
    /// The server answered the handshake with a version other than the pinned 178.
    case unsupportedServerVersion(Int)
    /// The server's hello did not have the shape of a version and a connection time.
    case badHandshake
}

/// A request that cannot be put on the wire.
public enum IBEncodingError: Error, Equatable, Sendable {
    /// A text field holds a character the wire cannot carry (only printable ASCII; payloads also tab and line breaks).
    case nonASCII(field: String)
    /// The request asks for something the library does not send, e.g. `"secType BAG"` or `"whatIf"`.
    case unsupported(String)
}
