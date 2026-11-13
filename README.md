# swift-ibkr

[![CI](https://github.com/peppperrroni/swift-ibkr/actions/workflows/ci.yml/badge.svg)](https://github.com/peppperrroni/swift-ibkr/actions/workflows/ci.yml)
[![Docs](https://github.com/peppperrroni/swift-ibkr/actions/workflows/docs.yml/badge.svg)](https://peppperrroni.github.io/swift-ibkr/)

A pure-Swift client for **Interactive Brokers' IB Gateway and TWS**, speaking the TWS API socket protocol
directly. One actor, async streams, no dependencies, and it runs on **macOS, iOS, Linux and Windows**.

Documentation, with articles on getting started, orders, market data and migrating from `ib_async`:
<https://peppperrroni.github.io/swift-ibkr/>.

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
| Connection | handshake, request throttle, `states()`, the raw `messages()` feed, `ib_async`'s connect options (`ConnectOptions`: read-only, account, startup fetch, throttle, connect options), connection stats, idle timeouts, throttle events, a log handler, client-0 auto-bind | ✅ handshake, throttle and feed live-checked; the options, stats, idle timeouts and log on the fake gateway, not yet run live (see KNOWN-GAPS) |
| Orders | place, modify, cancel, every placeOrder field (conditions, algos, pegged, combos, delta neutral), brackets, OCA, what-if, exercise, open and completed orders merged with ib_async's local states, trade log and fills, open/completed-order and filtered-execution one-shots, id reservation, raw send | ✅ plain orders live-checked; the rest on hand-built frames, not yet run live (see KNOWN-GAPS) |
| Executions | fills joined with commissions, corrections applied | ✅ live-checked |
| Positions | synced at connect, whole sets on every change | ✅ live-checked |
| Session | current time, accounts, next id, user info, log level, auto-bind, global cancel, opt-in reconnect | ✅ on the fake gateway; not yet run live (see KNOWN-GAPS) |
| Account | account summary, per-position P&L, portfolio, account values, Multi, account P&L, the latest P&L of each open subscription | ✅ summary and per-position P&L live-checked; the rest on the fake gateway, not yet run live (see KNOWN-GAPS) |
| Contract lookup | contract details with bonds, matching symbols, factories, qualifyContracts | ✅ details (not bonds) and symbols live-checked; the rest on the fake gateway, not yet run live (see KNOWN-GAPS) |
| Options and reference | option chains, option calculations, market rules, family codes, soft-dollar tiers | ✅ on hand-built frames and the fake gateway; not yet run live (see KNOWN-GAPS) |
| Market data | quotes with generic ticks and snapshots, `Ticker` streams and batch snapshots, the open-ticker registry, greeks, EFP, news ticks, real-time bars, depth book, depth exchanges, SMART components, tick-by-tick (alone or folded into a `Ticker`), BAG, typed «no permission» refusal | ✅ refusals live-checked; the data only on hand-built frames (no subscription yet) |
| History | bars with keepUpToDate (raw, or folded into whole bar lists), the live-bar registry, the 10225 resend, historical ticks, head timestamp, histogram, trading schedule, BAG | ✅ refusals live-checked; the data only on hand-built frames (no subscription yet) |
| Scanner | scan stream, one-shot scan, scanner parameters | ✅ on the fake gateway; not yet run live (see KNOWN-GAPS) |
| News | providers, article text, historical headlines, bulletins, news ticks through `marketData`, every news tick and bulletin received | ✅ on the fake gateway; not yet run live (see KNOWN-GAPS) |
| Fundamentals and Wall Street Horizon | fundamentals report XML, WSH metadata and event JSON, all as IB's text | ✅ on the fake gateway; not yet run live (see KNOWN-GAPS) |
| FA, display groups and verify | FA XML read and replace, TWS display groups (list, follow, update), the vendor verify handshake | ✅ on the fake gateway; not yet run live (see KNOWN-GAPS) |
| Flex reports | download by token and query id, topics, records as IB's strings with a strict Decimal accessor (the separate product IBKRFlex, SwiftPM only) | ✅ on hand-written XML and a fake HTTP layer; never run against IB's service |
| Gateway control | `IBC` starts and stops IB Gateway or TWS through an IBC install; `Watchdog` connects, probes on silence and restarts the app (macOS, Linux and Windows) | ✅ on a fake process and the fake gateway; never run against IBC |

What is still unconfirmed against a live gateway is listed in [`docs/KNOWN-GAPS.md`](docs/KNOWN-GAPS.md).
Releases follow [Semantic Versioning](https://semver.org/): from 1.0.0 on, a change that breaks the public API
comes only with a new major version. New cases in the protocol enums (`IBRequest`, `IBMessage`, `Tick`,
`IBClientError` and the like) follow IB's protocol and arrive in minor versions, so an exhaustive `switch` over
one may need a new branch after an update.
The stage 14 parity closure changes some public shapes (listed as **Breaking** under `[Unreleased]` in the CHANGELOG): `Tick.price` and `TickByTick.bidAsk` gain associated values, the `IBRequest` cases take `options`, `connect`, `tickers`, `Ticker.apply`, `ExecutionTracker.apply` and `OrderTracker.apply` gain parameters, `IBEncodingError` gains `frameTooLong`, and `==` on `Ticker`, `Execution`, `Fill`, `OrderSnapshot`, `PnL` and `AccountPnL` now compares the new fields. The next version number is chosen when that list is released.

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
    .package(url: "https://github.com/peppperrroni/swift-ibkr.git", from: "1.0.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [.product(name: "IBKR", package: "swift-ibkr")]),
]
```

Flex reports are a separate product, `.product(name: "IBKRFlex", package: "swift-ibkr")`, with `import IBKRFlex`. It needs only Foundation and does not depend on `IBKR`.

Or with CocoaPods:

```ruby
pod 'SwiftIBKR', :git => 'https://github.com/peppperrroni/swift-ibkr.git', :tag => '1.0.0'
```

The module is still `IBKR`, so `import IBKR` is the same under both. Publication to the CocoaPods trunk is pending, so install the pod from the tag as above. `IBKRFlex` is Swift Package Manager only; the pod ships `IBKR` alone.

These are the default ports:

| | Paper | Live |
|---|---|---|
| IB Gateway | 4002 | 4001 |
| TWS | 7497 | 7496 |

A runnable, read-only example is in [`Examples/IBKRExample`](Examples/IBKRExample):
`swift run --package-path Examples/IBKRExample ibkr-example [port] [clientID]` prints the server time, accounts,
positions and an account summary.

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
  several, it subscribes to each account's values only (up to `maxSyncedSubAccounts`, 50), and `portfolio()` stays
  empty unless `ConnectOptions.account` names the one whose portfolio to follow. Each connect drops the values of
  accounts the login no longer manages, and with several accounts the portfolio too.
- **Options.** `ib_async`'s connect options go in one `ConnectOptions`, reused by every reconnect attempt:

  ```swift
  try await client.connect(port: 4002, clientID: 7, options: ConnectOptions(
      readOnly: true,                       // no open or completed orders in the sync
      account: "DU0000001",                 // whose portfolio and values reqAccountUpdates follows
      fetch: [.positions, .executions],     // which sync requests run (`.all` by default, `[]` for none)
      throwsOnSyncError: false,             // a failed or late sync request is logged at .error, not thrown
      maxRequests: 45, requestsInterval: .seconds(1),   // the throttle; maxRequests 0 turns it off
      connectOptions: "+PACEAPI"))          // appended to the handshake
  ```

  Client id 0 also binds TWS's manual orders (`setAutoOpenOrders(true)`) first in the sync, as `ib_async` does.
- **Watching the connection.** `connectionStats()` (bytes and messages each way, both hellos included),
  `idleTimeouts(after:)` (the idle time once per silence, re-armed by the next frame), `throttling()` (`true`
  while the writer waits on the throttle) and `endpoint()`.
- **Logging.** The library logs nothing until you set a handler; it is then called synchronously, so keep it quick:

  ```swift
  client.setLogHandler { level, text in if level >= .info { print(level, text) } }
  ```

  `.debug` shows every frame (`>>> ` out, `<<< ` in, fields joined by `|`), `.info` state changes, orders and
  fills, `.warning` IB's warning codes and `.error` its fatal errors.
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

As in `ib_async`, the client's own calls publish at once: `placeOrder` a local `.pendingSubmit` snapshot,
`modifyOrder` the re-sent order, and `cancelOrder` a `.pendingCancel` one (`.cancelled` for a `.pendingSubmit` order
sent with `transmit` off). Each snapshot keeps its history in `log` (status changes, `Modify`, fills and IB's errors
with their codes) and its fills in `fills`; `isActive`, `isWaiting` and `isWorking` are `ib_async`'s status sets.
`orderEvents()` reports this client's modifications and cancel requests:

```swift
for await event in await client.orderEvents() { print(event) }   // .modified(snapshot), .cancelRequested(snapshot)
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
let (positions, changes) = await client.positions()    // on by default: the whole set after every change
Task { for await set in changes { print(set.map { "\($0.contract.symbol) \($0.quantity)" }) } }

let (items, itemSets) = await client.portfolio()       // one account (`ConnectOptions.account`): whole sets, with market value
let (values, valueChanges) = await client.accountValues()   // on by default: each changed tag, e.g. NetLiquidation
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
own request ids, so they do not feed `accountValues()` or `portfolio()`. Each `pnl` and `pnlSingle` value carries its
subscription's `account` and `modelCode` (and `conID` for `pnlSingle`); `pnlValues(account:modelCode:)` and
`pnlSingleValues(account:modelCode:conID:)` read the latest value of every open one, filtered as `ib_async`'s `pnl()`
and `pnlSingle()` filter (an empty argument matches all).

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
only those of the input's secType count; one left is `.qualified`, otherwise `.ambiguous` lists them, possibly none.
A `.qualified` contract keeps `SMART` when the input asked for it. Any other error throws, and a `BAG` is refused
before anything is sent.

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
// genericTicks: [GenericTick] adds IB's generic ticks: numbers ([233]) or tagged entries (["mdoff", "292:BRFG"] for news);
// snapshot: true ends the stream at tickSnapshotEnd, no cancel.
// .price, .size, .generic, .string, .dataType, .optionComputation, .efp, .requestParameters, .news

// A whole Ticker (bid/ask/last, OHLC, greeks, the rest keyed by field) after every update; depthRows adds the book.
// ib_async's names read the same ticks: t.low52Week, t.bidExchange, t.shortableShares, t.impliedVolatility, t.bidEFP, ...
// (nil until set; generic ticks of 0 or less read nil). t.marketPrice is the last when it is within bid/ask, else t.midpoint.
// As ib_async keeps them: t.prevBid ... t.prevLastSize, t.rtVolume, t.vwap, t.rtTime (RT volume never moves t.last),
// t.dividends, t.fundamentalRatios?.decimal("MKTCAP"), t.delayedLastTimestamp (tick 88), t.depth.bidsByPosition.
// t.time is when the update arrived; t.ticks, t.tickByTicks and t.domTicks hold what it brought. A slow consumer
// gets the newest ticker with the lists of every update it skipped: no tick is lost or seen twice.
Task { for try await t in try await client.tickers(aapl, depthRows: 5) { print(t.bid as Any, t.depth.bids.first as Any) } }
// tickByTick: .bidAsk (or .last, .allLast, .midPoint) folds IB's tick-by-tick events in too.
Task { for try await t in try await client.tickers(aapl, tickByTick: .last) { print(t.tickByTicks) } }
// ib_async's tick filters and bar builders: trades(), bids(), asks(), bidAsks(), midpoints() yield TickPoint(time, price,
// size); tickBars(count:), volumeBars(volume:) and timeBars(timer:) (any AsyncSequence of Date) yield BarList(bars,
// hasNewBar). Stopping the outer loop stops the tickers stream and sends its cancels.
Task { for try await p in try await client.tickers(aapl).trades() { print(p.time, p.price, p.size) } }
Task { for try await list in try await client.tickers(aapl).trades().tickBars(count: 100) { print(list.bars.last!) } }
// Snapshots of many contracts at once, in input order; the first error is thrown and the rest cancelled.
let snaps = try await client.tickers(for: [aapl, msft])
// ib_async's accessors over the open tickers streams: the latest Ticker by contract (by conID when set), all of them,
// and a stream of [ticker] for each update of any of them. An entry leaves when its stream ends, however it ends.
let latest = await client.ticker(for: aapl), open = await client.activeTickers()
Task { for await changed in await client.pendingTickers() { print(changed[0].contract.symbol, changed[0].last as Any) } }

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
// Live bars folded as ib_async's BarDataList: the whole list after each change, hasNewBar when a bar was added.
// IB's bust event (10225) resends the request under the same id; the stream goes on.
Task { for try await list in try await client.liveHistoricalBars(aapl, duration: "1 D", barSize: "5 mins") {
    print(list.bars.count, list.hasNewBar) } }
Task { for await live in await client.barUpdates() { print(live.requestID, live.bars.last as Any) } }   // every live subscription
let open = await client.liveBarSubscriptions()                                 // [LiveBars], by request id
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
Both throw `.ib` on IB's error and send no cancel, except a permission refusal, which sends 23 and throws
`.noMarketDataPermission`. Filter tags (`filterOptions: [TagValue]`) are those `scannerParameters()` lists.

### News

```swift
let providers = try await client.newsProviders()   // [NewsProvider]: code ("BRFG") and name
let news = try await client.historicalNews(conID: 265598, providerCodes: providers.map(\.code), totalResults: 10)
let article = try await client.newsArticle(providerCode: news[0].providerCode, articleID: news[0].articleID)
// Live headlines: a NEWS contract with the tagged generic ticks; each arrives as Tick.news.
let feed = try await client.marketData(Contract(symbol: "BRFG:BRFG_ALL", secType: "NEWS", exchange: "BRFG"),
                                       genericTicks: ["mdoff", "292"])
// IB's bulletins (exchange halts and notices); allMessages: true also sends the day's earlier ones.
Task { for try await b in try await client.newsBulletins() { print(b.msgType, b.message) } }
// Every news tick (any request) and bulletin (one per id, the last wins) since the last manual connect.
let (headlines, more) = await client.newsTicks()
let bulletins = await client.receivedBulletins()
```

`historicalNews` reads every headline up to IB's end marker and sends no cancel (IB has none). `start` and `end` are
optional `Date`s; `HistoricalNews.time` is IB's own text. `newsArticle` and `historicalNews` throw `.ib` on IB's error
(10172, 10187). IB holds one bulletin subscription per connection, so a second `newsBulletins()` while one is open
throws `.alreadySubscribed`; stopping the stream sends IB's cancel and frees the slot once its termination has run,
so a call made just after the stop may still throw `.alreadySubscribed` and can be retried.

### Fundamentals and Wall Street Horizon

```swift
let xml = try await client.fundamentalData(aapl, reportType: "ReportSnapshot")   // IB's XML, never parsed
let meta = try await client.wshMetaData()                                         // IB's JSON text
let events = try await client.wshEventData(WshEventData(conID: 265598, startDate: "20261101", endDate: "20261201"))
```

All three return IB's text as a `String` and throw `.ib` on IB's error (430 when a report is not available). A
`WshEventData` field left unset goes out as IB's `2147483647`. Ask for `wshMetaData()` before `wshEventData(_:)`, as IB
requires; the library does not enforce it. A cancelled `fundamentalData` sends IB's cancel. `wshEventData(_:)` cancels
after its answer; `wshMetaData()`, as `ib_async`, leaves its answered request open until the next `wshMetaData()` call
cancels it.

### FA, display groups and verify

```swift
let groups = try await client.faData(.groups)                        // an FA account's XML, never parsed
let done = try await client.replaceFA(.groups, xml: groups)           // IB's confirmation text
let list = try await client.displayGroups()                           // IB's raw "1|2|3"
let (id, updates) = try await client.displayGroupUpdates(1)
try await client.updateDisplayGroup(id, contractInfo: "265598@SMART")
for try await contractInfo in updates { print(contractInfo) }         // "265598@SMART"; stopping it unsubscribes
```

`faData` takes only IB's answer of its own type, so calls for different types can run at once. IB's refusal for a login
that is not an FA account names no request, so `faData` then waits until you cancel it. `replaceFA`, `displayGroups`
and the display-group stream throw `.ib` on IB's error. The four verify calls (`verifyRequest`, `verifyMessage`,
`verifyAndAuthRequest`, `verifyAndAuthMessage`) only send; IB's answers arrive through `messages()`. IB documents them
before startApi, which `connect` sends itself.

### Flex reports

```swift
import IBKRFlex

let report = try await FlexReport.download(token: token, queryID: "123456")   // polls until IB has it ready
for trade in report.extract("Trade") {
    print(trade["symbol"] ?? "", trade["tradeDate"] ?? "", trade.decimal("quantity") ?? 0, trade.decimal("tradePrice") ?? 0)
}
try report.data.write(to: URL(fileURLWithPath: "trades.xml"))                      // save
let saved = try FlexReport(data: Data(contentsOf: URL(fileURLWithPath: "trades.xml")))  // load
```

The token and the query id come from Client Portal: Settings → Flex Web Service gives the token, and each Flex query
shows its id. `topics` lists every tag that has attributes. Records keep IB's strings, with dates in the format the
query sets; `decimal(_:)` is `nil` for anything that is not entirely a number. Errors are `FlexError` (`.request`,
`.statement`, `.malformedXML`, `.http`). Cancel the task to stop the polling.

### Running the gateway with IBC

On macOS, Linux and Windows, `IBC` starts IB Gateway or TWS through an [IBC](https://github.com/IbcAlpha/IBC)
install, and `Watchdog` keeps it up, as `ib_async`'s classes of the same names do:

```swift
let ibc = IBC(twsVersion: 1030, gateway: true, tradingMode: "paper")   // credentials in IBC's config.ini
let client = IBClient()
client.setLogHandler { level, line in print(level, line) }             // IBC's stdout comes here at .debug
let watchdog = Watchdog(controller: ibc, client: client, port: 4002)
Task { for await event in await watchdog.events() { print(event) } }   // .starting, .started, .softTimeout, …
try await watchdog.start()
// … use `client`; react to `.started` to subscribe again after a restart …
await watchdog.stop()                                                   // disconnects and terminates the app
```

`Watchdog` starts the app, waits `appStartupTime` (30 s), connects, and after `appTimeout` (20 s) of silence
probes the app with `currentTime()`, or, with `probeContract`, with `ib_async`'s 30-second MIDPOINT history
request. No answer within `probeTimeout`, IB's error 100 or 1100, or a dropped connection restarts the app: it is
terminated (`.stopped`), and `retryDelay` later started and connected again (`.started`). `ibcPath` defaults to
`/opt/ibc`, or `C:\IBC` on Windows. `userID` and `password` go on IBC's command line, where other local users can
read them, as with `ib_async`; keep them in IBC's `config.ini` instead. `IBC` alone (`start()`, `terminate()`)
starts and stops the app without watching it.

### Errors

IB sends informational notices and real errors through the same message. The library sorts them with an explicit
table, which is in [`docs/DECISIONS.md`](docs/DECISIONS.md):

- **Notices** never fail anything. They include 2104 «market data farm connection is OK», 10167 «delayed data»
  and 399.
- **Warnings** (105, 321, 329, 434, 492, the codes `ib_async` treats as warnings) end the request they name. On an
  order that is not final they set `.validationError` (the order lives on) and record their text as `rejectReason`,
  which `modifyOrder` clears.
- **202** confirms a cancel. When IB cancelled the order itself (its price cap), the text after `reason:` becomes the
  order's `rejectReason`.
- **Everything else** is fatal to the request it belongs to.

All of them, notices included, are still visible on `messages()`.

## ib_async → swift-ibkr

Every `ib_async` call that reaches the socket has a counterpart below. Names are `ib_async`'s minus a leading
`req`, with `Id` written `ID`, except `faData`, `optionChains`, `displayGroups` and `displayGroupUpdates`
(DECISIONS). There is no `cancel…` call: leaving a stream's `for await` sends IB's cancel. «none» marks what the
library leaves out.

| ib_async | swift-ibkr |
|---|---|
| `connect` / `connectAsync` (with `startApi`) | `connect(host:port:clientID:timeout:reconnect:options:)` |
| `connect(readonly:account:raiseSyncErrors:fetchFields:)`, `StartupFetch`, `MaxSyncedSubAccounts` | `ConnectOptions` (`readOnly`, `account`, `throwsOnSyncError`, `fetch: StartupFetch`, `maxSyncedSubAccounts`), passed as `connect(…, options:)` |
| `disconnect` | `disconnect()` |
| `isConnected`, `connectedEvent`, `disconnectedEvent` | `states()` (the current state first) |
| `Watchdog` | `Watchdog` (macOS, Linux, Windows); `ReconnectPolicy`, passed as `connect(…, reconnect:)`, reconnects the socket without restarting the app |
| `Watchdog.startingEvent`, `startedEvent`, `stoppingEvent`, `stoppedEvent`, `softTimeoutEvent`, `hardTimeoutEvent` | `Watchdog.events()`: `WatchdogEvent` `.starting`, `.started`, `.stopping`, `.stopped`, `.softTimeout`, `.hardTimeout` |
| `IBC` (`start`, `terminate`, `IbcLogLevel`) | `IBC` (macOS, Linux, Windows): `start(logTo:)`, `terminate()`, `logLevel` |
| `setTimeout`, `timeoutEvent` | `idleTimeouts(after:)` (a stream of idle times) |
| `sleep`, `waitOnUpdate`, `loopUntil` | none: `async`/`await` |
| `Client.MaxRequests`, `Client.RequestsInterval`, `Client.setConnectOptions`, `Client.optCapab` | `ConnectOptions.maxRequests`, `.requestsInterval`, `.connectOptions`, `.optionalCapabilities` |
| `Client.throttleStart`, `Client.throttleEnd` | `throttling()` (a stream of `Bool`, the current state first) |
| `Client.connectionStats`, `ConnectionStats` | `connectionStats()`, `ConnectionStats` |
| `Client.getReqId`, `Client.updateReqId` | `reserveOrderID(atLeast:)` |
| `Client.send`, `Client.sendMsg` | `send(_:)` (any `IBRequest`; answers on `messages()`) |
| `Client.host`, `Client.port`, `Client.clientId` | `endpoint()` |
| `logToFile`, `logToConsole` | `setLogHandler(_:)` with `IBLogLevel` |
| `__version__` | `IBClient.libraryVersion` |
| `errorEvent` and the other raw events | thrown `IBClientError`s, the streams below, and `messages()` for every decoded frame |
| `reqCurrentTime` | `currentTime()` |
| `managedAccounts` / `reqManagedAccts` | `managedAccounts()` |
| `reqIds` | `nextOrderID()` |
| `reqUserInfo` | `userInfo()` |
| `setServerLogLevel` | `setServerLogLevel(_:)` |
| `reqAutoOpenOrders` | `setAutoOpenOrders(_:)` |
| `reqMarketDataType` | `setMarketDataType(_:)` |
| `placeOrder` (a new order) | `placeOrder(_:_:)`, which returns the order id |
| `placeOrder` (an existing order) | `modifyOrder(_:_:_:)` |
| `cancelOrder` | `cancelOrder(_:manualCancelOrderTime:)` |
| `reqGlobalCancel` | `cancelAllOrders()` |
| `whatIfOrder` | `whatIfOrder(_:_:)` |
| `exerciseOptions` | `exerciseOptions(_:action:quantity:account:override:)` |
| `trades`, `openTrades`, `orders`, `openOrders` | `orders()` (open and completed orders, synced at connect) |
| `reqOpenOrders`, `reqAllOpenOrders`, `reqCompletedOrders` | `fetchOpenOrders()`, `fetchAllOpenOrders()`, `completedOrders(apiOnly:)` (the `orders()` snapshots of the orders IB lists) |
| `Trade` | `OrderSnapshot` |
| `Trade.isActive`, `.isWaiting`, `.isWorking`, `OrderStatus.total`, `.mktCapPrice` | `OrderSnapshot.isActive`, `.isWaiting`, `.isWorking`, `.total`, `.marketCapPrice` (the sets also on `OrderStatus`) |
| `OrderState.transform`, `.formatted` | `OrderState.map(_:)`, `.formatted(digits:)` |
| `Trade.log`, `Trade.fills`, `TradeLogEntry` | `OrderSnapshot.log`, `.fills`, `TradeLogEntry` |
| `newOrderEvent`, `orderModifyEvent`, `cancelOrderEvent`, `Trade.modifyEvent`, `Trade.cancelEvent` | `orders()` (the local `.pendingSubmit` first), `orderEvents()` (`.modified`, `.cancelRequested`) |
| `fills`, `executions` | `executions()` (synced at connect) |
| `reqExecutions` | `executions(filter:)` (the joined fills of the executions IB lists) |
| `Fill` | `Fill` |
| `Fill.time`, `Execution.time` as datetime, `TimezoneTWS` | `Fill.time`, `Execution.date`, `ConnectOptions.gatewayTimeZone` |
| `formatIBDatetime`, `parseIBDatetime` | `IBDate.format(_:)`, `IBDate.parse(_:timeZone:)` |
| `timeRange`, `timeRangeAsync`, `waitUntil`, `waitUntilAsync` | `IBClient.timeRange(from:to:every:)`, `IBClient.wait(until:)` |
| `OptionComputation.__add__`, `__sub__`, `__mul__` | `+`, `-` and `* Decimal` on `OptionComputation` |
| `Forex.pair` | `Contract.pair` |
| `TradingSession`, `ContractDetails.tradingSessions()`, `liquidSessions()` | `TradingSession`, `ContractDetails.tradingSessions`, `.liquidSessions` |
| `MarketOrder`, `LimitOrder`, `StopOrder`, `StopLimitOrder` | `Order.market(_:quantity:)`, `.limit(_:quantity:price:)`, `.stop(_:quantity:stopPrice:)`, `.stopLimit(_:quantity:limitPrice:stopPrice:)` |
| `bracketOrder` | `Order.bracket(_:quantity:limitPrice:takeProfitPrice:stopLossPrice:)`, placed with `placeBracket(_:_:)` |
| `oneCancelsAll` | `Order.oneCancelsAll(_:group:type:)` |
| `PriceCondition`, `TimeCondition`, `MarginCondition`, `ExecutionCondition`, `VolumeCondition`, `PercentChangeCondition` | `OrderCondition.price`, `.time`, `.margin`, `.execution`, `.volume`, `.percentChange` |
| `positions`, `reqPositions` | `positions()` |
| `portfolio`, `reqAccountUpdates` | `portfolio()` (synced at connect, one managed account only) |
| `accountValues` | `accountValues()` |
| `accountSummary` / `reqAccountSummary` | `accountSummary(tags:group:)` (a stream; `tags` default to `ib_async`'s set, re-requested on 1102) |
| `reqAccountUpdatesMulti` | `accountUpdatesMulti(account:modelCode:ledgerAndNLV:)` (a stream) |
| `reqPositionsMulti` | `positionsMulti(account:modelCode:)` (a stream) |
| `reqPnL` | `pnl(account:modelCode:)` (a stream) |
| `pnl` | `pnlValues(account:modelCode:)` (the latest value of each open `pnl` stream) |
| `reqPnLSingle` | `pnlSingle(account:conID:modelCode:)` (a stream) |
| `pnlSingle` | `pnlSingleValues(account:modelCode:conID:)` (the latest value of each open `pnlSingle` stream) |
| `reqContractDetails` | `contractDetails(_:)` |
| `reqMatchingSymbols` | `matchingSymbols(_:)` |
| `qualifyContracts` | `qualifyContracts(_:)` |
| `Stock`, `Option`, `Future`, `ContFuture`, `Forex`, `Index`, `CFD`, `Commodity`, `Bond`, `FuturesOption`, `MutualFund`, `Warrant`, `Bag`, `Crypto` | `Contract.stock`, `.option`, `.future`, `.contFuture`, `.forex`, `.index`, `.cfd`, `.commodity`, `.bond`, `.futuresOption`, `.mutualFund`, `.warrant`, `.bag`, `.crypto` |
| `reqSecDefOptParams` | `optionChains(for:futFopExchange:)` |
| `calculateImpliedVolatility` | `calculateImpliedVolatility(_:optionPrice:underPrice:options:)` |
| `calculateOptionPrice` | `calculateOptionPrice(_:volatility:underPrice:options:)` |
| `reqMarketRule` | `marketRule(_:)` |
| `reqFamilyCodes` | `familyCodes()` |
| `reqSoftDollarTiers` | `softDollarTiers()` |
| `reqMktData` | `marketData(_:genericTicks:snapshot:regulatorySnapshot:options:)` (raw ticks) or `tickers(_:genericTicks:depthRows:smartDepth:tickByTick:options:)` (whole `Ticker`s), both streams |
| `ticker`, `tickers` | `ticker(for:)`, `activeTickers()` (the latest `Ticker` of each open `tickers` stream) |
| `reqTickers` | `tickers(for:regulatorySnapshot:)` |
| `pendingTickers`, `pendingTickersEvent` | `pendingTickers()` (a stream of `[Ticker]`: the ticker each `tickers` update changed) |
| `Ticker` | `Ticker` |
| `Ticker.marketPrice`, `Ticker.midpoint`, `Ticker.hasBidAsk` | `Ticker.marketPrice`, `Ticker.midpoint`, `Ticker.hasBidAsk` |
| `Ticker.ticks`, `Ticker.tickByTicks`, `Ticker.domTicks`, `Ticker.time` | the same names: what each `tickers` update brought, and when |
| `ticker.updateEvent.trades()`, `.bids()`, `.asks()`, `.bidasks()`, `.midpoints()` | `trades()`, `bids()`, `asks()`, `bidAsks()`, `midpoints()` on any `Ticker` sequence (`tickers(…)`), yielding `TickPoint` |
| `Tickfilter.timebars`, `.tickbars`, `.volumebars`, `BarList` | `timeBars(timer:)`, `tickBars(count:)`, `volumeBars(volume:)` on a `TickPoint` stream, yielding `BarList` (`bars`, `hasNewBar`) |
| `TickData`, `MktDepthData` (in `domTicks`), `Dividends`, `FundamentalRatios` | `TickData`, `DepthTick`, `Dividends`, `FundamentalRatios` |
| `newsTicks` | `newsTicks()` (every `Tick.news` since the last manual `connect`, and a stream of new ones) |
| `reqMktDepth` | `marketDepth(_:rows:smart:options:)` (whole `DepthBook`s), or `tickers` with `depthRows` |
| `Ticker.domBidsDict`, `Ticker.domAsksDict` | `Ticker.depth.bidsByPosition`, `Ticker.depth.asksByPosition` |
| `reqMktDepthExchanges` | `depthExchanges()` |
| `reqSmartComponents` | `smartComponents(_:)` |
| `reqTickByTickData` | `tickByTick(_:_:count:ignoreSize:)` |
| `reqRealTimeBars` | `realTimeBars(_:whatToShow:rth:options:)` |
| `realtimeBars` | `liveBarSubscriptions()` (`[LiveBars]`: the open real-time and live-history subscriptions with their bars) |
| `barUpdateEvent`, `BarDataList.updateEvent` | `barUpdates()` (every `LiveBars` change), `liveHistoricalBars(_:duration:barSize:whatToShow:rth:options:)` (`BarList`) |
| `reqHistoricalData` | `historicalBars(_:end:duration:barSize:whatToShow:rth:keepUpToDate:options:)`, or `liveHistoricalBars` for keepUpToDate folded into `BarList` |
| `reqHistoricalTicks` | `historicalTicks(_:start:end:count:whatToShow:rth:ignoreSize:options:)` |
| `reqHeadTimeStamp` | `headTimeStamp(_:whatToShow:rth:)` |
| `reqHistogramData` | `histogramData(_:period:rth:)` |
| `reqHistoricalSchedule` | `historicalSchedule(_:days:end:rth:)` |
| `reqScannerSubscription` | `scannerSubscription(_:options:filterOptions:)` (a stream) |
| `reqScannerData` | `scannerData(_:options:filterOptions:)` |
| `reqScannerParameters` | `scannerParameters()` |
| `reqNewsProviders` | `newsProviders()` |
| `reqNewsArticle` | `newsArticle(providerCode:articleID:options:)` |
| `reqHistoricalNews` | `historicalNews(conID:providerCodes:start:end:totalResults:options:)` |
| `reqNewsBulletins` | `newsBulletins(allMessages:)` (a stream) |
| `newsBulletins` | `receivedBulletins()` (every bulletin since the last manual `connect`, one per id) |
| `reqFundamentalData` | `fundamentalData(_:reportType:options:)` |
| `reqWshMetaData` / `getWshMetaData` | `wshMetaData()` |
| `reqWshEventData` / `getWshEventData` | `wshEventData(_:)` |
| `requestFA` | `faData(_:)` |
| `replaceFA` | `replaceFA(_:xml:)` |
| `queryDisplayGroups` | `displayGroups()` |
| `subscribeToGroupEvents` | `displayGroupUpdates(_:)` (a stream; stopping it unsubscribes) |
| `updateDisplayGroup` | `updateDisplayGroup(_:contractInfo:)` |
| `verifyRequest` | `verifyRequest(apiName:apiVersion:)` |
| `verifyMessage` | `verifyMessage(_:)` |
| `verifyAndAuthRequest` | `verifyAndAuthRequest(apiName:apiVersion:opaqueISVKey:)` |
| `verifyAndAuthMessage` | `verifyAndAuthMessage(_:xyzResponse:)` |
| `FlexReport(token, queryId)` / `download` | `FlexReport.download(token:queryID:)` |
| `FlexReport(path=)` / `load` / `save` | `FlexReport(data:)` / `report.data.write(to:)` |
| `extract` | `extract(_:)` (strings; `decimal(_:)` for numbers) |
| `topics` | `topics` |
| `root` | `FlexReport.elements` (`FlexElement`: `name`, `attributes`, `depth`, `text`) |
| `FlexError` | `FlexError` (four cases) |
| `df` | none |

## Development

Run the unit tests. They need no gateway, because they use a fake gateway and the recorded frames:

```bash
swift build
swift test
```

The decoder is also cross-checked against `ib_async` 2.1.0 itself, run offline: `Tests/IBKRTests/Oracle/` holds
the frames the tests use (the recordings, the fixtures, the fake gateway's replies and the frames the codec tests
build) with the wrapper calls `ib_async` makes for each, and `swift test` compares `IBDecoder` with them. All 82
messages `ib_async`'s decoder handles at protocol 178 are compared. Python
is needed only to regenerate the answers (`python -I Scripts/differential/generate.py`, see
[CONTRIBUTING](CONTRIBUTING.md#differential-oracle)); CI regenerates them and fails on any difference.

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

The Flex live test downloads your own Flex query from IB and only checks that a report with topics comes back:

```bash
IBKR_FLEX_TOKEN=<token> IBKR_FLEX_QUERY=<query id> swift test --filter FlexLiveTests
```

### Documents

| File | What it holds |
|---|---|
| [`docs/protocol-178.md`](docs/protocol-178.md) | every message's field order, and where sources disagree |
| [`docs/DECISIONS.md`](docs/DECISIONS.md) | design decisions, why each was taken and what was rejected |
| [`docs/KNOWN-GAPS.md`](docs/KNOWN-GAPS.md) | what is still open or unconfirmed live |
| [`docs/superpowers/`](docs/superpowers/) | the design spec and the plan for each stage |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | how to build, test, check doc coverage and send a change |

## License

[MIT](LICENSE). Interactive Brokers, IB Gateway and TWS are trademarks of Interactive Brokers LLC.
