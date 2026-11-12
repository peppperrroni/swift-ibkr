# Orders

Place, follow, modify and cancel orders.

## Placing and following

``IBClient/placeOrder(_:_:)`` returns the order id as soon as the frame is queued. The outcome arrives through
``IBClient/orders()``, a snapshot plus a stream of whole ``OrderSnapshot`` values. `orderType` and `tif` stay IB's own
strings (`"LMT"`, `"STP"`, `"DAY"`, `"GTC"` and so on), so an order type IB adds needs no library change.

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

``Order/market(_:quantity:)``, ``Order/limit(_:quantity:price:)``, ``Order/stop(_:quantity:stopPrice:)`` and
``Order/stopLimit(_:quantity:limitPrice:stopPrice:)`` build the common orders. ``IBClient/modifyOrder(_:_:_:)``
resends an order under its id, ``IBClient/cancelOrder(_:manualCancelOrderTime:)`` cancels one and
``IBClient/cancelAllOrders()`` cancels every open order. The status of an order is an ``OrderStatus``.

Fills arrive through ``IBClient/executions()``; a fill is published once its commission is in:

```swift
let (fills, fillUpdates) = await client.executions()
```

## Brackets and OCA groups

``Order/bracket(_:quantity:limitPrice:takeProfitPrice:stopLossPrice:)`` builds an entry with a take-profit and a
stop-loss. ``IBClient/placeBracket(_:_:)`` places it: it links the children to the parent and transmits the group with
the last leg. If any leg fails to encode, nothing is sent.

```swift
let bracket = Order.bracket(.buy, quantity: 100, limitPrice: 180, takeProfitPrice: 190, stopLossPrice: 175)
let ids = try await client.placeBracket(aapl, bracket)      // (parent:, takeProfit:, stopLoss:)

let exits = Order.oneCancelsAll([.limit(.sell, quantity: 100, price: 190), .stop(.sell, quantity: 100, stopPrice: 175)],
                                group: "exit", type: 1)   // IB cancels the other when one fills
```

``Order/oneCancelsAll(_:group:type:)`` puts orders in one OCA group.

## Conditions and algos

Every other `placeOrder` field is a property of ``Order`` and ``Contract``: conditions (``OrderCondition``), algos,
pegged orders, combos, delta-neutral, scale, hedge and so on.

```swift
var order = Order.limit(.buy, quantity: 100, price: 180)
order.conditions = [.price(conID: 265598, exchange: "SMART", isMore: true, price: 185)]   // only once AAPL trades above 185
order.conditionsCancelOrder = false                                                       // true cancels instead of submitting

var twap = Order.limit(.buy, quantity: 1000, price: 180)
twap.algoStrategy = "Twap"
twap.algoParams = [TagValue(tag: "startTime", value: "09:30:00 US/Eastern")]
```

Outgoing text must be printable ASCII, the same rule as IB's own client. Anything else throws
``IBEncodingError/nonASCII(field:)``.

## What-if and exercise

``IBClient/whatIfOrder(_:_:)`` returns IB's margin and commission for an order without placing it, as an
``OrderState``. ``IBClient/exerciseOptions(_:action:quantity:account:override:)`` exercises or lapses an option:

```swift
var option = call; option.multiplier = "100"
try await client.exerciseOptions(option, action: .exercise, quantity: 1, account: "DU0000001")
```

## How IB's errors reach an order

IB sends informational notices and real errors through the same message. Notices never fail anything. Warnings end
the request they name but do not reject an order that has not been acknowledged yet; the warning's text is recorded
as the order's `rejectReason`. Error 202 confirms a cancel, and when IB cancelled the order itself (its price cap),
the text after `reason:` becomes the `rejectReason`. Every other error is fatal to the request it belongs to. All of
them are still visible on ``IBClient/messages()``.
