# Getting Started

Add the package, reach a paper IB Gateway and read your account.

## Add the package

With Swift Package Manager:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/peppperrroni/swift-ibkr.git", from: "1.0.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [.product(name: "IBKR", package: "swift-ibkr")]),
]
```

Or with CocoaPods, where the module is still `IBKR`:

```ruby
pod 'SwiftIBKR', :git => 'https://github.com/peppperrroni/swift-ibkr.git', :tag => '1.0.0'
```

## Prepare the gateway

Run IB Gateway or TWS with *Enable ActiveX and Socket Clients* switched on. To place orders, also switch *Read-Only
API* off. These are the default ports:

| | Paper | Live |
|---|---|---|
| IB Gateway | 4002 | 4001 |
| TWS | 7497 | 7496 |

## Connect and read

``IBClient/connect(host:port:clientID:timeout:reconnect:)`` returns once the handshake is done and the open orders,
completed orders, executions, positions, portfolio and account values are synced.

```swift
import IBKR

let client = IBClient()
Task { for await state in await client.states() { print(state) } }   // the current state first
try await client.connect(port: 4002, clientID: 7)                      // paper IB Gateway on 127.0.0.1
print(try await client.currentTime())
print(try await client.managedAccounts())
for position in await client.positions().snapshot {
    print(position.contract.symbol, position.quantity, position.averageCost)
}
await client.disconnect()
```

``IBClient/states()`` hands out a fresh stream on every call, current state first. ``IBClient/currentTime()`` and
``IBClient/managedAccounts()`` are one-shot calls, and ``IBClient/positions()`` returns the synced snapshot plus a
stream of changes. Always call ``IBClient/disconnect()`` when you are done: a connected client is kept alive by its
reader and writer tasks.

## Staying connected

Reconnect is opt-in. Without a policy, a lost connection turns the state to `.disconnected(error)` and nothing
reconnects for you. With a ``ReconnectPolicy``, a connection that was up and then dropped publishes
`.disconnected(error)`, then `.connecting`, and is retried until it is back, `maxAttempts` run out, or you call
``IBClient/disconnect()``:

```swift
// pauses of 1, 2, 5, 10, 30 s (the last repeats), no attempt limit, a reqCurrentTime probe after 30 s of silence
try await client.connect(port: 4002, clientID: 7, reconnect: ReconnectPolicy())
```

- A first connect that fails is not retried.
- After `probeAfter` with no incoming frame the client asks IB the time; if as long again passes with nothing, it
  drops the connection and reconnects.
- Subscribers of `orders()`, `executions()`, `positions()`, `portfolio()` and `accountValues()` stay subscribed across
  a reconnect. Per-request streams end with the connection's error, so subscribe to them again, and set the market
  data type again.

## Next

- `Examples/IBKRExample` in the repository is a small read-only console program.
- <doc:Orders> places, follows, modifies and cancels orders.
- <doc:MarketData> covers quotes, bars, depth and history.
