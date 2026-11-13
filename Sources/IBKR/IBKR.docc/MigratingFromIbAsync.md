# Migrating from ib_async

How ib_async's calls and events map onto swift-ibkr.

## One actor instead of an event loop

``IBClient`` is an actor. There is no `ib.sleep` and no `waitOnUpdate`: you `await` a call, or iterate a stream.

## Names

Calls keep `ib_async`'s names, minus a leading `req`, with `Id` written `ID`. Four calls differ: `faData`,
`optionChains`, `displayGroups` and `displayGroupUpdates`.

## State instead of events

`trades()`, `fills()` and `positions()` and their events become a snapshot plus a stream of changes from
``IBClient/orders()``, ``IBClient/executions()`` and ``IBClient/positions()``. Raw frames are on
``IBClient/messages()``.

## Requests

One-shot requests return their answer. Streams send IB's cancel when the loop ends, so there is no `cancel...` call.

## Errors

A thrown ``IBClientError`` replaces `errorEvent`.

## Numbers

Money and sizes are `Decimal`, and IB's unset values are `nil` instead of `nan`.

## Reconnect and the gateway

``IBC`` and ``Watchdog`` start, probe and restart IB Gateway or TWS through an IBC install as `ib_async`'s classes
do, on macOS, Linux and Windows; ``Watchdog/events()`` replaces its six events. Without IBC, a ``ReconnectPolicy``
reconnects the socket to a gateway you start yourself.

## The full table

The "ib_async to swift-ibkr" section of the repository's README maps every call.

## One call, side by side

```python
ib = IB()
ib.connect('127.0.0.1', 4002, clientId=7)
trade = ib.placeOrder(Stock('AAPL', 'SMART', 'USD'), LimitOrder('BUY', 1, 180))
```

```swift
let client = IBClient()
try await client.connect(port: 4002, clientID: 7)
let id = try await client.placeOrder(.stock("AAPL", exchange: "SMART", currency: "USD"),
                                     .limit(.buy, quantity: 1, price: 180))
```
