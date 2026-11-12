import Foundation
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

    @Test func depthExchangesAndSmartComponentsCodec() throws {
        #expect(try IBRequest.depthExchanges.body() == body("82"))
        #expect(try IBRequest.smartComponents(requestID: 7, bboExchange: "9c0001").body() == body("83", "7", "9c0001"))
        #expect(IBDecoder.decode(body("80", "2", "ISLAND", "STK", "NASDAQ", "Deep2", "1", "NYSE", "STK", "NYSE", "Deep", "2147483647"))
            == .depthExchanges([
                DepthMarketDataDescription(exchange: "ISLAND", secType: "STK", listingExchange: "NASDAQ", serviceDataType: "Deep2", aggGroup: 1),
                DepthMarketDataDescription(exchange: "NYSE", secType: "STK", listingExchange: "NYSE", serviceDataType: "Deep", aggGroup: nil)]))
        #expect(IBDecoder.decode(body("82", "7", "2", "0", "NYSE", "N", "1", "ARCA", "P"))
            == .smartComponents(requestID: 7, [SmartComponent(bitNumber: 0, exchange: "NYSE", exchangeLetter: "N"),
                                               SmartComponent(bitNumber: 1, exchange: "ARCA", exchangeLetter: "P")]))
        for frame in [body("80", "-1"), body("82", "7", "-1")] {
            guard case .malformed = IBDecoder.decode(frame) else { Issue.record("not malformed"); return }
        }
    }

    @Test func deltaNeutralValidationDecodes() {
        #expect(IBDecoder.decode(body("56", "1", "7", "265598", "0.5", "187.25"))
            == .deltaNeutralValidation(requestID: 7, DeltaNeutralContract(conID: 265598, delta: d("0.5"), price: d("187.25"))))
    }

    @Test func reroutesDecode() {
        #expect(IBDecoder.decode(body("91", "7", "12087792", "IDEALPRO"))
            == .rerouteMarketData(requestID: 7, conID: 12087792, exchange: "IDEALPRO"))
        #expect(IBDecoder.decode(body("92", "7", "12087792", "IDEALPRO"))
            == .rerouteMarketDepth(requestID: 7, conID: 12087792, exchange: "IDEALPRO"))
    }

    @Test func tickReqParamsDecodes() {
        #expect(IBDecoder.decode(body("81", "7", "0.01", "9c0001", "3"))
            == .tick(requestID: 7, .requestParameters(minTick: d("0.01"), bboExchange: "9c0001", snapshotPermissions: 3)))
    }

    private let greeks = ["21", "7", "13", "1", "0.25", "0.55", "6.1", "0", "0.03", "0.12", "-0.05", "187.2"]

    @Test func optionComputationDecodes() {
        #expect(IBDecoder.decode(body(greeks)) == .tick(requestID: 7, .optionComputation(TickField(rawValue: 13), OptionComputation(
            tickAttrib: 1, impliedVol: d("0.25"), delta: d("0.55"), optPrice: d("6.1"), pvDividend: 0, gamma: d("0.03"),
            vega: d("0.12"), theta: d("-0.05"), undPrice: d("187.2")))))
    }

    @Test func uncomputedGreeksAreNil() {
        #expect(IBDecoder.decode(body("21", "7", "10", "0", "-1", "-2", "-1", "-1", "-2", "-2", "-2", "-1"))
            == .tick(requestID: 7, .optionComputation(TickField(rawValue: 10), OptionComputation(tickAttrib: 0))))
        #expect(IBDecoder.decode(body("21", "7", "11", "0", "1.7976931348623157E308", "0.5", "", "2147483647", "0.01", "0.1", "-0.02", "187"))
            == .tick(requestID: 7, .optionComputation(TickField(rawValue: 11), OptionComputation(
                tickAttrib: 0, delta: d("0.5"), gamma: d("0.01"), vega: d("0.1"), theta: d("-0.02"), undPrice: 187))))
    }

    @Test func shortOptionComputationIsMalformed() {
        guard case .malformed = IBDecoder.decode(body(Array(greeks.dropLast()))) else { Issue.record("not malformed"); return }
    }

    @Test func efpDecodes() {
        #expect(IBDecoder.decode(body("47", "1", "7", "38", "1.5", "1.50%", "187.3", "30", "20261218", "0.2", "0.25"))
            == .tick(requestID: 7, .efp(TickField(rawValue: 38), EFPData(
                basisPoints: d("1.5"), formattedBasisPoints: "1.50%", impliedFuture: d("187.3"), holdDays: 30,
                futureLastTradeDate: "20261218", dividendImpact: d("0.2"), dividendsToLastTradeDate: d("0.25")))))
    }

    @Test func newsTickDecodes() {
        #expect(IBDecoder.decode(body("84", "7", "1794321000000", "BRFG", "BRFG$12345", "Apple headline", "A:800015:L:en"))
            == .tick(requestID: 7, .news(NewsTick(
                timeStamp: 1794321000000, providerCode: "BRFG", articleID: "BRFG$12345", headline: "Apple headline",
                extraData: "A:800015:L:en"))))
    }

    @Test func delayedFieldsMapToLive() {
        #expect(TickField(rawValue: 66).live == .bid)
        #expect(TickField(rawValue: 75).live == .close)
        #expect(TickField.bid.live == .bid)
        #expect(TickField(rawValue: 80).live.rawValue == 10)
        #expect(TickField(rawValue: 83).live.rawValue == 13)
    }

    @Test func marketDataRequestsEncode() throws {
        #expect(try IBRequest.marketDataType(.delayed).body() == body("59", "1", "3"))
        #expect(try IBRequest.marketData(requestID: 7, contract: Contract(symbol: "AAPL")).body()
            == body(["1", "11", "7"] + aapl + ["0", "", "0", "0", ""]))
        #expect(try IBRequest.cancelMarketData(requestID: 7).body() == body("2", "2", "7"))
    }

    @Test func marketDataSendsItsParameters() throws {
        #expect(try IBRequest.marketData(requestID: 7, contract: Contract(symbol: "AAPL"), genericTicks: [100, 101, 104],
                                         snapshot: true, regulatorySnapshot: true).body()
            == body(["1", "11", "7"] + aapl + ["0", "100,101,104", "1", "1", ""]))
    }

    @Test func marketDataSendsTheDeltaNeutralContract() throws {
        var c = Contract(symbol: "AAPL")
        c.deltaNeutralContract = DeltaNeutralContract(conID: 265598, delta: d("0.5"), price: d("187.25"))
        #expect(try IBRequest.marketData(requestID: 7, contract: c).body()
            == body(["1", "11", "7"] + aapl + ["1", "265598", "0.5", "187.25", "", "0", "0", ""]))
    }

    @Test func marketDataSendsBagLegs() throws {
        #expect(try IBRequest.marketData(requestID: 7, contract: bagContract).body()
            == body(["1", "11", "7"] + bagBlock + bagLegs + ["0", "", "0", "0", ""]))
    }

    @Test func snapshotEndDecodes() {
        #expect(IBDecoder.decode(body("57", "1", "7")) == .tickSnapshotEnd(requestID: 7))
    }

    @Test func shortTickFramesAreMalformed() {
        guard case .malformed = IBDecoder.decode(body("1", "6", "7", "1")) else { Issue.record("not malformed"); return }
    }

    @Test func realTimeBarsEncodeAndDecode() throws {
        #expect(try IBRequest.realTimeBars(requestID: 7, contract: Contract(symbol: "AAPL"), whatToShow: "TRADES", rth: true).body()
            == body(["50", "3", "7"] + aapl + ["5", "TRADES", "1", ""]))
        #expect(try IBRequest.cancelRealTimeBars(requestID: 7).body() == body("51", "1", "7"))
        #expect(IBDecoder.decode(body("50", "3", "7", "1794321000", "351.0", "352.0", "350.5", "351.5", "1000", "351.2", "42"))
            == .realTimeBar(requestID: 7, Bar(time: Date(timeIntervalSince1970: 1794321000), open: d("351.0"), high: d("352.0"),
                                             low: d("350.5"), close: d("351.5"), volume: 1000, average: d("351.2"), count: 42)))
    }
}
