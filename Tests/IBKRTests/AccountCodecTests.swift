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

    private var aapl: Contract {
        var c = Contract(symbol: "AAPL")
        c.conID = 265598; c.secType = "STK"; c.strike = 0; c.currency = "USD"; c.localSymbol = "AAPL"; c.tradingClass = "NMS"
        return c
    }

    @Test func accountValueDecodes() {
        #expect(IBDecoder.decode(body("6", "2", "NetLiquidation", "100000.50", "USD", "DU1"))
            == .accountValue(AccountValue(account: "DU1", tag: "NetLiquidation", value: "100000.50", currency: "USD")))
    }

    @Test func portfolioItemDecodes() {
        var c = aapl; c.exchange = ""; c.primaryExchange = "NASDAQ"
        let fields = ["7", "8", "265598", "AAPL", "STK", "", "0.0", "", "", "NASDAQ", "USD", "AAPL", "NMS", "5", "187.25",
                      "936.25", "180.5", "33.75", "1.7976931348623157E308", "DU1"]
        #expect(IBDecoder.decode(body(fields))
            == .portfolioItem(PortfolioItem(account: "DU1", contract: c, quantity: 5, marketPrice: d("187.25"),
                                            marketValue: d("936.25"), averageCost: d("180.5"),
                                            unrealizedPNL: d("33.75"), realizedPNL: nil)))
    }

    @Test func accountTimeAndDownloadEndDecode() {
        #expect(IBDecoder.decode(body("8", "1", "14:35")) == .accountTime("14:35"))
        #expect(IBDecoder.decode(body("54", "1", "DU1")) == .accountDownloadEnd(account: "DU1"))
    }

    @Test func positionMultiDecodes() {
        var c = aapl; c.exchange = "NASDAQ"
        let fields = ["71", "1", "5", "DU1", "265598", "AAPL", "STK", "", "0.0", "", "", "NASDAQ", "USD", "AAPL", "NMS",
                      "10", "180.5", "M1"]
        #expect(IBDecoder.decode(body(fields)) == .positionMulti(
            requestID: 5, Position(account: "DU1", contract: c, quantity: 10, averageCost: d("180.5"), modelCode: "M1")))
        #expect(IBDecoder.decode(body("72", "1", "5")) == .positionMultiEnd(requestID: 5))
    }

    @Test func accountUpdateMultiDecodes() {
        #expect(IBDecoder.decode(body("73", "1", "6", "DU1", "M1", "NetLiquidation", "100000.50", "USD"))
            == .accountUpdateMulti(requestID: 6, AccountValue(account: "DU1", tag: "NetLiquidation", value: "100000.50",
                                                              currency: "USD", modelCode: "M1")))
        #expect(IBDecoder.decode(body("74", "1", "6")) == .accountUpdateMultiEnd(requestID: 6))
    }

    @Test func accountPnLDecodes() {
        #expect(IBDecoder.decode(body("94", "7", "12.5", "-3.25", "1.7976931348623157E308"))
            == .pnl(requestID: 7, AccountPnL(daily: d("12.5"), unrealized: d("-3.25"), realized: nil)))
    }

    @Test func shortAccountUpdateFramesAreMalformed() {
        for (fields, want) in [(["7", "8", "265598"], 7), (["73", "1", "6"], 73), (["94", "7"], 94)] {
            guard case .malformed(let id, _, _) = IBDecoder.decode(body(fields)) else {
                Issue.record("not malformed: \(fields)"); continue
            }
            #expect(id == want)
        }
    }

    @Test func accountUpdateRequestsEncode() throws {
        #expect(try IBRequest.accountUpdates(subscribe: true, account: "DU1").body() == body("6", "2", "1", "DU1"))
        #expect(try IBRequest.cancelPositions.body() == body("64", "1"))
        #expect(try IBRequest.positionsMulti(requestID: 5, account: "DU1", modelCode: "").body()
            == body("74", "1", "5", "DU1", ""))
        #expect(try IBRequest.cancelPositionsMulti(requestID: 5).body() == body("75", "1", "5"))
        #expect(try IBRequest.accountUpdatesMulti(requestID: 6, account: "DU1", modelCode: "", ledgerAndNLV: false).body()
            == body("76", "1", "6", "DU1", "", "0"))
        #expect(try IBRequest.cancelAccountUpdatesMulti(requestID: 6).body() == body("77", "1", "6"))
        #expect(try IBRequest.pnl(requestID: 7, account: "DU1", modelCode: "").body() == body("92", "7", "DU1", ""))
        #expect(try IBRequest.cancelPnL(requestID: 7).body() == body("93", "7"))
    }
}
