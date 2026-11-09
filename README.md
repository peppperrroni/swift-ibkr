# swift-ibkr

A pure-Swift client for Interactive Brokers' IB Gateway, speaking the TWS API socket protocol
pinned to **server version 178** (one field layout, no protobuf, which starts at 201).
Not affiliated with Interactive Brokers.

## Build and test

    swift build
    swift test

Field orders are documented in `docs/protocol-178.md`; design decisions in `docs/DECISIONS.md`.

## Status

**Stage 1 (done): codec and merging.** Frame encoding and decoding for the v178 messages in scope, the models,
and three pure-value trackers that merge IB's separate messages into whole objects: `OrderTracker` (orders),
`ExecutionTracker` (execDetails + commissionReport into fills), plus the position/quote state. No I/O yet.

**Next, stage 2:** the socket, the `IBClient` actor, request throttle, snapshot + stream, a live check on the
owner's paper account, and recording real frames as fixtures.
