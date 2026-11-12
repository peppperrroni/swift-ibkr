import Testing
@testable import IBKR

@Test func writerEncodesEachKind() throws {
    var w = FieldWriter()
    try w.add("BUY")
    w.add(Int?.none)
    w.add(7)
    w.add(d("0.0001"))
    w.add(d("100"))
    w.add(true)
    w.add(false)
    #expect(w.body == Array("BUY\0\07\00.0001\0100\01\00\0".utf8))
}

@Test func writerRefusesNonASCII() {
    var w = FieldWriter()
    #expect(throws: IBEncodingError.nonASCII(field: "Купить")) { try w.add("Купить") }
    #expect(throws: IBEncodingError.nonASCII(field: "a\u{7}")) { try w.add("a\u{7}") }
}

/// addPayload carries IB's XML and JSON text, which spans lines; add still refuses a control character.
@Test func payloadKeepsLineBreaksAndTabs() throws {
    var w = FieldWriter()
    try w.addPayload("<a>\r\n\t<b/>\n</a>")
    #expect(w.body == Array("<a>\r\n\t<b/>\n</a>\0".utf8))
    #expect(throws: IBEncodingError.nonASCII(field: "a\u{7}")) { try w.addPayload("a\u{7}") }
    #expect(throws: IBEncodingError.nonASCII(field: "é")) { try w.addPayload("é") }
    #expect(throws: IBEncodingError.nonASCII(field: "a\n")) { var v = FieldWriter(); try v.add("a\n") }
}

@Test func everyOptionalReaderMapsEverySentinel() throws {
    let sentinels = ["", "2147483647", "9223372036854775807", "1.7976931348623157E308", "-9223372036854775808"]
    for s in sentinels {
        var r = FieldReader(body(s, s, s))
        #expect(try r.optionalInt() == nil, "optionalInt \(s)")
        #expect(try r.optionalDecimal() == nil, "optionalDecimal \(s)")
        #expect(try r.optionalDouble() == nil, "optionalDouble \(s)")
    }
}

@Test func decimalRejectsTrailingGarbage() throws {
    for s in ["12.5x", "1.2.3", "--1", "1e", "0x10", " 1", "1 "] {
        var r = FieldReader(body(s))
        #expect(throws: IBProtocolError.badNumber(s, index: 0)) { try r.decimal() }
        var r2 = FieldReader(body(s))
        #expect(throws: IBProtocolError.badNumber(s, index: 0)) { try r2.optionalDecimal() }
    }
    var ok = FieldReader(body("-12.5", "+3", "1E3"))
    #expect(try ok.decimal() == d("-12.5"))
    #expect(try ok.decimal() == d("3"))
    #expect(try ok.decimal() == d("1000"))
}

@Test func emptyBodyHasNoFields() {
    let r = FieldReader([])
    #expect(r.fields == [])
    #expect(r.isAtEnd)
}

@Test func unsetSentinelsAreNil() throws {
    var r = FieldReader(body("", "2147483647", "9223372036854775807", "1.7976931348623157E308", "12.5"))
    #expect(try r.optionalInt() == nil)
    #expect(try r.optionalInt() == nil)
    #expect(try r.optionalInt() == nil)
    #expect(try r.optionalDecimal() == nil)
    #expect(try r.optionalDecimal() == d("12.5"))
    #expect(r.isAtEnd)
}

@Test func readerDecodesUTF8() throws {
    var r = FieldReader(body("Ордер отклонён"))
    #expect(try r.string() == "Ордер отклонён")
}

@Test func readerThrowsPastTheEnd() throws {
    var r = FieldReader(body("x"))
    #expect(try r.string() == "x")
    #expect(throws: IBProtocolError.missingField(index: 1)) { try r.string() }
    var r2 = FieldReader(body("x"))
    #expect(throws: IBProtocolError.badNumber("x", index: 0)) { try r2.int() }
}
