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
| Orders | place, modify, cancel, brackets, open and completed orders merged | ✅ live-checked |
| Executions | fills joined with commissions, corrections applied | ✅ live-checked |
| Positions | synced at connect, whole sets on every change | ✅ live-checked |
| Account | account summary, per-position P&L | ✅ live-checked |
| Contract lookup | contract details, matching symbols | ✅ live-checked |
| Market data | quotes, historical bars, depth book, tick-by-tick, typed «no permission» refusal | ✅ refusals live-checked; the data itself only on hand-built frames (no subscription yet) |

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
  executions and positions are all synced. One timeout covers all of that.
- **What it throws.** On failure it throws an `IBClientError`:
  - `.timeout`;
  - `.connectionClosed`;
  - `.ib(code:text:)` when the gateway refuses, for example 326 «client id already in use».
- **Streams.** Every call to `states()` or `messages()` hands out a fresh stream, so any number of consumers
  can listen.
- **No automatic reconnect.** A lost connection turns the state to `.disconnected(error)`, and nothing
  reconnects for you: call `connect` again.
- **Across a reconnect.** Subscribers of `orders()`, `executions()` and `positions()` stay subscribed. Per-request
  streams such as `accountSummary` and `pnlSingle` end with the connection's error instead, so subscribe to
  them again.
- **Always call `disconnect()`** when you are done. A connected client is kept alive by its reader and writer
  tasks, and its streams never finish on their own.

### Orders

`placeOrder` returns the order id as soon as the frame is queued. The outcome arrives through `orders()`.
`orderType` and `tif` are IB's own strings (`"LMT"`, `"STP"`, `"DAY"`, `"GTC"` and so on).

```swift
let (known, updates) = await client.orders()     // snapshot now, then every change as a whole order
Task { for await order in updates { print(order.orderID, order.status, order.filled) } }

let aapl = Contract(symbol: "AAPL")              // stock, SMART routing, USD by default
let id = try await client.placeOrder(aapl, Order(action: .buy, quantity: 1, orderType: "LMT", limitPrice: 180))
try await client.modifyOrder(id, aapl, Order(action: .buy, quantity: 1, orderType: "LMT", limitPrice: 181))
try await client.cancelOrder(id)
```

To place a bracket, hold the parent back with `transmit = false` and point the children at it by `parentID`.
The last child transmits the whole group:

```swift
var parent = Order(action: .buy, quantity: 100, orderType: "LMT", limitPrice: 180); parent.transmit = false
let parentID = try await client.placeOrder(aapl, parent)

var profit = Order(action: .sell, quantity: 100, orderType: "LMT", limitPrice: 190)
profit.parentID = parentID; profit.transmit = false
var stop = Order(action: .sell, quantity: 100, orderType: "STP", auxPrice: 175)
stop.parentID = parentID; stop.transmit = true

_ = try await client.placeOrder(aapl, profit)
_ = try await client.placeOrder(aapl, stop)
```

Outgoing text must be printable ASCII. This is the same rule as IB's own client, and anything else throws
`IBEncodingError.nonASCII(field:)`.

### Executions and positions

```swift
let (fills, fillUpdates) = await client.executions()   // a fill is published once its commission is in
let (positions, changes) = await client.positions()    // always on: the whole set after every change
Task { for await set in changes { print(set.map { "\($0.contract.symbol) \($0.quantity)" }) } }
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

### Contract lookup

One-shot calls wait for IB's whole answer. They throw `.ib(code: 200, ...)` when nothing matches, the
connection's error when it drops, and `.cancelled` when the calling task is cancelled.

```swift
let details = try await client.contractDetails(Contract(symbol: "AAPL"))   // [ContractDetails]: conID, minTick, hours ...
let matches = try await client.matchingSymbols("AAP")                      // [ContractDescription]
```

### Market data

Every feed below is a stream for one request: stopping it sends the cancel. When IB refuses it for want of a
data subscription, the stream ends with `.noMarketDataPermission(code:text:)`, so a UI can tell «not subscribed»
from a real failure.

```swift
// Quotes. Without a subscription ask for delayed data; it is not kept across reconnects, so set it after connect.
try await client.setMarketDataType(.delayed)
Task { for try await tick in try await client.marketData(aapl) { print(tick) } }   // .price, .size, .generic, .string, .dataType

// Historical bars: one .history batch, then the stream ends, unless keepUpToDate, which goes on with .update bars.
for try await event in try await client.historicalBars(aapl, duration: "1 D", barSize: "5 mins") {
    if case .history(let bars) = event { print(bars.count) }
}

// The depth book, whole after every update (bids and asks sorted by position); IB's reset (317) empties it.
Task { for try await book in try await client.marketDepth(aapl, rows: 10) { print(book.bids.first as Any) } }

// Tick-by-tick: every trade (.allLast / .last), quote (.bidAsk) or midpoint as it happens.
Task { for try await t in try await client.tickByTick(aapl, .allLast) { print(t) } }
```

- **Field numbers.** Delayed ticks carry their own field numbers. `TickField.live` maps each one to its
  real-time counterpart.
- **Bar times.** `Bar.time` is in epoch seconds. Daily bars are stamped 00:00 UTC of their day.
- **Depth without permissions.** IB sends notice 2152 and then nothing, so the depth stream just stays quiet (see
  [`docs/KNOWN-GAPS.md`](docs/KNOWN-GAPS.md)).

### Errors

IB sends informational notices and real errors through the same message. The library sorts them with an explicit
table, which is in [`docs/DECISIONS.md`](docs/DECISIONS.md):

- **Notices** never fail anything. They include 2104 «market data farm connection is OK», 10167 «delayed data»
  and 399.
- **202** confirms a cancel.
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
