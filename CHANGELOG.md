# Changelog

The format follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- `headTimeStamp(_:whatToShow:rth:)` (the earliest data date) and `histogramData(_:period:rth:)` (trade counts by price), with `HistogramData`, `IBRequest.headTimeStamp`, `.cancelHeadTimeStamp`, `.histogramData`, `.cancelHistogramData` (out 87, 90, 88, 89) and `IBMessage.headTimeStamp`, `.histogramData` (in 88, 89). New cases in public enums: an exhaustive `switch` over `IBRequest` or `IBMessage` needs new branches.
- `historicalTicks(_:start:end:count:whatToShow:rth:ignoreSize:)`, historical midpoint, bid/ask or trade ticks as `[TickByTick]`, with `IBRequest.historicalTicks` (out 96) and `IBMessage.historicalTicks` (in 96, 97, 98). New cases in public enums: an exhaustive `switch` over `IBRequest` or `IBMessage` needs new branches.
- `historicalSchedule(_:days:end:rth:)`, a contract's trading sessions, with `HistoricalSchedule` and `HistoricalSession`, and `IBMessage.historicalSchedule` (in 106); BAG history: `historicalBars` sends a `BAG`'s legs. A new case in a public enum: an exhaustive `switch` over `IBMessage` needs a new branch.
- `tickers(_:genericTicks:depthRows:smartDepth:)`, a stream of whole `Ticker`s folding `marketData` and, with `depthRows`, `marketDepth`; the newest is kept for a slow consumer, the first inner error ends it, and any end cancels both requests.
- `tickers(for:regulatorySnapshot:)`, one snapshot `Ticker` per contract in input order, every request sent before any is read; the first error is thrown and the requests still open are cancelled.
- `Ticker`, a contract's market data as one value, with `apply(_:)` folding each `Tick` into it after `ib_async`'s wrapper: named bid, ask, last, OHLC, volume, last timestamp, greeks and request parameters; every other tick in `prices`, `sizes`, `generics`, `strings` or `efp` by its live field; and a `DepthBook`.
- `depthExchanges()` and `smartComponents(_:)`, with `DepthMarketDataDescription` and `SmartComponent`, and the matching `IBRequest` and `IBMessage` cases (out 82/83, in 80/82). New cases in public enums: an exhaustive `switch` over `IBRequest` or `IBMessage` needs new branches.
- `realTimeBars(_:whatToShow:rth:)`, IB's five-second bars as a stream, with `IBRequest.realTimeBars`, `.cancelRealTimeBars` and `IBMessage.realTimeBar`; error 420 with a permission text ends it with `.noMarketDataPermission`. New cases in public enums: an exhaustive `switch` over `IBRequest` or `IBMessage` needs new branches.
- `marketData`'s `genericTicks`, `snapshot` and `regulatorySnapshot`; BAG and delta-neutral contracts in
  `marketData`; and `IBMessage.tickSnapshotEnd(requestID:)`, which ends a snapshot stream with no cancel. A new case in
  a public enum: an exhaustive `switch` over `IBMessage` needs a new branch.
- `Tick.optionComputation`, `.efp`, `.requestParameters` and `.news`, with the new types `OptionComputation`, `EFPData`
  and `NewsTick`: `marketData` yields option computations (21), EFP quotes (47), request parameters (81) and news
  ticks (84). An uncomputed greek is `nil`, and `TickField.live` maps the delayed greeks 80-83 to 10-13. New cases in
  a public enum: an exhaustive `switch` over `Tick` needs new branches.
- `IBMessage.deltaNeutralValidation`, `.rerouteMarketData` and `.rerouteMarketDepth` (56, 91, 92), decoded and
  delivered to `messages()` only; the market data stream stays open through a reroute. New cases in a public enum: an
  exhaustive `switch` over `IBMessage` needs new branches.
- Order factories `Order.market/limit/stop/stopLimit`, `Order.bracket` (a `BracketOrder`), `Order.oneCancelsAll` and
  `IBClient.placeBracket`, which links and transmits the three legs and sends none if any fails to encode.
- `exerciseOptions` with the new `ExerciseAction`, and `cancelOrder(_:manualCancelOrderTime:)`. `IBRequest` gains the
  case `exerciseOptions`: an exhaustive `switch` over the public enum needs a new branch.
- Opt-in reconnect: `connect(reconnect: ReconnectPolicy)` retries a dropped connection with paused attempts until
  `disconnect()` or `maxAttempts`, and probes a silent connection with reqCurrentTime, dropping it with `.timeout`
  when the probe goes unanswered. The order, position and portfolio snapshots stay visible while it retries.
- `accountUpdatesMulti`, `positionsMulti` and `pnl` request streams (account values and positions per account and
  model code, and account-level P&L).
- `portfolio()` and `accountValues()`, always on: `connect` subscribes to the account updates of a single account,
  or to each account's values through `Multi` when there are several, and waits for them.
- Wire codec for the account stream: account values, portfolio items, account time, the `Multi` position and account
  updates, and account-level P&L, with their requests. `Position` and `AccountValue` gain `modelCode`.
- Session requests: `currentTime()`, `managedAccounts()`, `nextOrderID()`, `userInfo()`, `setServerLogLevel(_:)`,
  `setAutoOpenOrders(_:)` and `cancelAllOrders()`.
- Public memberwise initializers on all models.
- iOS 16 as a supported platform, next to macOS 13.
- CI on every push and pull request: tests on macOS, Linux (Swift 6.0 and the latest) and Windows, and an iOS build.
- A `SwiftIBKR.podspec` (pod `SwiftIBKR`, module `IBKR`), linted in CI; trunk publication is pending.

- `placeOrder` sends every plain field of the order and contract: `Order` gains the rest of IB's placeOrder fields
  (open/close, origin, display size, discretionary amount, good-after / good-till times, FA fields, volatility,
  trailing, adjusted-order, MiFID II, cash quantity, soft dollar tier, misc options and more) and `Contract` gains
  `secIDType` / `secID`. New value types `TagValue` and `SoftDollarTier`. `volatility` goes out only for `VOL` order
  types.
- openOrder and completedOrder decode the order fields: every plain field `placeOrder` sends, plus the decoded-only
  `basisPoints` / `basisPointsType` (openOrder) and `autoCancelDate`, `refFuturesConID`, `shareholder`,
  `imbalanceOnly`, `routeMarketableToBbo` and `parentPermID` (completedOrder). Values are kept as the gateway sends
  them (`None`, `clearingIntent` `IB`).
- BAG combos, delta-neutral orders and contracts, scale and hedge orders: `placeOrder` sends and openOrder /
  completedOrder decode `Contract.comboLegs` and `deltaNeutralContract`, and the `Order` combo-leg prices, smart
  routing params, delta-neutral, scale and hedge fields. New value types `ComboLeg`, `OrderComboLeg` and
  `DeltaNeutralContract`. Every request other than `placeOrder`, `marketData` and `historicalBars` still refuses a `BAG` contract.
- Algos, PEG BENCH, BEST and MID, conditions and IBKRATS: `placeOrder` sends and openOrder / completedOrder decode
  `algoStrategy` / `algoParams`, the PEG BENCH reference fields, `conditions` with `conditionsIgnoreRTH` /
  `conditionsCancelOrder`, `minTradeQty`, `minCompeteSize`, `competeAgainstBestOffset` and the mid offsets. New types
  `OrderCondition` and `CompeteOffset`.
- `whatIfOrder(_:_:)` returns IB's margin and commission for an order without placing it, as a new `OrderState`
  (nine margins and three commissions as `Decimal?`, an unparseable margin `nil`, `commissionCurrency`,
  `warningText`). openOrder decodes it into
  the new `OpenOrderMessage.state`; what-if openOrders never reach `orders()`.
- `OrderSnapshot.advancedOrderRejectJSON`: the raw advanced-reject JSON of the last error for the order that had one.

### Changed
- `historicalBars` accepts a `BAG` and refuses `whatToShow` "SCHEDULE" (`.encoding(.unsupported)`): use `historicalSchedule`.
- `marketDepth` ends with `.noMarketDataPermission(code: 2152, text:)` and sends its cancel when IB's 2152 grants no `Depth:` exchange, instead of staying silent; a 2152 that grants some depth keeps the book open.
- tickReqParams (81) is a tick, `Tick.requestParameters`, and `marketData` yields it.
- `marketData` sends `Contract.deltaNeutralContract`. `IBRequest.marketData` gains three associated values
  (`genericTicks`, `snapshot`, `regulatorySnapshot`) whose defaults keep construction compiling; a `switch`/`case` on
  `.marketData` needs the new bindings.
- `contractDetails` sends the contract's `secIDType` and `secID` instead of empty fields.
- `connect` sends one more sync request (reqAccountUpdates, or one reqAccountUpdatesMulti per account) and returns
  only after its end marker.
- `connect` honours task cancellation: it throws `.cancelled` and leaves `.disconnected(.cancelled)`.
- `disconnect()` from `.connected` sends cancelPositions and closes the socket only after the queued frames are out
  (within 2 s), so an order placed just before it is no longer dropped.
- `ErrorKind.warning` for 105, 321, 329, 434 and 492, as in `ib_async`: it ends the request stream it names, but never
  marks an unacknowledged order inactive. Error `text` has its `\uXXXX` escapes decoded.
- A write that finds the peer gone throws `.connectionClosed`, not `.transport("send: ...")`, whether or not the
  reader has seen the close yet. A peer reset seen by the reader is `.connectionClosed` too.
- `placeOrder` and `modifyOrder` refuse an order with `whatIf` set (`.encoding(.unsupported("whatIf"))`): use
  `whatIfOrder`.
- A 202 keeps its reason: when IB cancels an order with text after `reason:` (its price cap), that text becomes the
  snapshot's `rejectReason`. A plain cancel still leaves it `nil`.
- A Filled openOrder waits for its orderStatus or its completedOrder: `orders()` no longer publishes `.filled` with
  `filled` 0 first, nor a part-filled order's `.filled` with the earlier fill. A completedOrder takes the waiting
  openOrder's ids and order, and the fill size when it is larger than the snapshot's. A completedOrder joined to a
  known order also copies `order.parentPermID`, and a later openOrder keeps it.

### Removed
- `IBMessage.tickRequestParameters`: 81 now decodes as `.tick(requestID:, .requestParameters(…))`.
- `OrderKey` is no longer public; the public API never used it.
- The `.unsupported` refusals of `placeOrder` for PEG order types and exchange IBKRATS: it now encodes every layout.

## [0.4.0] - 2026-11-11

### Added
- Connection: handshake, server-version gating, request throttle.
- Orders: place, modify and cancel, brackets, open and completed orders merged.
- Executions with commissions.
- Positions.
- Account summary and per-position P&L.
- Contract details and matching symbols.
- Market data: quotes, historical bars with keepUpToDate, depth book, tick-by-tick, typed no-permission refusal.
