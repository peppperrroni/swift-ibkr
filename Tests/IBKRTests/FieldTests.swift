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
    #expect(throws: IBEncodingError.self) { try w.add("a\u{7}") }
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
