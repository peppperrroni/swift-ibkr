public enum IBProtocolError: Error, Equatable, Sendable {
    case frameTooLong(Int)
    case missingField(index: Int)
    case badNumber(String, index: Int)
    case unsupportedServerVersion(Int)
    case badHandshake
}

public enum IBEncodingError: Error, Equatable, Sendable {
    case nonASCII(field: String)
    case unsupported(String)
}
