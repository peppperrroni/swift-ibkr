# swift-ibkr

A pure-Swift client for Interactive Brokers' IB Gateway, speaking the TWS API socket protocol
pinned to **server version 178** (one field layout, no protobuf, which starts at 201).
Not affiliated with Interactive Brokers.

## Build and test

    swift build
    swift test

Live tests run against a paper IB Gateway on 127.0.0.1:4002 and are skipped unless asked for; they refuse
to place anything unless every managed account starts with `DU`, and record the frames to `Tests/IBKRTests/Recorded/`:

    $env:IBKR_LIVE="1"; swift test --filter LiveTests

Add `$env:IBKR_LIVE_FILL="1"; $env:IBKR_LIVE_FILL_PRICE="<current AAPL price>"` to buy and sell back 1 AAPL with
marketable limits (+2% / -2% of that price, `outsideRTH`), so it runs in regular and extended hours (pre-market
from 09:00 UTC, after hours until 01:00 UTC). Afterwards clear them, so a later `swift test` in the same shell does
not trade:

    Remove-Item Env:IBKR_LIVE, Env:IBKR_LIVE_FILL, Env:IBKR_LIVE_FILL_PRICE

Field orders are documented in `docs/protocol-178.md`; design decisions in `docs/DECISIONS.md`.

## Use

    import IBKR

    let client = IBClient()                     // TCP to IB Gateway
    Task { for await state in await client.states() { print(state) } }
    Task { for await message in await client.messages() { print(message) } }
    try await client.connect(port: 4002, clientID: 7)   // host 127.0.0.1, timeout 10 s by default

    // Orders: placeOrder returns the id once the frame is queued; the outcome arrives through orders().
    let (known, updates) = await client.orders()          // snapshot now, then every change as a whole order
    Task { for await order in updates { print(order.orderID, order.status) } }
    let id = try await client.placeOrder(Contract(symbol: "AAPL"),
                                         Order(action: .buy, quantity: 1, orderType: "LMT", limitPrice: 180))
    let changed = Order(action: .buy, quantity: 1, orderType: "LMT", limitPrice: 181)
    try await client.modifyOrder(id, Contract(symbol: "AAPL"), changed)   // re-sends under the same id
    try await client.cancelOrder(id)

    let aapl = Contract(symbol: "AAPL")
    // A bracket: the parent is held (transmit = false), the children point at it by parentID, and the last
    // child transmits the whole group.
    var parent = Order(action: .buy, quantity: 100, orderType: "LMT", limitPrice: 180); parent.transmit = false
    let parentID = try await client.placeOrder(aapl, parent)
    var profit = Order(action: .sell, quantity: 100, orderType: "LMT", limitPrice: 190)
    profit.parentID = parentID; profit.transmit = false
    var stop = Order(action: .sell, quantity: 100, orderType: "STP", auxPrice: 175)
    stop.parentID = parentID; stop.transmit = true
    _ = try await client.placeOrder(aapl, profit); _ = try await client.placeOrder(aapl, stop)

    let (fills, fillUpdates) = await client.executions()   // a fill is published once execDetails and its commission are in
    // ...
    await client.disconnect()

`connect` returns once the handshake is done and open orders, completed orders and executions are synced; one
timeout covers all of it. It throws an `IBClientError` (`.timeout`, `.connectionClosed`, `.ib(code:text:)` when
the gateway refuses, e.g. 326 "client id already in use", and so on). `states()` and `messages()` hand out a fresh
stream on every call, so any number of consumers can listen; `states()` yields the current state first, and
`messages()` carries every decoded incoming message. A lost connection turns the state to `.disconnected(error)`
and is **not reconnected automatically**: call `connect` again. Subscribers stay subscribed across reconnects.

Always call `disconnect()` when done: a connected `IBClient` is kept alive by its reader and writer tasks, and its
streams never finish on their own.

## Status

**Stage 1 (done): codec and merging, no I/O.** The version-178 wire format (frames, fields, unset values
decode to nil); the handshake; the requests (startApi, reqIds, placeOrder including modify and brackets,
cancelOrder, reqOpenOrders, reqAllOpenOrders, reqAutoOpenOrders, reqCompletedOrders, reqExecutions); the decoders
(orderStatus, error with its code table, openOrder, completedOrder, execDetails, commissionReport, nextValidId,
managedAccounts, currentTime, orderBound, end markers, unknown and malformed frames); and two pure-value trackers
that merge IB's separate messages into whole objects: `OrderTracker` (orders) and `ExecutionTracker` (fills). No
sockets, no positions, no market data yet.

**Stage 2 (done): the client.** A plain OS socket (Windows and macOS), the `IBClient` actor with its request
throttle and snapshot + stream, and live checks on the owner's paper account (a limit order placed and cancelled;
1 AAPL bought and sold back pre-market, with commission) whose frames are recorded in `Tests/IBKRTests/Recorded/`
and replayed by the tests.
`main` is local: nothing is pushed. What is still open is in `docs/KNOWN-GAPS.md`.
