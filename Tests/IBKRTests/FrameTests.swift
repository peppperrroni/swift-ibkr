import Testing
@testable import IBKR

@Test func frameEncodesLengthBigEndian() {
    #expect(Frame.encode(Array("ab\0".utf8)) == [0, 0, 0, 3] + Array("ab\0".utf8))
}

@Test func readerReassemblesByteByByte() throws {
    var r = FrameReader()
    let bytes = Frame.encode(body("3", "5"))
    for (i, b) in bytes.enumerated() {
        try r.append([b])
        if i < bytes.count - 1 { #expect(r.next() == nil) }
    }
    #expect(r.next() == body("3", "5"))
    #expect(r.next() == nil)
}

@Test func readerSplitsTwoFramesInOneChunk() throws {
    var r = FrameReader()
    try r.append(Frame.encode(body("1")) + Frame.encode(body("2", "x")))
    #expect(r.next() == body("1"))
    #expect(r.next() == body("2", "x"))
    #expect(r.next() == nil)
}

@Test func readerRejectsOversizedFrame() {
    var r = FrameReader()
    #expect(throws: IBProtocolError.frameTooLong(16_777_216)) { try r.append([0x01, 0, 0, 0]) }
}
