import Testing
@testable import IBKR

@Suite struct ReferenceCodecTests {
    @Test func optionChainsCodec() throws {
        #expect(try IBRequest.secDefOptParams(requestID: 7, underlyingSymbol: "AAPL", futFopExchange: "",
                                              underlyingSecType: "STK", underlyingConID: 265598).body()
            == body("78", "7", "AAPL", "", "STK", "265598"))
        #expect(IBDecoder.decode(body("75", "7", "SMART", "265598", "AAPL", "100", "2", "20261218", "20270115",
                                      "3", "190", "195", "200"))
            == .securityDefinitionOptionParameter(requestID: 7, OptionChain(
                exchange: "SMART", underlyingConID: 265598, tradingClass: "AAPL", multiplier: "100",
                expirations: ["20261218", "20270115"], strikes: [190, 195, 200])))
        #expect(IBDecoder.decode(body("76", "7")) == .securityDefinitionOptionParameterEnd(requestID: 7))
        guard case .malformed = IBDecoder.decode(body("75", "7", "SMART", "265598", "AAPL", "100", "-1")) else {
            Issue.record("not malformed"); return
        }
    }
}
