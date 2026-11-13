import Foundation
import Testing
@testable import IBKR

private let t0 = Date(timeIntervalSince1970: 1794321000)
private func aaplTicker() -> Ticker { Ticker(contract: Contract(symbol: "AAPL")) }

/// The stateful fields `ib_async`'s wrapper keeps on a ticker: `prev…`, RT volume, dividends, ratios and the
/// per-update lists.
@Suite struct TickerStateTests {
    /// wrapper.py:1000-1034, 1068, 1093.
    @Test func prevFieldsKeepTheValueBefore() {
        var t = aaplTicker()
        t.apply(.price(.bid, price: 10, size: 1), at: t0)
        t.apply(.price(.bid, price: 11, size: 2), at: t0)
        #expect(t.prevBid == 10 && t.bid == 11 && t.prevBidSize == 1 && t.bidSize == 2)
        t.apply(.price(.ask, price: 12, size: 1), at: t0)
        t.apply(.price(.ask, price: 13, size: 2), at: t0)
        #expect(t.prevAsk == 12 && t.ask == 13 && t.prevAskSize == 1 && t.askSize == 2)
        t.apply(.price(.last, price: 10, size: 5), at: t0)
        t.apply(.price(.last, price: 11, size: 6), at: t0)
        #expect(t.prevLast == 10 && t.last == 11 && t.prevLastSize == 5 && t.lastSize == 6)
        t.apply(.size(.bidSize, 7), at: t0)
        #expect(t.prevBidSize == 2 && t.bidSize == 7 && t.prevBid == 10)
        t.apply(.size(.lastSize, 9), at: t0)
        #expect(t.prevLastSize == 6 && t.lastSize == 9)
    }

    /// wrapper.py:482-511, with R5: RT volume never moves `last`.
    @Test func rtVolumeParsesWithoutMovingLast() throws {
        var t = aaplTicker()
        let raw = "701.28;1;1348075471534;67854;701.46918464;true"
        t.apply(.string(TickField(rawValue: 48), raw), at: t0)
        #expect(t.rtVolume == 67854)
        #expect(t.vwap == d("701.46918464"))
        let rtTime = try #require(t.rtTime)
        #expect(abs(rtTime.timeIntervalSince1970 - 1348075471.534) < 0.001)
        #expect(t.last == nil && t.lastSize == nil && t.prevLast == nil)
        #expect(t.strings[TickField(rawValue: 48)] == raw)
        #expect(t.ticks == [TickData(time: t0, field: TickField(rawValue: 48), price: d("701.28"), size: 1)])
        t.apply(.string(TickField(rawValue: 77), "701.30;2;1348075471600;12;701.5;true"), at: t0)
        #expect(t.rtTradeVolume == 12 && t.rtVolume == 67854)
        t.ticks = []
        t.apply(.string(TickField(rawValue: 48), ";;1348075471534;67854;;true"), at: t0)
        #expect(t.ticks.isEmpty)
        t.apply(.string(TickField(rawValue: 48), "garbage"), at: t0)   // a parse failure changes nothing parsed
        #expect(t.rtVolume == 67854 && t.ticks.isEmpty && t.strings[TickField(rawValue: 48)] == "garbage")
    }

    /// wrapper.py:1233-1243.
    @Test func dividendsParse() {
        var t = aaplTicker()
        t.apply(.string(TickField(rawValue: 59), "0.83,0.92,20130219,0.23"), at: t0)
        #expect(t.dividends == Dividends(past12Months: d("0.83"), next12Months: d("0.92"),
                                         nextDate: Date(timeIntervalSince1970: 1361232000), nextAmount: d("0.23")))
        t.apply(.string(TickField(rawValue: 59), ",,,"), at: t0)
        #expect(t.dividends == Dividends())
        t.apply(.string(TickField(rawValue: 59), "x,1"), at: t0)
        #expect(t.dividends == Dividends())
    }

    /// wrapper.py:1208-1221.
    @Test func fundamentalRatiosKeepTextAndReadNumbers() throws {
        var t = aaplTicker()
        t.apply(.string(TickField(rawValue: 47), "CURRENCY=USD;MKTCAP=3000000.5;NPRICE=-99999.99;"), at: t0)
        let r = try #require(t.fundamentalRatios)
        #expect(r["CURRENCY"] == "USD")
        #expect(r.decimal("MKTCAP") == d("3000000.5"))
        #expect(r.decimal("NPRICE") == nil)
        #expect(r.decimal("CURRENCY") == nil)
        #expect(r.decimal("ABSENT") == nil)
        t.apply(.string(TickField(rawValue: 47), "A=1;B"), at: t0)
        #expect(t.fundamentalRatios == r)
    }

    /// wrapper.py:187: tick 88 has a field of its own.
    @Test func delayedLastTimestampStaysApart() {
        var t = aaplTicker()
        t.apply(.string(TickField(rawValue: 88), "1794321000"), at: t0)
        #expect(t.delayedLastTimestamp == t0)
        #expect(t.lastTimestamp == nil)
    }

    /// wrapper.py:1046, 1103, 1262.
    @Test func ticksRecordWhatIbAsyncRecords() {
        var t = aaplTicker()
        t.apply(.price(.bid, price: 10, size: 100), at: t0)
        #expect(t.ticks == [TickData(time: t0, field: .bid, price: 10, size: 100)])
        t.ticks = []
        t.apply(.size(.lastSize, 5), at: t0)
        #expect(t.ticks.isEmpty)
        t.apply(.price(.last, price: 12, size: 3), at: t0)
        t.ticks = []
        t.apply(.size(.lastSize, 5), at: t0)
        #expect(t.ticks == [TickData(time: t0, field: .lastSize, price: 12, size: 5)])
        t.ticks = []
        t.apply(.generic(TickField(rawValue: 24), d("0.3")), at: t0)
        #expect(t.ticks == [TickData(time: t0, field: TickField(rawValue: 24), price: d("0.3"), size: 0)])
        t.ticks = []
        t.apply(.price(TickField(rawValue: 68), price: 13, size: 1), at: t0)
        #expect(t.ticks == [TickData(time: t0, field: TickField(rawValue: 68), price: 13, size: 1)])
    }

    /// wrapper.py:1111-1195.
    @Test func tickByTickFoldsLikeIbAsync() {
        var t = aaplTicker()
        let trade = TickByTick.trade(time: t0, price: 10, size: 5, exchange: "X", conditions: "", pastLimit: false,
                                     unreported: false)
        let empty = TickByTick.trade(time: t0, price: -1, size: 0, exchange: "X", conditions: "", pastLimit: false,
                                     unreported: false)
        let quote = TickByTick.bidAsk(time: t0, bidPrice: 9, askPrice: 11, bidSize: 1, askSize: 0)
        let quote2 = TickByTick.bidAsk(time: t0, bidPrice: 9, askPrice: 12, bidSize: 1, askSize: 2)
        let mid = TickByTick.midPoint(time: t0, price: d("10.5"))
        t.apply(trade, at: t0)
        #expect(t.last == 10 && t.lastSize == 5 && t.prevLast == nil)
        t.apply(empty, at: t0)
        #expect(t.last == nil && t.lastSize == nil && t.prevLast == 10 && t.prevLastSize == 5)
        t.apply(quote, at: t0)
        #expect(t.bid == 9 && t.bidSize == 1 && t.ask == 11 && t.askSize == nil)
        t.apply(quote2, at: t0)
        #expect(t.bid == 9 && t.prevAsk == 11 && t.ask == 12 && t.askSize == 2)
        var before = t
        t.apply(mid, at: t0)
        before.tickByTicks.append(mid)
        #expect(t == before)
        #expect(t.tickByTicks == [trade, empty, quote, quote2, mid])
    }

    /// The `tickers` mailbox: a skipped ticker's lists go on to the next one taken, each exactly once.
    @Test func mailboxMergesWhatTheConsumerSkipped() async throws {
        struct Boom: Error {}
        let box = TickerMailbox(readers: [])
        func update(_ price: Decimal) -> Ticker {
            var t = aaplTicker()
            t.apply(.price(.last, price: price, size: 1), at: t0)
            return t
        }
        box.put(update(10))
        box.put(update(11))
        let first = try #require(try await box.next())
        #expect(first.last == 11 && first.ticks.map(\.price) == [10, 11])
        box.put(update(12))
        box.finish(throwing: Boom())
        #expect(try await box.next()?.ticks.map(\.price) == [12])
        await #expect(throws: Boom.self) { _ = try await box.next() }
        #expect(try await box.next() == nil)
    }

    /// A second task iterating the same stream ends at once instead of stranding the first one's wait.
    @Test func mailboxSecondIteratorEndsInsteadOfStrandingTheFirst() async throws {
        let box = TickerMailbox(readers: [])
        let stream = box.stream()
        let readers = (0..<2).map { _ in
            Task { var n = 0; for try await _ in stream { n += 1 }; return n }
        }
        try await Task.sleep(for: .milliseconds(100))   // both wait in next()
        box.put(aaplTicker())
        box.finish(throwing: nil)
        var taken = 0
        for r in readers { taken += try await within2s { try await r.value } }
        #expect(taken == 1)
    }

    @Test func depthBookByPosition() {
        var b = DepthBook()
        b.apply(DepthUpdate(position: 0, marketMaker: "", operation: .insert, side: .bid, price: 10, size: 1))
        b.apply(DepthUpdate(position: 2, marketMaker: "", operation: .insert, side: .bid, price: 9, size: 1))
        #expect(b.bidsByPosition.keys.sorted() == [0, 2])
        #expect(b.asksByPosition.isEmpty)
    }
}
