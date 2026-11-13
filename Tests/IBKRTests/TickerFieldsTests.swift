import Foundation
import Testing
@testable import IBKR

@Suite struct TickerFieldsTests {
    private func ticker(_ ticks: Tick...) -> Ticker {
        var t = Ticker(contract: Contract(symbol: "AAPL"))
        for tick in ticks { t.apply(tick) }
        return t
    }

    @Test func namedFieldsReadTheirTicks() {
        let t = ticker(
            .string(TickField(rawValue: 32), "Q"),
            .price(TickField(rawValue: 19), price: 120, size: nil),
            .size(TickField(rawValue: 89), 5000),
            .generic(TickField(rawValue: 24), d("0.31")),
            .efp(TickField(rawValue: 38), EFPData(basisPoints: 1)))
        #expect(t.bidExchange == "Q")
        #expect(t.low52Week == 120)
        #expect(t.shortableShares == 5000)
        #expect(t.impliedVolatility == d("0.31"))
        #expect(t.bidEFP?.basisPoints == 1)
        #expect(t.askExchange == nil && t.high52Week == nil && t.averageVolume == nil)
        #expect(t.histVolatility == nil && t.askEFP == nil && t.auctionPrice == nil)
    }

    @Test func delayedTwinsLandOnTheSameNames() {
        #expect(ticker(.price(TickField(rawValue: 103), price: d("4.5"), size: nil)).bidYield == d("4.5"))
    }

    @Test func genericNamesReadZeroAsNil() {
        #expect(ticker(.generic(.halted, 0)).halted == nil)
        #expect(ticker(.generic(.halted, 1)).halted == 1)
    }

    @Test func marketPriceFollowsIbAsync() {
        func quote(last: Decimal?, bid: Decimal = 10, bidSize: Decimal = 1) -> Ticker {
            var t = ticker(.price(.bid, price: bid, size: bidSize), .price(.ask, price: 11, size: 1))
            if let last { t.apply(.price(.last, price: last, size: 1)) }
            return t
        }
        let inside = quote(last: d("10.5"))
        #expect(inside.hasBidAsk && inside.midpoint == d("10.5") && inside.marketPrice == d("10.5"))
        #expect(quote(last: 12).marketPrice == d("10.5"))
        let noBidSize = quote(last: 12, bidSize: 0)
        #expect(!noBidSize.hasBidAsk && noBidSize.midpoint == nil && noBidSize.marketPrice == 12)
        #expect(!quote(last: 12, bid: -1).hasBidAsk)
        #expect(ticker().marketPrice == nil)
    }
}
