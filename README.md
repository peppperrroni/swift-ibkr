# swift-ibkr

A pure-Swift client for Interactive Brokers' IB Gateway, speaking the TWS API socket protocol
pinned to **server version 178** (one field layout, no protobuf, which starts at 201).
Not affiliated with Interactive Brokers.

## Build and test

    swift build
    swift test

Field orders are documented in `docs/protocol-178.md`; design decisions in `docs/DECISIONS.md`.
