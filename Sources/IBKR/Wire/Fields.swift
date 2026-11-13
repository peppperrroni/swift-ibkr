import Foundation

struct FieldWriter {
    private(set) var body: [UInt8] = []

    init() {}

    mutating func add(_ value: String) throws(IBEncodingError) {
        guard value.utf8.allSatisfy({ (0x20...0x7E).contains($0) }) else { throw .nonASCII(field: value) }
        put(value)
    }
    /// Text IB's own payloads carry (a filter's JSON, FA XML): `add`'s ASCII plus tab, LF and CR, which they hold as
    /// line breaks. `ib_async` sends them as they are; any other control character or non-ASCII still throws.
    mutating func addPayload(_ value: String) throws(IBEncodingError) {
        guard value.utf8.allSatisfy({ (0x20...0x7E).contains($0) || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }) else {
            throw .nonASCII(field: value)
        }
        put(value)
    }
    mutating func add(_ value: Int?) { put(value.map(String.init) ?? "") }
    mutating func add(_ value: Decimal?) { put(value.map { $0.description } ?? "") }
    mutating func add(_ value: Bool) { put(value ? "1" : "0") }
    /// A `Double`'s text (`0` → `0.0`): `ib_async`'s `str(float)` for the floats whose default is not unset.
    mutating func addDouble(_ value: Decimal) { put("\((value as NSDecimalNumber).doubleValue)") }

    private mutating func put(_ s: String) { body += Array(s.utf8) + [0] }
}

struct FieldReader {
    var fields: [String]
    var index = 0

    init(_ body: [UInt8]) {
        var parts = body.split(separator: 0, omittingEmptySubsequences: false)
        if body.isEmpty || body.last == 0 { parts.removeLast() }  // the terminator of the last field
        fields = parts.map { String(decoding: $0, as: UTF8.self) }
    }

    var isAtEnd: Bool { index >= fields.count }

    mutating func string() throws -> String {
        guard index < fields.count else { throw IBProtocolError.missingField(index: index) }
        defer { index += 1 }
        return fields[index]
    }

    /// IB's "no value" markers; "-9223372036854775808" is IB's own extra decimal sentinel.
    private static let unset: Set<String> = [
        "", "2147483647", "9223372036854775807", "1.7976931348623157E308", "-9223372036854775808",
    ]

    /// Optional sign, digits with at most one ".", optional exponent: nothing else.
    private static func isPlainNumber(_ s: String) -> Bool {
        let u = Array(s.utf8)
        var i = 0
        if i < u.count, u[i] == 0x2B || u[i] == 0x2D { i += 1 }
        var digits = 0
        while i < u.count, (0x30...0x39).contains(u[i]) { i += 1; digits += 1 }
        if i < u.count, u[i] == 0x2E {
            i += 1
            while i < u.count, (0x30...0x39).contains(u[i]) { i += 1; digits += 1 }
        }
        guard digits > 0 else { return false }
        if i < u.count, u[i] == 0x45 || u[i] == 0x65 {
            i += 1
            if i < u.count, u[i] == 0x2B || u[i] == 0x2D { i += 1 }
            var exp = 0
            while i < u.count, (0x30...0x39).contains(u[i]) { i += 1; exp += 1 }
            guard exp > 0 else { return false }
        }
        return i == u.count
    }

    /// A plain number (see `isPlainNumber`) as a `Decimal`; `nil` for anything else, IB's unset markers included.
    static func plainDecimal(_ s: String) -> Decimal? {
        isPlainNumber(s) ? Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) : nil
    }

    mutating func int() throws -> Int { try optionalInt() ?? 0 }
    mutating func decimal() throws -> Decimal { try optionalDecimal() ?? 0 }

    mutating func optionalInt() throws -> Int? {
        let at = index
        let s = try string()
        if Self.unset.contains(s) { return nil }
        guard let v = Int(s) else { throw IBProtocolError.badNumber(s, index: at) }
        return v
    }

    mutating func optionalDecimal() throws -> Decimal? {
        let at = index
        let s = try string()
        if Self.unset.contains(s) { return nil }
        guard Self.isPlainNumber(s), let v = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else {
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
        if Self.unset.contains(s) { return nil }
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
