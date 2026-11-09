import Foundation

struct FieldWriter {
    private(set) var body: [UInt8] = []

    init() {}

    mutating func add(_ value: String) throws(IBEncodingError) {
        guard value.utf8.allSatisfy({ (0x20...0x7E).contains($0) }) else { throw .nonASCII(field: value) }
        put(value)
    }
    mutating func add(_ value: Int?) { put(value.map(String.init) ?? "") }
    mutating func add(_ value: Decimal?) { put(value.map { $0.description } ?? "") }
    mutating func add(_ value: Bool) { put(value ? "1" : "0") }
    mutating func add(_ value: Double?) { put(value.map { "\($0)" } ?? "") }

    private mutating func put(_ s: String) { body += Array(s.utf8) + [0] }
}

struct FieldReader {
    var fields: [String]
    var index = 0

    init(_ body: [UInt8]) {
        var parts = body.split(separator: 0, omittingEmptySubsequences: false)
        if body.last == 0 { parts.removeLast() }  // the terminator of the last field
        fields = parts.map { String(decoding: $0, as: UTF8.self) }
    }

    var isAtEnd: Bool { index >= fields.count }

    mutating func string() throws -> String {
        guard index < fields.count else { throw IBProtocolError.missingField(index: index) }
        defer { index += 1 }
        return fields[index]
    }

    mutating func int() throws -> Int { try optionalInt() ?? 0 }
    mutating func decimal() throws -> Decimal { try optionalDecimal() ?? 0 }

    mutating func optionalInt() throws -> Int? {
        let at = index
        let s = try string()
        if s.isEmpty || s == "2147483647" || s == "9223372036854775807" { return nil }
        guard let v = Int(s) else { throw IBProtocolError.badNumber(s, index: at) }
        return v
    }

    mutating func optionalDecimal() throws -> Decimal? {
        let at = index
        let s = try string()
        if s.isEmpty || s == "2147483647" || s == "9223372036854775807" || s == "1.7976931348623157E308"
            || s == "-9223372036854775808" { return nil }
        guard let v = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else {
            throw IBProtocolError.badNumber(s, index: at)
        }
        return v
    }

    mutating func bool() throws -> Bool {
        let s = try string()
        return s == "1" || s == "true"
    }

    mutating func optionalDouble() throws -> Double? {
        let at = index
        let s = try string()
        if s.isEmpty || s == "1.7976931348623157E308" || s == "1.7976931348623157e308" { return nil }
        if s == "Infinite" { return .infinity }
        guard let v = Double(s) else { throw IBProtocolError.badNumber(s, index: at) }
        return v
    }

    mutating func double() throws -> Double { try optionalDouble() ?? 0 }

    mutating func skip(_ count: Int = 1) throws {
        guard index + count <= fields.count else { throw IBProtocolError.missingField(index: fields.count) }
        index += count
    }
}
