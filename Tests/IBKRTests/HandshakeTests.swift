import Testing
@testable import IBKR

@Suite struct HandshakeTests {
    @Test func helloIsPrefixAndVersionRange() {
        #expect(Handshake.hello() == Array("API\0".utf8) + [0, 0, 0, 9] + Array("v100..178".utf8))
    }

    @Test func serverHelloParses() throws {
        let t = "20261109 10:41:35 Central European Standard Time"
        let r = try Handshake.parseServerHello(body("178", t))
        #expect(r.serverVersion == 178)
        #expect(r.connectionTime == t)
    }

    @Test func serverHelloOtherVersionThrows() {
        #expect(throws: IBProtocolError.unsupportedServerVersion(176)) { try Handshake.parseServerHello(body("176", "t")) }
        #expect(throws: IBProtocolError.unsupportedServerVersion(201)) { try Handshake.parseServerHello(body("201", "t")) }
        #expect(throws: IBProtocolError.badHandshake) { try Handshake.parseServerHello(body("178")) }
    }
}
