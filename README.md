# swift-ibkr

A pure-Swift client for Interactive Brokers' IB Gateway, speaking the TWS API socket protocol
pinned to **server version 178** (one field layout, no protobuf, which starts at 201).
Not affiliated with Interactive Brokers.

## Build and test

    swift build
    swift test

Field orders are documented in `docs/protocol-178.md`; design decisions in `docs/DECISIONS.md`.

## Status

**Stage 1 (done): codec and merging, no I/O.** The version-178 wire format (frames, fields, unset values
decode to nil); the handshake; the requests (startApi, reqIds, placeOrder including modify and brackets,
cancelOrder, reqOpenOrders, reqAllOpenOrders, reqAutoOpenOrders, reqCompletedOrders, reqExecutions); the decoders
(orderStatus, error with its code table, openOrder, completedOrder, execDetails, commissionReport, nextValidId,
managedAccounts, currentTime, orderBound, end markers, unknown and malformed frames); and two pure-value trackers
that merge IB's separate messages into whole objects: `OrderTracker` (orders) and `ExecutionTracker` (fills). No
sockets, no positions, no market data yet.

**Next, stage 2:** the socket, the `IBClient` actor, request throttle, snapshot + stream, a live check on the
owner's paper account, and recording real frames as fixtures. What stage 1 leaves open is in
`docs/KNOWN-GAPS.md`.
