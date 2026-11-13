enum Frame {
    static let maxLength = 0xFF_FFFF

    /// Length prefix (4 bytes, big-endian) followed by the body; a body above `maxLength` throws `.frameTooLong`.
    static func encode(_ body: [UInt8]) throws(IBEncodingError) -> [UInt8] {
        guard body.count <= maxLength else { throw .frameTooLong(body.count) }
        let n = UInt32(body.count)
        return [UInt8(n >> 24), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)] + body
    }
}

struct FrameReader {
    private var buffer: [UInt8] = []

    mutating func append(_ bytes: [UInt8]) throws(IBProtocolError) {
        buffer += bytes
        try checkLength()
    }

    /// The next whole frame's body, or nil until one is in. Checks the header too: an oversized one that came in
    /// behind a frame already taken throws here, not at the next `append`.
    mutating func next() throws(IBProtocolError) -> [UInt8]? {
        try checkLength()
        guard let length = pendingLength, buffer.count >= 4 + length else { return nil }
        let body = Array(buffer[4..<(4 + length)])
        buffer.removeFirst(4 + length)
        return body
    }

    private func checkLength() throws(IBProtocolError) {
        if let length = pendingLength, length > Frame.maxLength { throw .frameTooLong(length) }
    }

    private var pendingLength: Int? {
        guard buffer.count >= 4 else { return nil }
        return buffer[0..<4].reduce(0) { $0 << 8 | Int($1) }
    }
}
