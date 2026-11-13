import Testing
@testable import IBKR

@Test func frameEncodesLengthBigEndian() throws {
    #expect(try Frame.encode(Array("ab\0".utf8)) == [0, 0, 0, 3] + Array("ab\0".utf8))
}

@Test func readerReassemblesByteByByte() throws {
    var r = FrameReader()
    let bytes = try Frame.encode(body("3", "5"))
    for (i, b) in bytes.enumerated() {
        try r.append([b])
        if i < bytes.count - 1 { #expect(try r.next() == nil) }
    }
    #expect(try r.next() == body("3", "5"))
    #expect(try r.next() == nil)
}

@Test func readerSplitsTwoFramesInOneChunk() throws {
    var r = FrameReader()
    try r.append(try Frame.encode(body("1")) + Frame.encode(body("2", "x")))
    #expect(try r.next() == body("1"))
    #expect(try r.next() == body("2", "x"))
    #expect(try r.next() == nil)
}

@Test func readerRejectsOversizedFrame() {
    var r = FrameReader()
    #expect(throws: IBProtocolError.frameTooLong(16_777_216)) { try r.append([0x01, 0, 0, 0]) }
}

@Test func encodeRefusesAnOversizedFrame() {
    let body = [UInt8](repeating: 0x41, count: Frame.maxLength + 1)
    #expect(throws: IBEncodingError.frameTooLong(Frame.maxLength + 1)) { _ = try Frame.encode(body) }
}

@Test func readerAcceptsTheMaximumFrame() throws {
    var r = FrameReader()
    try r.append(try Frame.encode([UInt8](repeating: 0x41, count: Frame.maxLength)))
    #expect(try r.next()?.count == Frame.maxLength)
    #expect(throws: IBProtocolError.frameTooLong(Frame.maxLength + 1)) { try r.append([0x01, 0, 0, 0]) }
}

/// The header behind a good frame in the same chunk is checked when that frame is taken, not at the next chunk.
@Test func oversizedHeaderAfterAGoodFrameFailsAtOnce() throws {
    var r = FrameReader()
    try r.append(try Frame.encode(body("1")) + [0x01, 0, 0, 0])
    #expect(try r.next() == body("1"))
    #expect(throws: IBProtocolError.frameTooLong(16_777_216)) { try r.next() }
}
