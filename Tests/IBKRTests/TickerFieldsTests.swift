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
        #expect(quote(last: 10).marketPrice == 10 && quote(last: 11).marketPrice == 11, "bid <= last <= ask")
    }

    // The ids as ib_async's PRICE/SIZE/GENERIC/STRING/EFP_TICK_MAP list them (wrapper.py:82-185), typed from there.
    private static var strings: [(Int, KeyPath<Ticker, String?>)] { [
        (25, \.optionBidExchange), (26, \.optionAskExchange), (32, \.bidExchange), (33, \.askExchange),
        (84, \.lastExchange), (85, \.lastRegTime), (91, \.reutersMutualFunds), (100, \.socialMarketAnalytics),
    ] }
    private static var prices: [(Int, KeyPath<Ticker, Decimal?>)] { [
        (15, \.low13Week), (16, \.high13Week), (17, \.low26Week), (18, \.high26Week), (19, \.low52Week),
        (20, \.high52Week), (35, \.auctionPrice), (37, \.markPrice), (50, \.bidYield), (103, \.bidYield),
        (51, \.askYield), (104, \.askYield), (52, \.lastYield), (57, \.lastRTHTrade), (78, \.creditmanMarkPrice),
        (79, \.creditmanSlowMarkPrice), (92, \.etfNavClose), (93, \.etfNavPriorClose), (94, \.etfNavBid),
        (95, \.etfNavAsk), (96, \.etfNavLast), (97, \.etfFrozenNavLast), (98, \.etfNavHigh), (99, \.etfNavLow),
        (101, \.estimatedIPOMidpoint), (102, \.finalIPOLast),
    ] }
    private static var sizes: [(Int, KeyPath<Ticker, Decimal?>)] { [
        (63, \.volumeRate3Min), (64, \.volumeRate5Min), (65, \.volumeRate10Min), (21, \.averageVolume),
        (22, \.openInterest), (27, \.callOpenInterest), (28, \.putOpenInterest), (29, \.callVolume),
        (30, \.putVolume), (34, \.auctionVolume), (36, \.auctionImbalance), (61, \.regulatoryImbalance),
        (86, \.futuresOpenInterest), (87, \.averageOptionVolume), (89, \.shortableShares),
    ] }
    private static var generics: [(Int, KeyPath<Ticker, Decimal?>)] { [
        (23, \.histVolatility), (24, \.impliedVolatility), (31, \.indexFuturePremium), (46, \.shortable),
        (49, \.halted), (54, \.tradeCount), (55, \.tradeRate), (56, \.volumeRate), (58, \.rtHistVolatility),
        (60, \.bondFactorMultiplier), (90, \.delayedHalted),
    ] }
    private static var efps: [(Int, KeyPath<Ticker, EFPData?>)] { [
        (38, \.bidEFP), (39, \.askEFP), (40, \.lastEFP), (41, \.openEFP), (42, \.highEFP), (43, \.lowEFP),
        (44, \.closeEFP),
    ] }

    /// Each id sets its own name and no other name of its kind.
    @Test func everyNamedTickReadsItsID() {
        func check<V: Equatable>(_ table: [(Int, KeyPath<Ticker, V?>)], _ value: V, _ tick: (TickField, V) -> Tick) {
            for (id, name) in table {
                let t = ticker(tick(TickField(rawValue: id), value))
                #expect(t[keyPath: name] == value, "tick \(id)")
                for (other, otherName) in table where otherName != name {
                    #expect(t[keyPath: otherName] == nil, "tick \(id) also set the name of \(other)")
                }
            }
        }
        check(Self.strings, "X") { .string($0, $1) }
        check(Self.prices, d("1.5")) { .price($0, price: $1, size: nil) }
        check(Self.sizes, 7) { .size($0, $1) }
        check(Self.generics, d("0.25")) { .generic($0, $1) }
        check(Self.efps, EFPData(basisPoints: 2)) { .efp($0, $1) }
    }
}
