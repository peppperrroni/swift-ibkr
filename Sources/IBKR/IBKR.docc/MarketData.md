# Market Data

Quotes, tickers, bars, depth and history, and what happens without a subscription.

## Without a subscription

Every feed is a stream for one request: stopping it sends the cancel. When IB refuses a feed for want of a data
subscription, the stream ends with ``IBClientError/noMarketDataPermission(code:text:)``, so a UI can tell "not
subscribed" from a real failure.

Without a subscription ask for delayed data with ``IBClient/setMarketDataType(_:)``. It is not kept across
reconnects, so set it after every connect:

```swift
try await client.setMarketDataType(.delayed)
```

## Quotes and tickers

``IBClient/marketData(_:genericTicks:snapshot:regulatorySnapshot:options:)`` streams raw ``Tick`` values.
`genericTicks` adds IB's generic ticks: numbers (`[233]`) or tagged entries (`["mdoff", "292:BRFG"]` for news);
`snapshot: true` ends the stream at tickSnapshotEnd, with no cancel.

``IBClient/tickers(_:genericTicks:depthRows:smartDepth:tickByTick:options:)`` yields a whole ``Ticker`` after every
update, built with its two `apply(_:at:)` methods (one for a ``Tick``, one for a ``TickByTick``); `depthRows` adds the
book and `tickByTick` IB's tick-by-tick events. Each element carries the arrival `time` and what its update brought in
`ticks`, `tickByTicks` and `domTicks`; a slow consumer gets the newest ticker with the lists of every update it skipped,
so no tick is lost or seen twice. ``IBClient/tickers(for:regulatorySnapshot:)`` takes snapshots of many contracts at
once, in input order; the first error is thrown and the rest cancelled.

As `ib_async`'s accessors, ``IBClient/ticker(for:)`` and ``IBClient/activeTickers()`` read the latest ``Ticker`` of
every open `tickers` stream, ``IBClient/pendingTickers()`` streams each one it changes, and
``IBClient/newsTicks()`` and ``IBClient/receivedBulletins()`` keep every news tick and bulletin since the last
manual connect.

```swift
// Quotes. Without a subscription ask for delayed data; it is not kept across reconnects, so set it after connect.
try await client.setMarketDataType(.delayed)
Task { for try await tick in try await client.marketData(aapl) { print(tick) } }

// A whole Ticker (bid/ask/last, OHLC, greeks, the rest keyed by field) after every update; depthRows adds the book.
Task { for try await t in try await client.tickers(aapl, depthRows: 5) { print(t.bid as Any, t.depth.bids.first as Any) } }
// Snapshots of many contracts at once, in input order; the first error is thrown and the rest cancelled.
let snaps = try await client.tickers(for: [aapl, msft])
// The latest ticker of an open tickers stream, matched by conID as ib_async does.
let latest = await client.ticker(for: aapl)
```

Delayed ticks carry their own field numbers; `TickField.live` maps each one to its real-time counterpart.

## Bars, depth and tick-by-tick

``IBClient/realTimeBars(_:whatToShow:rth:options:)`` yields 5-second ``Bar`` values (the only size IB allows).
``IBClient/marketDepth(_:rows:smart:options:)`` yields the whole ``DepthBook`` after every update, and
``IBClient/tickByTick(_:_:count:ignoreSize:)`` yields every trade, quote or midpoint as it happens.

```swift
// Real-time bars (5 seconds, the only size IB allows), as `Bar`.
Task { for try await bar in try await client.realTimeBars(aapl) { print(bar.close) } }

// The depth book, whole after every update (bids and asks sorted by position); IB's reset (317) empties it.
Task { for try await book in try await client.marketDepth(aapl, rows: 10) { print(book.bids.first as Any) } }

// Tick-by-tick: every trade (.allLast / .last), quote (.bidAsk) or midpoint as it happens.
Task { for try await t in try await client.tickByTick(aapl, .allLast) { print(t) } }
```

Without depth permissions IB sends notice 2152 and then nothing; when the text names no `Depth:` exchange the depth
stream ends with a permission error and sends its cancel.

## History

``IBClient/historicalBars(_:end:duration:barSize:whatToShow:rth:keepUpToDate:options:)`` yields one `.history` batch and ends,
unless `keepUpToDate`, which goes on with `.update` bars;
``IBClient/liveHistoricalBars(_:duration:barSize:whatToShow:rth:options:)`` folds those updates into a whole
``BarList`` as `ib_async` does, and ``IBClient/liveBarSubscriptions()`` and ``IBClient/barUpdates()`` follow every
live bar subscription. IB's bust event (10225) resends a live bar request under the same id. ``IBClient/historicalTicks(_:start:end:count:whatToShow:rth:ignoreSize:options:)``,
``IBClient/headTimeStamp(_:whatToShow:rth:)``, ``IBClient/histogramData(_:period:rth:)`` and
``IBClient/historicalSchedule(_:days:end:rth:)`` are one-shot calls. `Bar.time` is in epoch seconds, and daily bars
are stamped 00:00 UTC of their day.

```swift
// Bars: one .history batch, then the stream ends, unless keepUpToDate, which goes on with .update bars.
for try await event in try await client.historicalBars(aapl, duration: "1 D", barSize: "5 mins") {
    if case .history(let bars) = event { print(bars.count) }
}
let ticks = try await client.historicalTicks(aapl, start: from, count: 1000)   // [TickByTick]; whatToShow "TRADES", "BID_ASK" or "MIDPOINT"
let first = try await client.headTimeStamp(aapl)                               // Date of the earliest data
let hist = try await client.histogramData(aapl, period: "1 week")              // [HistogramData] (price, count)
let sched = try await client.historicalSchedule(aapl, days: 5)                 // HistoricalSchedule, IB's raw strings and time zone
```

## Stopping a stream

Leaving a `for try await` loop, or cancelling the task that runs it, sends IB's cancel for that request. There is no
separate cancel call.
