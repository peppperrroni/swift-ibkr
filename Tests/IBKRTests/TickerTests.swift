import Foundation
import Testing
@testable import IBKR

@Suite struct TickerTests {
    @Test func ticksFoldIntoTheTicker() {
        var t = Ticker(contract: Contract(symbol: "AAPL"))
        for tick: Tick in [
            .price(.bid, price: d("351.5"), size: d("200")),
            .price(.ask, price: d("351.6"), size: d("100")),
            .price(.last, price: d("351.55"), size: d("10")),
            .size(.volume, d("12345")),
            .price(TickField(rawValue: 72), price: d("352"), size: 0),
            .price(.close, price: d("350"), size: 0),
            .price(TickField(rawValue: 20), price: d("400"), size: 0),
            .string(.lastTimestamp, "1794321000"),
            .generic(.halted, 0),
            .dataType(.delayed),
            .requestParameters(minTick: d("0.01"), bboExchange: "9c0001", snapshotPermissions: 3),
        ] { t.apply(tick) }

        #expect(t.bid == d("351.5"))
        #expect(t.bidSize == 200)
        #expect(t.ask == d("351.6"))
        #expect(t.askSize == 100)
        #expect(t.last == d("351.55"))
        #expect(t.lastSize == 10)
        #expect(t.volume == 12345)
        #expect(t.high == 352)
        #expect(t.close == 350)
        #expect(t.prices[TickField(rawValue: 20)] == 400)
        #expect(t.lastTimestamp == Date(timeIntervalSince1970: 1794321000))
        #expect(t.generics[.halted] == 0)
        #expect(t.marketDataType == .delayed)
        #expect(t.minTick == d("0.01"))
        #expect(t.bboExchange == "9c0001")
        #expect(t.snapshotPermissions == 3)
    }

    @Test func anEmptySideClearsItsPrice() {
        var t = Ticker(contract: Contract(symbol: "AAPL"))
        t.apply(.price(.bid, price: d("351.5"), size: d("200")))
        t.apply(.size(.bidSize, 0))
        #expect(t.bid == nil)
        #expect(t.bidSize == 0)
        t.apply(.price(.ask, price: -1, size: 0))
        #expect(t.ask == nil)
        #expect(t.askSize == 0)
    }

    @Test func lastSizeWaitsForALast() {
        var t = Ticker(contract: Contract(symbol: "AAPL"))
        t.apply(.size(.lastSize, 5))
        #expect(t.lastSize == nil)
    }

    @Test func anEmptyLastAfterACloseIsNil() {
        var t = Ticker(contract: Contract(symbol: "AAPL"))
        t.apply(.price(.close, price: 350, size: 0))
        t.apply(.price(.last, price: -1, size: 0))
        #expect(t.last == nil)
        #expect(t.lastSize == 0)
    }

    @Test func greeksGoToTheirSide() {
        var t = Ticker(contract: Contract(symbol: "AAPL"))
        let c1 = OptionComputation(tickAttrib: 0, delta: d("0.5"))
        let c2 = OptionComputation(tickAttrib: 1, delta: d("0.5"))
        let c3 = OptionComputation(tickAttrib: 0, delta: d("0.6"))
        t.apply(.optionComputation(TickField(rawValue: 10), c1))
        #expect(t.bidGreeks == c1)
        t.apply(.optionComputation(TickField(rawValue: 83), c2))
        #expect(t.modelGreeks == c2)
        t.apply(.optionComputation(TickField(rawValue: 53), c3))
        #expect(t.custGreeks == c3)
    }

    @Test func efpStringsAndNews() {
        var t = Ticker(contract: Contract(symbol: "AAPL"))
        let e = EFPData(basisPoints: d("1.5"), holdDays: 30)
        t.apply(.efp(TickField(rawValue: 38), e))
        #expect(t.efp[TickField(rawValue: 38)] == e)
        t.apply(.string(TickField(rawValue: 84), "NYSE"))
        #expect(t.strings[TickField(rawValue: 84)] == "NYSE")
        let before = t
        t.apply(.news(NewsTick(timeStamp: 1, providerCode: "BZ", articleID: "A1", headline: "H")))
        #expect(t == before)
    }

    @Test func delayedYieldsLandOnTheirLiveFields() {
        var t = Ticker(contract: Contract(symbol: "AAPL"))
        t.apply(.price(TickField(rawValue: 103), price: d("4.5"), size: 0))
        #expect(t.prices[TickField(rawValue: 50)] == d("4.5"))
        #expect(t.prices[TickField(rawValue: 103)] == nil)
    }

    @Test func aPriceAfterAnEmptySideRestoresIt() {
        var t = Ticker(contract: Contract(symbol: "AAPL"))
        t.apply(.price(.bid, price: d("351.5"), size: d("200")))
        t.apply(.size(.bidSize, 0))
        t.apply(.price(.bid, price: d("351.6"), size: d("100")))
        #expect(t.bid == d("351.6"))
        #expect(t.bidSize == 100)
    }

    @Test func aPriceWithoutSizeKeepsThePrice() {
        var t = Ticker(contract: Contract(symbol: "AAPL"))
        t.apply(.price(.bid, price: d("351.5"), size: nil))
        #expect(t.bid == d("351.5"))
        #expect(t.bidSize == nil)
    }

    @Test func delayedBidLandsOnBid() {
        var t = Ticker(contract: Contract(symbol: "AAPL"))
        t.apply(.price(TickField(rawValue: 66), price: d("351.4"), size: 100))
        #expect(t.bid == d("351.4"))
        #expect(t.bidSize == 100)
        #expect(t.prices.isEmpty)
    }

    @Test func tickNyseKeepsMinusOneWithoutAClose() {
        var t = Ticker(contract: Contract(symbol: "AAPL"))
        t.apply(.price(.last, price: -1, size: 0))
        #expect(t.last == -1)
        #expect(t.lastSize == 0)
    }

    @Test func aZeroOrBadTimestampIsIgnored() {
        var t = Ticker(contract: Contract(symbol: "AAPL"))
        t.apply(.string(.lastTimestamp, "1794321000"))
        t.apply(.string(.lastTimestamp, "0"))
        t.apply(.string(.lastTimestamp, "x"))
        #expect(t.lastTimestamp == Date(timeIntervalSince1970: 1794321000))
    }
}
