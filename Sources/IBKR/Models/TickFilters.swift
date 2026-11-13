import Foundation

/// One tick as `ib_async`'s tick filters emit it: the time, price and size of a `TickData`, or a ticker's midpoint.
public struct TickPoint: Sendable, Equatable, Encodable {
    /// When the tick's update was folded in.
    public var time: Date
    /// The tick's price.
    public var price: Decimal
    /// The tick's size; `0` where IB sent none, and for a midpoint.
    public var size: Decimal

    /// Creates a point with every field given.
    public init(time: Date, price: Decimal, size: Decimal) {
        self.time = time
        self.price = price
        self.size = size
    }
}

/// What a bar builder yields, `ib_async`'s `BarList` with its `updateEvent(bars, hasNewBar)`: every bar built so
/// far, the forming one last, and whether the last yield completed a bar. `bars` grows without bound for as long as
/// the stream runs, as in `ib_async`.
public struct BarList: Sendable, Equatable, Encodable {
    /// Every bar built so far, oldest first.
    public var bars: [Bar]
    /// `true` when this update completed a bar, `false` when it only moved the forming one.
    public var hasNewBar: Bool

    /// Creates a bar list with every field given.
    public init(bars: [Bar], hasNewBar: Bool) {
        self.bars = bars
        self.hasNewBar = hasNewBar
    }
}

/// `ib_async`'s tick filters (ticker.py:302-385). Each returned stream is unbounded, and stopping it cancels the
/// task reading this sequence, so a `tickers` stream underneath stops and sends its cancels.
extension AsyncSequence where Element == Ticker, Self: Sendable {
    /// The trade ticks (4, 5, 48, 68, 71) of every ticker, in order; a tick without a price is skipped and one
    /// without a size reads 0.
    public func trades() -> AsyncThrowingStream<TickPoint, any Error> { points([4, 5, 48, 68, 71]) }

    /// The bid ticks (0, 1, 66, 69) of every ticker, as `trades()`.
    public func bids() -> AsyncThrowingStream<TickPoint, any Error> { points([0, 1, 66, 69]) }

    /// The ask ticks (2, 3, 67, 70) of every ticker, as `trades()`.
    public func asks() -> AsyncThrowingStream<TickPoint, any Error> { points([2, 3, 67, 70]) }

    /// The bid and ask ticks of every ticker, as `trades()`.
    public func bidAsks() -> AsyncThrowingStream<TickPoint, any Error> { points([0, 1, 66, 69, 2, 3, 67, 70]) }

    /// One point per ticker that brought ticks: its `time` and `midpoint`, size 0; skipped while there is no
    /// midpoint.
    public func midpoints() -> AsyncThrowingStream<TickPoint, any Error> {
        relay(()) { _, t in
            guard !t.ticks.isEmpty, let mid = t.midpoint, let time = t.time ?? t.ticks.last?.time else { return [] }
            return [TickPoint(time: time, price: mid, size: 0)]
        }
    }

    private func points(_ types: Set<Int>) -> AsyncThrowingStream<TickPoint, any Error> {
        relay(()) { _, t in
            t.ticks.compactMap { k in
                guard types.contains(k.field.rawValue), let price = k.price else { return nil }
                return TickPoint(time: k.time, price: price, size: k.size ?? 0)
            }
        }
    }
}

/// `ib_async`'s bar builders (ticker.py:406-503). Bars have `average` `nil` and `count` the number of ticks; every
/// returned stream is unbounded and stopping it stops this one.
extension AsyncThrowingStream where Element == TickPoint, Failure == any Error {
    /// Bars cut by `timer`, `ib_async`'s `timebars`: the first date opens a bar (points before it are dropped), each
    /// point moves the open bar and yields with `hasNewBar` `false`, and each later date closes it and yields with
    /// `true`. A bar that got no point takes the previous bar's close (volume and count 0); one with no previous bar
    /// either is dropped without a yield. Any `AsyncSequence` of `Date` serves as the timer, as any event serves
    /// `ib_async`; the stream ends when the timer or this stream does.
    public func timeBars<Timer: AsyncSequence & Sendable>(timer: Timer) -> AsyncThrowingStream<BarList, any Error>
        where Timer.Element == Date {
        // One channel fed from one task group, so a point never overtakes a date it arrived before.
        let (merged, out) = AsyncThrowingStream<TimeBarInput, any Error>.makeStream()
        let task = Task {
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { for try await p in self { out.yield(.point(p)) } }
                    group.addTask { for try await d in timer { out.yield(.date(d)) } }
                    try await group.next()
                    group.cancelAll()
                }
                out.finish()
            } catch {
                out.finish(throwing: error)
            }
        }
        out.onTermination = { _ in task.cancel() }
        return merged.relay(TimeBarBuilder()) { b, input -> [BarList] in
            switch input {
            case let .point(p): b.add(p).map { [$0] } ?? []
            case let .date(d): b.close(at: d).map { [$0] } ?? []
            }
        }
    }

    /// Bars of `count` points each, `ib_async`'s `tickbars`: yields (with `hasNewBar` `true`) each time a bar
    /// completes.
    public func tickBars(count: Int) -> AsyncThrowingStream<BarList, any Error> {
        relay([Bar]()) { bars, p in Bar.add(p, to: &bars) { $0.count == count } }
    }

    /// Bars that each reach `volume`, `ib_async`'s `volumebars`: yields (with `hasNewBar` `true`) each time a bar's
    /// volume reaches it.
    public func volumeBars(volume: Decimal) -> AsyncThrowingStream<BarList, any Error> {
        relay([Bar]()) { bars, p in Bar.add(p, to: &bars) { $0.volume >= volume } }
    }
}

extension Bar {
    fileprivate init(_ p: TickPoint, time: Date) {
        self.init(time: time, open: p.price, high: p.price, low: p.price, close: p.price, volume: p.size, count: 1)
    }

    fileprivate mutating func add(_ p: TickPoint) {
        high = max(high, p.price)
        low = min(low, p.price)
        close = p.price
        volume += p.size
        count += 1
    }

    /// `TickBars`/`VolumeBars.on_source`: a full last bar starts a new one, and a bar that this point fills yields.
    fileprivate static func add(_ p: TickPoint, to bars: inout [Bar], full: (Bar) -> Bool) -> [BarList] {
        if let last = bars.last, !full(last) { bars[bars.count - 1].add(p) } else { bars.append(Bar(p, time: p.time)) }
        return full(bars[bars.count - 1]) ? [BarList(bars: bars, hasNewBar: true)] : []
    }
}

enum TimeBarInput: Sendable {
    case point(TickPoint)
    case date(Date)
}

/// `TimeBars`' state machine (ticker.py:406-450), apart from its inputs so it can be tested without a clock.
struct TimeBarBuilder: Sendable {
    var bars: [Bar] = []
    /// The date that opened the current bar; `nil` before the first date.
    var opened: Date?
    /// Whether the current bar is `bars.last` (it got a point, or was filled).
    var current = false

    mutating func add(_ p: TickPoint) -> BarList? {
        guard let opened else { return nil }
        if current { bars[bars.count - 1].add(p) } else { bars.append(Bar(p, time: opened)); current = true }
        return BarList(bars: bars, hasNewBar: false)
    }

    mutating func close(at date: Date) -> BarList? {
        let closing = opened
        opened = date
        guard let closing else { return nil }
        if !current, let close = bars.last?.close {
            bars.append(Bar(time: closing, open: close, high: close, low: close, close: close, volume: 0, count: 0))
            current = true
        }
        defer { current = false }
        return current ? BarList(bars: bars, hasNewBar: true) : nil
    }
}

extension AsyncSequence where Self: Sendable {
    /// Reads this sequence in a task into an unbounded stream, through `step` and its `state`; stopping the stream
    /// cancels the task, and so this sequence.
    func relay<State: Sendable, T: Sendable>(
        _ state: State, _ step: @escaping @Sendable (inout State, Element) -> [T]
    ) -> AsyncThrowingStream<T, any Error> {
        let (stream, out) = AsyncThrowingStream.makeStream(of: T.self, throwing: (any Error).self)
        let task = Task {
            var state = state
            do {
                for try await e in self { for t in step(&state, e) { out.yield(t) } }
                out.finish()
            } catch {
                out.finish(throwing: error)
            }
        }
        out.onTermination = { _ in task.cancel() }
        return stream
    }
}
