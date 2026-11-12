import Testing
@testable import IBKR

@Suite struct LookupCodecTests {
    private let aapl = ["0", "AAPL", "STK", "", "0.0", "", "", "SMART", "", "USD", "", ""]

    @Test func contractDetailsEncodes() throws {
        #expect(try IBRequest.contractDetails(requestID: 5, contract: Contract(symbol: "AAPL")).body()
            == body(["9", "8", "5"] + aapl + ["0", "", "", ""]))
    }

    @Test func matchingSymbolsEncodes() throws {
        #expect(try IBRequest.matchingSymbols(requestID: 6, pattern: "AAP").body() == body("81", "6", "AAP"))
        #expect(throws: IBEncodingError.nonASCII(field: "ААР")) {
            try IBRequest.matchingSymbols(requestID: 6, pattern: "ААР").body()
        }
    }

    @Test func bagContractIsRefused() {
        #expect(throws: IBEncodingError.unsupported("secType BAG")) {
            try IBRequest.contractDetails(requestID: 5, contract: Contract(symbol: "X", secType: "BAG")).body()
        }
    }

    private func contractData(secIds: [String] = [], trailing: [String] = []) -> [String] {
        ["10", "5", "AAPL", "STK", "", "0.0", "?", "SMART", "USD", "AAPL", "NMS", "NMS", "265598", "0.01", "",
         "LMT,MKT", "SMART,NASDAQ", "1", "0", "APPLE INC", "NASDAQ", "", "Technology", "Computers", "Computers",
         "US/Eastern", "20261110:0400-20261110:2000;20261111:CLOSED", "20261110:0930-20261110:1600;20261111:CLOSED",
         "", "0", String(secIds.count / 2)] + secIds
        + ["1", "", "", "26,26", "", "COMMON", "1", "1", "1"] + trailing
    }

    private var expected: ContractDetails {
        var c = Contract(symbol: "AAPL", primaryExchange: "NASDAQ")
        c.conID = 265598; c.strike = 0; c.right = "?"; c.localSymbol = "AAPL"; c.tradingClass = "NMS"
        var x = ContractDetails(
            contract: c, marketName: "NMS", minTick: d("0.01"), priceMagnifier: 1, longName: "APPLE INC",
            stockType: "COMMON", orderTypes: ["LMT", "MKT"], validExchanges: ["SMART", "NASDAQ"],
            timeZoneID: "US/Eastern", tradingHours: "20261110:0400-20261110:2000;20261111:CLOSED",
            liquidHours: "20261110:0930-20261110:1600;20261111:CLOSED",
            minSize: 1, sizeIncrement: 1, suggestedSizeIncrement: 1)
        x.industry = "Technology"; x.category = "Computers"; x.subcategory = "Computers"
        x.evMultiplier = 0; x.aggGroup = 1; x.marketRuleIDs = [26, 26]
        return x
    }

    @Test func contractDataDecodes() {
        let f = contractData()
        #expect(f.count == 40)
        #expect(IBDecoder.decode(body(f)) == .contractData(requestID: 5, expected))
    }

    @Test func contractDataWithSecIdsAndTrailingFieldsDecodes() {
        let f = contractData(secIds: ["ISIN", "US0378331005", "FIGI", "BBG000B9XRY4"], trailing: ["x", "y"])
        var want = expected
        want.secIDList = [TagValue(tag: "ISIN", value: "US0378331005"), TagValue(tag: "FIGI", value: "BBG000B9XRY4")]
        #expect(IBDecoder.decode(body(f)) == .contractData(requestID: 5, want))
    }

    @Test func contractDataSplitsLastTimes() {
        func decoded(_ lastTimes: String) -> ContractDetails? {
            var f = contractData(); f[4] = lastTimes
            guard case .contractData(_, let x) = IBDecoder.decode(body(f)) else { return nil }
            return x
        }
        let a = decoded("20261218 16:00 US/Central")
        #expect(a?.contract.lastTradeDateOrContractMonth == "20261218" && a?.lastTradeTime == "16:00")
        #expect(a?.timeZoneID == "US/Central")
        let b = decoded("20261218-16:00:00")
        #expect(b?.contract.lastTradeDateOrContractMonth == "20261218" && b?.lastTradeTime == "16:00:00")
        #expect(b?.timeZoneID == "US/Eastern")
        let c = decoded("202612")
        #expect(c?.contract.lastTradeDateOrContractMonth == "202612" && c?.lastTradeTime == "")
    }

    @Test func contractDataUnescapesLongName() {
        var f = contractData(); f[19] = "CAF\\u00c9"
        guard case .contractData(_, let x) = IBDecoder.decode(body(f)) else { Issue.record("not decoded"); return }
        #expect(x.longName == "CAF\u{C9}")
    }

    @Test func badMarketRuleIDsAreMalformed() {
        var f = contractData(); f[34] = "26,x"
        guard case .malformed(let id, _, _) = IBDecoder.decode(body(f)) else { Issue.record("not malformed"); return }
        #expect(id == 10)
    }

    private let bondFrame = ["18", "7", "IBM", "BOND", "459200HU8", "3.45", "20270210", "20170210", "A2 A-", "FIXED",
        "FIXED", "0", "1", "0", "", "SMART", "USD", "IBM 3.45 02/10/27", "IBCID123", "123456789", "0.001", "LMT,MKT",
        "SMART", "", "", "0", "", "IBM 3.45 02/10/27", "", "", "0", "1", "239", "1", "1", "1"]

    @Test func bondContractDataDecodes() {
        #expect(bondFrame.count == 36)
        var c = Contract(symbol: "IBM", secType: "BOND")
        c.conID = 123456789; c.tradingClass = "IBCID123"
        var x = ContractDetails(
            contract: c, marketName: "IBM 3.45 02/10/27", minTick: d("0.001"), priceMagnifier: 0,
            longName: "IBM 3.45 02/10/27", stockType: "", orderTypes: ["LMT", "MKT"], validExchanges: ["SMART"],
            timeZoneID: "", tradingHours: "", liquidHours: "", minSize: 1, sizeIncrement: 1, suggestedSizeIncrement: 1)
        x.cusip = "459200HU8"; x.coupon = d("3.45"); x.maturity = "20270210"; x.issueDate = "20170210"
        x.ratings = "A2 A-"; x.bondType = "FIXED"; x.couponType = "FIXED"; x.callable = true
        x.aggGroup = 1; x.marketRuleIDs = [239]
        #expect(IBDecoder.decode(body(bondFrame)) == .contractData(requestID: 7, x))
    }

    @Test func shortBondFrameIsMalformed() {
        guard case .malformed(let id, _, _) = IBDecoder.decode(body(Array(bondFrame.prefix(21)))) else {
            Issue.record("not malformed"); return
        }
        #expect(id == 18)
    }

    @Test func contractDataEndDecodes() {
        #expect(IBDecoder.decode(body("52", "1", "5")) == .contractDataEnd(requestID: 5))
    }

    @Test func negativeSymbolCountsAreMalformed() {
        for f in [["79", "6", "-1"],
                  ["79", "6", "1", "265598", "AAPL", "STK", "NASDAQ", "USD", "-1", "APPLE INC", ""]] {
            guard case .malformed = IBDecoder.decode(body(f)) else { Issue.record("not malformed: \(f)"); return }
        }
    }

    @Test func symbolSamplesDecode() {
        let f = ["79", "6", "2", "265598", "AAPL", "STK", "NASDAQ", "USD", "2", "OPT", "WAR", "APPLE INC", "",
                 "38708077", "AAPL", "STK", "MEXI", "MXN", "0", "APPLE INC", ""]
        guard case .symbolSamples(6, let list) = IBDecoder.decode(body(f)) else { Issue.record("not decoded"); return }
        #expect(list.count == 2)
        #expect(list[0].derivativeSecTypes == ["OPT", "WAR"])
        #expect(list[0].contract.conID == 265598 && list[0].contract.primaryExchange == "NASDAQ")
        #expect(list[0].contract.exchange == "" && list[0].description == "APPLE INC")
        #expect(list[1].contract.currency == "MXN" && list[1].derivativeSecTypes.isEmpty)
    }

    @Test func shortLookupFramesAreMalformed() {
        let cut = Array(contractData().prefix(14))  // after minTick
        let short = ["79", "6", "2", "265598", "AAPL", "STK", "NASDAQ", "USD", "0", "APPLE INC", ""]
        for (fields, want) in [(cut, 10), (short, 79)] {
            guard case .malformed(let id, _, _) = IBDecoder.decode(body(fields)) else {
                Issue.record("not malformed: \(fields)"); continue
            }
            #expect(id == want)
        }
    }
}
