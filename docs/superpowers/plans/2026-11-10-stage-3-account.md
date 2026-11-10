# swift-ibkr Stage 3: Positions, Account Summary, P&L — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `IBClient` gives a consumer the account's positions (snapshot + stream of whole sets, in sync from the moment `connect` returns), an account-summary subscription and a per-position P&L subscription, checked on the fake gateway and once live on the owner's paper account.

**Architecture:** Codec first (three incoming messages with their end markers, four outgoing requests), then a `PositionTracker` beside the order and execution trackers, fed by a `reqPositions` that joins the connect-time sync and stays on for the whole connection. Account summary and P&L are per-request streams: `IBClient` keeps a registry of open request streams keyed by reqId, routes their messages and fatal errors to them, sends the cancel when the consumer stops and ends them all when the connection ends.

**Tech Stack:** Swift 6.4.2, SwiftPM tools 6.0 (Swift 6 language mode), Foundation, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-09-swift-ibkr-design.md` (sections «Устройство», «Публичный API», «Сообщения», «Этапы» item 3).

## Global Constraints

- Repository `C:\Users\viohn\swift-ibkr`, branch `stage-3-account` off `main` (1378ada). Nothing is pushed to GitHub, and `main` is not moved, without the owner's «да». Build with `swift build`, test with `swift test`.
- No dependencies. Swift 6 strict concurrency, no warnings in `Sources/`.
- Never copy code from the official `ibapi`. Field order goes into `docs/protocol-178.md` first; the layouts below follow `ib_async` (checked 2026-11-10 against its `decoder.py` / `client.py`).
- Orders and requests share ONE id counter (`IBClient.nextRequestID()`).
- Money and quantities are `Decimal`; IB's unset markers (`""`, `1.7976931348623157E308`, …) read as `nil` through `FieldReader.optionalDecimal()`. In tests use `d("…")`.
- Tests use `@testable import IBKR`, the helpers `body(_:)`, `d(_:)`, `within2s`, and `FakeGateway` (its `onRequest` replies are fed before its defaults). A test that waits on an async event waits at most 2 s.
- Commits: one imperative sentence + reasoning; last line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. `README.md`, `docs/DECISIONS.md`, `docs/KNOWN-GAPS.md` and `docs/protocol-178.md` change in the commit whose behaviour they describe. At the end verify the series with `git rebase --exec "swift test > /dev/null" main`.
- Live tests run only with `IBKR_LIVE=1`, and only the controller runs them, on the paper account, after the owner's go. Recordings redact every account id to `DU0000001`; the real account id never enters the repository.

## Decisions taken in this plan (owner can veto)

- **Positions are always on**, as in `ib_async`: `connect` sends `reqPositions` with the sync and waits for `positionEnd`; `cancelPositions` is never sent. `positions()` is snapshot + `AsyncStream<[Position]>` like `orders()`, not the spec sketch's per-call `AsyncThrowingStream`. Why: a trading app needs positions from the first moment, as it needs orders; `reqPositions` has no reqId, so there is no per-request error to throw; one subscription per connection needs no reference counting.
- A position of 0 is removed from the set (`ib_async` does the same). The set is keyed by (account, conID) and sorted by account, then conID.
- On reconnect the old set stays visible until the new sync's `positionEnd`, then is replaced whole: a position closed while disconnected disappears then, not before.
- `accountSummary` and `pnlSingle` streams end, throwing, when the connection ends (the end's error, or `.connectionClosed` for `disconnect()`), and are not resumed on reconnect: the consumer subscribes again. A fatal IB error with the stream's reqId ends it with `.ib(code:text:)`.
- `AccountValue.value` stays IB's string: some tags are text (`AccountType`), and the consumer knows which tags it asked for.
- The account-summary stream yields the whole set (keyed by account, tag, currency) at `accountSummaryEnd` and, after the first end, on every change; it never yields a set equal to the one it yielded last. Whether IB repeats `accountSummaryEnd` after each 3-minute update is unknown; this rule is right either way, and the live run tells.
- Not in this stage: account-level `reqPnL` (92), `reqAccountUpdates` (portfolio with market value), `cancelPositions`. Public memberwise initialisers for the new models wait for stage 5, like the others.

## Review Focus

1. The connection drops while an account-summary or P&L stream is open → the stream throws, the consumer's `for try await` ends, nothing hangs → Task 4 `disconnectEndsRequestStreams`.
2. IB refuses a third concurrent account summary (error 322) → that stream throws `.ib(code: 322, …)`, the others go on → Task 4 `accountSummaryErrorEndsOnlyItsStream`.
3. The consumer drops a stream → the cancel goes out, so IB stops sending and the two-subscription limit frees up; a late message for the dead reqId is ignored → Task 4 `stoppingAStreamSendsItsCancel`.
4. A position closed while disconnected → gone after reconnect, without a spurious intermediate set → Task 3 `reconnectReplacesPositionsWhole`.
5. P&L fields IB leaves unset (Double max) → `nil`, never 1.8e308 → Task 1 `pnlSingleDecodes`.

---

### Task 1: Codec for positions, account summary and P&L

**Files:**
- Create: `Sources/IBKR/Models/Account.swift`, `Tests/IBKRTests/AccountCodecTests.swift`
- Modify: `Sources/IBKR/Messages/IBMessage.swift`, `Sources/IBKR/Messages/IBDecoder.swift`, `Sources/IBKR/Messages/IBRequest.swift`, `docs/protocol-178.md`

**Interfaces:**
- Produces:
  - `public struct Position: Sendable, Equatable { public var account: String; public var contract: Contract; public var quantity: Decimal; public var averageCost: Decimal }`
  - `public struct AccountValue: Sendable, Equatable { public var account: String; public var tag: String; public var value: String; public var currency: String }`
  - `public struct PnL: Sendable, Equatable { public var position: Decimal; public var daily: Decimal?; public var unrealized: Decimal?; public var realized: Decimal?; public var value: Decimal? }`
  - `IBMessage` cases: `.position(Position)` (61), `.positionEnd` (62), `.accountSummary(requestID: Int, AccountValue)` (63), `.accountSummaryEnd(requestID: Int)` (64), `.pnlSingle(requestID: Int, PnL)` (95).
  - `IBRequest` cases: `.positions` (61), `.accountSummary(requestID: Int, group: String, tags: [String])` (62), `.cancelAccountSummary(requestID: Int)` (63), `.pnlSingle(requestID: Int, account: String, modelCode: String, conID: Int)` (94), `.cancelPnLSingle(requestID: Int)` (95).
- Wire layouts (protocol-178 sections to add, one per message, in the file's existing table style):
  - in 61: id, version (skip), account, then the 11-field contract that `contract(&r)` in `OrderDecoding.swift` already reads (conId … tradingClass, no primaryExchange), position (decimal), avgCost (decimal).
  - in 62: id, version. in 63: id, version, reqId, account, tag, value, currency. in 64: id, version, reqId.
  - in 95: id, reqId, pos, dailyPnL, unrealizedPnL, realizedPnL, value — no version field; all but reqId are decimals that may be unset.
  - out 61: `61`, `1`. out 62: `62`, `1`, reqId, group, tags joined with `,`. out 63: `63`, `1`, reqId. out 94: `94`, reqId, account, modelCode, conId. out 95: `95`, reqId.

- [ ] **Step 1: Write the failing tests** in `AccountCodecTests.swift`
  - `positionDecodes`: `["61","3","DU1","265598","AAPL","STK","","0.0","","","NASDAQ","USD","AAPL","NMS","5","351.66000005"]` decodes to `.position(Position(account: "DU1", contract: c, quantity: d("5"), averageCost: d("351.66000005")))`, where `c` is `Contract(symbol: "AAPL")` with conID 265598, strike `0`, exchange `"NASDAQ"`, localSymbol `"AAPL"`, tradingClass `"NMS"`.
  - `positionEndDecodes`: `["62","1"]` → `.positionEnd`.
  - `accountSummaryDecodes`: `["63","1","7","DU1","NetLiquidation","1000000.00","USD"]` → `.accountSummary(requestID: 7, AccountValue(account: "DU1", tag: "NetLiquidation", value: "1000000.00", currency: "USD"))`; `["64","1","7"]` → `.accountSummaryEnd(requestID: 7)`.
  - `pnlSingleDecodes`: `["95","9","1","12.5","-3.25","1.7976931348623157E308","351.66"]` → `.pnlSingle(requestID: 9, PnL(position: 1, daily: d("12.5"), unrealized: d("-3.25"), realized: nil, value: d("351.66")))`.
  - `shortAccountFramesAreMalformed`: `["95","9","1"]` and `["63","1","7","DU1"]` decode to `.malformed` with ids 95 and 63.
  - `accountRequestsEncode`: `IBRequest.positions.body() == body("61","1")`; `.accountSummary(requestID: 7, group: "All", tags: ["NetLiquidation","BuyingPower"])` → `body("62","1","7","All","NetLiquidation,BuyingPower")`; `.cancelAccountSummary(requestID: 7)` → `body("63","1","7")`; `.pnlSingle(requestID: 9, account: "DU1", modelCode: "", conID: 265598)` → `body("94","9","DU1","","265598")`; `.cancelPnLSingle(requestID: 9)` → `body("95","9")`.
  - `nonASCIIAccountSummaryTagThrows`: tags `["Чистая"]` throws `IBEncodingError.nonASCII`.

- [ ] **Step 2: Run** `swift test --filter AccountCodecTests` — expect compile failure (types and cases missing).
- [ ] **Step 3: Implement** the models, cases, decoder branches and request bodies; add the protocol-178 sections. Strings go through `FieldWriter.add(_: String)` so non-ASCII throws.
- [ ] **Step 4: Run** `swift test` — all green, including the existing `everyRecordedFrameDecodes`.
- [ ] **Step 5: Commit** («Decode positions, account summary and single-position P&L, and encode their requests»).

### Task 2: PositionTracker

**Files:**
- Create: `Sources/IBKR/State/PositionTracker.swift`, `Tests/IBKRTests/PositionTrackerTests.swift`

**Interfaces:**
- Consumes: `Position`, `IBMessage.position`, `.positionEnd` (Task 1).
- Produces: `struct PositionTracker { init(); private(set) var positions: [Position]; mutating func reload(); mutating func apply(_ message: IBMessage) -> [Position]? }`. `apply` returns the new whole set when the visible set changed (or at a reload's end), else `nil`. While reloading, `.position` goes to a pending set and returns `nil`; `.positionEnd` makes the pending set visible and returns it. `.positionEnd` outside a reload returns `nil`.

- [ ] **Step 1: Write the failing tests** (helper `pos(_ account: String, _ conID: Int, _ qty: String) -> IBMessage`)
  - `positionUpdateReplacesByAccountAndConID`: apply `pos("DU1",1,"5")`, then `pos("DU1",1,"3")` → second returns a set of one with quantity 3.
  - `zeroPositionIsRemoved`: after `pos("DU1",1,"5")`, `pos("DU1",1,"0")` returns `[]`.
  - `sameConIDInTwoAccountsIsTwoPositions` and `positionsAreSortedByAccountThenConID`: applying `("DU2",1)`, `("DU1",2)`, `("DU1",1)` leaves the order `DU1/1, DU1/2, DU2/1`.
  - `reloadPublishesOnlyAtItsEnd`: with `[DU1/1]` visible, `reload()`, `pos("DU1",2,"1")` returns `nil` and `positions` is still `[DU1/1]`; `.positionEnd` returns `[DU1/2]`.
  - `unrelatedMessagesPublishNothing`: `.openOrderEnd` and a stray `.positionEnd` return `nil`.
- [ ] **Step 2: Run** `swift test --filter PositionTrackerTests` — fails to compile.
- [ ] **Step 3: Implement** with a dictionary keyed by account and conID; sort when publishing.
- [ ] **Step 4: Run** `swift test` — green.
- [ ] **Step 5: Commit** («Track positions by account and contract, replacing the set whole after a reload»).

### Task 3: Positions in `IBClient`

**Files:**
- Modify: `Sources/IBKR/Client/IBClient.swift`, `Tests/IBKRTests/FakeGateway.swift`, existing client tests whose sent-frame counts grow by one, `README.md`, `docs/DECISIONS.md`
- Test: `Tests/IBKRTests/IBClientPositionTests.swift`

**Interfaces:**
- Consumes: `PositionTracker` (Task 2), `IBRequest.positions` (Task 1).
- Produces: `public func positions() -> (snapshot: [Position], updates: AsyncStream<[Position]>)` — the set now, then every whole new set, registered in the same actor step. `connect` sends `.positions` with the sync's other requests and adds `.positionEnd` to the end markers it waits for. `connect` calls `positionTracker.reload()`; the tracker itself lives across connections. `FakeGateway` answers `61` with `["62","1"]` by default.

- [ ] **Step 1: Write the failing tests**
  - `syncedPositionsAreInSnapshot`: `onRequest` answers `61` with one position frame; after `connect`, `positions().snapshot` is that one position.
  - `connectWaitsForPositionEnd`: a `FakeGateway(answersPositions: false)` (new init flag, default `true`) never answers `61`; `connect(timeout: .milliseconds(300))` throws `.timeout`.
  - `positionChangeIsPublishedAsAWholeSet`: connected with one position; subscribe; feed a second position frame → first update has 2 positions.
  - `reconnectReplacesPositionsWhole`: connect with `DU1/1`; subscribe; disconnect; reconnect with `DU1/2` → the subscriber's next update is exactly `[DU1/2]`, and none in between holds both.
  - Update the existing tests that count sent frames (`waitForSent`) for the extra `reqPositions`.
- [ ] **Step 2: Run** `swift test --filter IBClientPositionTests` — fails.
- [ ] **Step 3: Implement**; README «Use» gains `positions()`; DECISIONS gains the «positions always on» and «zero removed / replaced at reload» rows with what was rejected.
- [ ] **Step 4: Run** `swift test` — green.
- [ ] **Step 5: Commit** («Sync positions at connect and keep them streaming for the whole connection»).

### Task 4: Account summary and P&L request streams

**Files:**
- Modify: `Sources/IBKR/Client/IBClient.swift`, `README.md`, `docs/DECISIONS.md`
- Test: `Tests/IBKRTests/IBClientAccountTests.swift`

**Interfaces:**
- Consumes: Task 1's requests and messages; `ErrorCode.kind`, `IBClientError`.
- Produces:
  - `public func accountSummary(tags: [String], group: String = "All") throws(IBClientError) -> AsyncThrowingStream<[AccountValue], any Error>` — set keyed by (account, tag, currency), sorted the same way; yield rule as in «Decisions».
  - `public func pnlSingle(account: String, conID: Int, modelCode: String = "") throws(IBClientError) -> AsyncThrowingStream<PnL, any Error>` — every `pnlSingle` message as it comes.
  - Both throw `.notConnected` unless connected and `.encoding` before registering anything; the reqId comes from `nextRequestID()`.
  - Internal `var requestStreamCount: Int` for tests.
- Routing: a message whose reqId has an open stream goes to it (and still to `messages()`); a `.fatal` error with that reqId finishes it with `.ib(code:text:)` and removes it without a cancel; notices do not touch it. The consumer stopping removes it and, if the same connection is still up, sends `.cancelAccountSummary` / `.cancelPnLSingle`. `end()` finishes every open stream with its error (`.connectionClosed` when it has none) and clears the registry.

- [ ] **Step 1: Write the failing tests**
  - `accountSummaryYieldsTheSetAtEnd`: request `["NetLiquidation","BuyingPower"]`; the sent frame is `["62","1",id,"All","NetLiquidation,BuyingPower"]`; feed two values for `DU1` and the end → first element is both, sorted by tag.
  - `accountSummaryYieldsChangesAfterEndButNoRepeats`: after the first set, a changed value yields the new set; a second identical end yields nothing (check with a following change being the next element).
  - `accountSummaryErrorEndsOnlyItsStream`: two streams; error `["4","2",id1,"322","Maximum number of account summary requests exceeded",""]` → stream 1 throws `.ib(code: 322, …)`; stream 2 still yields its set.
  - `noticeDoesNotEndAStream`: error code 2104 with the stream's reqId → the stream still yields afterwards.
  - `stoppingAStreamSendsItsCancel`: break out after the first element → `["63","1",id]` is sent, `requestStreamCount == 0`; a later `["63","1",id,…]` value is ignored without effect. Same for P&L with `["95",id]`.
  - `pnlSingleYieldsEachUpdate`: sent frame `["94",id,"DU1","","265598"]`; two fed updates come out in order.
  - `disconnectEndsRequestStreams`: `disconnect()` → both stream kinds throw `.connectionClosed`; a peer close → they throw the client's end error; no cancel is sent after the end.
  - `requestStreamsNeedAConnection`: before `connect`, both throw `.notConnected`.
  - `badTagRegistersNothing`: tag `"Чистая"` throws `.encoding`, `requestStreamCount == 0`, nothing sent.
- [ ] **Step 2: Run** `swift test --filter IBClientAccountTests` — fails.
- [ ] **Step 3: Implement**; README «Use» gains both calls and the 2-subscription limit; DECISIONS gains the stream-ending and `value`-as-string rows.
- [ ] **Step 4: Run** `swift test` — green.
- [ ] **Step 5: Commit** («Stream account summary and single-position P&L per request, cancelled when the consumer stops»).

### Task 5: Live check on paper, recordings, docs

Controller-run: the subagent writes the code and runs only `swift test`; the controller runs the live tests after the owner's go.

**Files:**
- Modify: `Tests/IBKRTests/LiveTests.swift`, `Tests/IBKRTests/RecordedFrameTests.swift`, `README.md`, `docs/DECISIONS.md`, `docs/KNOWN-GAPS.md`
- Create (by the live run): `Tests/IBKRTests/Recorded/liveAccountSummary.json`; re-recorded `liveOrderFillsWithCommission.json`

- [ ] **Step 1: Live tests**
  - New `liveAccountSummary` (`IBKR_LIVE=1`): `accountSummary(tags: ["NetLiquidation","TotalCashValue","BuyingPower"])` → within 15 s a set holding `NetLiquidation` for every managed account; every `positions().snapshot` entry's account is managed; leaving the loop cancels.
  - Extend `liveOrderFillsWithCommission`: before the BUY take the guard account's AAPL quantity `q0` from the snapshot and subscribe to position updates; after the BUY fill wait (30 s) for an update with AAPL at `q0 + 1`, then for a `pnlSingle(account:, conID: 265598)` value with position `q0 + 1`; after the SELL fill wait for AAPL back at `q0` and for the SELL's fill with commission, expecting `realizedPNL != nil`. These waits sit inside the existing `do` blocks, so any failure still reaches the flattening SELL.
- [ ] **Step 2: Run** `swift test` (live skipped) — green; commit («Check positions, account summary and P&L live on the paper account»).
- [ ] **Step 3 (controller): Live run** — `IBKR_LIVE=1` for `liveAccountSummary`; with the owner's go and a fresh AAPL price, `IBKR_LIVE_FILL=1` for the fill test. Check the recordings for the real account id (`grep` must find nothing).
- [ ] **Step 4: Recorded-frame tests** from what the run produced: `recordedAccountSummaryDecodes` (a `NetLiquidation` value for `DU0000001`), `recordedPositionAndPnLDecode` (AAPL position frames and the `pnlSingle` values seen), and the SELL commission's `realizedPNL` in `recordedFillHasCommission`. Exact values come from the recording.
- [ ] **Step 5: Docs** — KNOWN-GAPS header «after stage 3»; settle the realized-P&L commission line if the run saw it; record whether `accountSummaryEnd` repeats and what `pnlSingle` sends for unset values; README status «Stage 3 (done)». Commit («Record the live account frames and settle what the run showed»).
