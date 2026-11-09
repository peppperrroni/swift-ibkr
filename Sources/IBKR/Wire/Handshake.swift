public enum Handshake {
    public static let version = 178

    /// "API\0", then the length-prefixed version range with no trailing NUL; the only unframed write.
    static func hello() -> [UInt8] {
        let range = Array("v100..\(version)".utf8)
        let n = UInt32(range.count)
        return Array("API\0".utf8) + [UInt8(n >> 24), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)] + range
    }

    static func parseServerHello(_ body: [UInt8]) throws(IBProtocolError) -> (serverVersion: Int, connectionTime: String) {
        let fields = FieldReader(body).fields
        guard fields.count == 2, let v = Int(fields[0]) else { throw .badHandshake }
        guard v == version else { throw .unsupportedServerVersion(v) }
        return (v, fields[1])
    }
}
