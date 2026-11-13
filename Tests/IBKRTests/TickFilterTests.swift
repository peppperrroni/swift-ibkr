import Foundation
import Testing
@testable import IBKR

private let t0 = Date(timeIntervalSince1970: 1794321000)
private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }
private func tick(_ type: Int, _ price: Decimal?, _ size: Decimal?, _ s: Double = 0) -> TickData {
    TickData(time: at(s), field: TickField(rawValue: type), price: price, size: size)
}
private func ticker(_ ticks: [TickData], bid: Decimal? = nil, ask: Decimal? = nil, time: Date? = t0) -> Ticker {
    Ticker(contract: Contract(symbol: "AAPL"), bid: bid, bidSize: 1, ask: ask, askSize: 1, time: time, ticks: ticks)
}
/// A finished source of the tickers given.
private func source(_ tickers: [Ticker]) -> AsyncStream<Ticker> {
    AsyncStream { c in tickers.forEach { c.yield($0) }; c.finish() }
}
private func all<T: Sendable>(_ stream: AsyncThrowingStream<T, any Error>) async throws -> [T] {
    try await within2s { try await take(0, stream).result.value }
}
private func point(_ price: Decimal, _ size: Decimal, _ s: Double = 0) -> TickPoint {
    TickPoint(time: at(s), price: price, size: size)
}

/// A timer whose dates the test hands in one at a time, and which says each time its consumer asks for the next
/// one: when it asks for date n+1, date n is already in the builder's channel, so no wall clock is involved.
private struct SteppedTimer: AsyncSequence, Sendable {
    typealias Element = Date
    let dates: AsyncStream<Date>
    let pulls: AsyncStream<Void>.Continuation
    struct AsyncIterator: AsyncIteratorProtocol {
        var dates: AsyncStream<Date>.AsyncIterator
        let pulls: AsyncStream<Void>.Continuation
        mutating func next() async -> Date? { pulls.yield(); return await dates.next() }
    }
    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(dates: dates.makeAsyncIterator(), pulls: pulls) }
}

/// `ib_async`'s tick filters and bar builders (ticker.py:302-503) over hand-built ticker streams.
@Suite struct TickFilterTests {
    @Test func tradesFilterKeepsTradeTicksInOrder() async throws {
        let t = ticker([tick(1, 10, 1), tick(4, 11, 2), tick(5, 11, 3), tick(48, 12, 4), tick(8, nil, 100)])
        let got = try await all(source([t]).trades())
        #expect(got == [point(11, 2), point(11, 3), point(12, 4)])
    }

    @Test func tradesSkipANilPriceAndReadANilSizeAsZero() async throws {
        let t = ticker([tick(4, nil, 2), tick(68, 9, nil), tick(71, 9, 1)])
        #expect(try await all(source([t]).trades()) == [point(9, 0), point(9, 1)])
    }

    @Test func bidsAsksAndBidAsksSplit() async throws {
        let t = ticker([tick(0, 1, 5), tick(2, 3, 6), tick(1, 2, 7), tick(3, 4, 8), tick(66, 5, 1), tick(67, 6, 1),
                        tick(69, 7, 1), tick(70, 8, 1), tick(4, 9, 1)])
        #expect(try await all(source([t]).bids()) == [point(1, 5), point(2, 7), point(5, 1), point(7, 1)])
        #expect(try await all(source([t]).asks()) == [point(3, 6), point(4, 8), point(6, 1), point(8, 1)])
        #expect(try await all(source([t]).bidAsks()).map(\.price) == [1, 3, 2, 4, 5, 6, 7, 8])
    }

    @Test func midpointsFollowTickers() async throws {
        let tickers = [
            ticker([tick(1, 10, 1)], bid: 10, ask: 12, time: at(1)),
            ticker([], bid: 10, ask: 14, time: at(2)),
            ticker([tick(2, 16, 1)], bid: 10, ask: 16, time: at(3)),
            ticker([tick(2, nil, 0)], bid: 10, ask: nil, time: at(4)),
        ]
        let got = try await all(source(tickers).midpoints())
        #expect(got == [point(11, 0, 1), point(13, 0, 3)])
    }

    /// ticker.py:452-477.
    @Test func tickBarsCutEveryCount() async throws {
        let points = [point(1, 1, 0), point(3, 1, 1), point(2, 1, 2), point(5, 1, 3)]
        let got = try await all(AsyncThrowingStream { c in points.forEach { c.yield($0) }; c.finish() }
            .tickBars(count: 2))
        let b1 = Bar(time: at(0), open: 1, high: 3, low: 1, close: 3, volume: 2, count: 2)
        let b2 = Bar(time: at(2), open: 2, high: 5, low: 2, close: 5, volume: 2, count: 2)
        #expect(got == [BarList(bars: [b1], hasNewBar: true), BarList(bars: [b1, b2], hasNewBar: true)])
    }

    /// ticker.py:479-503: the bar that reaches the volume completes; the third point alone reaches it again.
    @Test func volumeBarsCutAtVolume() async throws {
        let points = [point(1, 1, 0), point(2, 2, 1), point(3, 3, 2)]
        let got = try await all(AsyncThrowingStream { c in points.forEach { c.yield($0) }; c.finish() }
            .volumeBars(volume: 3))
        let b1 = Bar(time: at(0), open: 1, high: 2, low: 1, close: 2, volume: 3, count: 2)
        let b2 = Bar(time: at(2), open: 3, high: 3, low: 3, close: 3, volume: 3, count: 1)
        #expect(got == [BarList(bars: [b1], hasNewBar: true), BarList(bars: [b1, b2], hasNewBar: true)])
    }

    /// ticker.py:406-450: the first date only opens a bar (a point before it is dropped), a point updates the open
    /// bar, a date closes it, and a bar with no point takes the previous close.
    @Test func timeBarsTakeThePreviousCloseWhenEmpty() async throws {
        let (dates, timerIn) = AsyncStream.makeStream(of: Date.self)
        let (pulls, pulled) = AsyncStream.makeStream(of: Void.self)
        let (points, pointsIn) = AsyncThrowingStream.makeStream(of: TickPoint.self, throwing: (any Error).self)
        let bars = points.timeBars(timer: SteppedTimer(dates: dates, pulls: pulled))
        let got = try await within2s {
            var pull = pulls.makeAsyncIterator()
            var out = bars.makeAsyncIterator()
            var seen: [BarList] = []
            _ = await pull.next()                  // the timer asks for t1
            timerIn.yield(at(10))
            _ = await pull.next()                  // t1 is in the channel
            pointsIn.yield(point(1, 1, 11))
            pointsIn.yield(point(2, 1, 12))
            for _ in 0..<2 { seen.append(try #require(try await out.next())) }
            timerIn.yield(at(20))
            seen.append(try #require(try await out.next()))
            timerIn.yield(at(30))
            seen.append(try #require(try await out.next()))
            return seen
        }
        let b1 = Bar(time: at(10), open: 1, high: 2, low: 1, close: 2, volume: 2, count: 2)
        let b2 = Bar(time: at(20), open: 2, high: 2, low: 2, close: 2, volume: 0, count: 0)
        let forming = Bar(time: at(10), open: 1, high: 1, low: 1, close: 1, volume: 1, count: 1)
        #expect(got == [
            BarList(bars: [forming], hasNewBar: false),
            BarList(bars: [b1], hasNewBar: false),
            BarList(bars: [b1], hasNewBar: true),
            BarList(bars: [b1, b2], hasNewBar: true),
        ])
    }

    /// P0: a point before the first date is dropped, and a bar with neither a point nor a previous close is dropped
    /// without a yield.
    @Test func timeBarsDropWhatHasNoBar() {
        var b = TimeBarBuilder()
        #expect(b.add(point(1, 1)) == nil)
        #expect(b.close(at: at(0)) == nil)
        #expect(b.close(at: at(1)) == nil)
        #expect(b.bars.isEmpty)
        #expect(b.add(point(2, 1, 2)) == BarList(
            bars: [Bar(time: at(1), open: 2, high: 2, low: 2, close: 2, volume: 1, count: 1)], hasNewBar: false))
    }

    @Test func stoppingAFilterStopsItsSource() async throws {
        let (stopped, stop) = AsyncStream.makeStream(of: Void.self)
        let src = AsyncStream<Ticker> { c in
            c.yield(ticker([tick(4, 1, 1)]))
            c.onTermination = { _ in stop.yield() }
        }
        let bars = src.trades().tickBars(count: 1)
        let reader = Task { for try await _ in bars {} }
        let terminated = try await within2s {
            reader.cancel()
            var it = stopped.makeAsyncIterator()
            return await it.next() != nil
        }
        #expect(terminated)
    }
}
