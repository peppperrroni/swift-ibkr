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

    @Test func calculationsEncode() throws {
        #expect(try IBRequest.calculateImpliedVolatility(requestID: 7, contract: aaplCall, optionPrice: d("6.1"),
                                                         underPrice: d("187.2"), options: []).body()
            == body(["54", "3", "7"] + aaplCallBlock + ["6.1", "187.2", "0", ""]))
        #expect(try IBRequest.calculateOptionPrice(requestID: 7, contract: aaplCall, volatility: d("0.25"),
                                                   underPrice: d("187.2"),
                                                   options: [TagValue(tag: "a", value: "1"), TagValue(tag: "b", value: "2")]).body()
            == body(["55", "3", "7"] + aaplCallBlock + ["0.25", "187.2", "2", "a=1;b=2;"]))
        #expect(try IBRequest.cancelCalculateImpliedVolatility(requestID: 7).body() == body("56", "1", "7"))
        #expect(try IBRequest.cancelCalculateOptionPrice(requestID: 7).body() == body("57", "1", "7"))
    }
}
