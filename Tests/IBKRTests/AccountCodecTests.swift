import Testing
@testable import IBKR

@Suite struct AccountCodecTests {
    @Test func positionDecodes() {
        var c = Contract(symbol: "AAPL")
        c.conID = 265598; c.strike = 0; c.exchange = "NASDAQ"; c.localSymbol = "AAPL"; c.tradingClass = "NMS"
        let fields = ["61", "3", "DU1", "265598", "AAPL", "STK", "", "0.0", "", "", "NASDAQ", "USD", "AAPL", "NMS",
                      "5", "351.66000005"]
        #expect(IBDecoder.decode(body(fields))
            == .position(Position(account: "DU1", contract: c, quantity: d("5"), averageCost: d("351.66000005"))))
    }

    @Test func positionEndDecodes() {
        #expect(IBDecoder.decode(body("62", "1")) == .positionEnd)
    }

    @Test func accountSummaryDecodes() {
        #expect(IBDecoder.decode(body("63", "1", "7", "DU1", "NetLiquidation", "1000000.00", "USD"))
            == .accountSummary(requestID: 7, AccountValue(account: "DU1", tag: "NetLiquidation",
                                                          value: "1000000.00", currency: "USD")))
        #expect(IBDecoder.decode(body("64", "1", "7")) == .accountSummaryEnd(requestID: 7))
    }

    @Test func pnlSingleDecodes() {
        #expect(IBDecoder.decode(body("95", "9", "1", "12.5", "-3.25", "1.7976931348623157E308", "351.66"))
            == .pnlSingle(requestID: 9, PnL(position: 1, daily: d("12.5"), unrealized: d("-3.25"),
                                            realized: nil, value: d("351.66"))))
    }

    @Test func shortAccountFramesAreMalformed() {
        for (fields, want) in [(["95", "9", "1"], 95), (["63", "1", "7", "DU1"], 63)] {
            guard case .malformed(let id, _, _) = IBDecoder.decode(body(fields)) else {
                Issue.record("not malformed: \(fields)"); continue
            }
            #expect(id == want)
        }
    }

    @Test func accountRequestsEncode() throws {
        #expect(try IBRequest.positions.body() == body("61", "1"))
        #expect(try IBRequest.accountSummary(requestID: 7, group: "All", tags: ["NetLiquidation", "BuyingPower"]).body()
            == body("62", "1", "7", "All", "NetLiquidation,BuyingPower"))
        #expect(try IBRequest.cancelAccountSummary(requestID: 7).body() == body("63", "1", "7"))
        #expect(try IBRequest.pnlSingle(requestID: 9, account: "DU1", modelCode: "", conID: 265598).body()
            == body("94", "9", "DU1", "", "265598"))
        #expect(try IBRequest.cancelPnLSingle(requestID: 9).body() == body("95", "9"))
    }

    @Test func nonASCIIAccountSummaryTagThrows() {
        #expect(throws: IBEncodingError.nonASCII(field: "Чистая")) {
            try IBRequest.accountSummary(requestID: 7, group: "All", tags: ["Чистая"]).body()
        }
    }
}
