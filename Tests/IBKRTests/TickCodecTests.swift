import Testing
@testable import IBKR

@Suite struct TickCodecTests {
    private let aapl = ["0", "AAPL", "STK", "", "0.0", "", "", "SMART", "", "USD", "", ""]

    @Test func tickPriceDecodes() {
        #expect(IBDecoder.decode(body("1", "6", "7", "1", "351.5", "200", "1"))
            == .tick(requestID: 7, .price(.bid, price: d("351.5"), size: d("200"))))
    }

    @Test func tickSizeGenericStringDecode() {
        #expect(IBDecoder.decode(body("2", "6", "7", "8", "1234567")) == .tick(requestID: 7, .size(.volume, d("1234567"))))
        #expect(IBDecoder.decode(body("45", "6", "7", "49", "0")) == .tick(requestID: 7, .generic(.halted, 0)))
        #expect(IBDecoder.decode(body("46", "6", "7", "45", "1794321000"))
            == .tick(requestID: 7, .string(.lastTimestamp, "1794321000")))
    }

    @Test func marketDataTypeDecodes() {
        #expect(IBDecoder.decode(body("58", "1", "7", "3")) == .tick(requestID: 7, .dataType(.delayed)))
        guard case .malformed = IBDecoder.decode(body("58", "1", "7", "9")) else { Issue.record("not malformed"); return }
    }

    @Test func tickReqParamsDecodes() {
        #expect(IBDecoder.decode(body("81", "7", "0.01", "9c0001", "3"))
            == .tickRequestParameters(requestID: 7, minTick: d("0.01"), bboExchange: "9c0001", snapshotPermissions: 3))
    }

    @Test func delayedFieldsMapToLive() {
        #expect(TickField(rawValue: 66).live == .bid)
        #expect(TickField(rawValue: 75).live == .close)
        #expect(TickField.bid.live == .bid)
    }

    @Test func marketDataRequestsEncode() throws {
        #expect(try IBRequest.marketDataType(.delayed).body() == body("59", "1", "3"))
        #expect(try IBRequest.marketData(requestID: 7, contract: Contract(symbol: "AAPL")).body()
            == body(["1", "11", "7"] + aapl + ["0", "", "0", "0", ""]))
        #expect(try IBRequest.cancelMarketData(requestID: 7).body() == body("2", "2", "7"))
    }

    @Test func shortTickFramesAreMalformed() {
        guard case .malformed = IBDecoder.decode(body("1", "6", "7", "1")) else { Issue.record("not malformed"); return }
    }
}
