# Stage 14: Parity Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every row of `docs/PARITY.md` that says `MISSING` becomes `added` with a working, tested Swift name, the
open KNOWN-GAPS items that do not need a live gateway are closed, and the documents of record agree with the code.

**Architecture:** The audit (Task 1, done) split the 164 MISSING rows into 15 groups. Tasks 2–13 implement them in
an order that lets each task build on the names of the one before; Task 14 closes KNOWN-GAPS and Task 15 the
documents.
- Models first: `Encodable` everywhere (Task 2), the wire fields (Task 3), then `Ticker` (Tasks 4–5), the tick
  filters (Task 6) and the order lifecycle (Task 7).
- Then the client: live bars (Task 8), the subscription registry (Task 9), `ConnectOptions` and the session
  plumbing (Task 10), the convenience one-shots (Task 11), dates (Task 12), IBC and `Watchdog` (Task 13).
- No new message id is needed: every request ib_async sends already has an `IBRequest` case. The wire work is new
  fields inside existing messages.

**Tech Stack:** Swift 6 (tools 6.0), SwiftPM, Foundation (`Process` for IBC only), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-12-parity-and-1.0-design.md` («Цели» 2–3, «Анти-цели», «Решения после
проверки строителем», «На усмотрение строителя»). The audit is `docs/PARITY.md`; the planning aid with ib_async
file:line per row is `.superpowers/sdd/2026-11-12-stage-14-parity-closure/audit-missing.md`. The controller's
rulings R1–R20 in `.superpowers/sdd/2026-11-12-stage-14-parity-closure/progress.md` are binding and folded in
below. The owner's brief overrides the spec's IBC non-goal: «всё как в ib_async».

## Global Constraints

- Repository `C:\Users\viohn\swift-ibkr`, branch `gaps-and-parity` (Task 1 is 5176ba1). Never push, never touch
  `main`, never tag, no podspec version bump, no release.
- No package dependencies. `// swift-tools-version: 6.0`, platforms macOS 13 / iOS 16 unchanged. Protocol pinned
  to 178. Wire layouts follow the ib_async clone (data only, never run, never copy IB's `ibapi`); when a plan array
  disagrees with ib_async, ib_async wins and the implementer reports it.
- Swift names: Swift-style, no `req` prefix, `Id` → `ID`, `Rth` → `RTH` (the DECISIONS naming row).
- Money and sizes are `Decimal`; unset is `nil`; no UNSET sentinel in a public type.
- Every new public type: `Sendable`, `Equatable` where it is a value, `Encodable` (after Task 2), a public
  memberwise init, a doc comment on the type and on every public member, and a line in
  `PublicAPITests.everyPublicModelIsConstructible` (plain `import IBKR`).
- Request streams send their cancel when the consumer stops; snapshot+stream state never drops an event; every
  new or changed request has a codec test AND an IB-error test.
- Recorded live frames keep decoding (`RecordedFrameTests`); the real paper account id never appears (use
  `DU0000001`, `DU1`, `DU123456`).
- Each implementation task flips its PARITY.md rows from `MISSING` to `added` with the Swift name in the same
  commit (R2, R19); `present` keeps meaning «in 1.0.0». In the same commit the task changes every other document
  of record its behaviour touches: README (Status row, guide, the ib_async names table), DECISIONS, KNOWN-GAPS,
  `docs/protocol-178.md`, CHANGELOG `## [Unreleased]` (`### Added` / `### Changed`, a breaking change marked
  **Breaking**).
- Code that uses Foundation `Process` sits under `#if os(macOS) || os(Linux) || os(Windows)`, its tests too. CI
  runs macOS, Linux and Windows and builds iOS, so everything must compile on all four.
- Commits: one imperative sentence, then the reasoning (read `git log -5`). Last line exactly
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Tests: `timeout 900 swift test`, foreground, before every commit (1.0.0 had 487). A test waits on an async event
  for at most 2 s (`within2s`); time-driven tests inject `Duration`s of tens of milliseconds, never seconds.
- Test helpers: `FakeGateway` (`Tests/IBKRTests/FakeGateway.swift`: `feed`, `onRequest`, `waitForSent`,
  `syncFrames` = 6), `Gateways` for several connects, `Fixtures`, `ibError(_:_:_:)`, `aaplCall`, `bagContract`,
  `body(_:)`, `d(_:)`, `within2s`, `within(_:seconds:_:)`, `take(_:_:)` (`Tests/IBKRTests/Helpers.swift`). A
  connected client in a test is `IBClient(connector: gateway.connector)` + `connect(clientID: 7)` (clientID 0 adds
  the auto-bind frame, Task 10). `aapl` in the arrays below is the 12-field contract block
  `["0","AAPL","STK","","0.0","","","SMART","","USD","",""]`.

## Task order and dependencies

| Task | Needs |
|---|---|
| 2 Encodable, deprecated order fields | — |
| 3 Wire fields | 2 |
| 4 Ticker named fields and helpers | 2 |
| 5 Ticker parsed and stateful fields | 3 (`Tick.price` attributes), 4 |
| 6 Tick filters and bar builders | 5 (`Ticker.ticks`, `Ticker.time`) |
| 7 Order helpers and lifecycle | 2 |
| 8 Live bars, bar registry, 10225 | 3 (options), 6 (`BarList`) |
| 9 Subscription registry | 5 |
| 10 ConnectOptions, stats, idle, throttle, logging | 7 (order log lines) |
| 11 One-shots, ids, raw send, account summary default | 7, 8 (`RequestStream.resend`), 10 (`ConnectOptions`) |
| 12 Dates, util time, model extras | 10 (`ConnectOptions`) |
| 13 IBC and Watchdog | 10 (`ConnectOptions`, `idleTimeouts`, the log handler) |
| 14 KNOWN-GAPS closure | 10 (the log handler) |
| 15 Docs closure | all |

## Decisions beyond the spec

Every name below is new public API; every behaviour change is against an existing DECISIONS row and names the
ruling. Each is recorded in DECISIONS in its task's commit.

1. **Breaking source changes (R14; group 11).** `Tick.price` gains `attributes: TickAttrib`, `TickByTick.bidAsk`
   gains `bidPastLow:askPastHigh:`, the `IBRequest` cases `marketData`, `historicalData`, `realTimeBars`,
   `marketDepth`, `historicalTicks` gain `options: [TagValue] = []` and `tickByTick` gains
   `count: Int = 0, ignoreSize: Bool = false`. Construction keeps compiling (defaulted associated values); a pattern
   with the old number of bindings does not. A parallel new case would leave old consumers silently missing price
   ticks, so the payload changes. CHANGELOG marks them **Breaking**; README's semver rule makes the next release
   2.0.0, which is the owner's call.
2. **Encodable (R10, R20).** Synthesised `Encodable` (not `Decodable`) on every public value type of `IBKR`
   (models, `OrderSnapshot`, `Fill`, `DepthBook`, `OpenOrderMessage`, `CompletedOrderMessage`, `IBErrorMessage`,
   `IBMessage`, every enum payload) and on `FlexRecord`. `TickField` also gets `CodingKeyRepresentable`, so the
   ticker dictionaries encode as JSON objects. Left out: `IBClient`, the trackers, `IBRequest`, the error enums,
   `ConnectionState`.
3. **Deprecated order fields (R7).** `Order.eTradeOnly: Bool?`, `firmQuoteOnly: Bool?`, `nbboPriceCap: Decimal?`;
   `nil` writes today's wire default and the wire default decodes back to `nil`. DECISIONS row 110 changes.
4. **Ticker.** Named computed properties over `prices`/`sizes`/`generics`/`strings`/`efp` (no new `TickField`
   statics); generic-tick names read `<= 0` as `nil`, as wrapper.py:1262. New stored fields `time`, `prevBid` …
   `prevLastSize`, `rtVolume`, `rtTradeVolume`, `rtTime`, `vwap`, `delayedLastTimestamp`, `dividends`,
   `fundamentalRatios`, `ticks: [TickData]`, `tickByTicks: [TickByTick]`, `domTicks: [DepthTick]`; helpers
   `hasBidAsk`, `midpoint`, `marketPrice`; `DepthBook.bidsByPosition` / `asksByPosition`. RT volume keeps `last`
   from tick 4 (R5, DECISIONS row kept). `FundamentalRatios` keeps IB's strings with a `decimal(_:)` accessor
   (ib_async keeps non-numbers such as `CURRENCY=USD` as text).
5. **Per-update, not per-packet.** `Ticker.ticks`, `time` and `pendingTickers()` follow one fold step (one tick,
   book update or tick-by-tick event), like the existing `messages()` row. A `tickers` element that a slow consumer
   never saw hands its per-update lists on to the next one (merge-on-drop), so filters lose no tick.
6. **Tick filters.** `trades()`, `bids()`, `asks()`, `bidAsks()`, `midpoints()` on any `AsyncSequence` of `Ticker`
   yield `TickPoint`; `timeBars(timer:)`, `tickBars(count:)`, `volumeBars(volume:)` yield `BarList`. The time
   builder takes any `AsyncSequence` of `Date` as its timer, as ib_async takes an event (`IBClient.timeRange` fits).
7. **Orders (R3, R4, R18).** `placeOrder`/`placeBracket` publish a local `.pendingSubmit` snapshot with a log
   entry; `modifyOrder` logs `Modify`, clears `rejectReason` and emits `OrderEvent.modified`; `cancelOrder`
   publishes `.pendingCancel` (or `.cancelled` for an untransmitted `.pendingSubmit` or an `.inactive` order) and
   emits `OrderEvent.cancelRequested`; a warning (105/321/329/434/492) on a live order sets `.validationError`.
   New: `TradeLogEntry`, `OrderEvent`, `orderEvents()`, `OrderStatus.apiUpdate`, `.validationError`, `isActive`,
   `isWaiting`, `isWorking`, `OrderSnapshot.total`, `.log`, `.fills`, `.marketCapPrice`, `.isActive`/…,
   `OrderState.map(_:)`, `OrderState.formatted(digits:)`. DECISIONS rows 31, 49, 84 and the error table's warning
   line change.
8. **Live bars (R6).** `liveHistoricalBars(_:duration:barSize:whatToShow:rth:options:)` yields `BarList`;
   `liveBarSubscriptions()` and `barUpdates()` read a registry of `LiveBars`. 10225 cancels and resends the same
   request under the same reqId for `realTimeBars`, `liveHistoricalBars` and `historicalBars(keepUpToDate: true)`;
   the «10225 stays fatal» half of DECISIONS row 66 is reversed.
9. **Registry.** `ticker(for:)`, `activeTickers()`, `pendingTickers()`, `pnlValues(account:modelCode:)`,
   `pnlSingleValues(account:modelCode:conID:)`, `newsTicks()`, `receivedBulletins()`. `AccountPnL` gains
   `account`/`modelCode` and `PnL` gains `account`/`modelCode`/`conID`, set from the subscription (as ib_async's
   `PnL`). README's «none: each stream yields its own» row goes. News ticks and bulletins are kept from one manual
   connect to the next.
10. **Connection (R11, R12, R13).** `ConnectOptions`, `StartupFetch`, `connect(…, options:)`,
    `ConnectionStats` + `connectionStats()`, `idleTimeouts(after:)`, `throttling()`, `endpoint()`,
    `IBClient.libraryVersion` (not `IBKR.version`: a type named like the module breaks `IBKR.Contract`
    qualification), `IBLogLevel`, `IBLogHandler`, `setLogHandler(_:)`. Client 0 sends `setAutoOpenOrders(true)` in
    the sync (DECISIONS row 100 reversed, R13). `throwsOnSyncError` defaults to `true` (today's behaviour).
    `StartupFetch.positions` really gates reqPositions (ib_async always sends it; a flag that does nothing is a
    trap).
11. **One-shots (R13, R16).** `fetchOpenOrders()`, `fetchAllOpenOrders()`, `completedOrders(apiOnly:)`,
    `executions(filter:)`, `reserveOrderID(atLeast:)`, `send(_:)` made public, `accountSummary(tags:group:)`
    defaulting to ib_async's 34 tags + `$LEDGER:ALL` and re-requested on 1102 (cancel + resend, same reqId), and the
    id-less one-shots failing on a fatal or warning `-1` error and on `ConnectOptions.idlessRequestTimeout` with
    `.timeout` (DECISIONS rows 86, 91, 95 change). 165 on a scan yields `[]` (R13, Task 3).
12. **Dates.** `IBDate.format(_:)`, `IBDate.parse(_:timeZone:)`, `IBClient.timeRange(from:to:every:)`,
    `IBClient.wait(until:)`, `ConnectOptions.gatewayTimeZone`, `Execution.date`, `Fill.time` (arrival time for a
    live fill, reqId −1; the execution's time for a replay). A zone-less execution time reads in
    `gatewayTimeZone ?? UTC` (recorded evidence: the live fill's `20261110-11:56:31` is UTC), where ib_async falls
    back to the machine's zone. DECISIONS row 8 changes (the string stays, a `Date` joins it).
13. **Model extras.** `OptionComputation` `+`, `-`, `*`; `Contract.pair`; `TradingSession`;
    `ContractDetails.tradingSessions` / `liquidSessions`; `FlexReport.elements` and `FlexElement` made public.
14. **IBC and Watchdog (R8, R9, R11).** `actor IBC` (start/terminate, stdout to a client's log handler at
    `logLevel`), `actor Watchdog`, `WatchdogEvent`; macOS, Linux and Windows only. DECISIONS lifts the spec's
    non-goal citing «всё как в ib_async». The Watchdog probe is `currentTime()` unless `probeContract` is set (R8).
    README's `Watchdog → ReconnectPolicy` and `IBC → none` rows change.
15. **KNOWN-GAPS (R17, R18).** A cancellable non-blocking connect; EINTR retry; `IBEncodingError.frameTooLong` from
    `Frame.encode`; the execution tracker caps unmatched halves at 10 000; a fatal error on a sync
    reqAccountUpdatesMulti id after connect ends the current `accountValues()` streams (see the R17 note in Task
    14). The «Subscriber buffers» line moves to DECISIONS.

## Review Focus

1. **A slow `tickers` consumer under filters.** `tickers` buffers only the newest `Ticker`; a dropped element must
   not take its trades with it, or `trades()` and every bar builder undercount. Test: Task 5
   `droppedTickerHandsOnItsTicks`.
2. **Cancel before IB has acknowledged.** A `placeOrder` immediately followed by `cancelOrder` (and then IB's 202)
   must end `.cancelled` with three log entries, never stuck at `.pendingCancel`, and a `transmit = false` order
   must go `.cancelled` at once. Test: Task 7 `cancelBeforeAcknowledgementEndsCancelled`.
3. **Unrelated `-1` errors while an id-less one-shot waits.** A farm notice (2104) must not fail `currentTime()`;
   a fatal `-1` (1100, connectivity lost) must fail it with `.ib`; silence must end in `.timeout`. Test: Task 11
   `idlessOneShotIgnoresNoticesAndFailsOnFatal`.
4. **Stopping the Watchdog mid-cycle.** `stop()` during the app's startup pause must terminate the app once, emit
   `.stopping` then `.stopped`, and never start the app again. Test: Task 13 `stopDuringStartupTerminatesOnce`.
5. **Both live execution-time formats.** `20261110-11:56:31` (a live fill, UTC, no zone) and
   `20261110 06:56:31 US/Eastern` (a replay) must give the same instant in `Execution.date`, with and without
   `gatewayTimeZone`. Test: Task 12 `executionDateReadsBothLiveFormats`.

---

### Task 1: Parity audit — DONE (5176ba1)

`docs/PARITY.md`: present 219 · MISSING 164 · n/a 33.

### Task 2: `Encodable` on every public model, and the deprecated order fields

**Files:**
- Modify: every file declaring a public value type in `Sources/IBKR/Models/`, `Sources/IBKR/State/`
  (`OrderSnapshot`, `Fill`, `DepthBook`; not the trackers), `Sources/IBKR/Messages/IBMessage.swift`,
  `Sources/IBKR/Messages/OrderDecoding.swift`, `Sources/IBKRFlex/FlexRecord.swift`; `Sources/IBKR/Models/Order.swift`,
  `Sources/IBKR/Messages/PlaceOrderEncoding.swift:34`, `Sources/IBKR/Messages/OrderDecoding.swift:91`
- Test: create `Tests/IBKRTests/EncodableTests.swift`; modify `PlaceOrderTests.swift`, `OpenOrderTests.swift`
- Docs: DECISIONS (an Encodable row; row 110), protocol-178 (rows 52–54 and the convention lines 35–36: the three
  fields are now modelled), CHANGELOG, PARITY (`tree`, `Order.eTradeOnly…` → `added`)

**Interfaces:**
- Produces: `Encodable` on every type in decision 2. Synthesis does not work from an extension in another file, so
  the conformance goes on the declaration. `TickField: CodingKeyRepresentable`.
- Produces: `Order.eTradeOnly: Bool? = nil`, `Order.firmQuoteOnly: Bool? = nil`, `Order.nbboPriceCap: Decimal? = nil`
  (placeOrder rows 52–54, openOrder fields 54–56; completedOrder has none).

- [ ] **Step 1: Write the failing tests** in `EncodableTests.swift` (plain `import IBKR`):
  - `everyPublicModelEncodes`: build one value of every type `everyPublicModelIsConstructible` builds (copy its
    constructors), plus `IBMessage.tick(requestID: 1, .price(.bid, price: 1, size: 2))` and an `IBMessage.openOrder`,
    and `JSONEncoder().encode` each without throwing (helper `func json<T: Encodable>(_ v: T) throws -> String`).
  - `tickerDictionariesEncodeAsObjects`: `Ticker(contract: Contract(symbol: "AAPL"), prices: [TickField(rawValue: 15): 1])`
    encodes with `"prices":{"15":1}` in it.
  - `decimalsEncodeAsNumbers`: a `Bar` with `open: d("351.5")` encodes with `"open":351.5` in it (not a keyed
    mantissa).
  - `PlaceOrderTests.deprecatedOrderFieldsAreSent`: the base order with `eTradeOnly = true`, `firmQuoteOnly = false`,
    `nbboPriceCap = d("1.5")` equals `base` with fields 52, 53, 54 = `"1"`, `"0"`, `"1.5"` (client.py:562-564); with
    all three `nil` it equals `base` unchanged (`"0"`, `"0"`, `""`).
  - `OpenOrderTests.deprecatedOrderFieldsDecode` (decoder.py:948-950): the base openOrder fixture with fields 54–56 =
    `"1"`, `"0"`, `"2.5"` decodes to `eTradeOnly == true`, `firmQuoteOnly == nil`, `nbboPriceCap == d("2.5")`; the
    unchanged fixture (`"0"`, `"0"`, `""`) decodes all three to `nil`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "Encodable|deprecatedOrderFields"`. Expected: compile FAIL
  (no `Encodable` conformance, no `eTradeOnly`).
- [ ] **Step 3: Implement.** Add `, Encodable` to each declaration. Encode the three order fields: `nil` → the
  table's constant, `true` → `"1"`, `false` → `"0"`, `nbboPriceCap` as a `Decimal?`. Decode: bool `"1"` → `true`,
  anything else → `nil`; `nbboPriceCap` through `optionalDecimal()`.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS; `RecordedFrameTests` unchanged.
- [ ] **Step 5: Docs, PARITY, commit** («Make every public model Encodable and model IB's three deprecated order
  fields as optionals»). DECISIONS row: «synthesised `Encodable`, never `Decodable`, on every public value type
  (R10)» | ib_async's `util.tree` is one-way to JSON; decoding would promise a stable schema | `Codable`; a `tree`
  function. Row 110: the three deprecated fields are optional and `nil` keeps the wire default (R7).

**Named risks:** `Decimal`'s JSON form differs between Darwin's and swift-corelibs' `JSONEncoder` (the
`decimalsEncodeAsNumbers` test catches it; on a mismatch, report it rather than hand-write `encode(to:)`); a type
missed by the sweep (the reviewer greps `public struct|public enum` against the conformance list); a recorded
openOrder whose fields 54–56 are not `0`, `0`, `""`.

### Task 3: Wire fields (group 11)

**Files:**
- Modify: `Sources/IBKR/Models/Contract.swift`, `Sources/IBKR/Models/Execution.swift`,
  `Sources/IBKR/Models/MarketData.swift` (`Tick`, `TickByTick`, new `TickAttrib`),
  `Sources/IBKR/Messages/IBRequest.swift:59-82,331-390`, `Sources/IBKR/Messages/IBDecoder.swift:35-39,250`,
  `Sources/IBKR/Messages/MarketDataDecoding.swift` (tick-by-tick type 3, historicalTicks 97),
  `Sources/IBKR/Client/IBClient.swift` (`marketData`, `tickers`, `historicalBars`, `realTimeBars`, `marketDepth`,
  `historicalTicks`, `tickByTick`), `Sources/IBKR/Client/IBClient+Research.swift` (scanner 165),
  `Sources/IBKR/Models/Ticker.swift:106` (the new `.price` pattern)
- Test: `RequestTests.swift`, `TickCodecTests.swift`, `TickByTickTests.swift`, `HistoricalTests.swift`,
  `DecoderTests.swift`, `DepthTests.swift`, `IBClientMarketDataTests.swift`, `IBClientResearchTests.swift`,
  `PublicAPITests.swift`
- Docs: protocol-178 (out 9, 20, 87, 88, 96, 1, 50, 10, 97; in 1, 11, 99, 97; Disagreements: the two
  TickAttribBidAsk layouts and TickAttrib's non-ib_async source), DECISIONS (decision 1; row 77's «bid/ask mask
  dropped» half; a 165 row), CHANGELOG (Added, and **Breaking** under Changed), PARITY (`Contract.includeExpired`,
  `Contract.issuerId`, the five option lists, `reqTickByTickData(numberOfTicks:ignoreSize:)`, `Execution.evRule…`,
  `TickAttrib`, `TickAttribBidAsk`, `reqScannerSubscription: empty scan on 165` → `added`; the notes of
  `HistoricalTickBidAsk` and `TickByTickBidAsk` drop «without the attributes»), README names rows for the changed
  signatures

**Interfaces:**
- Produces:
  - `Contract.includeExpired = false`, `Contract.issuerID = ""`.
  - `Execution.evRule = ""`, `Execution.evMultiplier: Decimal? = nil`, `Execution.modelCode = ""` (init parameters
    defaulted, appended last).
  - `public struct TickAttrib: Sendable, Equatable, Encodable { public var canAutoExecute, pastLimit, preOpen: Bool }`
    with a defaulted memberwise init and `public init(mask: Int)` (bits 0, 1, 2).
  - `Tick.price(TickField, price: Decimal?, size: Decimal?, attributes: TickAttrib = TickAttrib())`.
  - `TickByTick.bidAsk(time:bidPrice:askPrice:bidSize:askSize:bidPastLow: Bool = false, askPastHigh: Bool = false)`.
  - The `IBRequest` payloads of decision 1.
  - Client: `marketData(_:genericTicks:snapshot:regulatorySnapshot:options:)`,
    `tickers(_:genericTicks:depthRows:smartDepth:options:)` (the options go to the market-data request only),
    `historicalBars(_:end:duration:barSize:whatToShow:rth:keepUpToDate:options:)`,
    `realTimeBars(_:whatToShow:rth:options:)`, `marketDepth(_:rows:smart:options:)`,
    `historicalTicks(_:start:end:count:whatToShow:rth:ignoreSize:options:)`, `tickByTick(_:_:count:ignoreSize:)`;
    every `options: [TagValue] = []`, written with `IBRequest.tagValues`.

- [ ] **Step 1: Write the failing codec tests** (field orders from client.py and decoder.py):
  - `contractDetailsSendsIncludeExpiredAndIssuerID` (client.py:743): `includeExpired = true, issuerID = "e1"` →
    `["9","8","4"] + aapl + ["1","","","e1"]`.
  - `historicalDataSendsIncludeExpiredAndChartOptions` (client.py:808): `includeExpired = true`, `keepUpToDate: true`,
    `options: [TagValue(tag: "a", value: "1")]` → `["20","9"] + aapl + ["1","","5 mins","1 D","1","TRADES","2","1","a=1;"]`.
  - `headTimeStampAndHistogramSendIncludeExpired` (client.py:1096, 1101): `["87","9"] + aapl + ["1","1","TRADES","2"]`,
    `["88","9"] + aapl + ["1","1","3 days"]`.
  - `historicalTicksSendIncludeExpiredAndMiscOptions` (client.py:1125): field 14 `"1"`, last three `"1","0","a=1;"`.
  - `marketDataSendsOptions` (client.py:443-467): `["1","11","7"] + aapl + ["0","","0","0","a=1;b=2;"]`.
  - `realTimeBarsSendOptions` (client.py:915): `["50","3","7"] + aapl + ["5","TRADES","1","a=1;"]`.
  - `marketDepthSendsOptions` (client.py:759): `["10","5","7"] + aapl + ["5","1","a=1;"]`.
  - `tickByTickSendsCountAndIgnoreSize` (client.py:1151): `["97","7"] + aapl + ["Last","10","1"]`.
  - `tickPriceDecodesItsAttributes` (decoder.py:200-206 drops the mask; the bits are IB's documentation, R14):
    `["1","6","7","1","351.5","200","5"]` → `.tick(requestID: 7, .price(.bid, price: d("351.5"), size: d("200"), attributes: TickAttrib(canAutoExecute: true, pastLimit: false, preOpen: true)))`;
    mask `"0"` → `TickAttrib()`.
  - `tickByTickBidAskDecodesItsMask` (decoder.py:865, bit 0 = bidPastLow):
    `["99","8","3","1794321000","351.4","351.6","300","200","1"]` → `bidPastLow: true, askPastHigh: false`; mask
    `"2"` → the reverse.
  - `historicalTicksBidAskDecodesItsMask` (decoder.py:803, bit 0 = **askPastHigh**):
    `["97","9","1","1794321000","1","351.4","351.6","300","200","1"]` → `askPastHigh: true, bidPastLow: false`.
  - `execDetailsDecodesEVAndModel` (decoder.py:426-464): `DecoderTests.execDetailsDecodes`' array with fields
    27–29 = `"EVR"`, `"0.5"`, `"M1"` → `evRule "EVR"`, `evMultiplier d("0.5")`, `modelCode "M1"`; the old array
    (empty) → `""`, `nil`, `""`.
- [ ] **Step 2: Write the failing client tests:**
  - `changedRequestsFailOnTheirError`: `ibError(id, "200", "No security definition has been found")` ends each of
    `marketData`, `historicalBars(keepUpToDate: true)`, `realTimeBars`, `marketDepth`, `tickByTick(count: 10, ignoreSize: true)`
    (all opened with options) with `.ib(code: 200, …)`, and makes `historicalTicks(…, options:)`,
    `contractDetails`, `headTimeStamp` and `histogramData` (contract with `includeExpired`) throw it.
  - `scanEmptiedBy165YieldsEmpty` (wrapper.py:1670-1675): a `scannerSubscription` gets one scan, then
    `ibError(id, "165", "Historical Market Data Service query message:no items retrieved")` → the next element is
    `[]` and the stream stays open (a later scan still arrives); `scannerData` answered by 165 returns `[]`.
- [ ] **Step 3: Run** the new tests. Expected: compile FAIL.
- [ ] **Step 4: Implement.** Replace the constant fields at IBRequest.swift:334, 348, 352, 357, 360, 367, 372, 377,
  382, 386, 389 with the new values. Read the masks per message exactly as ib_async's two decoders do (they
  disagree; record it under protocol-178 Disagreements). `Ticker.apply` matches `.price(field, p, s, _)`. The
  scanner routes take `.error(let e) where e.code == 165` before any other handling and yield (or answer) `[]`.
- [ ] **Step 5: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 6: Docs, PARITY, commit** («Send includeExpired, issuerId, the option lists and the tick-by-tick count,
  and decode the tick attributes and the execution EV fields»), naming the source break in the body.

**Named risks:** the source break (the reviewer checks CHANGELOG says **Breaking** and lists each case); the
opposite bit orders of 99 and 97 (one test each); `TickAttrib`'s bits come from IB's documentation, not ib_async
(Task 14 lists them as unseen live); 165 is a notice routed by reqId, so the scanner route must see it.

### Task 4: `Ticker` named fields and derived helpers (groups 1, 3)

**Files:**
- Create: `Sources/IBKR/Models/TickerFields.swift` (`extension Ticker`)
- Test: create `Tests/IBKRTests/TickerFieldsTests.swift`
- Docs: README (Market data guide: two lines on the names and `marketPrice`; the names-table row
  `Ticker.marketPrice, Ticker.midpoint, the tick filters and bar builders` becomes the helpers, the filters follow
  in Task 6), CHANGELOG, PARITY (every group-1 row, and `hasBidAsk`, `midpoint`, `marketPrice` → `added`)

**Interfaces:**
- Produces (each `public var … { get }` reading the live-keyed dictionaries; tick ids from wrapper.py:82-195):
  - strings → `String?`: `bidExchange` 32, `askExchange` 33, `lastExchange` 84, `lastRegTime` 85,
    `optionBidExchange` 25, `optionAskExchange` 26, `reutersMutualFunds` 91, `socialMarketAnalytics` 100.
  - prices → `Decimal?`: `low13Week` 15, `high13Week` 16, `low26Week` 17, `high26Week` 18, `low52Week` 19,
    `high52Week` 20, `bidYield` 50, `askYield` 51, `lastYield` 52, `markPrice` 37, `lastRTHTrade` 57,
    `creditmanMarkPrice` 78, `creditmanSlowMarkPrice` 79, `etfNavClose` 92, `etfNavPriorClose` 93, `etfNavBid` 94,
    `etfNavAsk` 95, `etfNavLast` 96, `etfFrozenNavLast` 97, `etfNavHigh` 98, `etfNavLow` 99,
    `estimatedIPOMidpoint` 101, `finalIPOLast` 102, `auctionPrice` 35.
  - sizes → `Decimal?`: `averageVolume` 21, `openInterest` 22, `callOpenInterest` 27, `putOpenInterest` 28,
    `callVolume` 29, `putVolume` 30, `auctionVolume` 34, `auctionImbalance` 36, `regulatoryImbalance` 61,
    `volumeRate3Min` 63, `volumeRate5Min` 64, `volumeRate10Min` 65, `futuresOpenInterest` 86,
    `averageOptionVolume` 87, `shortableShares` 89.
  - generics → `Decimal?`, `nil` when the value is `<= 0` (wrapper.py:1262): `indexFuturePremium` 31,
    `histVolatility` 23, `impliedVolatility` 24, `shortable` 46, `halted` 49, `tradeCount` 54, `tradeRate` 55,
    `volumeRate` 56, `rtHistVolatility` 58, `bondFactorMultiplier` 60, `delayedHalted` 90.
  - EFP → `EFPData?`: `bidEFP` 38, `askEFP` 39, `lastEFP` 40, `openEFP` 41, `highEFP` 42, `lowEFP` 43, `closeEFP` 44.
  - `hasBidAsk: Bool` (bid and ask set and not -1, both sizes > 0), `midpoint: Decimal?` ((bid + ask) / 2 when
    `hasBidAsk`), `marketPrice: Decimal?` (last when bid ≤ last ≤ ask, else the midpoint; last when there is no
    bid/ask) — ticker.py:263-297.
- Names follow the DECISIONS naming rule (`avVolume` → `averageVolume`, `Rth` → `RTH`, `Ipo` → `IPO`,
  `Efp` → `EFP`, `optionBidExch` → `optionBidExchange`); PARITY's Swift column gives each.

- [ ] **Step 1: Write the failing tests:**
  - `namedFieldsReadTheirTicks`: apply `.string(TickField(rawValue: 32), "Q")`,
    `.price(TickField(rawValue: 19), price: 120, size: nil)`, `.size(TickField(rawValue: 89), 5000)`,
    `.generic(TickField(rawValue: 24), d("0.31"))`, `.efp(TickField(rawValue: 38), EFPData(basisPoints: 1))` →
    `bidExchange == "Q"`, `low52Week == 120`, `shortableShares == 5000`, `impliedVolatility == d("0.31")`,
    `bidEFP?.basisPoints == 1`; every other name `nil`.
  - `delayedTwinsLandOnTheSameNames`: tick 103 (delayed bid yield) sets `bidYield`.
  - `genericNamesReadZeroAsNil`: `.generic(.halted, 0)` → `halted == nil`; `1` → `1`.
  - `marketPriceFollowsIbAsync`: bid 10 / ask 11, sizes 1 / 1, last 10.5 → `marketPrice 10.5`, `midpoint 10.5`;
    last 12 → `10.5` (the midpoint); bid size 0 → `hasBidAsk false` and `marketPrice` = last; bid `-1` →
    `hasBidAsk false`; no last and no bid/ask → `nil`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter TickerFieldsTests`. Expected: compile FAIL.
- [ ] **Step 3: Implement** the computed properties, one line each.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs, PARITY, commit** («Name every ticker field ib_async names and add hasBidAsk, midpoint and
  marketPrice»).

**Named risks:** a wrong tick id (the reviewer checks each against wrapper.py:82-195); the `<= 0` rule hides a real
`halted 0` («not halted»), as ib_async does (the doc comment says so).

### Task 5: `Ticker` parsed and stateful fields (group 2)

**Files:**
- Modify: `Sources/IBKR/Models/Ticker.swift` (fields, `apply(_:at:)`, `apply(_ tickByTick:at:)`),
  `Sources/IBKR/State/DepthBook.swift`, `Sources/IBKR/Client/IBClient.swift` (`tickers`, `fold`, `TickerPart`, a
  private raw-depth stream)
- Create: `Sources/IBKR/Models/TickerParts.swift` (`TickData`, `DepthTick`, `Dividends`, `FundamentalRatios`)
- Test: create `Tests/IBKRTests/TickerStateTests.swift`; modify `IBClientMarketDataTests.swift`, `PublicAPITests.swift`
- Docs: DECISIONS (decision 5; the RT-volume row keeps `last` from tick 4 and gains the parsed fields, R5; the
  `tickers` row 73 adds tick-by-tick and merge-on-drop), README (Market data guide), CHANGELOG, PARITY (`time`,
  `timestamp`, `prev…`, `vwap`, `rtVolume…`, `delayedLastTimestamp`, `dividends`, `fundamentalRatios`, `ticks`,
  `tickByTicks`, `domBidsDict…`, `domTicks`, `Dividends`, `FundamentalRatios` → `added`; the `TickData` row's
  Swift name becomes `TickData`; the RT-volume row keeps its R5 difference note)

**Interfaces:**
- Produces:
  - `public struct TickData { public var time: Date; public var field: TickField; public var price: Decimal?; public var size: Decimal? }`
    (`field` is IB's raw tick type, not `live`: tick 68 stays 68, as ib_async's `TickData.tickType`).
  - `public struct DepthTick { public var time: Date; public var update: DepthUpdate }`.
  - `public struct Dividends { public var past12Months, next12Months: Decimal?; public var nextDate: Date?; public var nextAmount: Decimal? }`
    (`nextDate` is 00:00 UTC of IB's `yyyyMMdd`, as `Bar` reads a day).
  - `public struct FundamentalRatios { public var values: [String: String]; public subscript(_ tag: String) -> String?; public func decimal(_ tag: String) -> Decimal? }`
    (`decimal` is `nil` for `-99999.99` and for non-numbers).
  - `Ticker` stored fields, defaulted in the init: `time: Date?`, `prevBid`, `prevBidSize`, `prevAsk`,
    `prevAskSize`, `prevLast`, `prevLastSize: Decimal?`, `rtVolume`, `rtTradeVolume: Decimal?`, `rtTime: Date?`,
    `vwap: Decimal?`, `delayedLastTimestamp: Date?`, `dividends: Dividends?`,
    `fundamentalRatios: FundamentalRatios?`, `ticks: [TickData]`, `tickByTicks: [TickByTick]`,
    `domTicks: [DepthTick]`.
  - `Ticker.apply(_ tick: Tick, at time: Date = Date())` (replaces `apply(_:)`, source compatible) and
    `Ticker.apply(_ tick: TickByTick, at time: Date = Date())`.
  - `DepthBook.bidsByPosition`, `asksByPosition: [Int: DepthLevel]`.
  - `tickers(_:genericTicks:depthRows:smartDepth:tickByTick: TickByTickType? = nil, options:)`.
- Consumed by Task 6 (`ticks`, `time`) and Task 9 (the fold).

- [ ] **Step 1: Write the failing model tests** (`TickerStateTests`, `let t0 = Date(timeIntervalSince1970: 1794321000)`):
  - `prevFieldsKeepTheValueBefore` (wrapper.py:1000-1034): bid 10 then bid 11 → `prevBid 10`, `bid 11`; the same
    for ask, and for last through tick 4; a size-only tick 0 sets `prevBidSize`; tick 5 sets `prevLastSize`.
  - `rtVolumeParsesWithoutMovingLast` (wrapper.py:482-511, R5): `.string(TickField(rawValue: 48), "701.28;1;1348075471534;67854;701.46918464;true")`
    → `rtVolume 67854`, `vwap d("701.46918464")`, `rtTime` within 1 ms of `Date(timeIntervalSince1970: 1348075471.534)`,
    `last` still `nil`, the raw string still in `strings`, and
    `ticks == [TickData(time: t0, field: TickField(rawValue: 48), price: d("701.28"), size: 1)]`; tick 77 sets
    `rtTradeVolume`; an empty price (`";;1348075471534;67854;;true"`) appends no tick.
  - `dividendsParse` (wrapper.py:1233-1243): tick 59 `"0.83,0.92,20130219,0.23"` →
    `Dividends(past12Months: d("0.83"), next12Months: d("0.92"), nextDate: 2013-02-19 00:00 UTC, nextAmount: d("0.23"))`;
    `",,,"` → all `nil`.
  - `fundamentalRatiosKeepTextAndReadNumbers` (wrapper.py:1208-1221): tick 47
    `"CURRENCY=USD;MKTCAP=3000000.5;NPRICE=-99999.99;"` → `["CURRENCY"] == "USD"`,
    `decimal("MKTCAP") == d("3000000.5")`, `decimal("NPRICE") == nil`, `decimal("CURRENCY") == nil`.
  - `delayedLastTimestampStaysApart` (wrapper.py:187): tick 88 `"1794321000"` sets `delayedLastTimestamp`, not
    `lastTimestamp`.
  - `ticksRecordWhatIbAsyncRecords` (wrapper.py:1046, 1103, 1262): price tick 1 → `TickData(t0, 1, 10, 100)`; tick 5
    with no last → nothing; tick 5 after a last → `(t0, 5, last, size)`; generic tick 24 → `(t0, 24, value, 0)`.
  - `tickByTickFoldsLikeIbAsync` (wrapper.py:1111-1195): `.trade` moves `prevLast`/`last`/`lastSize` (`-1`/`0` →
    `nil`); `.bidAsk` moves each changed side (`<= 0` → `nil`); `.midPoint` only appends; each lands in
    `tickByTicks`.
  - `depthBookByPosition`: bid inserts at 0 and 2 → `bidsByPosition.keys.sorted() == [0, 2]`.
- [ ] **Step 2: Write the failing client tests** (`IBClientMarketDataTests`):
  - `tickersStampTimeAndResetPerUpdate`: two ticks fed → the second `Ticker` has `ticks.count == 1` and a `time`.
  - `tickersFoldTickByTickAndCancelIt`: `tickers(aapl, tickByTick: .bidAsk)` sends 1 and 97; a 99 type-3 frame moves
    `bid`; stopping the stream sends 2 and 98.
  - `tickersRecordDepthTicksAndReset`: with `depthRows: 5`, a 12 insert → `domTicks.count == 1`,
    `depth.bids.count == 1`; a 317 → `depth` empty and `domTicks` holds one delete per removed row (wrapper.py:1681).
  - `droppedTickerHandsOnItsTicks` (Review Focus 1): three trades (tick 4, three prices) fed before the consumer
    reads; the one element read has `ticks.map(\.price) == [p1, p2, p3]`.
- [ ] **Step 3: Run** `timeout 900 swift test --filter "TickerStateTests|tickers"`. Expected: compile FAIL.
- [ ] **Step 4: Implement the model.** `apply(_:at:)` follows wrapper.py:995-1106 and 1200-1243 for the new fields
  and appends to `ticks` (it never clears them; the fold does). A parse failure leaves the field unchanged and
  keeps the raw string in `strings`.
- [ ] **Step 5: Implement the fold.** `TickerPart` gains `.depth(DepthUpdate)`, `.depthReset` and
  `.tickByTick(TickByTick)`. `tickers` opens, in order, a private raw-depth request stream (the same request,
  refusal and 2152 rules as `marketDepth` — reuse its route — but yielding each update and the 317 reset,
  unbounded), `marketData`, and `tickByTick` when asked; a later one that throws stops the ones already open. Each
  fold step clears `ticks`, `tickByTicks` and `domTicks`, applies the part with `now = Date()`, sets `time = now`,
  and yields with merge-on-drop:

```swift
let t = ticker
if case .dropped(let unseen) = out.yield(t) {   // bufferingNewest(1): the consumer never saw `unseen`
    var merged = t
    merged.ticks = unseen.ticks + t.ticks
    merged.tickByTicks = unseen.tickByTicks + t.tickByTicks
    merged.domTicks = unseen.domTicks + t.domTicks
    _ = out.yield(merged)                         // replaces the unmerged `t` in the buffer
}
```

- [ ] **Step 6: Run** `timeout 900 swift test`. Expected: PASS (the existing `tickers…` tests included).
- [ ] **Step 7: Docs, PARITY, commit** («Keep ib_async's stateful ticker fields: time, previous values, RT volume,
  dividends, ratios, and the ticks, tick-by-ticks and depth ticks of each update»).

**Named risks:** merge-on-drop must run on every yield path (tick, book, tick-by-tick); the raw-depth stream must
keep `marketDepth`'s 2152/317 semantics; `Ticker` equality now includes `time`, so tests comparing whole tickers
set it; `tickers(for:)` snapshots keep every tick in `ticks`, since no fold clears them (documented).

### Task 6: Tick filters and bar builders (group 4)

**Files:**
- Create: `Sources/IBKR/Models/TickFilters.swift`
- Test: create `Tests/IBKRTests/TickFilterTests.swift`; modify `PublicAPITests.swift`
- Docs: DECISIONS (decision 6), README (Market data guide: a short `trades()` / `tickBars(count:)` example; names
  table: the filters and builders), CHANGELOG, PARITY (all 13 group-4 rows → `added`)

**Interfaces:**
- Consumes: `Ticker.ticks`, `Ticker.time`, `Ticker.midpoint` (Tasks 4–5), `Bar`.
- Produces:
  - `public struct TickPoint { public var time: Date; public var price: Decimal; public var size: Decimal }`.
  - `public struct BarList { public var bars: [Bar]; public var hasNewBar: Bool }` (Task 8 reuses it).
  - `extension AsyncSequence where Element == Ticker, Self: Sendable`: `trades()` (ticks 4, 5, 48, 68, 71),
    `bids()` (0, 1, 66, 69), `asks()` (2, 3, 67, 70), `bidAsks()` (both), `midpoints()` (one point per ticker
    whose `ticks` is non-empty: `time`, `midpoint`, size 0), each `-> AsyncThrowingStream<TickPoint, any Error>`
    (ticker.py:302-385). A tick with a `nil` price is skipped and a `nil` size reads 0; a `nil` midpoint is
    skipped.
  - `extension AsyncThrowingStream where Element == TickPoint, Failure == any Error`:
    `timeBars<Timer: AsyncSequence & Sendable>(timer: Timer) -> AsyncThrowingStream<BarList, any Error> where Timer.Element == Date`,
    `tickBars(count: Int) -> AsyncThrowingStream<BarList, any Error>`,
    `volumeBars(volume: Decimal) -> AsyncThrowingStream<BarList, any Error>` (ticker.py:406-503). Bars are `Bar`
    with `average: nil`; `Bar.count` counts ticks. `tickBars`/`volumeBars` yield when a bar completes
    (`hasNewBar` true); `timeBars` yields on every point (`false`) and on every timer date (`true`), filling a bar
    with no tick from the previous close and dropping one that has neither.
  - Every returned stream is unbounded and, when its consumer stops, cancels the task reading its source, which
    stops a `tickers` stream and so sends its cancels.

- [ ] **Step 1: Write the failing tests** (hand-built `AsyncStream<Ticker>` sources, no client):
  - `tradesFilterKeepsTradeTicksInOrder`: one ticker with ticks 1, 4, 5, 48, 8 → the points of 4, 5, 48.
  - `bidsAsksAndBidAsksSplit`; `midpointsFollowTickers` (a ticker with empty `ticks` yields nothing).
  - `tickBarsCutEveryCount` (ticker.py:452-477): prices 1, 3, 2, 5, size 1, count 2 → `[Bar(o1 h3 l1 c3 v2 n2)]`,
    then the same plus `Bar(o2 h5 l2 c5 v2 n2)`, `hasNewBar` true both times.
  - `volumeBarsCutAtVolume` (ticker.py:479-503): sizes 1, 2, 3 with volume 3 → one completed bar after the second
    point.
  - `timeBarsTakeThePreviousCloseWhenEmpty` (ticker.py:406-450): timer t1, points 1 and 2 (two `false` yields),
    timer t2 → `([b1 (1, 2, 1, 2)], true)`, timer t3 with no point → `([b1, b2 (2, 2, 2, 2)], true)`.
  - `stoppingAFilterStopsItsSource`: a source whose `onTermination` records; cancelling the filter's reader
    terminates the source within 2 s.
- [ ] **Step 2: Run** `timeout 900 swift test --filter TickFilterTests`. Expected: compile FAIL.
- [ ] **Step 3: Implement** with one internal relay helper (a `Task` reading the source into an unbounded
  `AsyncThrowingStream`, cancelled from `onTermination`); the builders are pure state machines over points and
  timer dates. `timeBars` reads the timer and the points into one channel from one task group, so a timer date and
  a point never race on the bar list.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs, PARITY, commit** («Add ib_async's tick filters and time, tick and volume bar builders as async
  sequence operators»).

**Named risks:** cancellation must reach the source, or a `tickers` subscription leaks (anti-goal); `timeBars`'
two inputs must not reorder a point after a later timer date; `BarList.bars` grows without bound, as in ib_async
(the doc comment says so).

### Task 7: Order status helpers and order lifecycle (groups 5, 6)

Two commits: 7a helpers, 7b lifecycle.

**Files:**
- Modify: `Sources/IBKR/Models/OrderStatus.swift`, `Sources/IBKR/Models/OrderState.swift`,
  `Sources/IBKR/State/OrderTracker.swift`, `Sources/IBKR/Client/IBClient.swift` (`placeOrder`, `placeBracket`,
  `modifyOrder`, `cancelOrder`, `submit`, `handle`, new `orderEvents()`)
- Create: `Sources/IBKR/Models/TradeLog.swift` (`TradeLogEntry`, `OrderEvent`)
- Test: `OrderTrackerTests.swift`, `IBClientOrderTests.swift`, `RecordedFrameTests.swift` (expectations gain the
  local snapshots), `PublicAPITests.swift`
- Docs: DECISIONS rows 31, 49, 84 and the error table's warning line (R3, R4, R18), CHANGELOG (Added; Changed:
  `orders()` publishes one more element per placed order, R3), README (Orders guide: the local states, `log`,
  `fills`, `orderEvents()`; names: the `Trade` helpers), KNOWN-GAPS (drop «`rejectReason` is never cleared once
  set»), PARITY (group 5 and 6 rows; the `newOrderEvent` note: now exact)

**Interfaces:**
- 7a produces: `OrderStatus.apiUpdate` (`"ApiUpdate"`), `OrderStatus.validationError` (`"ValidationError"`);
  `isActive` (PendingSubmit, ApiPending, PreSubmitted, Submitted, ValidationError, ApiUpdate), `isWaiting`
  (PendingSubmit, ApiPending, PreSubmitted), `isWorking` (Submitted, ValidationError, ApiUpdate) — order.py:262-300;
  `OrderSnapshot.total` (filled + remaining), `isActive`/`isWaiting`/`isWorking` (through `status`),
  `marketCapPrice: Decimal? = nil` (merged from `OrderStatusMessage.marketCapPrice`);
  `OrderState.map(_ transform: (Decimal) -> Decimal) -> OrderState` over the twelve numbers (`nil` stays `nil`);
  `OrderState.formatted(digits: Int = 2) -> [String: String]` keyed by field name (`"initMarginChange"` …),
  grouped `"300,000.21"` in `en_US_POSIX`, `""` for `nil` (order.py:327-380).
- 7b produces: `public struct TradeLogEntry { public var time: Date; public var status: OrderStatus; public var message: String; public var errorCode: Int? }`;
  `public enum OrderEvent: Sendable, Equatable, Encodable { case modified(OrderSnapshot), cancelRequested(OrderSnapshot) }`;
  `OrderSnapshot.log: [TradeLogEntry] = []`, `OrderSnapshot.fills: [Fill] = []` (init parameters defaulted);
  `public func orderEvents() -> AsyncStream<OrderEvent>` (fresh per call, unbounded);
  `OrderTracker.apply(_:at time: Date = Date())`,
  `OrderTracker.placed(orderID:clientID:contract:order:at:) -> [OrderSnapshot]` (replaces `sent`),
  `OrderTracker.cancelRequested(orderID:at:) -> [OrderSnapshot]`, `OrderTracker.add(_ fill: Fill, at:) -> [OrderSnapshot]`.
- Rules (ib.py:780-855, wrapper.py:765-835, 1590-1639):
  - `placed`, a new key: a snapshot at `.pendingSubmit` with `log [(t, .pendingSubmit, "")]`. An existing one that is
    not final: order and contract replaced, `rejectReason = nil` (R18), log `(t, status, "Modify")`; the client
    yields `.modified(snapshot)`.
  - An orderStatus that changes the snapshot logs `(t, status, "")`; an unchanged `Submitted` right after a
    `Modify` entry logs `"Modified"`; any other unchanged one appends nothing.
  - `cancelRequested`, a known non-final order → `.cancelled` if (`.pendingSubmit` and `!order.transmit`) or
    `.inactive`, else `.pendingCancel`; log `(t, new, "")`; the client yields `.cancelRequested`. Unknown or final:
    nothing.
  - A warning-kind error on a known non-final order → `.validationError`, `rejectReason` = text, log
    `(t, .validationError, text, code)` (R4). A fatal one keeps today's rule with «unacknowledged» now meaning
    `.pendingSubmit` or `.apiPending` (→ `.inactive`), logged with its code. 202 logs `(t, .cancelled, text, 202)`.
  - `add(fill)`: found by `execution.permID`, else clientID/orderID; a correction replaces the fill with the same
    correction key; log `(t, status, "Fill \(shares)@\(price)")` (Decimal's description; ib_async prints floats).
    The client calls it for each fill `executionTracker.apply` returns and publishes the snapshot on `orders()`.

- [ ] **Step 1 (7a): Write the failing tests:** `statusSetsMatchIbAsync` (each of the eleven statics against the
  three sets), `snapshotTotalAndSets`, `marketCapPriceIsMerged` (an orderStatus frame with field 11 `"187.5"`),
  `orderStateMapAndFormatted` (`OrderState(initMarginChange: d("300000.211"))` →
  `formatted()["initMarginChange"] == "300,000.21"`, `["commission"] == ""`; `map { $0 * 2 }` doubles every set
  number).
- [ ] **Step 2: Run, implement, run** `timeout 900 swift test`. Expected: FAIL, then PASS. Commit («Add ib_async's
  order status sets, the trade total and the OrderState helpers»).
- [ ] **Step 3 (7b): Write the failing tests** (`OrderTrackerTests` with fixed times; `IBClientOrderTests` on the
  fake gateway):
  - `placeOrderPublishesPendingSubmitAtOnce`: `orders().updates` yields `.pendingSubmit` with one log entry before
    any gateway reply; the following openOrder/orderStatus merge onto it.
  - `modifyLogsAndClearsRejectReason`: an order with `rejectReason` from a 110, then `modifyOrder` → `rejectReason`
    `nil`, the log ends `Modify`, `orderEvents()` yields `.modified`; a following unchanged `Submitted` logs
    `Modified`.
  - `cancelBeforeAcknowledgementEndsCancelled` (Review Focus 2): place, cancel at once → `.pendingCancel`;
    `ibError(id, "202", "Order Canceled - reason:")` → `.cancelled`; log statuses
    `[.pendingSubmit, .pendingCancel, .cancelled]`. With `transmit = false` the cancel gives `.cancelled` at once and
    `orderEvents()` yields `.cancelRequested`.
  - `warningSetsValidationError`: `ibError(id, "321", "Error validating request")` → `.validationError`,
    `rejectReason` set, `isActive && isWorking`.
  - `fillsJoinTheirOrder`: an order, then execDetails + commission (the `reconnectDoesNotRepublishFills` arrays
    with the order's id) → `fills.count == 1` and the last log message `"Fill 100@187.25"`.
  - `bracketPublishesThreeLocalSnapshots`.
- [ ] **Step 4: Run** `timeout 900 swift test --filter "OrderTracker|IBClientOrder"`. Expected: FAIL.
- [ ] **Step 5: Implement** the rules above; `whatIfOrder` still never reaches the tracker.
- [ ] **Step 6: Run** `timeout 900 swift test`. Expected: PASS after the recorded-frame expectations gain each placed
  order's leading `.pendingSubmit` element (the reviewer checks that nothing else moved).
- [ ] **Step 7: Docs, PARITY, commit** («Publish ib_async's local order states with a trade log, fills, and modify and
  cancel events»).

**Named risks:** `upsert` publishes only on change and a log append always changes the snapshot, so a duplicate
orderStatus must not append; a modify of a final order (ib_async asserts; Swift makes no local change and IB
answers); `orders()` grows by one element per placement (CHANGELOG); `rejectReason` is cleared only by
`modifyOrder`, and the history stays in `log`.

### Task 8: keepUpToDate history, the bar registry and 10225 (group 7; `realtimeBars`)

**Files:**
- Modify: `Sources/IBKR/Client/IBClient.swift` (`RequestStream.resend`, `routeToStream` for 10225, `realTimeBars`,
  `historicalBars`, the bar registry), `Sources/IBKR/Models/History.swift` (`LiveBars`, `BarList.apply`)
- Create: `Sources/IBKR/Client/IBClient+Bars.swift` (`liveHistoricalBars`, `liveBarSubscriptions`, `barUpdates`)
- Test: `HistoricalTests.swift`, `IBClientMarketDataTests.swift`, `PublicAPITests.swift`
- Docs: DECISIONS row 66 (the 10225 half reversed, R6) and rows 59/73 where they describe `historicalBars`; README
  (History guide; names `reqRealTimeBars, realtimeBars`, `barUpdateEvent`), CHANGELOG (Changed: 10225 resends),
  PARITY (`barUpdateEvent`, `BarDataList.updateEvent`, `realtimeBars`, the 10225 row → `added`; the
  `RealTimeBarList` note)

**Interfaces:**
- Consumes: `BarList` (Task 6), the option payloads (Task 3).
- Produces:
  - `extension BarList { public mutating func apply(_ bar: Bar) -> Bool }` (wrapper.py:923-942: an older bar is
    dropped and returns `false`; a later one appends with `hasNewBar = true`; the same time replaces the last bar
    when it differs, with `hasNewBar = false`; an identical one returns `false`).
  - `public struct LiveBars { public var requestID: Int; public var contract: Contract; public var barSize: String; public var whatToShow: String; public var bars: [Bar]; public var hasNewBar: Bool }`.
  - `public func liveHistoricalBars(_ contract: Contract, duration: String, barSize: String, whatToShow: String = "TRADES", rth: Bool = true, options: [TagValue] = []) throws(IBClientError) -> AsyncThrowingStream<BarList, any Error>`
    (keepUpToDate history with `end` empty, as IB requires; the first batch, then each changing update; a batch
    after a resend is ignored, as ib_async's `_results` drops it).
  - `public func liveBarSubscriptions() -> [LiveBars]` (the open `realTimeBars` and `liveHistoricalBars`, by reqId).
  - `public func barUpdates() -> AsyncStream<LiveBars>` (every change of any of them; fresh per call, unbounded).
  - internal `RequestStream.resend: IBRequest?`: on error 10225 for a reqId whose stream has one, the client sends
    `cancel`, then `resend`, and keeps the stream open (wrapper.py:1694-1721).

- [ ] **Step 1: Write the failing tests:**
  - `barListFoldFollowsIbAsync`: the four cases of `apply`.
  - `liveHistoricalBarsFoldUpdates`: a two-bar 17 frame, then 90 updates at the last bar's time (a changed close)
    and at a later time → `(2 bars, true)`, `(2, false)`, `(3, true)`; an older update yields nothing; stopping
    sends `["25","1",id]`.
  - `liveHistoricalBarsFailOnTheirError`: `ibError(id, "162", "Historical Market Data Service error message:…")` →
    `.ib`.
  - `bustEventResendsUnderTheSameID` (R6): `realTimeBars` with options, then
    `ibError(id, "10225", "Bust event occurred, current subscription is deactivated.")` → the gateway sees
    `["51","1",id]` and then the original 50 frame again, same id and options; a later bar still arrives. The same
    for `liveHistoricalBars` (25, then 20) and `historicalBars(keepUpToDate: true)`.
  - `liveBarSubscriptionsAndBarUpdates`: one `realTimeBars` and one `liveHistoricalBars` → the snapshot lists both
    with their contracts; `barUpdates()` yields each new bar; a stopped stream leaves the registry.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "BarList|liveHistorical|bustEvent|liveBar"`. Expected: FAIL.
- [ ] **Step 3: Implement.** The registry is an actor dictionary keyed by reqId, written by the routes and emptied
  in `stopped`, in the error path and in `end`.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS. The old «10225 ends the stream» test becomes the
  resend test (the reviewer checks it was changed, not deleted).
- [ ] **Step 5: Docs, PARITY, commit** («Fold keepUpToDate history into whole bar lists, keep a registry of live
  bars, and resubscribe on IB's bust event»).

**Named risks:** a resend must reuse the stored request with its options; the registry entry must go on every exit
path (consumer stop, IB error, connection end) or state leaks; `realTimeBars` bars accumulate in the registry for
the subscription's lifetime, as in ib_async's `RealTimeBarList`.

### Task 9: Subscription registry accessors (group 8)

**Files:**
- Modify: `Sources/IBKR/Client/IBClient.swift` (registry state; the `tickers` fold records into it; the `pnl` and
  `pnlSingle` routes record; `handle` collects news ticks and bulletins), `Sources/IBKR/Models/Account.swift`
  (`AccountPnL`, `PnL`)
- Create: `Sources/IBKR/Client/IBClient+Registry.swift`
- Test: create `Tests/IBKRTests/IBClientRegistryTests.swift`; modify `PublicAPITests.swift`
- Docs: DECISIONS (decision 9), README (names: `ticker`, `tickers`, `pendingTickers`, `pnl`, `pnlSingle`,
  `newsTicks`, `newsBulletins`; the «none: each `tickers` stream yields its own» row goes), CHANGELOG, PARITY (the
  group-8 rows and `pendingTickersEvent` → `added`; the `PnL`/`PnLSingle` notes)

**Interfaces:**
- Consumes: the Task 5 fold.
- Produces:
  - `public func ticker(for contract: Contract) -> Ticker?` (by `conID` when non-zero, else by `==`, as
    contract.py:145-161).
  - `public func activeTickers() -> [Ticker]`.
  - `public func pendingTickers() -> AsyncStream<[Ticker]>` (each fold step yields `[ticker]`; fresh per call).
  - `public func pnlValues(account: String = "", modelCode: String = "") -> [AccountPnL]` and
    `public func pnlSingleValues(account: String = "", modelCode: String = "", conID: Int? = nil) -> [PnL]` (the
    latest value of each open subscription; an empty argument matches all, ib.py:554-590).
  - `AccountPnL.account = ""`, `.modelCode = ""`; `PnL.account = ""`, `.modelCode = ""`, `.conID = 0`, set by the
    streams from their request (init parameters defaulted).
  - `public func newsTicks() -> (snapshot: [NewsTick], updates: AsyncStream<NewsTick>)` (every `Tick.news` on any
    reqId) and `public func receivedBulletins() -> [NewsBulletin]` (by `msgID`, last wins, first-seen order); both
    reset at a manual `connect`.

- [ ] **Step 1: Write the failing tests:** `tickerRegistryFollowsOpenStreams` (two `tickers` streams, `ticker(for:)`
  by a conID-only contract, `activeTickers().count == 2`, a stopped one gone within 2 s);
  `pendingTickersYieldEachUpdate`; `pnlValuesFilterByAccount` (two `pnl` streams for `DU1` and `DU2`, frames 94 →
  `pnlValues(account: "DU1")` is one value with `account "DU1"`); `pnlSingleValuesCarryTheirConID`;
  `newsTicksCollectAcrossSubscriptions` (84 frames on two reqIds); `bulletinsAreKeptByID` (two 14 frames with the
  same msgID → one).
- [ ] **Step 2: Run, implement, run** `timeout 900 swift test`. Expected: FAIL, then PASS.
- [ ] **Step 3: Docs, PARITY, commit** («Keep the latest value of every open ticker and P&L subscription and every
  news tick and bulletin, as ib_async's accessors read them»).

**Named risks:** the fold runs off the actor, so each record is an actor hop and must not reorder updates of one
ticker; an entry must go when its stream ends for any reason; news ticks grow for the whole connection (as in
ib_async).

### Task 10: ConnectOptions, stats, idle timeouts, throttle, endpoint, version, auto-bind, logging (groups 9, 14)

**Files:**
- Create: `Sources/IBKR/Client/ConnectOptions.swift` (`ConnectOptions`, `StartupFetch`, `ConnectionStats`,
  `IBLogLevel`, `IBLogHandler`), `Sources/IBKR/Client/IBClient+Session.swift`
- Modify: `Sources/IBKR/Client/IBClient.swift` (`connect`, `open`, `start`'s writer, `handle`, `sync`, counters,
  log calls), `Sources/IBKR/Client/Throttle.swift`, `Sources/IBKR/Wire/Handshake.swift`
- Test: create `Tests/IBKRTests/ConnectOptionsTests.swift`; modify `HandshakeTests.swift`, `ThrottleTests.swift`,
  `IBClientConnectTests.swift`, `PublicAPITests.swift`
- Docs: protocol-178 (Handshake: `v100..178 <connectOptions>`; startApi's capabilities field), DECISIONS (rows 13,
  43, 44, 100 (R13), decision 10, a logging row (R11)), README (Connecting guide: `options:` and logging; Status
  Connection row; names: `connect` options, `setTimeout`, the `Client.*` rows, `logToFile`), CHANGELOG, PARITY
  (every group-9 row except `TimezoneTWS`; `logToFile, logToConsole`, `formatSI`, `__version__` → `added`)

**Interfaces:**
- Produces:
  - `public struct ConnectOptions: Sendable, Equatable { public var readOnly = false; public var account: String? = nil; public var fetch: StartupFetch = .all; public var maxSyncedSubAccounts = 50; public var throwsOnSyncError = true; public var maxRequests = 45; public var requestsInterval: Duration = .seconds(1); public var connectOptions = ""; public var optionalCapabilities = ""; public init(…every field defaulted…) }`
    (Task 11 adds `idlessRequestTimeout`, Task 12 `gatewayTimeZone`).
  - `public struct StartupFetch: OptionSet, Sendable { positions, ordersOpen, ordersComplete, accountUpdates, subAccountUpdates, executions; static let all; static let none: StartupFetch = [] }`
    (ib.py:60-78).
  - `connect(host:port:clientID:timeout:reconnect:options: ConnectOptions = .init())`; reconnect attempts reuse it.
  - Sync rules (ib.py:2040-2100): client 0 first sends `autoOpenOrders(true)`; `readOnly` skips open and completed
    orders; each request runs only under its `fetch` flag (`.positions` gates reqPositions); one account → today's
    reqAccountUpdates; several → `account` (when set) gets reqAccountUpdates and, while the count is
    `<= maxSyncedSubAccounts`, each account a reqAccountUpdatesMulti. With `throwsOnSyncError = false` a fatal error
    on a sync request, or the deadline reached with only sync end markers due, is logged at `.error` and `connect`
    succeeds.
  - `public struct ConnectionStats { public var startTime: Date; public var duration: Duration; public var bytesReceived, bytesSent, messagesReceived, messagesSent: Int }`,
    `CustomStringConvertible` as `"1.23 kB sent in 45 messages, 6.78 MB received in 1.2 k messages, session 12.3 s"`
    through an internal `formatSI(_:)` (util.py:274: three significant digits and an SI prefix);
    `public func connectionStats() throws(IBClientError) -> ConnectionStats` (`.notConnected` unless connected;
    counted by the client: bytes include the hello, messages count frames written and frames received).
  - `public func idleTimeouts(after: Duration) -> AsyncStream<Duration>`: while connected, yields the idle time
    once each time `after` passes with no incoming frame, and re-arms on the next frame (wrapper.py:440-467).
  - `public func throttling() -> AsyncStream<Bool>`: the current state first, then `true` when the writer starts
    waiting on the throttle and `false` when its queue is empty again (client.py:323-351).
  - `public func endpoint() -> (host: String, port: Int, clientID: Int)?` (`nil` when disconnected).
  - `public static let libraryVersion = "1.0.0"` on `IBClient`, kept equal to the podspec's `s.version`.
  - `public enum IBLogLevel: Int, Sendable, Comparable { case debug, info, warning, error }`,
    `public typealias IBLogHandler = @Sendable (IBLogLevel, String) -> Void`,
    `public nonisolated func setLogHandler(_ handler: IBLogHandler?)` (a lock-protected box, so IBC and `Watchdog`
    log without an actor hop), internal `nonisolated func log(_ level: IBLogLevel, _ text: @autoclosure () -> String)`.
    Lines: `.debug` `>>> ` / `<<< ` and the fields joined by `|` for every frame each way; `.info` state changes,
    placeOrder/modify/cancel (`"placeOrder 12: BUY 1 AAPL LMT 180"`) and fills; `.warning` warning codes; `.error`
    fatal IB errors. Nothing is formatted while no handler is set.
  - `Throttle(limit:window:)` with `limit == 0` never waits; `Handshake.hello(connectOptions: String = "")` sends
    `"v100..178"`, or `"v100..178 <opts>"` (client.py:218-224); startApi sends `optionalCapabilities`
    (client.py:1016).

- [ ] **Step 1: Write the failing tests:**
  - `HandshakeTests.helloCarriesConnectOptions`: `hello(connectOptions: "+PACEAPI")` ends with `v100..178 +PACEAPI`.
  - `ThrottleTests.zeroLimitNeverWaits`.
  - `clientZeroAutoBindsInTheSync`: `connect(clientID: 0)` sends `["15","1","1"]` right after 71; client 7 does not.
  - `readOnlyAndFetchGateTheSync`: `options: .init(readOnly: true)` sends no 16 and no 99; `fetch: []` sends only 71
    and `connect` returns at once; `fetch: [.positions]` sends 61 only.
  - `accountOptionSubscribesThatAccount`: accounts `"DU1,DU2"` with `account: "DU2"` → a 6 for DU2 and two 76s;
    `maxSyncedSubAccounts: 1` → no 76.
  - `syncErrorsCanBeLogged`: a fatal error on the sync's executions id with `throwsOnSyncError: false` → `connect`
    returns and the handler saw one `.error` line; with the default it throws as today.
  - `optionalCapabilitiesGoInStartAPI`; `throttleOptionsAreUsed` (`maxRequests: 1`,
    `requestsInterval: .milliseconds(50)`: the third frame leaves ≥ 100 ms after the first).
  - `connectionStatsCountBothWays` (after the sync `messagesSent == 6`, bytes > 0; `.notConnected` after
    `disconnect()`); `formatSIMatchesIbAsync` (`0 → "0 "`, `999 → "999 "`, `1234 → "1.23 k"`, `0.5 → "500 m"`).
  - `idleTimeoutsFireOnSilenceAndRearm` (`after: .milliseconds(50)`: one element ≥ 50 ms; a fed frame re-arms; a
    second element follows).
  - `throttlingReportsStartAndEnd` (`maxRequests: 1`: three quick requests → `[false, true, false]`).
  - `endpointNamesTheConnection`; `libraryVersionMatchesThePodspec` (reads `SwiftIBKR.podspec` at the package root
    found from `#filePath`).
  - `logHandlerSeesFramesAndOrders`: `.debug` lines start with `>>> 71|2|7|` and `<<< `; a placeOrder gives one
    `.info` line.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "ConnectOptionsTests|Handshake|Throttle"`. Expected: FAIL.
- [ ] **Step 3: Implement.** The writer task reports throttle start/end and its sent counts through actor hops;
  `messagesSent` counts frames actually written.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS (the sync-count tests use client 7, so
  `FakeGateway.syncFrames` stays 6).
- [ ] **Step 5: Docs, PARITY, commit** («Add ConnectOptions with ib_async's connect options and startup fetch set,
  connection stats, idle timeouts, throttle events and a log handler, and auto-bind client 0»).

**Named risks:** auto-bind changes client 0's frames (DECISIONS row 100, CHANGELOG); `fetch: []` must not leave
`syncEnds` empty-but-non-nil so `connect` hangs; the handler runs synchronously on the actor (FA XML and verify
payloads appear at `.debug` only); `idleTimeouts` must stop its timer task when the consumer stops.

### Task 11: Convenience one-shots, ids, raw send, account summary default (group 10; R13, R16)

**Files:**
- Create: `Sources/IBKR/Client/IBClient+Orders.swift`
- Modify: `Sources/IBKR/Client/IBClient.swift` (`answer` for id-less waiters; `routeToStream`: openOrder,
  completedOrder and their ends to local waiters, `-1` errors, 1102; `accountSummary`; `send` made public),
  `Sources/IBKR/Client/ConnectOptions.swift` (`idlessRequestTimeout`), `Sources/IBKR/Client/IBClientError.swift`
  (`.timeout`'s doc)
- Test: create `Tests/IBKRTests/IBClientOneShotTests.swift`; modify `IBClientAccountTests.swift`,
  `IBClientSessionTests.swift`, `IBClientReferenceTests.swift`, `IBClientResearchTests.swift`
- Docs: DECISIONS rows 86, 91, 95 (the id-less one-shots fail on a `-1` fatal or warning and are bounded, R16), row
  58 (accountSummary's default tags and 1102, R13), decision 11; README (names: `reqOpenOrders`,
  `reqAllOpenOrders`, `reqCompletedOrders`, `reqExecutions`, `getReqId`, `send`, `accountSummary`), KNOWN-GAPS (drop
  the id-less one-shots line), CHANGELOG, PARITY (group-10 rows → `added`)

**Interfaces:**
- Consumes: the order tracker (Task 7), `RequestStream.resend` (Task 8), `ConnectOptions` (Task 10).
- Produces:
  - `public func fetchOpenOrders() async throws(IBClientError) -> [OrderSnapshot]` (5 to 53) and
    `public func fetchAllOpenOrders() async throws(IBClientError) -> [OrderSnapshot]` (16 to 53): the tracker's
    snapshots of the orders whose openOrder came in the answer, in arrival order.
  - `public func completedOrders(apiOnly: Bool = false) async throws(IBClientError) -> [OrderSnapshot]` (99 to 102).
  - `public func executions(filter: ExecutionFilter) async throws(IBClientError) -> [Fill]` (7 with a reqId, to 55):
    the joined fills of the executions listed, at the end marker. Recorded evidence
    (`liveOrderFillsWithCommission.json`): the replay's commission reports arrive before 55. An execution still
    without its commission is left out and logged at `.warning`.
  - `public func reserveOrderID(atLeast minimum: Int = 0) throws(IBClientError) -> Int` (client.py:162-173).
  - `public func send(_ request: IBRequest) throws(IBClientError)` (the existing internal one; its doc says answers
    arrive on `messages()` and a `placeOrder` sent this way skips `orders()`'s local states).
  - `accountSummary(tags: [String] = IBClient.defaultAccountSummaryTags, group: String = "All")`, with
    `public static let defaultAccountSummaryTags: [String]` = ib.py:2247-2258's 34 tags and `"$LEDGER:ALL"`. On notice
    1102 every open account-summary stream sends its cancel and its request again under its reqId (ib.py:414).
  - `ConnectOptions.idlessRequestTimeout: Duration? = .seconds(10)`. The id-less one-shots (`currentTime`,
    `managedAccounts`, `nextOrderID`, `depthExchanges`, `marketRule`, `familyCodes`, `scannerParameters`,
    `newsProviders`, `faData`, `fetchOpenOrders`, `fetchAllOpenOrders`, `completedOrders`) end with
    `.ib(code:text:)` on a fatal or warning error with reqId −1, and with `.timeout` after the bound (`nil`: no
    bound). An unrelated −1 error fails every one waiting (documented).

- [ ] **Step 1: Write the failing tests:**
  - `fetchOpenOrdersReturnsTheAnswer`: `onRequest` answers 5 with two openOrder frames (`Fixtures.openOrderFields`)
    and `["53","1"]` → two snapshots; the same for `fetchAllOpenOrders` (16); `completedOrdersReturnsTheAnswer` (99 →
    one completedOrder and `["102"]`).
  - `executionsWithFilterReturnsJoinedFills`: 7 answered by the `reconnectDoesNotRepublishFills` exec and
    commission arrays (reqId set to the request's) and `["55","1",id]` → one `Fill`; the sent frame carries the
    filter. `executionsFailOnTheirError`: `ibError(id, "321", …)` → `.ib`.
  - `reserveOrderIDTakesFromTheSequence`: two calls give n, n+1; `atLeast: 100` gives 100; the next `placeOrder`
    uses 101.
  - `rawSendGoesThroughTheQueue`: `send(.currentTime)` → the gateway sees `["49","1"]`.
  - `accountSummaryDefaultsToIbAsyncTags`: the 62 frame's tag field is the joined default list, group `All`.
    `accountSummaryResubscribesOn1102`: `ibError("-1", "1102", "Connectivity between IB and Trader Workstation has been restored - data maintained.")`
    → 63, then 62 again with the same reqId; the stream keeps yielding.
  - `idlessOneShotIgnoresNoticesAndFailsOnFatal` (Review Focus 3): during `currentTime()`, a `-1` 2104 changes
    nothing; `ibError("-1", "1100", "Connectivity between IB and Trader Workstation has been lost.")` ends it with
    `.ib(code: 1100, …)`; with `idlessRequestTimeout: .milliseconds(50)` and no answer it throws `.timeout`; the same
    timeout for `faData`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "IBClientOneShotTests|accountSummary|idless"`. Expected: FAIL.
- [ ] **Step 3: Implement.** Local waiters (keys < −1) are also offered `.openOrder`, `.openOrderEnd`,
  `.completedOrder` and `.completedOrdersEnd`; `handle` already applies the trackers before `routeToStream`, so the
  snapshots are in place when a waiter reads them. The timeout is one task per waiter, cancelled when it ends.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs, PARITY, commit** («Add ib_async's open, completed and filtered-execution one-shots, id
  reservation, a public raw send and the default account summary, and bound the id-less one-shots»).

**Named risks:** a sync in flight must not feed a one-shot (they require `.connected`); the 1102 resend must skip
streams of an older generation; a timeout task must not outlive its waiter; 1100 is fatal in the error table, so a
connectivity drop now fails every id-less waiter (intended: R16).

### Task 12: Dates, util time helpers and model extras (groups 12, 13)

**Files:**
- Create: `Sources/IBKR/Models/IBDate.swift` (`IBDate`; the formatters at `IBRequest.swift:395-407` move here as
  internal statics), `Sources/IBKR/Models/TradingSessions.swift`, `Sources/IBKR/Client/IBClient+Time.swift`
- Modify: `Sources/IBKR/Models/Execution.swift` (`date`), `Sources/IBKR/State/ExecutionTracker.swift` (`Fill.time`,
  `apply(_:receivedAt:)`), `Sources/IBKR/Messages/IBDecoder.swift` (internal `decode(_:gatewayTimeZone:)`),
  `Sources/IBKR/Client/IBClient.swift`, `Sources/IBKR/Client/ConnectOptions.swift` (`gatewayTimeZone`),
  `Sources/IBKR/Models/MarketData.swift` (`OptionComputation` operators), `Sources/IBKR/Models/Contract.swift`
  (`pair`), `Sources/IBKRFlex/FlexReport.swift`, `Sources/IBKRFlex/FlexXML.swift`
- Test: create `Tests/IBKRTests/IBDateTests.swift`; modify `DecoderTests.swift`, `ExecutionTrackerTests.swift`,
  `IBClientConnectTests.swift`, `Tests/IBKRFlexTests/FlexReportTests.swift`, `PublicAPITests.swift`
- Docs: DECISIONS row 8 (decision 12), README (names: the util helpers, `TimezoneTWS`, `Forex.pair`,
  `TradingSession`, `FlexReport.root`), KNOWN-GAPS (the execDetails-time line now points at `Execution.date`; it
  stays a live-format item), CHANGELOG, PARITY (groups 12 and 13 except `tree`; `TimezoneTWS` and the
  `timeRange`/`waitUntil` IB aliases → `added`)

**Interfaces:**
- Produces:
  - `public enum IBDate { public static func format(_ date: Date) -> String; public static func parse(_ text: String, timeZone: TimeZone = TimeZone(identifier: "UTC")!) -> Date? }`
    (util.py:574-622). Format: `yyyyMMdd HH:mm:ss UTC`. Parse: 8 characters → that day 00:00 in `timeZone`; all
    digits → epoch seconds; at least two spaces and no double space → `yyyyMMdd HH:mm:ss` in the zone named by the
    rest; otherwise spaces and `-` removed and the first 16 characters read as `yyyyMMddHH:mm:ss` in `timeZone`;
    anything else `nil`.
  - On `IBClient`: `public nonisolated static func timeRange(from start: Date, to end: Date, every step: Duration) -> AsyncStream<Date>`
    and `public nonisolated static func wait(until date: Date) async throws` (util.py:409-475: points before now are
    skipped, each point is yielded once reached, a stopped consumer ends it).
  - `ConnectOptions.gatewayTimeZone: TimeZone? = nil`; `Execution.date: Date?` (the decoder reads `time` in
    `gatewayTimeZone ?? UTC`); `Fill.time: Date?` and `Fill(contract:execution:commission:time: Date? = nil)`;
    `ExecutionTracker.apply(_ message: IBMessage, receivedAt: Date? = nil)` — the client passes `Date()` for an
    execDetails with reqId −1 (live) and `nil` otherwise, which takes `execution.date` (wrapper.py:821-823).
  - `OptionComputation` `static func +`, `-` (two computations) and `*` (a computation and a `Decimal`): field-wise
    on the seven greeks with `nil` read as 0 (a result is `nil` only when both sides are), `undPrice` from the left,
    `tickAttrib` 0 (objects.py:370-413).
  - `Contract.pair: String` (`symbol + currency`, contract.py:377).
  - `public struct TradingSession { public var start: Date; public var end: Date }`;
    `ContractDetails.tradingSessions`, `liquidSessions: [TradingSession]` (contract.py:599-635: split on `;`, skip
    `CLOSED`, read each `yyyyMMdd:HHmm-yyyyMMdd:HHmm` in `TimeZone(identifier: timeZoneID)`; an unknown zone → `[]`).
  - `IBKRFlex`: `public struct FlexElement: Sendable, Equatable, Encodable` (`name`, `attributes`, `depth`, `text`,
    a public memberwise init) and `public let elements: [FlexElement]` on `FlexReport`.

- [ ] **Step 1: Write the failing tests:**
  - `formatMatchesIbAsync` (2026-11-10 21:00:00 UTC → `"20261110 21:00:00 UTC"`); `parseReadsEveryIbForm`
    (`"20261110"`, `"1794344400"`, `"20261110 16:00:00 US/Eastern"`, `"20261110  16:00:00"`,
    `"2026-11-10 16:00:00.0"`, and `"noon"` → `nil`).
  - `executionDateReadsBothLiveFormats` (Review Focus 5): `"20261110-11:56:31"` and `"20261110 06:56:31 US/Eastern"`
    give the same instant; with `gatewayTimeZone` US/Eastern the first reads five hours later; the recorded frames
    decode with `date` set.
  - `liveFillTimeIsArrivalReplayIsExecution`: an execDetails with reqId −1 gets a `Fill.time` within 2 s of now; the
    sync's replay gets `execution.date`.
  - `timeRangeSkipsPastPointsAndYieldsEach` (start 1 s ago, step 20 ms, end 70 ms ahead → about three points, each
    ≥ now, in order); `waitUntilReturnsAtTheDate`.
  - `greeksAddSubtractAndScale`; `forexPair`; `tradingSessionsParseAndSkipClosed`
    (`"20261110:0930-20261110:1600;20261111:CLOSED"` in `US/Eastern` → one session 14:30–21:00 UTC);
    `FlexReportTests.elementsArePublic`.
- [ ] **Step 2: Run, implement, run** `timeout 900 swift test`. Expected: FAIL, then PASS.
- [ ] **Step 3: Docs, PARITY, commit** («Read IB's dates as ib_async does: IBDate, execution and fill times, trading
  sessions, time ranges, greek arithmetic and the Flex elements»).

**Named risks:** shared `DateFormatter`s must never be mutated after creation (one per zone, or `Calendar`
arithmetic); `TimeZone(identifier: "US/Eastern")` must exist on Windows' ICU (the test covers it); the zone-less
default (UTC) differs from ib_async's local zone (decision 12).

### Task 13: IBC and Watchdog (group 15; R8, R9, R11)

**Files:**
- Create: `Sources/IBKR/Client/IBC.swift`, `Sources/IBKR/Client/Watchdog.swift` (each wholly inside
  `#if os(macOS) || os(Linux) || os(Windows)`)
- Test: create `Tests/IBKRTests/WatchdogTests.swift` (the same guard)
- Docs: DECISIONS (a row lifting the spec's non-goal citing «всё как в ib_async», R9; the probe choice, R8; the
  Windows `twsSettingsPath` quirk kept as ib_async has it), README (Status: a «Gateway control» row, «on a fake
  process and the fake gateway; never run against IBC»; a guide section «Running the gateway with IBC»; names `IBC`,
  `Watchdog`), KNOWN-GAPS (IBC and `Watchdog` never ran against an IBC install), CHANGELOG, PARITY (all 25 group-15
  rows → `added`)

**Interfaces:**
- Consumes: `ConnectOptions`, `idleTimeouts(after:)`, the log handler (Task 10), `currentTime()`, `historicalBars`,
  `states()`, `messages()`.
- Produces:
  - `public actor IBC` with `public nonisolated let twsVersion: Int, gateway: Bool, tradingMode: String, twsPath: String, twsSettingsPath: String, ibcPath: String, ibcIni: String, javaPath: String, userID: String, password: String, fixUserID: String, fixPassword: String, on2FATimeout: String, logLevel: IBLogLevel`
    and `public init(twsVersion: Int = 0, gateway: Bool = false, tradingMode: String = "", …, ibcPath: String = <"/opt/ibc", or "C:\\IBC" on Windows>, …, logLevel: IBLogLevel = .debug)`
    (ibcontroller.py:84-104); `public func start(logTo client: IBClient? = nil) async throws` (a no-op while
    running; a launch failure throws); `public func terminate() async` (Windows: `taskkill /F /T /PID <pid>`;
    elsewhere terminate and wait; a no-op when not running). Stdout lines go to `client`'s handler at `logLevel`.
  - internal `func arguments(windows: Bool) -> [String]`: the script (`<ibcPath>\scripts\StartIBC.bat` or
    `<ibcPath>/scripts/ibcstart.sh`), then each non-empty field in ib_async's order (ibcontroller.py:129-160):
    `twsVersion` bare, `--gateway`/`/Gateway`, `--mode=`/`/Mode:`, `--tws-path=`/`/TwsPath:`,
    `--tws-settings-path=`/(the bare value on Windows, as ib_async), `--ibc-path=`/`/IbcPath:`,
    `--ibc-ini=`/`/Config:`, `--java-path=`/`/JavaPath:`, `--user=`/`/User:`, `--pw=`/`/PW:`,
    `--fix-user=`/`/FIXUser:`, `--fix-pw=`/`/FIXPW:`, `--on2fatimeout=`/`/On2FATimeout:`.
  - internal launcher seam: `protocol LaunchedApp: Sendable { var lines: AsyncStream<String> { get }; func terminate() async }`,
    `typealias AppLauncher = @Sendable (_ arguments: [String], _ windows: Bool) throws -> any LaunchedApp`, an
    internal `IBC(…, launcher:)`; the default launcher is Foundation `Process` with a stdout `Pipe`.
  - `public enum WatchdogEvent: Sendable, Equatable, Encodable { case starting, started, stopping, stopped, softTimeout, hardTimeout }`.
  - `public actor Watchdog` with `public init(controller: IBC, client: IBClient, host: String = "127.0.0.1", port: Int = 7497, clientID: Int = 1, connectTimeout: Duration = .seconds(2), options: ConnectOptions = .init(), appStartupTime: Duration = .seconds(30), appTimeout: Duration = .seconds(20), retryDelay: Duration = .seconds(2), probeContract: Contract? = nil, probeTimeout: Duration = .seconds(4))`
    (ibcontroller.py:261-274; every parameter a `public nonisolated let`); `public func start() async throws(IBClientError)`
    (`.alreadyConnected` unless the client is `.disconnected`; emits `.starting` and starts the loop);
    `public func stop() async` (emits `.stopping`, disconnects and ends the loop, which terminates the app and emits
    `.stopped`); `public func events() -> AsyncStream<WatchdogEvent>` (fresh per call).
  - The loop (ibcontroller.py:304-366): start the app, sleep `appStartupTime`,
    `connect(host:port:clientID:timeout: connectTimeout, options:)`, `.started`. On each
    `idleTimeouts(after: appTimeout)` element: `.softTimeout`, then the probe bounded by `probeTimeout` —
    `currentTime()`, or with `probeContract` the history request `30 S` / `5 secs` / `MIDPOINT` / `rth: false`
    whose first batch must be non-empty (R8); no answer → `.hardTimeout` and a restart. Error 100 or 1100 on
    `messages()`, or `.disconnected` on `states()`, also restarts. Every exit: disconnect, `controller.terminate()`,
    `.stopped`, then, unless stopped, sleep `retryDelay` and go round.

- [ ] **Step 1: Write the failing tests** (a `FakeLauncher` that records launches and terminations; clients on
  `Gateways`; every duration in milliseconds):
  - `ibcArgumentsMatchIbAsync`: `IBC(twsVersion: 1030, gateway: true, tradingMode: "paper", userID: "u", password: "p")`
    → Unix `["/opt/ibc/scripts/ibcstart.sh", "1030", "--gateway", "--mode=paper", "--ibc-path=/opt/ibc", "--user=u", "--pw=p"]`,
    Windows `["C:\\IBC\\scripts\\StartIBC.bat", "1030", "/Gateway", "/Mode:paper", "/IbcPath:C:\\IBC", "/User:u", "/PW:p"]`
    (pass `ibcPath` explicitly for the platform-independent check).
  - `ibcLinesGoToTheLogHandler`: two fake stdout lines reach the client's handler at `.debug`.
  - `ibcTerminateIsIdempotent`.
  - `watchdogStartsConnectsAndStops`: `[.starting, .started]`, then `stop()` → `.stopping`, `.stopped`; one launch,
    one termination.
  - `hardTimeoutRestartsTheApp`: the first gateway never answers 49 → `.softTimeout`, `.hardTimeout`, `.stopped`,
    `.starting`, `.started` on the second gateway; two launches.
  - `probeContractUsesTheHistoryProbe` (R8): the probe frame is 20 with `30 S`, `5 secs`, `MIDPOINT`, `0`.
  - `error1100Restarts`; `startOnAConnectedClientThrows`.
  - `stopDuringStartupTerminatesOnce` (Review Focus 4): `stop()` while the loop sleeps `appStartupTime` → one
    termination, `[.starting, .stopping, .stopped]`, and no second launch within 200 ms.
- [ ] **Step 2: Run** `timeout 900 swift test --filter WatchdogTests`. Expected: compile FAIL.
- [ ] **Step 3: Implement.** The loop is one `Task` held by the actor; `stop()` cancels it, and the loop's
  cancellation path runs the terminate-and-`.stopped` step exactly once. The real launcher reads stdout lines on
  its own thread into the `AsyncStream`; on Windows the `.bat` runs through `cmd.exe /c`. Never log the command
  line: it holds the password.
- [ ] **Step 4: Run** `timeout 900 swift test` (Windows locally). The guard must also compile out of the iOS build,
  which only CI checks: the reviewer reads the guard.
- [ ] **Step 5: Docs, PARITY, commit** («Add IBC and Watchdog, which start IB Gateway or TWS through IBC, probe it
  and restart it, as ib_async does»).

**Named risks:** `Process` with a `.bat` on Windows (the test only checks arguments); a password on the command
line is visible to other local users (the doc comment says so, as with ib_async); the loop must not leak the
idle-timeout, messages or states consumers across restarts; stop/restart races.

### Task 14: KNOWN-GAPS closure (R17, R18)

**Files:**
- Modify: `Sources/IBKR/Client/TCPSocket.swift`, `Sources/IBKR/Wire/Frame.swift`, `Sources/IBKR/Errors.swift`
  (`IBEncodingError.frameTooLong(Int)`), `Sources/IBKR/Client/IBClient.swift` (`encode`, the R17 path),
  `Sources/IBKR/State/ExecutionTracker.swift` (the cap), `Tests/IBKRTests/FakeGateway.swift` (stay-open mode,
  blocking writes)
- Test: `TCPSocketTests.swift`, `FrameTests.swift`, `FieldTests.swift`, `ExecutionTrackerTests.swift`,
  `IBClientOrderTests.swift` (`frameAfterDisconnectIsIgnored`), `IBClientConnectTests.swift`,
  `IBClientAccountTests.swift`
- Docs: KNOWN-GAPS (rewritten, Step 5), DECISIONS (the «Subscriber buffers» line moves here as a row; rows 9 (the
  cap) and 104 (R17)), CHANGELOG (Changed)

**Interfaces:**
- Produces: `TCPSocket.connect` checks a cancel flag, set by `withTaskCancellationHandler`, between `poll` slices
  of at most 100 ms and throws `.cancelled`; `poll`, `send` and `recv` retry on `EINTR` (POSIX) and `WSAEINTR`
  (Windows); `Frame.encode(_:) throws(IBEncodingError) -> [UInt8]` throws `.frameTooLong(count)` above
  `Frame.maxLength`; `ExecutionTracker` evicts the oldest unmatched half above `maxPending = 10_000` (internal
  `init(maxPending:)` for tests); a fatal error on a sync reqAccountUpdatesMulti id after `connect` returned
  finishes every current `accountValues()` updates stream, logs the error at `.error` and drops the id (R17).
- **R17 as built:** `accountValues()` returns an `AsyncStream`, which cannot carry an error, and making it throwing
  breaks every consumer's `for await`. So the streams end (no silent stall), the typed error is on `messages()` and
  in the log, and the next `connect` re-arms. A typed error in the stream itself is a 2.0.0 change.

- [ ] **Step 1: Write the failing tests:**
  - `connectReturnsSoonAfterCancel`: `TCPSocket.connect(host: "10.255.255.1", port: 4002, timeout: .seconds(30))` in
    a task cancelled after 100 ms ends (with any error) within 1 s of the cancel.
  - `encodeRefusesAnOversizedFrame` (`Frame.maxLength + 1` bytes → `.frameTooLong`); `readerAcceptsTheMaximumFrame`
    (exactly `0xFFFFFF` bytes reassemble; one more is rejected at the header).
  - `FieldTests.intAndDecimalOfEmptyAreZero`; `FieldTests.boolDoubleAndSkip` (bool `"1"`/`"0"`/`""`, double
    `"1.5"`/`""`, `skip(2)` then the third field).
  - `drainingDisconnectClosesWithinTwoSeconds`: `FakeGateway(blocksWrites: true)` once synced → `disconnect()` →
    `isClosed` within 2.5 s (`within("close", seconds: 4)`).
  - `frameAfterDisconnectIsIgnored` runs on `FakeGateway(staysOpenAfterClose: true)` and fails with the generation
    guard in `receive` removed (prove it once by deleting the guard locally).
  - `lateStopDoesNotCancelAReusedID`: a stream on connection 1 under reqId n; disconnect; reconnect (a second gateway
    with the same `nextValidID`) and open a stream under n; stop the first consumer → no cancel for n reaches the
    second gateway, and the second stream still routes. It fails with the guard in `stopped` removed.
  - `unmatchedHalvesAreCapped`: `ExecutionTracker(maxPending: 3)`, four lone commissions, then the first one's
    execDetails → no fill (evicted); the fourth's → a fill.
  - `fatalErrorOnASyncMultiIDEndsAccountValues` (R17): accounts `"DU1,DU2"`, after `connect`
    `ibError(<a sync 76 id>, "321", "x")` → the `accountValues()` updates stream finishes within 2 s, and one `.error`
    log line.
- [ ] **Step 2: Run** the new tests. Expected: FAIL.
- [ ] **Step 3: Implement.** The poll slices end at the deadline or at the cancel, whichever is first.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: KNOWN-GAPS.** Keep only items that need a live gateway, a data subscription, a token or the owner's
  account, each saying which. «Sockets» and «To build later» go with the lines this stage closed; both «GitHub Pages
  not enabled» lines go (Pages is on: <https://peppperrroni.github.io/swift-ibkr/>); `exerciseOptions` and the
  verify-order lines move under «To confirm against a live gateway»; add the stage-14 live items (the TickAttrib
  bits, IBC/Watchdog, the 165 empty scan, 10225, ValidationError on a live warning, the read-only API mode,
  `+PACEAPI`, 50+ sub-accounts). Title «Known gaps after stage 14».
- [ ] **Step 6: Commit** («Close the socket, frame, tracker and test gaps KNOWN-GAPS listed, and keep only what needs
  a live gateway there»).

**Named risks:** the cancellable connect touches three OSes (`WSAPoll` on Windows; CI is the only check for macOS and
Linux); 10.255.255.1 may fail fast (unreachable) on a runner, and the test only asserts the bound; `Frame.encode`
now throws, so every caller (`IBClient.encode`, `FakeGateway.feed`, tests) handles it.

### Task 15: Documents closure

**Files:**
- Modify: `README.md` (Status, guide, the ib_async names table), `Sources/IBKR/IBKR.docc/MigratingFromIbAsync.md`,
  `MarketData.md`, `Orders.md`, `GettingStarted.md`, `IBKR.md` (topic groups for the new types),
  `Sources/IBKRFlex/IBKRFlex.docc/IBKRFlex.md`, `CHANGELOG.md`, `docs/PARITY.md`, `docs/DECISIONS.md`
- No source changes except doc comments the gate flags.

- [ ] **Step 1: PARITY.** No row says `MISSING`; the legend has `added` («implemented in stage 14») beside
  `present` («in 1.0.0»); the Totals line is recounted from the rows (expected `present` 219, `added` 164, `n/a`
  33 unless a task split or merged a row).
- [ ] **Step 2: README.** Every `added` row's Swift name appears in the names table, and every name in the table
  exists in `Sources` with those labels (checked against the symbol graph). Status rows cover live bars, the
  registry, IBC/Watchdog and logging with their real test state; the semver paragraph names decision 1's breaking
  changes.
- [ ] **Step 3: DocC.** MigratingFromIbAsync loses «A `ReconnectPolicy` replaces `Watchdog`. There is no IBC» and
  gains IBC/Watchdog, `ConnectOptions`, the order log, the tick filters and the registry; MarketData covers the
  named fields, `ticks` and the filters; Orders covers the local states, `log`, `fills`, `orderEvents()`; IBKR.md
  lists the new types in its topic groups. Every symbol link must resolve (`--warnings-as-errors` in CI).
- [ ] **Step 4: CHANGELOG** `## [Unreleased]`: an `### Added` entry per task; `### Changed` with each behaviour
  change (R3, R4, R6, R13's auto-bind, R17, R18) and decision 1's **Breaking** list; no version, no date.
- [ ] **Step 5: Gates.** `timeout 900 swift test` → PASS. The doc-coverage gate of `.github/workflows/docs.yml`
  (Python 3 is on this machine as `py`):

```bash
dir="$PWD/.build/symbol-graphs"; mkdir -p "$dir"
for t in IBKR IBKRFlex; do swift build --target $t -Xswiftc -emit-symbol-graph -Xswiftc -emit-symbol-graph-dir -Xswiftc "$dir"; done
py Scripts/doc-coverage.py "$dir"/IBKR.symbols.json "$dir"/IBKRFlex.symbols.json
```

  Expected: exit 0 and «checked N public symbols» on stderr. DocC's `docbuild` runs on macOS only; CI's docs job is
  its check.
- [ ] **Step 6: Commit** («Bring README, the DocC articles, CHANGELOG and PARITY in line with the parity closure»).

**Named risks:** a README name that does not exist with those labels; DocC symbol links to the `#if os(…)` IBC and
`Watchdog` types do not resolve in an iOS docbuild (name them in code voice in the articles, not as ``symbol``
links); PARITY's totals drifting from its rows.
