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
        return ContractDetails(
            contract: c, marketName: "NMS", minTick: d("0.01"), priceMagnifier: 1, longName: "APPLE INC",
            stockType: "COMMON", orderTypes: ["LMT", "MKT"], validExchanges: ["SMART", "NASDAQ"],
            timeZoneID: "US/Eastern", tradingHours: "20261110:0400-20261110:2000;20261111:CLOSED",
            liquidHours: "20261110:0930-20261110:1600;20261111:CLOSED",
            minSize: 1, sizeIncrement: 1, suggestedSizeIncrement: 1)
    }

    @Test func contractDataDecodes() {
        let f = contractData()
        #expect(f.count == 40)
        #expect(IBDecoder.decode(body(f)) == .contractData(requestID: 5, expected))
    }

    @Test func contractDataWithSecIdsAndTrailingFieldsDecodes() {
        let f = contractData(secIds: ["ISIN", "US0378331005", "FIGI", "BBG000B9XRY4"], trailing: ["x", "y"])
        #expect(IBDecoder.decode(body(f)) == .contractData(requestID: 5, expected))
    }

    @Test func contractDataEndDecodes() {
        #expect(IBDecoder.decode(body("52", "1", "5")) == .contractDataEnd(requestID: 5))
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
