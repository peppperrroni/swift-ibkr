# Changelog

The format follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Public memberwise initializers on all models.
- iOS 16 as a supported platform, next to macOS 13.
- CI on every push and pull request: tests on macOS, Linux (Swift 6.0 and the latest) and Windows, and an iOS build.
- A `SwiftIBKR.podspec` (pod `SwiftIBKR`, module `IBKR`), linted in CI; trunk publication is pending.

### Changed
- `ErrorKind.warning` for 105, 321, 329, 434 and 492, as in `ib_async`: it ends the request stream it names, but never
  marks an unacknowledged order inactive. Error `text` has its `\uXXXX` escapes decoded.
- A write that finds the peer gone throws `.connectionClosed`, not `.transport("send: ...")`, whether or not the
  reader has seen the close yet. A peer reset seen by the reader is `.connectionClosed` too.

### Removed
- `OrderKey` is no longer public; the public API never used it.

## [0.4.0] - 2026-11-11

### Added
- Connection: handshake, server-version gating, request throttle.
- Orders: place, modify and cancel, brackets, open and completed orders merged.
- Executions with commissions.
- Positions.
- Account summary and per-position P&L.
- Contract details and matching symbols.
- Market data: quotes, historical bars with keepUpToDate, depth book, tick-by-tick, typed no-permission refusal.
