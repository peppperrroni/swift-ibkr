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
| Connection | handshake, request throttle, `states()`, the raw `messages()` feed | ✅ live-checked |
| Orders | place, modify, cancel, every placeOrder field (conditions, algos, pegged, combos, delta neutral), brackets, OCA, what-if, exercise, open and completed orders merged | ✅ plain orders live-checked; the rest on hand-built frames, not yet run live (see KNOWN-GAPS) |
| Executions | fills joined with commissions, corrections applied | ✅ live-checked |
| Positions | synced at connect, whole sets on every change | ✅ live-checked |
| Session | current time, accounts, next id, user info, log level, auto-bind, global cancel, opt-in reconnect | ✅ on the fake gateway; not yet run live (see KNOWN-GAPS) |
| Account | account summary, per-position P&L, portfolio, account values, Multi, account P&L | ✅ summary and per-position P&L live-checked; the rest on the fake gateway, not yet run live (see KNOWN-GAPS) |
| Contract lookup | contract details with bonds, matching symbols, factories, qualifyContracts | ✅ details (not bonds) and symbols live-checked; the rest on the fake gateway, not yet run live (see KNOWN-GAPS) |
| Options and reference | option chains, option calculations, market rules, family codes, soft-dollar tiers | ✅ on hand-built frames and the fake gateway; not yet run live (see KNOWN-GAPS) |
| Market data | quotes with generic ticks and snapshots, `Ticker` streams and batch snapshots, greeks, EFP, news ticks, real-time bars, depth book, depth exchanges, SMART components, tick-by-tick (alone or folded into a `Ticker`), BAG, typed «no permission» refusal | ✅ refusals live-checked; the data only on hand-built frames (no subscription yet) |
| History | bars with keepUpToDate, historical ticks, head timestamp, histogram, trading schedule, BAG | ✅ refusals live-checked; the data only on hand-built frames (no subscription yet) |
| Scanner | scan stream, one-shot scan, scanner parameters | ✅ on the fake gateway; not yet run live (see KNOWN-GAPS) |
| News | providers, article text, historical headlines, bulletins, news ticks through `marketData` | ✅ on the fake gateway; not yet run live (see KNOWN-GAPS) |
| Fundamentals and Wall Street Horizon | fundamentals report XML, WSH metadata and event JSON, all as IB's text | ✅ on the fake gateway; not yet run live (see KNOWN-GAPS) |
| FA, display groups and verify | FA XML read and replace, TWS display groups (list, follow, update), the vendor verify handshake | ✅ on the fake gateway; not yet run live (see KNOWN-GAPS) |
| Flex reports | download by token and query id, topics, records as IB's strings with a strict Decimal accessor (the separate product IBKRFlex, SwiftPM only) | ✅ on hand-written XML and a fake HTTP layer; never run against IB's service |

What is still unconfirmed against a live gateway is listed in [`docs/KNOWN-GAPS.md`](docs/KNOWN-GAPS.md).
Releases follow [Semantic Versioning](https://semver.org/): from 1.0.0 on, a change that breaks the public API
comes only with a new major version. New cases in the protocol enums (`IBRequest`, `IBMessage`, `Tick`,
`IBClientError` and the like) follow IB's protocol and arrive in minor versions, so an exhaustive `switch` over
one may need a new branch after an update.

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

## ib_async → swift-ibkr

Every `ib_async` call that reaches the socket has a counterpart below. Names are `ib_async`'s minus a leading
`req`, with `Id` written `ID`, except `faData`, `optionChains`, `displayGroups` and `displayGroupUpdates`
(DECISIONS). There is no `cancel…` call: leaving a stream's `for await` sends IB's cancel. «none» marks what the
library leaves out.

| ib_async | swift-ibkr |
|---|---|
| `connect` / `connectAsync` (with `startApi`) | `connect(host:port:clientID:timeout:reconnect:)` |
| `disconnect` | `disconnect()` |
| `isConnected`, `connectedEvent`, `disconnectedEvent` | `states()` (the current state first) |
| `Watchdog` | `ReconnectPolicy`, passed as `connect(…, reconnect:)` |
| `IBC` | none |
| `sleep`, `waitOnUpdate`, `loopUntil`, `setTimeout` | none: `async`/`await` |
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
| `trades`, `openTrades`, `orders`, `openOrders`, `reqOpenOrders`, `reqAllOpenOrders`, `reqCompletedOrders` | `orders()` (open and completed orders, synced at connect) |
| `Trade` | `OrderSnapshot` |
| `fills`, `executions`, `reqExecutions` | `executions()` (synced at connect) |
| `Fill` | `Fill` |
| `MarketOrder`, `LimitOrder`, `StopOrder`, `StopLimitOrder` | `Order.market(_:quantity:)`, `.limit(_:quantity:price:)`, `.stop(_:quantity:stopPrice:)`, `.stopLimit(_:quantity:limitPrice:stopPrice:)` |
| `bracketOrder` | `Order.bracket(_:quantity:limitPrice:takeProfitPrice:stopLossPrice:)`, placed with `placeBracket(_:_:)` |
| `oneCancelsAll` | `Order.oneCancelsAll(_:group:type:)` |
| `PriceCondition`, `TimeCondition`, `MarginCondition`, `ExecutionCondition`, `VolumeCondition`, `PercentChangeCondition` | `OrderCondition.price`, `.time`, `.margin`, `.execution`, `.volume`, `.percentChange` |
| `positions`, `reqPositions` | `positions()` |
| `portfolio`, `reqAccountUpdates` | `portfolio()` (synced at connect, one managed account only) |
| `accountValues` | `accountValues()` |
| `accountSummary` / `reqAccountSummary` | `accountSummary(tags:group:)` (a stream) |
| `reqAccountUpdatesMulti` | `accountUpdatesMulti(account:modelCode:ledgerAndNLV:)` (a stream) |
| `reqPositionsMulti` | `positionsMulti(account:modelCode:)` (a stream) |
| `pnl` / `reqPnL` | `pnl(account:modelCode:)` (a stream) |
| `pnlSingle` / `reqPnLSingle` | `pnlSingle(account:conID:modelCode:)` (a stream) |
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
| `reqMktData`, `ticker` | `marketData(_:genericTicks:snapshot:regulatorySnapshot:options:)` (raw ticks) or `tickers(_:genericTicks:depthRows:smartDepth:tickByTick:options:)` (whole `Ticker`s), both streams |
| `reqTickers` | `tickers(for:regulatorySnapshot:)` |
| `pendingTickers` | none: each `tickers` stream yields its own `Ticker` |
| `Ticker` | `Ticker` |
| `Ticker.marketPrice`, `Ticker.midpoint`, `Ticker.hasBidAsk` | `Ticker.marketPrice`, `Ticker.midpoint`, `Ticker.hasBidAsk` |
| `Ticker.ticks`, `Ticker.tickByTicks`, `Ticker.domTicks`, `Ticker.time` | the same names: what each `tickers` update brought, and when |
| `TickData`, `MktDepthData` (in `domTicks`), `Dividends`, `FundamentalRatios` | `TickData`, `DepthTick`, `Dividends`, `FundamentalRatios` |
| the tick filters and bar builders | none |
| `newsTicks` | `Tick.news` from `marketData` with the news generic ticks |
| `reqMktDepth` | `marketDepth(_:rows:smart:options:)` (whole `DepthBook`s), or `tickers` with `depthRows` |
| `Ticker.domBidsDict`, `Ticker.domAsksDict` | `Ticker.depth.bidsByPosition`, `Ticker.depth.asksByPosition` |
| `reqMktDepthExchanges` | `depthExchanges()` |
| `reqSmartComponents` | `smartComponents(_:)` |
| `reqTickByTickData` | `tickByTick(_:_:count:ignoreSize:)` |
| `reqRealTimeBars`, `realtimeBars` | `realTimeBars(_:whatToShow:rth:options:)` |
| `reqHistoricalData` | `historicalBars(_:end:duration:barSize:whatToShow:rth:keepUpToDate:options:)` |
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
| `FlexError` | `FlexError` (four cases) |
| `df` | none |

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
