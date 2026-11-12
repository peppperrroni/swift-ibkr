# swift-ibkr

[![CI](https://github.com/peppperrroni/swift-ibkr/actions/workflows/ci.yml/badge.svg)](https://github.com/peppperrroni/swift-ibkr/actions/workflows/ci.yml)

A pure-Swift client for **Interactive Brokers' IB Gateway and TWS**, speaking the TWS API socket protocol
directly. One actor, async streams, no dependencies, and it runs on **macOS, iOS, Linux and Windows**.

```swift
import IBKR

let client = IBClient()
try await client.connect(port: 4002, clientID: 7)          // paper IB Gateway

let id = try await client.placeOrder(Contract(symbol: "AAPL"),
                                     Order(action: .buy, quantity: 1, orderType: "LMT", limitPrice: 180))
for await order in await client.orders().updates where order.orderID == id {
    print(order.status)                                     // Submitted, Filled, Cancelled ...
}
```

> **Not affiliated with Interactive Brokers.** This library places real orders when you point it at a live
> account. Try everything on a paper account first. The software comes with no warranty (see [LICENSE](LICENSE)).

## Why

- **Pure Swift, no dependencies.** It does not wrap IB's official client, and it contains none of IB's code.
  The wire layouts follow the open-source [ib_async](https://github.com/ib-api-reloaded/ib_async) and are
  written down in [`docs/protocol-178.md`](docs/protocol-178.md).
- **Swift concurrency all the way.** `IBClient` is an actor. Every feed is an `AsyncStream`, or an
  `AsyncThrowingStream` when IB can refuse it, and errors are typed (`throws(IBClientError)`).
- **Whole objects, not message soup.** IB reports an order in several pieces: openOrder, orderStatus and
  completedOrder. A fill arrives as execDetails plus a commission report, and IB resends and corrects them. The
  library merges these and publishes only whole orders and fills, and only when something actually changed.
- **Snapshot plus stream.** `orders()`, `executions()` and `positions()` return the current state together with
  a stream of changes, so a late subscriber never misses the past.
- **Checked on the real gateway.** The frames of live paper-account runs are recorded in
  `Tests/IBKRTests/Recorded/` and replayed by the unit tests.

## Status

The protocol is pinned to **server version 178**, which has one field layout and no protobuf (protobuf starts at
201). The client offers it in the handshake, and current gateways agree to it.

| Area | What you get | State |
|---|---|---|
| Connection | handshake, request throttle, `states()`, the raw `messages()` feed | ✅ live-checked |
| Orders | place, modify, cancel, every placeOrder field (conditions, algos, pegged, combos, delta neutral), brackets, OCA, what-if, exercise, open and completed orders merged | ✅ plain orders live-checked; the rest on hand-built frames, a live run is due in stage 13 |
| Executions | fills joined with commissions, corrections applied | ✅ live-checked |
| Positions | synced at connect, whole sets on every change | ✅ live-checked |
| Session | current time, accounts, next id, user info, log level, auto-bind, global cancel, opt-in reconnect | ✅ on the fake gateway; a live run is due in stage 13 |
| Account | account summary, per-position P&L, portfolio, account values, Multi, account P&L | ✅ summary and per-position P&L live-checked; the rest on the fake gateway, a live run is due in stage 13 |
| Contract lookup | contract details, matching symbols, qualification, option chains, option calculations, market rules, family codes, soft-dollar tiers | ✅ details and symbols live-checked; qualification, option chains, option calculations, market rules, family codes and soft-dollar tiers on the fake gateway, a live run is due in stage 13 |
| Market data | quotes with generic ticks and snapshots, `Ticker` streams and batch snapshots, greeks, EFP, news ticks, real-time bars, depth book, depth exchanges, SMART components, tick-by-tick, BAG, typed «no permission» refusal | ✅ refusals live-checked; the data only on hand-built frames (no subscription yet) |
| History | bars with keepUpToDate, historical ticks, head timestamp, histogram, trading schedule, BAG | ✅ refusals live-checked; the data only on hand-built frames (no subscription yet) |
| Scanner | scan stream, one-shot scan, scanner parameters | ✅ on the fake gateway; a live run is due in stage 13 |
| News | providers, article text, historical headlines | ✅ on the fake gateway; a live run is due in stage 13 |

What is still unconfirmed against a live gateway is listed in [`docs/KNOWN-GAPS.md`](docs/KNOWN-GAPS.md).
There are no tagged releases yet, and the API may still change.

## Installation

**Requirements**

- Swift 6.0 or later.
- macOS 13+, iOS 16+, Linux or Windows. CI tests macOS, Linux (Swift 6.0 and the latest) and Windows on every
  push and builds for iOS; what it leaves out is in [`docs/KNOWN-GAPS.md`](docs/KNOWN-GAPS.md).
- IB Gateway or TWS running, with *Enable ActiveX and Socket Clients* switched on. To place orders, also switch
  *Read-Only API* off.

Add the package with Swift Package Manager:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/peppperrroni/swift-ibkr.git", branch: "main"),
],
targets: [
    .target(name: "MyApp", dependencies: [.product(name: "IBKR", package: "swift-ibkr")]),
]
```

Or with CocoaPods:

```ruby
pod 'SwiftIBKR', :git => 'https://github.com/peppperrroni/swift-ibkr.git', :tag => '<version>'
```

The module is still `IBKR`, so `import IBKR` is the same under both. Publication to the CocoaPods trunk is pending.

These are the default ports:

| | Paper | Live |
|---|---|---|
| IB Gateway | 4002 | 4001 |
| TWS | 7497 | 7496 |

## Guide

### Connecting

```swift
let client = IBClient()
Task { for await state in await client.states() { print(state) } }        // current state first
Task { for await message in await client.messages() { print(message) } }  // every decoded frame

try await client.connect(port: 4002, clientID: 7)   // host 127.0.0.1, 10 s timeout by default
// ...
await client.disconnect()
```

- **When `connect` returns.** It returns once the handshake is done and the open orders, completed orders,
  executions, positions, portfolio and account values are all synced. One timeout covers all of that.
- **Accounts.** With one managed account, `connect` subscribes to its account updates (portfolio and values). With
  several, it subscribes to each account's values only, and `portfolio()` stays empty: use `positions()`. Each
  connect drops the values of accounts the login no longer manages, and with several accounts the portfolio too.
- **What it throws.** On failure it throws an `IBClientError`:
  - `.timeout`;
  - `.connectionClosed`;
  - `.ib(code:text:)` when the gateway refuses, for example 326 «client id already in use»;
  - `.cancelled` when the calling task is cancelled; the state turns `.disconnected(.cancelled)`.
- **Streams.** Every call to `states()` or `messages()` hands out a fresh stream, so any number of consumers
  can listen.
- **Reconnect is opt-in.** Without a policy, a lost connection turns the state to `.disconnected(error)` and
  nothing reconnects for you: call `connect` again. With one, a connection that was up and then dropped
  publishes `.disconnected(error)`, then `.connecting`, and is retried until it is back, `maxAttempts` run out
  (`.disconnected(lastError)`), or you call `disconnect()`:

  ```swift
  // pauses of 1, 2, 5, 10, 30 s (the last repeats), no attempt limit, a reqCurrentTime probe after 30 s of silence
  try await client.connect(port: 4002, clientID: 7, reconnect: ReconnectPolicy())
  ```

  A first `connect` that fails is not retried, and `connect` throws `.alreadyConnected` while attempts run. After
  `probeAfter` with no incoming frame the client asks IB the time; if as long again passes with nothing, it drops
  the connection with `.timeout` and reconnects. A reconnect resends only the sync: request streams end at the drop,
  and `setMarketDataType` must be set again.
- **Across a reconnect.** Subscribers of `orders()`, `executions()`, `positions()`, `portfolio()` and
  `accountValues()` stay subscribed, and their snapshots keep the last known state while it retries. Per-request
  streams such as `accountSummary` and `pnlSingle` end with the connection's error instead, so subscribe to them
  again.
- **What `disconnect()` does.** From `.connected` it sends cancelPositions behind every request already queued
  (an order placed just before still goes out), then closes the socket, within 2 s at the latest. The state turns
  `.disconnected(nil)` and per-request streams end at once.
- **Always call `disconnect()`** when you are done. A connected client is kept alive by its reader and writer
  tasks, and its streams never finish on their own.

### Orders

`placeOrder` returns the order id as soon as the frame is queued. The outcome arrives through `orders()`.
`orderType` and `tif` stay IB's own strings (`"LMT"`, `"STP"`, `"DAY"`, `"GTC"` and so on), so an order type IB adds
needs no library change.

```swift
let (known, updates) = await client.orders()     // snapshot now, then every change as a whole order
Task { for await order in updates { print(order.orderID, order.status, order.filled) } }

let aapl = Contract(symbol: "AAPL")              // stock, SMART routing, USD by default
let call = Contract.option("AAPL", lastTradeDateOrContractMonth: "20261218", strike: 200, right: "C",
                           exchange: "SMART", currency: "USD")   // also .stock .future .forex("EURUSD") .index .bag ...; ib_async's defaults ("" exchange and currency)
let id = try await client.placeOrder(aapl, .limit(.buy, quantity: 1, price: 180))
try await client.modifyOrder(id, aapl, .limit(.buy, quantity: 1, price: 181))
try await client.cancelOrder(id)                 // cancelOrder(id, manualCancelOrderTime: "20261112-15:00:00") records a hand cancel
```

`Order.market`, `.limit`, `.stop` and `.stopLimit` build the common orders. `placeBracket` places an entry with a
take-profit and a stop-loss: it links the children to the parent and transmits the group with the last leg. If any
leg fails to encode, nothing is sent.

```swift
let bracket = Order.bracket(.buy, quantity: 100, limitPrice: 180, takeProfitPrice: 190, stopLossPrice: 175)
let ids = try await client.placeBracket(aapl, bracket)      // (parent:, takeProfit:, stopLoss:)

let exits = Order.oneCancelsAll([.limit(.sell, quantity: 100, price: 190), .stop(.sell, quantity: 100, stopPrice: 175)],
                                group: "exit", type: 1)   // IB cancels the other when one fills
```

Every other `placeOrder` field is a property of `Order` and `Contract`: conditions, algos, pegged orders, combos,
delta-neutral, scale, hedge and so on.

```swift
var order = Order.limit(.buy, quantity: 100, price: 180)
order.conditions = [.price(conID: 265598, exchange: "SMART", isMore: true, price: 185)]   // only once AAPL trades above 185
order.conditionsCancelOrder = false                                                       // true cancels instead of submitting

var twap = Order.limit(.buy, quantity: 1000, price: 180)
twap.algoStrategy = "Twap"
twap.algoParams = [TagValue(tag: "startTime", value: "09:30:00 US/Eastern")]
```

`try await client.whatIfOrder(aapl, order)` returns IB's margin and commission for an order without placing it, as
an `OrderState`. To exercise or lapse an option:

```swift
var option = call; option.multiplier = "100"
try await client.exerciseOptions(option, action: .exercise, quantity: 1, account: "DU0000001")
```

Outgoing text must be printable ASCII. This is the same rule as IB's own client, and anything else throws
`IBEncodingError.nonASCII(field:)`.

### Executions, positions and portfolio

```swift
let (fills, fillUpdates) = await client.executions()   // a fill is published once its commission is in
let (positions, changes) = await client.positions()    // always on: the whole set after every change
Task { for await set in changes { print(set.map { "\($0.contract.symbol) \($0.quantity)" }) } }

let (items, itemSets) = await client.portfolio()       // always on, one account only: whole sets, with market value
let (values, valueChanges) = await client.accountValues()   // always on: each changed tag, e.g. NetLiquidation
Task { for await v in valueChanges where v.tag == "NetLiquidation" { print(v.account, v.value, v.currency) } }
```

### Account summary and P&L

Each call opens one subscription. The subscription ends when the consumer stops (the library then sends the
cancel), when IB reports an error for it, or when the connection ends. IB allows two account summaries at a
time, and a third throws `.ib(code: 322, ...)`.

```swift
Task {
    for try await set in try await client.accountSummary(tags: ["NetLiquidation", "BuyingPower"]) {
        print(set.map { "\($0.tag) \($0.value) \($0.currency)" })   // value is IB's string
    }
}
Task {
    for try await pnl in try await client.pnlSingle(account: "DU1234567", conID: 265598) {
        print(pnl.daily as Any, pnl.unrealized as Any)
    }
}
```

`accountUpdatesMulti(account:modelCode:ledgerAndNLV:)` and `positionsMulti(account:modelCode:)` stream the whole set at
IB's end marker and again on every change; `pnl(account:modelCode:)` streams each account P&L update. They use their
own request ids, so they do not feed `accountValues()` or `portfolio()`.

### Session

```swift
let now = try await client.currentTime()           // IB's clock, as a Date
let accounts = try await client.managedAccounts()  // [String]
let next = try await client.nextOrderID()          // what the next placeOrder takes; not consumed
let branding = try await client.userInfo()         // whiteBrandingId, "" for most accounts
try await client.setServerLogLevel(.detail)        // the gateway's own log
try await client.setAutoOpenOrders(true)           // bind other clients' orders (clientId 0 only)
try await client.cancelAllOrders()                 // the outcome arrives through orders()
```

The first four wait like the contract lookups below: they throw the connection's error when it ends and
`.cancelled` when the calling task is cancelled. All seven throw `.notConnected` before `connect`.

### Contract lookup

One-shot calls wait for IB's whole answer. They throw `.ib(code: 200, ...)` when nothing matches, the
connection's error when it drops, and `.cancelled` when the calling task is cancelled.

```swift
let details = try await client.contractDetails(Contract(symbol: "AAPL"))   // [ContractDetails]: conID, minTick, hours, marketRuleIDs, secIDList ...; bonds (Contract.bond) come back the same way
let matches = try await client.matchingSymbols("AAP")                      // [ContractDescription]
let checked = try await client.qualifyContracts([.stock("AAPL", exchange: "SMART", currency: "USD")])
// [ContractQualification], one per input: .qualified(Contract), .ambiguous([Contract]) or .notFound
var aapl = Contract.stock("AAPL", exchange: "SMART", currency: "USD"); aapl.conID = 265598
let chains = try await client.optionChains(for: aapl)       // [OptionChain]: exchange, tradingClass, multiplier, expirations, strikes
let call = Contract.option("AAPL", lastTradeDateOrContractMonth: "20261218", strike: 200, right: "C", exchange: "SMART", currency: "USD")
let iv = try await client.calculateImpliedVolatility(call, optionPrice: 6.5, underPrice: 187.25)  // OptionComputation
let price = try await client.calculateOptionPrice(call, volatility: 0.25, underPrice: 187.25)     // OptionComputation
let steps = try await client.marketRule(details[0].marketRuleIDs[0])       // [PriceIncrement]: lowEdge, increment
let codes = try await client.familyCodes()                                 // [FamilyCode]: accountID, familyCodeStr
let tiers = try await client.softDollarTiers()                             // [SoftDollarTier]
```

`qualifyContracts` sends every lookup at once. IB's 200 is `.notFound` rather than an error. With several matches,
only those of the input's secType count; one left is `.qualified` (keeping `SMART`), otherwise `.ambiguous` lists
them, possibly none. Any other error throws, and a `BAG` is refused before anything is sent.

`optionChains(for:futFopExchange:)` needs the underlying's `conID` (qualify it first). It returns one `OptionChain` per
exchange and trading class once IB's end marker arrives; IB has no cancel for it.

`calculateImpliedVolatility` and `calculateOptionPrice` return IB's first computation (volatility, greeks, price) and
then send IB's cancel. Without a data subscription they throw `.noMarketDataPermission`, like `marketData`.

### Market data

Every feed below is a stream for one request: stopping it sends the cancel. When IB refuses it for want of a
data subscription, the stream ends with `.noMarketDataPermission(code:text:)`, so a UI can tell «not subscribed»
from a real failure.

```swift
// Quotes. Without a subscription ask for delayed data; it is not kept across reconnects, so set it after connect.
try await client.setMarketDataType(.delayed)
Task { for try await tick in try await client.marketData(aapl) { print(tick) } }
// genericTicks: [Int] adds IB's generic tick types (e.g. [233]); snapshot: true ends the stream at tickSnapshotEnd, no cancel.
// .price, .size, .generic, .string, .dataType, .optionComputation, .efp, .requestParameters, .news

// A whole Ticker (bid/ask/last, OHLC, greeks, the rest keyed by field) after every update; depthRows adds the book.
Task { for try await t in try await client.tickers(aapl, depthRows: 5) { print(t.bid as Any, t.depth.bids.first as Any) } }
// Snapshots of many contracts at once, in input order; the first error is thrown and the rest cancelled.
let snaps = try await client.tickers(for: [aapl, msft])

// Real-time bars (5 seconds, the only size IB allows), as `Bar`.
Task { for try await bar in try await client.realTimeBars(aapl) { print(bar.close) } }

// The depth book, whole after every update (bids and asks sorted by position); IB's reset (317) empties it.
Task { for try await book in try await client.marketDepth(aapl, rows: 10) { print(book.bids.first as Any) } }
let venues = try await client.depthExchanges()          // [DepthMarketDataDescription]
let parts = try await client.smartComponents("a6")      // [SmartComponent], by the bboExchange from a quote

// Tick-by-tick: every trade (.allLast / .last), quote (.bidAsk) or midpoint as it happens.
Task { for try await t in try await client.tickByTick(aapl, .allLast) { print(t) } }
```

A BAG (combo) contract is accepted by `marketData` (so by `tickers` without `depthRows`, and by `tickers(for:)`), by historical bars and by
the schedule. Real-time bars, depth, tick-by-tick, historical ticks, the head timestamp and the histogram refuse it.

#### History

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

- **Field numbers.** Delayed ticks carry their own field numbers. `TickField.live` maps each one to its
  real-time counterpart.
- **Bar times.** `Bar.time` is in epoch seconds. Daily bars are stamped 00:00 UTC of their day.
- **Depth without permissions.** IB sends notice 2152 and then nothing. When the text before «Unknown market data
  permissions» (the phrase must be there) names no `Depth:` exchange, the depth stream ends with `.noMarketDataPermission(code: 2152, …)` and
  sends its cancel; otherwise it stays open. The rule rests on one recorded frame (see `docs/DECISIONS.md` and
  [`docs/KNOWN-GAPS.md`](docs/KNOWN-GAPS.md)).

### Scanner

```swift
let xml = try await client.scannerParameters()   // IB's XML: instruments, locations, scan codes, filters
let top = ScannerSubscription(instrument: "STK", locationCode: "STK.US.MAJOR", scanCode: "TOP_PERC_GAIN", numberOfRows: 10)
let rows = try await client.scannerData(top)     // [ScanData]: rank, contract, marketName ...
Task { for try await scan in try await client.scannerSubscription(top) { print(scan.map(\.contract.symbol)) } }
```

`scannerSubscription` yields each whole scan as IB refreshes it and keeps only the newest for a slow consumer; it
never ends by itself, and stopping it sends IB's cancel. `scannerData` returns the first scan and then cancels.
Both throw `.ib` on IB's error. Filter tags (`filterOptions: [TagValue]`) are those `scannerParameters()` lists.

### News

```swift
let providers = try await client.newsProviders()   // [NewsProvider]: code ("BRFG") and name
let news = try await client.historicalNews(conID: 265598, providerCodes: providers.map(\.code), totalResults: 10)
let article = try await client.newsArticle(providerCode: news[0].providerCode, articleID: news[0].articleID)
```

`historicalNews` reads every headline up to IB's end marker and sends no cancel (IB has none). `start` and `end` are
optional `Date`s; `HistoricalNews.time` is IB's own text. `newsArticle` and `historicalNews` throw `.ib` on IB's error
(10172, 10187).

### Errors

IB sends informational notices and real errors through the same message. The library sorts them with an explicit
table, which is in [`docs/DECISIONS.md`](docs/DECISIONS.md):

- **Notices** never fail anything. They include 2104 «market data farm connection is OK», 10167 «delayed data»
  and 399.
- **Warnings** (105, 321, 329, 434, 492, the codes `ib_async` treats as warnings) end the request they name, but do
  not reject an order that has not been acknowledged yet.
- **202** confirms a cancel. When IB cancelled the order itself (its price cap), the text after `reason:` becomes the
  order's `rejectReason`.
- **Everything else** is fatal to the request it belongs to.

All of them, notices included, are still visible on `messages()`.

## Development

Run the unit tests. They need no gateway, because they use a fake gateway and the recorded frames:

```bash
swift build
swift test
```

The live tests run against a **paper** IB Gateway on 127.0.0.1:4002 and are skipped unless you ask for them.
They refuse to place anything unless every managed account starts with `DU`, which marks a paper account. They
also record the frames to `Tests/IBKRTests/Recorded/`, with the account id redacted.

```bash
IBKR_LIVE=1 swift test --filter LiveTests
```

To also buy and sell back 1 AAPL with marketable limits, add `IBKR_LIVE_FILL=1` and
`IBKR_LIVE_FILL_PRICE=<current AAPL price>`. The BUY goes 1% above that price and the SELL 1% under the BUY's
fill, both with `outsideRTH`. That lets the test run in regular and extended hours: pre-market from 09:00 UTC,
after hours until 01:00 UTC.

On Windows PowerShell, set the variables with `$env:IBKR_LIVE="1"`. Remove them afterwards
(`Remove-Item Env:IBKR_LIVE, Env:IBKR_LIVE_FILL, Env:IBKR_LIVE_FILL_PRICE`), so that a later `swift test` in the
same shell does not trade.

### Documents

| File | What it holds |
|---|---|
| [`docs/protocol-178.md`](docs/protocol-178.md) | every message's field order, and where sources disagree |
| [`docs/DECISIONS.md`](docs/DECISIONS.md) | design decisions, why each was taken and what was rejected |
| [`docs/KNOWN-GAPS.md`](docs/KNOWN-GAPS.md) | what is still open or unconfirmed live |
| [`docs/superpowers/`](docs/superpowers/) | the design spec and the plan for each stage |

## License

[MIT](LICENSE). Interactive Brokers, IB Gateway and TWS are trademarks of Interactive Brokers LLC.
