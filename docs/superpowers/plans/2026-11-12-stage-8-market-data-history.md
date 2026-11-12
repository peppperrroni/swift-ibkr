# Stages 8 and 9: Market Data and History, Complete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every market-data and history message `ib_async` sends or decodes is in `IBRequest` / `IBMessage` with a
codec test and a client call:
- reqMktData with generic ticks, snapshots, BAG legs and the delta-neutral contract;
- ticks 21, 47, 81, 57 and 84, and messages 56, 91 and 92;
- real-time bars, depth exchanges, smart components, historical ticks, the head timestamp, the histogram and the
  trading schedule;
- a `Ticker` folded from ticks, with a stream (`tickers`) and a batch snapshot (`tickers(for:)`).

The stage also settles the depth-after-2152 question from the recorded live frames.

**Architecture:** The work follows the existing pattern: codec first, then a client call over `openStream`.
- Tasks 1–5 add the stage-8 wire messages and their calls, one group at a time.
- Task 6 decides 2152 in the depth stream's route.
- Task 7 adds `Ticker` as a pure value with `apply(_:)`.
- Task 8 builds `tickers` by composing the existing `marketData` and `marketDepth` streams, so it reuses their cancel and
  refusal rules.
- Tasks 9–11 add stage 9 on the same pattern.
- Task 12 closes the records and checks the series.

**Tech Stack:** Swift 6 (tools 6.0), SwiftPM, Foundation, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-12-parity-and-1.0-design.md`: «Этапы» items 8 and 9, «Перечень» rows Рыночные
данные and История, and «Решения после проверки строителем» item 2 (stage 8). The base spec is
`docs/superpowers/specs/2026-11-09-swift-ibkr-design.md`.

## Global Constraints

- Repository `C:\Users\viohn\swift-ibkr`, branch `stage-8-market-data` off `main` (d825d36).
- Protocol pinned to server version 178. No package dependencies; `Package.swift` keeps `// swift-tools-version: 6.0`.
- Money and quantities are `Decimal`. IB's unset markers read as `nil` through `FieldReader.optional…()`. No UNSET
  sentinel in a public type. Use `d("…")` in tests.
- Field orders come from `ib_async` 2.1.0 (`ab629f3`: `client.py`, `decoder.py`, `wrapper.py`, `ticker.py`). Every
  array in this plan was checked against that source at 178. Never copy code from IB's `ibapi`.
- Orders and requests share ONE id counter (`IBClient.nextRequestID()`).
- Every new public value type is `Sendable, Equatable`, has a public memberwise init, and joins
  `PublicAPITests.everyPublicModelIsConstructible` (plain `import IBKR`).
- Every request stream sends its cancel when the consumer stops it, where IB has a cancel message. A stream the
  client finishes itself (an end marker, a one-shot answer) sends none, unless a task says otherwise.
- The recorded live frames keep decoding: `everyRecordedFrameDecodes` and the `recorded…` tests stay green.
- The real paper account id never appears. Fixtures use `DU1`, and recordings use `DU0000001`.
- The documents of record (`README.md`, `docs/DECISIONS.md`, `docs/KNOWN-GAPS.md`, `docs/protocol-178.md`,
  `CHANGELOG.md`) change in the same commit as the behaviour they describe:
  - each task's decisions get their DECISIONS rows (numbers refer to «Decisions beyond the spec» at the end);
  - every public API change gets a CHANGELOG `Unreleased` line;
  - a new case in a public enum (`Tick`, `IBMessage`, `IBRequest`) is noted as breaking exhaustive switches.
- Commit messages are one imperative sentence, then the reasoning. Read `git log` first. The last line is exactly
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Run tests as `timeout 900 swift test`, in the foreground. A test waits on an async event for at most 2 s (`within2s`).
- CI (macOS, Linux 6.0 and latest, Windows, pod-lint) must be green. Push the branch
  (`git push -u origin stage-8-market-data`) and watch
  `gh run watch --exit-status $(gh run list --branch stage-8-market-data --limit 1 --json databaseId -q '.[0].databaseId')`.
  Moving and pushing `main` is the controller's job.

## Review Focus

1. **Greeks IB has not computed.** IB sends `-1` (impliedVol, optPrice, pvDividend, undPrice) or `-2` (delta, gamma,
   vega, theta). A consumer must see `nil`, never `-1` or `-2` read as a price or a greek. Test: Task 2
   `uncomputedGreeksAreNil`.
2. **A `tickers(for:)` batch where one contract fails.** It must throw the first error, and every other snapshot
   still open must be cancelled, with no stream left registered. Test: Task 8
   `tickersForFailsOnAnErrorAndCancelsTheRest`.
3. **Stopping a `tickers` stream that also carries depth.** Both cancels must go out (2 and 11), or one subscription
   leaks a market-data line. Test: Task 8 `tickersWithDepthCarryTheBookAndCancelBoth`.
4. **A 2152 that grants depth on some exchanges.** The book must keep streaming, because only an account with no depth
   at all gets the refusal. Test: Task 6 `depthGoesOnWhen2152GrantsSomeDepth`.
5. **Historical ticks over several frames** (`done` 0, then 1). Every tick must come back, in order, and the call must
   not return at the first frame. Test: Task 10 `historicalTicksCollectUntilDone`.

## Shared test fixtures (added to `Tests/IBKRTests/Fixtures.swift` in Task 1)

```swift
/// AAPL BAG with two legs; its 12-field contract block and the 9 leg fields reqMktData and reqHistoricalData send.
let bagContract: Contract = {
    var c = Contract(symbol: "AAPL", secType: "BAG")
    c.comboLegs = [ComboLeg(conID: 265598, ratio: 1, action: .buy, exchange: "SMART"),
                   ComboLeg(conID: 272093, ratio: 2, action: .sell, exchange: "SMART")]
    return c
}()
let bagBlock = ["0", "AAPL", "BAG", "", "0.0", "", "", "SMART", "", "USD", "", ""]
let bagLegs = ["2", "265598", "1", "BUY", "SMART", "272093", "2", "SELL", "SMART"]
```

`aapl` below is each test file's existing private
`["0", "AAPL", "STK", "", "0.0", "", "", "SMART", "", "USD", "", ""]`. `connected(gateway)` is the existing per-file
helper (client id 7). `id` is read from the sent frame, as in the existing client tests.

---

### Task 1: reqMktData parameters, BAG legs, the delta-neutral contract and snapshot end (sonnet)

**Files:**
- Modify: `Sources/IBKR/Messages/IBRequest.swift`, `Sources/IBKR/Messages/IBMessage.swift`,
  `Sources/IBKR/Messages/IBDecoder.swift`, `Sources/IBKR/Client/IBClient.swift`
- Test: `Tests/IBKRTests/TickCodecTests.swift`, `RequestTests.swift`, `IBClientMarketDataTests.swift`, `Fixtures.swift`
- Docs:
  - protocol-178: the reqMktData table is rewritten with its two conditional groups:
    - `+ comboLegsCount` and 4 fields per leg after the contract, only for `BAG`;
    - `+ conId, delta, price` after row 15 when the delta-neutral contract is present.
    It gains a new section «tickSnapshotEnd (in 57)».
  - DECISIONS: row 22 now says BAG is accepted by placeOrder and marketData; add decisions 2 and 3.
  - CHANGELOG:
    - Added: `marketData`'s `genericTicks`, `snapshot` and `regulatorySnapshot`, BAG and delta-neutral contracts in
      marketData, and `IBMessage.tickSnapshotEnd`.
    - Changed: marketData sends `Contract.deltaNeutralContract`; `IBRequest.marketData` gains three associated values,
      whose defaults keep construction compiling.

**Interfaces:**
- Produces:
  - `case marketData(requestID: Int, contract: Contract, genericTicks: [Int] = [], snapshot: Bool = false, regulatorySnapshot: Bool = false)`.
    The wire, as `ib_async` `client.reqMktData`, is:
    1. `1, 11, reqId`, then the contract block with `allowBag: true`;
    2. `comboLegs(&w, c)`;
    3. `1, conID, delta, price` (`addDouble` for both) when `c.deltaNeutralContract != nil`, else `0`;
    4. `genericTicks` joined by `","`, `snapshot`, `regulatorySnapshot`, and `""`.
  - `static func comboLegs(_ w: inout FieldWriter, _ c: Contract) throws(IBEncodingError)` in `IBRequest`:
    - it writes nothing unless `c.secType == "BAG"`;
    - otherwise it writes the count, then `conID, ratio, action.rawValue, exchange` per leg.
    Task 9 reuses it.
  - `IBMessage.tickSnapshotEnd(requestID: Int)`, decoded from `57, version, reqId`.
  - `public func marketData(_ contract: Contract, genericTicks: [Int] = [], snapshot: Bool = false, regulatorySnapshot: Bool = false) throws(IBClientError) -> AsyncThrowingStream<Tick, any Error>`.
    Its route finishes the stream at `.tickSnapshotEnd` and returns `true`, so no cancel goes out.
  - `routeToStream` routes `.tickSnapshotEnd(let id)`.

- [ ] **Step 1: Write the failing tests**
  - `TickCodecTests`:
    - `marketDataSendsItsParameters`:
      `.marketData(requestID: 7, contract: Contract(symbol: "AAPL"), genericTicks: [100, 101, 104], snapshot: true, regulatorySnapshot: true)`
      → `body(["1", "11", "7"] + aapl + ["0", "100,101,104", "1", "1", ""])`.
    - `marketDataSendsTheDeltaNeutralContract`: AAPL with
      `deltaNeutralContract = DeltaNeutralContract(conID: 265598, delta: d("0.5"), price: d("187.25"))` →
      `body(["1", "11", "7"] + aapl + ["1", "265598", "0.5", "187.25", "", "0", "0", ""])` (23 fields).
    - `marketDataSendsBagLegs`: `.marketData(requestID: 7, contract: bagContract)` →
      `body(["1", "11", "7"] + bagBlock + bagLegs + ["0", "", "0", "0", ""])` (29 fields).
    - `snapshotEndDecodes`: `body("57", "1", "7")` → `.tickSnapshotEnd(requestID: 7)`.
    - The existing `marketDataRequestsEncode` stays as it is: the defaults give the old 20 fields.
  - `RequestTests.bagIsStillRefusedOutsidePlaceOrder` becomes `bagIsRefusedWhereIBSendsNoLegs`. Both
    `.marketDepth(requestID: 1, contract: bagContract, rows: 5, smart: true)` and
    `.tickByTick(requestID: 1, contract: bagContract, type: .last)` throw `.unsupported("secType BAG")`. Tasks 4, 10
    and 11 add their requests to it.
  - `IBClientMarketDataTests`:
    - `marketDataSendsGenericTicks`: `marketData(aapl, genericTicks: [100, 101, 104])` → the sent frame has
      `[16] == "100,101,104"`, `[17] == "0"` and `[18] == "0"`.
    - `snapshotEndsWithoutCancel`:
      1. `marketData(aapl, snapshot: true, regulatorySnapshot: true)` → the sent frame has `[17] == "1"` and
         `[18] == "1"`.
      2. Feed `["1", "6", id, "1", "351.5", "200", "0"]`, then `["57", "1", id]`. `take(0, stream)` →
         `[.price(.bid, price: d("351.5"), size: d("200"))]`.
      3. After 50 ms, the sent count is still `syncFrames + 1`, and `requestStreamCount == 0`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "TickCodecTests|RequestTests|IBClientMarketDataTests"`.
  Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above. The doc comment on `IBRequest.contract` names placeOrder and marketData
  as the callers that pass `allowBag: true`.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («Send reqMktData's generic ticks, snapshot flags, BAG legs and delta-neutral contract»).

### Task 2: Ticks 21, 47, 81 and 84 (opus)

**Files:**
- Create: `Sources/IBKR/Messages/MarketDataDecoding.swift` (`extension IBDecoder` with the new decode helpers; later tasks
  add theirs here)
- Modify: `Sources/IBKR/Models/MarketData.swift`, `Sources/IBKR/Messages/IBMessage.swift` (remove
  `.tickRequestParameters`), `Sources/IBKR/Messages/IBDecoder.swift`
- Test: `TickCodecTests.swift`, `IBClientMarketDataTests.swift`, `PublicAPITests.swift`
- Docs:
  - protocol-178: new sections «tickOptionComputation (in 21)», «tickEFP (in 47)» and «tickNews (in 84)». tickReqParams
    (in 81) is now «decoded as a tick and yielded by marketData».
  - DECISIONS: row 62 is rewritten (decision 4); add decisions 5, 6 and 7.
  - CHANGELOG:
    - Added: `Tick.optionComputation`, `.efp`, `.requestParameters`, `.news`; `OptionComputation`, `EFPData`,
      `NewsTick`.
    - Changed: 81 is a tick and `marketData` yields it; `IBMessage.tickRequestParameters` is removed.

**Interfaces:**
- Produces:
  - `public struct OptionComputation`, with fields `tickAttrib: Int`, then `impliedVol`, `delta`, `optPrice`,
    `pvDividend`, `gamma`, `vega`, `theta` and `undPrice`, all `Decimal?`. Its init takes `tickAttrib` and defaults
    every other field to `nil`.
  - `public struct EFPData`, with fields `basisPoints: Decimal?`, `formattedBasisPoints: String`,
    `impliedFuture: Decimal?`, `holdDays: Int?`, `futureLastTradeDate: String`, `dividendImpact: Decimal?` and
    `dividendsToLastTradeDate: Decimal?`. Its init defaults each field to `nil` or `""`.
  - `public struct NewsTick`, with fields `timeStamp: Int`, `providerCode`, `articleID`, `headline` and `extraData`
    (`String`). Its init is `init(timeStamp:providerCode:articleID:headline:extraData: = "")`.
  - `Tick` gains these cases: `.optionComputation(TickField, OptionComputation)`, `.efp(TickField, EFPData)`,
    `.requestParameters(minTick: Decimal?, bboExchange: String, snapshotPermissions: Int)` and `.news(NewsTick)`.
  - The new layouts, as `ib_async` `decoder.py` reads them:
    - 21, 12 fields, no version: `21, reqId, tickType, tickAttrib, impliedVol, delta, optPrice, pvDividend, gamma, vega, theta, undPrice`.
      After `optionalDecimal`, these become `nil`:
      - impliedVol, optPrice, pvDividend and undPrice when equal to `-1`;
      - delta, gamma, vega and theta when equal to `-2`.
    - 47, 11 fields: `47, version, reqId, tickType, basisPoints, formattedBasisPoints, impliedFuture, holdDays, futureLastTradeDate, dividendImpact, dividendsToLastTradeDate`.
    - 81 (unchanged layout) → `.tick(requestID:, .requestParameters(…))`.
    - 84, 7 fields, no version: `84, reqId, timeStamp, providerCode, articleId, headline, extraData`.
  - `TickField.live` also maps the delayed greeks: 80 → 10, 81 → 11, 82 → 12 and 83 → 13.
  - `marketData` needs no change: it already yields every `.tick` for its reqId.

- [ ] **Step 1: Write the failing tests**
  - `TickCodecTests`:
    - `optionComputationDecodes`:
      `body("21", "7", "13", "1", "0.25", "0.55", "6.1", "0", "0.03", "0.12", "-0.05", "187.2")` →
      `.tick(requestID: 7, .optionComputation(TickField(rawValue: 13), OptionComputation(tickAttrib: 1, impliedVol: d("0.25"), delta: d("0.55"), optPrice: d("6.1"), pvDividend: 0, gamma: d("0.03"), vega: d("0.12"), theta: d("-0.05"), undPrice: d("187.2"))))`.
    - `uncomputedGreeksAreNil` (Review Focus 1):
      - `body("21", "7", "10", "0", "-1", "-2", "-1", "-1", "-2", "-2", "-2", "-1")` → field 10 and
        `OptionComputation(tickAttrib: 0)`, with every value nil;
      - `body("21", "7", "11", "0", "1.7976931348623157E308", "0.5", "", "2147483647", "0.01", "0.1", "-0.02", "187")`
        → `impliedVol`, `optPrice` and `pvDividend` are nil; `delta 0.5`, `gamma 0.01`, `vega 0.1`, `theta -0.02`,
        `undPrice 187`.
    - `shortOptionComputationIsMalformed`: the first frame without its last field → `.malformed`.
    - `efpDecodes`: `body("47", "1", "7", "38", "1.5", "1.50%", "187.3", "30", "20261218", "0.2", "0.25")` →
      `.tick(requestID: 7, .efp(TickField(rawValue: 38), EFPData(basisPoints: d("1.5"), formattedBasisPoints: "1.50%", impliedFuture: d("187.3"), holdDays: 30, futureLastTradeDate: "20261218", dividendImpact: d("0.2"), dividendsToLastTradeDate: d("0.25"))))`.
    - `newsTickDecodes`:
      `body("84", "7", "1794321000000", "BRFG", "BRFG$12345", "Apple headline", "A:800015:L:en")` →
      `.tick(requestID: 7, .news(NewsTick(timeStamp: 1794321000000, providerCode: "BRFG", articleID: "BRFG$12345", headline: "Apple headline", extraData: "A:800015:L:en")))`.
    - `tickReqParamsDecodes` now expects
      `.tick(requestID: 7, .requestParameters(minTick: d("0.01"), bboExchange: "9c0001", snapshotPermissions: 3))`.
    - `delayedFieldsMapToLive` adds `TickField(rawValue: 80).live.rawValue == 10` and
      `TickField(rawValue: 83).live.rawValue == 13`.
  - `IBClientMarketDataTests.marketDataYieldsGreeksAndParameters`: feed
    `["21", id, "13", "1", "0.25", "0.55", "6.1", "0", "0.03", "0.12", "-0.05", "187.2"]`, then
    `["81", id, "0.01", "9c0001", "3"]`. `take(2)` → `[.optionComputation(…), .requestParameters(…)]`, with the
    values above.
  - `PublicAPITests`: `OptionComputation(tickAttrib: 0).delta == nil`, `EFPData().holdDays == nil` and
    `NewsTick(timeStamp: 1, providerCode: "P", articleID: "A", headline: "H").extraData == ""`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "TickCodecTests|IBClientMarketDataTests"`. Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS, including `everyRecordedFrameDecodes`.
- [ ] **Step 5: Docs and commit** («Decode option computations, EFP, request parameters and news as ticks»).

### Task 3: deltaNeutralValidation (56) and the reroutes (91, 92) (sonnet)

**Files:**
- Modify: `IBMessage.swift`, `IBDecoder.swift`
- Test: `TickCodecTests.swift`, `IBClientMarketDataTests.swift`
- Docs:
  - protocol-178: three new sections, «deltaNeutralValidation (in 56)», «rerouteMktDataReq (in 91)» and
    «rerouteMktDepthReq (in 92)».
  - DECISIONS: decision 8.
  - CHANGELOG: Added, the three `IBMessage` cases.

**Interfaces:**
- Produces:
  - `.deltaNeutralValidation(requestID: Int, DeltaNeutralContract)`, from `56, version, reqId, conId, delta, price`.
    `delta` and `price` are read with `decimal()`, as `ib_async` reads `float(x or 0)`.
  - `.rerouteMarketData(requestID: Int, conID: Int, exchange: String)` from `91, reqId, conId, exchange`, and
    `.rerouteMarketDepth(…)` from the same layout under id 92.
  - None of them is routed to a stream. They reach `messages()` only.

- [ ] **Step 1: Write the failing tests**
  - `TickCodecTests`:
    - `deltaNeutralValidationDecodes`: `body("56", "1", "7", "265598", "0.5", "187.25")` →
      `.deltaNeutralValidation(requestID: 7, DeltaNeutralContract(conID: 265598, delta: d("0.5"), price: d("187.25")))`.
    - `reroutesDecode`: `body("91", "7", "12087792", "IDEALPRO")` →
      `.rerouteMarketData(requestID: 7, conID: 12087792, exchange: "IDEALPRO")`; the same fields under `"92"` →
      `.rerouteMarketDepth(…)`.
  - `IBClientMarketDataTests.rerouteLeavesTheStreamOpen`: after `marketData(aapl)`, feed `["91", id, "12087792", "IDEALPRO"]`,
    then `["1", "6", id, "1", "351.5", "200", "0"]`. `take(1)` yields the bid tick.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "TickCodecTests|IBClientMarketDataTests"`. Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («Decode deltaNeutralValidation and the market data and depth reroutes»).

### Task 4: Real-time bars (sonnet)

**Files:**
- Modify: `IBRequest.swift`, `IBMessage.swift`, `IBDecoder.swift`, `IBClient.swift`
- Test: `TickCodecTests.swift`, `RequestTests.swift`, `IBClientMarketDataTests.swift`
- Docs:
  - protocol-178: «reqRealTimeBars (out 50)», «cancelRealTimeBars (out 51)» and «realtimeBar (in 50)».
  - DECISIONS: decision 9, and row 60 notes that 10225 now also ends `realTimeBars`.
  - CHANGELOG: Added, `realTimeBars(_:whatToShow:rth:)` and the new cases.

**Interfaces:**
- Produces:
  - `IBRequest.realTimeBars(requestID: Int, contract: Contract, whatToShow: String, rth: Bool)`. Its 19 fields are
    `50, 3, reqId, contract(12), barSize 5, whatToShow, useRTH, realTimeBarsOptions ""`, and BAG is refused.
  - `IBRequest.cancelRealTimeBars(requestID: Int)` → `51, 1, reqId`.
  - `IBMessage.realTimeBar(requestID: Int, Bar)`. Its 11 fields are
    `50, version, reqId, time, open, high, low, close, volume, wap, count`:
    - `time` is epoch seconds through `int()`;
    - `wap` becomes `average` through `optionalDecimal`.
  - `public func realTimeBars(_ contract: Contract, whatToShow: String = "TRADES", rth: Bool = true) throws(IBClientError) -> AsyncThrowingStream<Bar, any Error>`.
    It uses `openStream` with cancel `.cancelRealTimeBars`, and the buffer is `.unbounded`.
  - `routeToStream` routes `.realTimeBar(let id, _)`.

- [ ] **Step 1: Write the failing tests**
  - `TickCodecTests.realTimeBarsEncodeAndDecode`:
    - `.realTimeBars(requestID: 7, contract: Contract(symbol: "AAPL"), whatToShow: "TRADES", rth: true)` →
      `body(["50", "3", "7"] + aapl + ["5", "TRADES", "1", ""])`;
    - `.cancelRealTimeBars(requestID: 7)` → `body("51", "1", "7")`;
    - `body("50", "3", "7", "1794321000", "351.0", "352.0", "350.5", "351.5", "1000", "351.2", "42")` →
      `.realTimeBar(requestID: 7, Bar(time: Date(timeIntervalSince1970: 1794321000), open: d("351.0"), high: d("352.0"), low: d("350.5"), close: d("351.5"), volume: 1000, average: d("351.2"), count: 42))`.
  - `bagIsRefusedWhereIBSendsNoLegs` adds `.realTimeBars(requestID: 1, contract: bagContract, whatToShow: "TRADES", rth: true)`.
  - `IBClientMarketDataTests.realTimeBarsStreamAndCancel`:
    1. `realTimeBars(aapl, whatToShow: "MIDPOINT", rth: false)` → the sent frame's last four fields are
       `["5", "MIDPOINT", "0", ""]`.
    2. Feed the bar frame with `id`. `take(1)` → that bar.
    3. `reader.cancel()` → the next sent frame is `["51", "1", id]`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "TickCodecTests|RequestTests|IBClientMarketDataTests"`.
  Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («Stream real-time five-second bars»).

### Task 5: Depth exchanges and smart components (sonnet)

**Files:**
- Modify: `Sources/IBKR/Models/MarketData.swift`, `IBRequest.swift`, `IBMessage.swift`, `MarketDataDecoding.swift`,
  `IBDecoder.swift`, `IBClient.swift`
- Test: `TickCodecTests.swift`, `IBClientMarketDataTests.swift`, `PublicAPITests.swift`
- Docs:
  - protocol-178: «reqMktDepthExchanges (out 82)», «mktDepthExchanges (in 80)», «reqSmartComponents (out 83)» and
    «smartComponents (in 82)».
  - DECISIONS: decision 10, and row 69 lists `depthExchanges` among the id-less one-shots.
  - CHANGELOG: Added, `depthExchanges()`, `smartComponents(_:)`, `DepthMarketDataDescription` and `SmartComponent`.

**Interfaces:**
- Produces:
  - `public struct DepthMarketDataDescription`, with fields `exchange`, `secType`, `listingExchange` and
    `serviceDataType` (`String`), and `aggGroup: Int?`.
  - `public struct SmartComponent`, with fields `bitNumber: Int`, `exchange: String` and `exchangeLetter: String`.
  - `IBRequest.depthExchanges` → `82` (one field). `IBRequest.smartComponents(requestID: Int, bboExchange: String)` →
    `83, reqId, bboExchange`.
  - `IBMessage.depthExchanges([DepthMarketDataDescription])`, from
    `80, n, n × (exchange, secType, listingExch, serviceDataType, aggGroup)`. There is no version and no reqId, and
    `aggGroup` is read with `optionalInt`.
  - `IBMessage.smartComponents(requestID: Int, [SmartComponent])`, from
    `82, reqId, n, n × (bitNumber, exchange, exchangeLetter)`, with no version.
  - Both counts go through `wireCount`, so a negative count is `.malformed`.
  - `public func depthExchanges() async throws(IBClientError) -> [DepthMarketDataDescription]`, through
    `answer(.depthExchanges)`. `routeToStream` offers `.depthExchanges` to the id-less waiters, beside `.currentTime`.
  - `public func smartComponents(_ bboExchange: String) async throws(IBClientError) -> [SmartComponent]`, through
    `answer(…, id:)`. `routeToStream` routes `.smartComponents(let id, _)`.

- [ ] **Step 1: Write the failing tests**
  - `TickCodecTests.depthExchangesAndSmartComponentsCodec`:
    - `IBRequest.depthExchanges` → `body("82")`;
    - `.smartComponents(requestID: 7, bboExchange: "9c0001")` → `body("83", "7", "9c0001")`;
    - `body("80", "2", "ISLAND", "STK", "NASDAQ", "Deep2", "1", "NYSE", "STK", "NYSE", "Deep", "2147483647")` →
      `.depthExchanges([DepthMarketDataDescription(exchange: "ISLAND", secType: "STK", listingExchange: "NASDAQ", serviceDataType: "Deep2", aggGroup: 1), DepthMarketDataDescription(exchange: "NYSE", secType: "STK", listingExchange: "NYSE", serviceDataType: "Deep", aggGroup: nil)])`;
    - `body("82", "7", "2", "0", "NYSE", "N", "1", "ARCA", "P")` →
      `.smartComponents(requestID: 7, [SmartComponent(bitNumber: 0, exchange: "NYSE", exchangeLetter: "N"), SmartComponent(bitNumber: 1, exchange: "ARCA", exchangeLetter: "P")])`;
    - `body("80", "-1")` and `body("82", "7", "-1")` → `.malformed`.
  - `IBClientMarketDataTests`:
    - `depthExchangesAnswers`: `onRequest` answers `["82"]` with the 80 frame above → the two descriptions. The sent
      frame is `["82"]`, and `requestStreamCount == 0`.
    - `smartComponentsAnswers`: `onRequest` answers a `"83"` frame `f` with `["82", f[1], "1", "0", "NYSE", "N"]` →
      `[SmartComponent(bitNumber: 0, exchange: "NYSE", exchangeLetter: "N")]`. The sent frame is
      `["83", f[1], "9c0001"]`.
  - `PublicAPITests`: build one of each.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "TickCodecTests|IBClientMarketDataTests"`. Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («Ask IB for its depth exchanges and SMART components»).

### Task 6: Decide depth after 2152 from the recorded frames (sonnet)

**The evidence.** `Tests/IBKRTests/Recorded/liveMarketData.json` comes from the 2026-11-11 paper run with no data
subscription and `marketDepth(aapl, rows: 5)` (smart). For the depth reqId 4 it holds exactly one frame:

```
["4", "2", "4", "2152", "Exchanges - Top: IBEOS; OVERNIGHT; Unknown market data permissions - Depth: NASDAQ; BATS; ARCA; BEX; NYSE; IEX; Top: BYX; AMEX; PEARL; T24X; MEMX; EDGEA; TXSE; CHX; NYSENAT; PSX; LTSE; ISE; DRCTEDGE; ", ""]
```

After it comes nothing for reqId 4. The next frame is the tick-by-tick refusal (reqId 5), which the live test sent only
after its 15 s silence limit ran out. The text has two parts:
- before `Unknown market data permissions` it lists what the login is granted: here `Top:` only, with no `Depth:`;
- after it come the exchanges whose permission IB does not know.

`ib_async` logs 2152 as a warning (2100–2199) and leaves the ticker silent, which is the hang this stage must close.

**Decision (decision 11).** Notice 2152 for a `marketDepth` reqId ends the stream with
`.noMarketDataPermission(code: 2152, text:)` and sends the depth cancel, as every permission refusal does (IB keeps a
refused subscription open). It does so only when the granted part of the text names no `Depth:` exchange. When the
granted part has `Depth:`, the stream stays open: a partly permitted book must keep streaming. The global error table
does not change (2152 stays a notice everywhere), because the evidence covers depth only.

**Files:**
- Modify: `Sources/IBKR/Messages/ErrorCode.swift`, `Sources/IBKR/Client/IBClient.swift` (`marketDepth`'s route and
  doc comment)
- Test: `Tests/IBKRTests/DepthTests.swift`, `ErrorCodeTests.swift`, `RecordedFrameTests.swift`, `LiveTests.swift`
  (depth no longer passes `silenceIsAnAnswer`; the `firstOrRefusal` comment names only tick-by-tick as possibly silent)
- Docs:
  - DECISIONS: row 17 is rewritten as decision 11, with the evidence, and with «silence» and «ending on any 2152» as
    the rejected options.
  - KNOWN-GAPS: the «`marketDepth` without depth permissions never yields…» bullet is replaced by «a 2152 that grants
    `Depth:` on some exchanges is unseen live; the rule keeps such a book open».
  - README: the «Depth without permissions» bullet now says the stream ends with `.noMarketDataPermission` (code 2152).
  - protocol-178: the updateMktDepthL2 paragraph states the rule.
  - CHANGELOG: Changed, `marketDepth` ends with `.noMarketDataPermission` when IB's 2152 grants no depth.

**Interfaces:**
- Produces:
  - `static func grantsNoDepth(_ text: String) -> Bool` (internal) in `ErrorCode`. It takes the text before the first
    `Unknown market data permissions`, or the whole text when that is absent, and returns `true` when that part lacks
    `Depth:`.
  - `marketDepth`'s route, on `.error(let e) where e.code == 2152 && ErrorCode.grantsNoDepth(e.text)`, calls
    `out.finish(throwing: IBClientError.noMarketDataPermission(code: 2152, text: e.text))` and returns `false`. The
    entry then stays until the termination hop, and `stopped` sends `.cancelMarketDepth`.

- [ ] **Step 1: Write the failing tests**
  - `ErrorCodeTests.grantsNoDepthReadsTheGrantedPart`:
    - `true` for the recorded text above;
    - `true` for `"Exchanges - Top: IBEOS; "`;
    - `false` for `"Exchanges - Depth: ISLAND; Top: BYX; Unknown market data permissions - Depth: BATS; "`;
    - `false` for `"Exchanges - Depth: ISLAND; "`.
  - `RecordedFrameTests.recordedDepth2152EndsTheDepthStream`:
    1. Take the frame from `recording("liveMarketData")` whose `[0] == "4"` and `[3] == "2152"`.
    2. Connect, call `marketDepth(Contract(symbol: "AAPL"), rows: 5)` and feed `replacing(frame, [2: id])`.
    3. The stream throws `.noMarketDataPermission(code: 2152, text: frame[4])`.
    4. The next sent frame is `["11", "1", id, "1"]`, and `requestStreamCount == 0`.
    5. `recordedMarketDataRefusalsAreTyped` stays unchanged (`seen[2152] == false`, still a notice), and its doc
       comment names the new test.
  - `DepthTests.depthGoesOnWhen2152GrantsSomeDepth` (Review Focus 4): feed
    `["4", "2", id, "2152", "Exchanges - Depth: ISLAND; Top: BYX; Unknown market data permissions - Depth: BATS; ", ""]`,
    then `["12", "1", id, "0", "0", "1", "351.5", "100"]`. The first book has one bid.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "ErrorCodeTests|RecordedFrameTests|DepthTests"`. Expected: FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («End the depth stream when IB's 2152 grants no depth»). The message quotes the
  recorded frame as the evidence.

### Task 7: The `Ticker` value (opus)

**Files:**
- Create: `Sources/IBKR/Models/Ticker.swift`, `Tests/IBKRTests/TickerTests.swift`
- Test: `PublicAPITests.swift`
- Docs: DECISIONS (decision 12), CHANGELOG (Added: `Ticker` with `apply(_:)`)

**Interfaces:**
- Consumes: the `Tick` cases from Tasks 1–2, `OptionComputation`, `EFPData`, `DepthBook`, and `TickField.live`.
- Produces:
  ```swift
  public struct Ticker: Sendable, Equatable {
      public var contract: Contract
      public var marketDataType: MarketDataType          // default .realtime
      public var minTick: Decimal?
      public var bboExchange: String                     // default ""
      public var snapshotPermissions: Int                // default 0
      public var bid, bidSize, ask, askSize, last, lastSize: Decimal?
      public var open, high, low, close, volume: Decimal?
      public var lastTimestamp: Date?
      public var bidGreeks, askGreeks, lastGreeks, modelGreeks, custGreeks: OptionComputation?
      public var prices: [TickField: Decimal]            // every other price tick, keyed by its live field
      public var sizes: [TickField: Decimal]
      public var generics: [TickField: Decimal]
      public var strings: [TickField: String]
      public var efp: [TickField: EFPData]
      public var depth: DepthBook
      public init(contract: Contract, …every other field with the default above, nil, [:] or DepthBook())
      public mutating func apply(_ tick: Tick)
  }
  ```
  `apply` keys every field by `k = field.live`, after `ib_async` `wrapper.py` priceSizeTick, tickSize, tickGeneric,
  tickString and tickOptionComputation:
  - `.price(_, p, s)`:
    - `k == .bid`: `bid = s == 0 ? nil : p` and `bidSize = s`. `.ask` works the same way.
    - `k == .last`: when `p == -1`, `s == 0` and `(close ?? 0) > 0`, then `last = nil` and `lastSize = 0`. Otherwise
      `last = p` and `lastSize = s`.
    - `.high`, `.low`, `.close` and `.open` set their named fields.
    - Anything else sets `prices[k] = p`.
  - `.size(_, s)`:
    - `.bidSize` sets `bidSize = s`, and `bid = nil` when `s == 0`. `.askSize` works the same way.
    - `.lastSize` sets `lastSize = s` only when `last != nil`.
    - `.volume` sets `volume = s`.
    - Anything else sets `sizes[k] = s`.
  - `.generic(_, v)` sets `generics[k] = v`.
  - `.string(_, v)`: for `k == .lastTimestamp`, a non-zero integer sets `lastTimestamp` (epoch seconds); `"0"` and
    non-numbers are ignored. Anything else sets `strings[k] = v`.
  - `.dataType(t)` sets `marketDataType`. `.requestParameters` sets `minTick`, `bboExchange` and
    `snapshotPermissions`.
  - `.optionComputation(_, c)`: raw value 10, 11, 12, 13 or 53 sets bid, ask, last, model or cust greeks. Any other
    field is ignored.
  - `.efp(f, e)` sets `efp[f] = e`. `.news` changes nothing.

- [ ] **Step 1: Write the failing tests** in `TickerTests`. Each starts from `var t = Ticker(contract: Contract(symbol: "AAPL"))`.
  - `ticksFoldIntoTheTicker`. Apply, in order:
    1. `.price(.bid, price: d("351.5"), size: d("200"))`, `.price(.ask, price: d("351.6"), size: d("100"))` and
       `.price(.last, price: d("351.55"), size: d("10"))`;
    2. `.size(.volume, d("12345"))`, `.price(TickField(rawValue: 72), price: d("352"), size: 0)` and
       `.price(.close, price: d("350"), size: 0)`;
    3. `.price(TickField(rawValue: 20), price: d("400"), size: 0)`, `.string(.lastTimestamp, "1794321000")` and
       `.generic(.halted, 0)`;
    4. `.dataType(.delayed)` and `.requestParameters(minTick: d("0.01"), bboExchange: "9c0001", snapshotPermissions: 3)`.

    Then expect:
    - `bid 351.5`, `bidSize 200`, `ask 351.6`, `askSize 100`, `last 351.55`, `lastSize 10`;
    - `volume 12345`, `high 352`, `close 350`, `prices[TickField(rawValue: 20)] == 400`;
    - `lastTimestamp == Date(timeIntervalSince1970: 1794321000)`, `generics[.halted] == 0`;
    - `marketDataType == .delayed`, `minTick 0.01`, `bboExchange "9c0001"`, `snapshotPermissions 3`.
  - `anEmptySideClearsItsPrice`:
    - bid 351.5 / 200, then `.size(.bidSize, 0)` → `bid == nil`, `bidSize == 0`;
    - `.price(.ask, price: -1, size: 0)` → `ask == nil`, `askSize == 0`.
  - `lastSizeWaitsForALast`: `.size(.lastSize, 5)` on a fresh ticker → `lastSize == nil`.
  - `anEmptyLastAfterACloseIsNil`: `.price(.close, price: 350, size: 0)`, then `.price(.last, price: -1, size: 0)` →
    `last == nil`, `lastSize == 0`.
  - `greeksGoToTheirSide`:
    - `.optionComputation(TickField(rawValue: 10), c1)` → `bidGreeks == c1`;
    - field 83 with `c2` → `modelGreeks == c2`;
    - field 53 with `c3` → `custGreeks == c3`.
    `c1`, `c2` and `c3` differ by `tickAttrib` or `delta`.
  - `efpStringsAndNews`:
    - `.efp(TickField(rawValue: 38), e)` → `efp[TickField(rawValue: 38)] == e`;
    - `.string(TickField(rawValue: 84), "NYSE")` → `strings[TickField(rawValue: 84)] == "NYSE"`;
    - a `.news(…)` leaves `t` equal to its value before.
  - `PublicAPITests`: `Ticker(contract: contract).bid == nil`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter TickerTests`. Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («Fold ticks into a Ticker value»).

### Task 8: `tickers` stream and `tickers(for:)` batch (opus)

**Files:**
- Modify: `Sources/IBKR/Client/IBClient.swift`
- Test: `Tests/IBKRTests/IBClientMarketDataTests.swift`
- Docs: DECISIONS (decisions 13 and 14), CHANGELOG (Added: `tickers(_:genericTicks:depthRows:smartDepth:)` and
  `tickers(for:regulatorySnapshot:)`)

**Interfaces:**
- Consumes: `marketData(_:genericTicks:snapshot:regulatorySnapshot:)` (Task 1), `marketDepth` (Task 6), `Ticker` (Task 7).
- Produces:
  - `public func tickers(_ contract: Contract, genericTicks: [Int] = [], depthRows: Int? = nil, smartDepth: Bool = true) throws(IBClientError) -> AsyncThrowingStream<Ticker, any Error>`.
    It opens `marketData(contract, genericTicks:)`, then `marketDepth(contract, rows:, smart:)` when `depthRows` is set,
    and returns a stream with `bufferingPolicy: .bufferingNewest(1)`:
    - one task per inner stream forwards its elements (a tick, or a whole book) into one internal channel;
    - one fold loop applies each tick with `ticker.apply`, or sets `ticker.depth = book`, and yields the whole
      `ticker` after each element;
    - the first inner error finishes the outer stream with that error;
    - the outer stream's `onTermination` cancels the tasks. That ends the inner `for try await` loops, so each inner
      stream's own cancel goes out.
  - `public func tickers(for contracts: [Contract], regulatorySnapshot: Bool = false) async throws(IBClientError) -> [Ticker]`.
    It opens `marketData(c, snapshot: true, regulatorySnapshot:)` for every contract before reading any (as `ib_async`
    `reqTickersAsync`), then folds each stream to its snapshot end. It returns the tickers in the order of
    `contracts`, each with its own contract. On the first error it throws, and every stream still registered is
    stopped, which sends its cancel. A cancelled caller task throws `.cancelled`.

- [ ] **Step 1: Write the failing tests** in `IBClientMarketDataTests`
  - `tickersYieldWholeTickers`:
    1. `tickers(aapl)` → the sent frame is a `"1"` with `[16] == ""`.
    2. Feed `["1", "6", id, "1", "351.5", "200", "0"]` and `["2", "6", id, "0", "300"]`.
    3. A reader task reads until a ticker has `bidSize == d("300")`, and keeps the stream. That ticker has
       `bid == d("351.5")`. Do not use `take(2)`: the stream keeps only the newest Ticker, so the first one may be
       replaced before it is read.
    4. `reader.cancel()` → the next sent frame is `["2", "2", id]`.
  - `tickersWithDepthCarryTheBookAndCancelBoth` (Review Focus 3):
    1. `tickers(aapl, depthRows: 5)` → the two frames after the sync begin `"1"` and `"10"`.
    2. Feed `["12", "1", did, "0", "0", "1", "351.5", "100"]` and `["1", "6", qid, "1", "351.5", "200", "0"]`.
    3. The first ticker with `depth.bids.count == 1 && bid != nil` arrives within 2 s.
    4. `reader.cancel()` → the next two sent frames, in either order, are `["2", "2", qid]` and `["11", "1", did, "1"]`,
       and then `requestStreamCount == 0`.
  - `tickersEndWithTheirDepthRefusal`:
    1. `tickers(aapl, depthRows: 5)`, then feed the 2152 frame of Task 6's recording to `did`.
    2. The stream throws `.noMarketDataPermission(code: 2152, …)`.
    3. Both cancels are sent, and `requestStreamCount == 0`.
  - `tickersForReturnsSnapshotsInOrder`:
    1. `onRequest` answers every `"1"` frame `f` with `["1", "6", f[2], "1", f[4] == "AAPL" ? "351.5" : "420.1", "100", "0"]`,
       then `["57", "1", f[2]]`.
    2. `tickers(for: [Contract(symbol: "AAPL"), Contract(symbol: "MSFT")])` → two tickers: symbols `AAPL`, `MSFT`
       and bids `351.5`, `420.1`.
    3. Both sent frames have `[17] == "1"` and `[18] == "0"`. No `"2"` frame is sent, and `requestStreamCount == 0`.
  - `tickersForFailsOnAnErrorAndCancelsTheRest` (Review Focus 2):
    1. `onRequest` answers the AAPL `"1"` frame with `["4", "2", f[2], "200", "No security definition", ""]` and
       leaves MSFT unanswered.
    2. `tickers(for: [AAPL, MSFT])` throws `.ib(code: 200, text: "No security definition")`.
    3. `["2", "2", msftID]` is sent within 2 s, and `requestStreamCount == 0`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter IBClientMarketDataTests`. Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above. The channel can be a private `AsyncThrowingStream` of a private
  two-case enum. `tickers(for:)` must not rely on an unread stream being deallocated to send its cancel unless
  `tickersForFailsOnAnErrorAndCancelsTheRest` proves it does.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS. Run the two Review Focus tests 20 times
  (`for i in $(seq 20); do timeout 900 swift test --filter "tickersWithDepth|tickersForFails" > /dev/null || echo FAIL $i; done`)
  and expect no `FAIL`.
- [ ] **Step 5: Docs and commit** («Stream whole Tickers and take batch snapshots»).

### Task 9: History for BAG contracts and the trading schedule (sonnet)

**Files:**
- Create: `Sources/IBKR/Models/History.swift` (`HistoricalSession`, `HistoricalSchedule`; Task 11 adds `HistogramData`)
- Modify: `IBRequest.swift` (`historicalData` sends legs, and formatDate 1 for SCHEDULE), `IBMessage.swift`,
  `MarketDataDecoding.swift`, `IBDecoder.swift`, `IBClient.swift`
- Test: `HistoricalTests.swift`, `PublicAPITests.swift`
- Docs:
  - protocol-178:
    - reqHistoricalData: `+ comboLegsCount` and 4 fields per leg after formatDate, only for BAG; formatDate is `1`
      for `SCHEDULE`, `2` otherwise; «A BAG contract is refused» is deleted.
    - new section «historicalSchedule (in 106)».
  - DECISIONS: row 22 adds historicalData (decision 15); add decision 16, and row 63 notes the SCHEDULE exception.
  - CHANGELOG:
    - Added: `historicalSchedule(_:days:end:rth:)`, `HistoricalSchedule`, `HistoricalSession`, and BAG history.
    - Changed: `historicalBars` accepts a `BAG`.

**Interfaces:**
- Consumes: `IBRequest.comboLegs` (Task 1).
- Produces:
  - The historicalData wire, as `ib_async` `client.reqHistoricalData`:
    `20, reqId, contract(12, allowBag), includeExpired, end, barSize, duration, useRTH, whatToShow, formatDate`, then
    `comboLegs`, then `keepUpToDate, chartOptions`. formatDate is `whatToShow == "SCHEDULE" ? 1 : 2`.
  - `public struct HistoricalSession`, with fields `startDateTime`, `endDateTime` and `refDate` (`String`).
  - `public struct HistoricalSchedule`, with fields `startDateTime`, `endDateTime` and `timeZone` (`String`), and
    `sessions: [HistoricalSession]`.
  - `IBMessage.historicalSchedule(requestID: Int, HistoricalSchedule)`, from
    `106, reqId, startDateTime, endDateTime, timeZone, count, count × (startDateTime, endDateTime, refDate)`. There is
    no version, and the count goes through `wireCount`.
  - `public func historicalSchedule(_ contract: Contract, days: Int, end: Date? = nil, rth: Bool = true) async throws(IBClientError) -> HistoricalSchedule`:
    - it sends `.historicalData(… end: end, barSize: "1 day", duration: "\(days) D", rth: rth, whatToShow: "SCHEDULE", keepUpToDate: false)`,
      as `ib_async` `reqHistoricalScheduleAsync` does;
    - the stream's cancel is `.cancelHistoricalData`;
    - the route yields, finishes and returns `true` on `.historicalSchedule`.
  - `routeToStream` routes `.historicalSchedule(let id, _)`.

- [ ] **Step 1: Write the failing tests**
  - `HistoricalCodecTests`:
    - `historicalBagSendsLegs`:
      `.historicalData(requestID: 9, contract: bagContract, end: nil, barSize: "1 day", duration: "5 D", rth: true, whatToShow: "TRADES", keepUpToDate: false)`
      → `body(["20", "9"] + bagBlock + ["0", "", "1 day", "5 D", "1", "TRADES", "2"] + bagLegs + ["0", ""])`.
    - `scheduleSendsFormatDateOne`: the same request on `Contract(symbol: "AAPL")` with `whatToShow: "SCHEDULE"` →
      `body(["20", "9"] + aapl + ["0", "", "1 day", "5 D", "1", "SCHEDULE", "1", "0", ""])`.
    - `historicalScheduleDecodes`: the frame
      `["106", "9", "20261106-09:30:00", "20261112-16:00:00", "US/Eastern", "2", "20261111-09:30:00", "20261111-16:00:00", "20261111", "20261112-09:30:00", "20261112-16:00:00", "20261112"]`
      decodes to
      `.historicalSchedule(requestID: 9, HistoricalSchedule(startDateTime: "20261106-09:30:00", endDateTime: "20261112-16:00:00", timeZone: "US/Eastern", sessions: [HistoricalSession(startDateTime: "20261111-09:30:00", endDateTime: "20261111-16:00:00", refDate: "20261111"), HistoricalSession(startDateTime: "20261112-09:30:00", endDateTime: "20261112-16:00:00", refDate: "20261112")]))`.
      With `f[5] = "-1"` it is `.malformed`.
    - `historicalRequestEncodes` stays unchanged.
  - `historicalScheduleAnswers`:
    1. `onRequest` answers a `"20"` frame `f` with the 106 frame above, with `f[1]` as its reqId.
    2. `historicalSchedule(Contract(symbol: "AAPL"), days: 5)` returns that schedule.
    3. The sent frame's `[15...22]` is `["", "1 day", "5 D", "1", "SCHEDULE", "1", "0", ""]`.
    4. After 50 ms no `"25"` has been sent, and `requestStreamCount == 0`.
  - `PublicAPITests`: build a `HistoricalSchedule` with one `HistoricalSession`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "HistoricalCodecTests|historicalSchedule"`. Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («Send BAG legs with history and ask for the trading schedule»).

### Task 10: Historical ticks (sonnet)

**Files:**
- Modify: `IBRequest.swift`, `IBMessage.swift`, `MarketDataDecoding.swift`, `IBDecoder.swift`, `IBClient.swift`
- Test: `HistoricalTests.swift`, `RequestTests.swift`
- Docs:
  - protocol-178: «reqHistoricalTicks (out 96)» and «historicalTicks / historicalTicksBidAsk / historicalTicksLast
    (in 96, 97, 98)».
  - DECISIONS: decision 17.
  - CHANGELOG: Added, `historicalTicks(_:start:end:count:whatToShow:rth:ignoreSize:)` and the new cases.

**Interfaces:**
- Produces:
  - `IBRequest.historicalTicks(requestID: Int, contract: Contract, start: Date?, end: Date?, count: Int, whatToShow: String, rth: Bool, ignoreSize: Bool)`.
    Its 22 fields are
    `96, reqId, contract(12), includeExpired 0, startDateTime, endDateTime, numberOfTicks, whatToShow, useRth, ignoreSize, miscOptions ""`:
    - the dates go through `IBRequest.endFormat`, with `nil` as `""`;
    - BAG is refused.
  - `IBMessage.historicalTicks(requestID: Int, [TickByTick], done: Bool)`. All three layouts share it, with no version:
    - 96: `96, reqId, n, n × (time, unused, price, size), done` → `.midPoint(time:price:)`.
    - 97: `97, reqId, n, n × (time, mask, priceBid, priceAsk, sizeBid, sizeAsk), done` → `.bidAsk(…)`. The mask is
      read and dropped.
    - 98: `98, reqId, n, n × (time, mask, price, size, exchange, specialConditions), done` → `.trade(…)`, with
      `pastLimit` = bit 0 and `unreported` = bit 1.
  - `public func historicalTicks(_ contract: Contract, start: Date? = nil, end: Date? = nil, count: Int, whatToShow: String = "TRADES", rth: Bool = true, ignoreSize: Bool = false) async throws(IBClientError) -> [TickByTick]`:
    - the cancel is `nil`: IB has no cancel for it;
    - the route yields each tick, and on `done` finishes and returns `true`.
  - `routeToStream` routes `.historicalTicks(let id, _, _)`.

- [ ] **Step 1: Write the failing tests**
  - `HistoricalCodecTests`:
    - `historicalTicksRequestEncodes`:
      `.historicalTicks(requestID: 7, contract: Contract(symbol: "AAPL"), start: Date(timeIntervalSince1970: 1794321000), end: nil, count: 100, whatToShow: "TRADES", rth: true, ignoreSize: false)`
      → `body(["96", "7"] + aapl + ["0", "20261110-14:30:00", "", "100", "TRADES", "1", "0", ""])`.
    - `historicalTicksDecode`, with `t = Date(timeIntervalSince1970: 1794321000)`:
      - `body("96", "7", "2", "1794321000", "0", "351.5", "0", "1794321001", "0", "351.55", "0", "1")` →
        `.historicalTicks(requestID: 7, [.midPoint(time: t, price: d("351.5")), .midPoint(time: t + 1, price: d("351.55"))], done: true)`.
      - `body("97", "7", "1", "1794321000", "3", "351.5", "351.6", "100", "200", "1")` →
        `[.bidAsk(time: t, bidPrice: d("351.5"), askPrice: d("351.6"), bidSize: 100, askSize: 200)]`, done true.
      - `body("98", "7", "1", "1794321000", "2", "351.5", "100", "ISLAND", "T", "0")` →
        `[.trade(time: t, price: d("351.5"), size: 100, exchange: "ISLAND", conditions: "T", pastLimit: false, unreported: true)]`,
        done false.
      - `body("98", "7", "-1", "0")` → `.malformed`.
  - `bagIsRefusedWhereIBSendsNoLegs` adds `.historicalTicks(requestID: 1, contract: bagContract, …)`.
  - `historicalTicksCollectUntilDone` (Review Focus 5):
    1. `onRequest` answers a `"96"` frame `f` with two frames: `["98", f[1], "1", "1794321000", "0", "351.5", "100", "ISLAND", "", "0"]`
       and `["98", f[1], "1", "1794321001", "2", "351.6", "50", "NYSE", "T", "1"]`.
    2. `historicalTicks(aapl, start: t, count: 2)` returns both trades in order; the second has `unreported` true.
    3. After 50 ms, nothing more has been sent, and `requestStreamCount == 0`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "HistoricalCodecTests|historicalTicks|RequestTests"`. Expected: a
  compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («Ask for historical midpoint, bid/ask and trade ticks»).

### Task 11: Head timestamp and histogram (sonnet)

**Files:**
- Modify: `Sources/IBKR/Models/History.swift` (`HistogramData`), `IBRequest.swift`, `IBMessage.swift`,
  `MarketDataDecoding.swift`, `IBDecoder.swift` (88 reuses `barTime`), `IBClient.swift`
- Test: `HistoricalTests.swift`, `RequestTests.swift`, `PublicAPITests.swift`
- Docs:
  - protocol-178: «reqHeadTimeStamp (out 87)», «cancelHeadTimeStamp (out 90)», «headTimestamp (in 88)»,
    «reqHistogramData (out 88)», «cancelHistogramData (out 89)» and «histogramData (in 89)».
  - DECISIONS: decisions 18 and 19.
  - CHANGELOG: Added, `headTimeStamp(_:whatToShow:rth:)`, `histogramData(_:period:rth:)`, `HistogramData`, and the
    new cases.

**Interfaces:**
- Produces:
  - `IBRequest.headTimeStamp(requestID: Int, contract: Contract, whatToShow: String, rth: Bool)`. Its 18 fields are
    `87, reqId, contract(12), includeExpired 0, useRTH, whatToShow, formatDate 2`.
  - `IBRequest.cancelHeadTimeStamp(requestID: Int)` → `90, reqId`.
  - `IBRequest.histogramData(requestID: Int, contract: Contract, rth: Bool, period: String)`. Its 17 fields are
    `88, reqId, contract(12), includeExpired 0, useRTH, timePeriod`.
  - `IBRequest.cancelHistogramData(requestID: Int)` → `89, reqId`. BAG is refused by both requests.
  - `IBMessage.headTimeStamp(requestID: Int, Date)`, from `88, reqId, headTimestamp`, where `headTimestamp` goes through
    `barTime`.
  - `public struct HistogramData`, with fields `price: Decimal` and `count: Int`.
  - `IBMessage.histogramData(requestID: Int, [HistogramData])`, from `89, reqId, n, n × (price, count)`, with the count
    through `wireCount`.
  - `public func headTimeStamp(_ contract: Contract, whatToShow: String = "TRADES", rth: Bool = true) async throws(IBClientError) -> Date`:
    - it uses `openStream` with cancel `.cancelHeadTimeStamp`;
    - its route yields, finishes and returns `false`, so the termination hop sends 90 after the answer, as `ib_async`
      does.
  - `public func histogramData(_ contract: Contract, period: String, rth: Bool = true) async throws(IBClientError) -> [HistogramData]`:
    - it uses `openStream` with cancel `.cancelHistogramData`;
    - its route returns `true` on the answer, so 89 goes out only when the caller's task is cancelled first.
  - `routeToStream` routes `.headTimeStamp(let id, _)` and `.histogramData(let id, _)`.

- [ ] **Step 1: Write the failing tests**
  - `HistoricalCodecTests.headTimeStampAndHistogramCodec`:
    - `.headTimeStamp(requestID: 7, contract: Contract(symbol: "AAPL"), whatToShow: "TRADES", rth: true)` →
      `body(["87", "7"] + aapl + ["0", "1", "TRADES", "2"])`;
    - `.cancelHeadTimeStamp(requestID: 7)` → `body("90", "7")`;
    - `.histogramData(requestID: 7, contract: …, rth: true, period: "3 days")` →
      `body(["88", "7"] + aapl + ["0", "1", "3 days"])`;
    - `.cancelHistogramData(requestID: 7)` → `body("89", "7")`;
    - `body("88", "7", "1104503400")` → `.headTimeStamp(requestID: 7, Date(timeIntervalSince1970: 1104503400))`;
    - `body("88", "7", "20050103")` → the date `1104710400` (00:00 UTC);
    - `body("88", "7", "20050103  09:30:00")` → `.malformed`;
    - `body("89", "7", "2", "351.5", "100", "351.6", "250")` →
      `.histogramData(requestID: 7, [HistogramData(price: d("351.5"), count: 100), HistogramData(price: d("351.6"), count: 250)])`.
  - `bagIsRefusedWhereIBSendsNoLegs` adds both requests with `bagContract`.
  - Client tests:
    - `headTimeStampAnswersThenCancels`: `onRequest` answers `"87"` with `["88", f[1], "1104503400"]` → the call
      returns `Date(timeIntervalSince1970: 1104503400)`. Within 2 s the next sent frame is `["90", f[1]]`, then
      `requestStreamCount == 0`.
    - `headTimeStampFailsOnItsError`: the answer is
      `["4", "2", f[1], "162", "Historical Market Data Service error message:HMDS query returned no data", ""]` →
      throws `.ib(code: 162, …)`. After 50 ms no `"90"` has been sent.
    - `histogramDataAnswers`: answers `"88"` with the 89 frame → the two entries. No `"89"` is sent, and
      `requestStreamCount == 0`.
    - `histogramDataCancelledSendsItsCancel`: no answer. The calling task is cancelled → it throws `.cancelled`, and
      `["89", id]` is sent.
  - `PublicAPITests`: `HistogramData(price: 1, count: 2).count == 2`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "HistoricalCodecTests|headTimeStamp|histogramData|RequestTests"`.
  Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («Ask for the head timestamp and the price histogram»).

### Task 12: Documents, per-commit check, CI (sonnet)

**Files:**
- Modify: `README.md`, `CHANGELOG.md`, `docs/DECISIONS.md`, `docs/KNOWN-GAPS.md`

- [ ] **Step 1: README «Market data»** gains:
  - `tickers` with `depthRows` and `tickers(for:)`;
  - `marketData`'s `genericTicks` and `snapshot`, and the new `Tick` cases in the snippet comment;
  - `realTimeBars`, `depthExchanges` and `smartComponents`;
  - a «History» subsection for `historicalTicks`, `headTimeStamp`, `histogramData` and `historicalSchedule`, with BAG
    accepted by `marketData` and history.

  The «Status» Market data row reads «quotes with generic ticks and snapshots, `Ticker` streams and batch snapshots,
  greeks, EFP, news ticks, real-time bars, depth book, depth exchanges, SMART components, tick-by-tick, BAG, typed «no
  permission» refusal». A new History row reads «bars with keepUpToDate, historical ticks, head timestamp, histogram,
  trading schedule, BAG». Both rows read «✅ refusals live-checked; the data only on hand-built frames (no
  subscription yet)».
- [ ] **Step 2: KNOWN-GAPS** heading and intro read «after stage 9». The «Market data is unchecked live» bullet names
  the stage 8–9 calls too. Then commit («Record stages 8 and 9 in the README and the status table»).
- [ ] **Step 3: Check the records against this plan.**
  - Every line of «Decisions beyond the spec» has its DECISIONS row, plus decision 1 as one names row.
  - Every public API change has a CHANGELOG `Unreleased` line.
  - protocol-178 has a section for every message in the spec's Рыночные данные and История rows, and no section
    still says a BAG is refused by marketData or historicalData.
  - Fix any gap in a commit of its own.
- [ ] **Step 4: Verify the series commit by commit** in a detached worktree:
  ```bash
  git worktree add --detach ../swift-ibkr-check stage-8-market-data
  git -C ../swift-ibkr-check rebase --exec "timeout 900 swift test > /dev/null" main
  git worktree remove ../swift-ibkr-check
  ```
  Expected: `Successfully rebased`. A failing commit is fixed on `stage-8-market-data` and the check is run again.
- [ ] **Step 5: Push and watch CI** with the command under Global Constraints. Expected: every job is green. A failing
  job gets its root cause fixed in a new commit, with no weakened test, then push and watch again.

## Decisions beyond the spec

1. Names:
   - calls: `marketData(_:genericTicks:snapshot:regulatorySnapshot:)`, `tickers(_:genericTicks:depthRows:smartDepth:)`,
     `tickers(for:regulatorySnapshot:)`, `realTimeBars(_:whatToShow:rth:)`, `depthExchanges()`, `smartComponents(_:)`,
     `historicalTicks(_:start:end:count:whatToShow:rth:ignoreSize:)`, `headTimeStamp(_:whatToShow:rth:)`,
     `histogramData(_:period:rth:)`, `historicalSchedule(_:days:end:rth:)`;
   - types: `OptionComputation`, `EFPData`, `NewsTick`, `Ticker`, `DepthMarketDataDescription`, `SmartComponent`,
     `HistogramData`, `HistoricalSchedule`, `HistoricalSession`;
   - fields keep `ib_async`'s names (`impliedVol`, `optPrice`, `undPrice`), except `listingExch` → `listingExchange`
     and `articleId` → `articleID`.
2. `genericTicks` is `[Int]`, sent comma-joined.
3. Any stream that gets tickSnapshotEnd (57) ends there with no cancel, as `ib_async` ends the request.
4. tickReqParams (81) becomes `Tick.requestParameters` and `marketData` yields it. `IBMessage.tickRequestParameters` is
   removed, which rewrites DECISIONS row 62.
5. Greeks: `-1` (impliedVol, optPrice, pvDividend, undPrice) and `-2` (delta, gamma, vega, theta) become `nil`.
   `ib_async` keeps vega and theta at `-2`.
6. `TickField.live` maps the delayed greeks 80–83 to 10–13.
7. A news tick's `timeStamp` stays IB's raw `Int`, because its unit is undocumented in `ib_async`. News stays out of
   `Ticker`, as in `ib_async`, and reaches consumers through `marketData`.
8. 56, 91 and 92 reach `messages()` only, and no stream reacts to them, as `ib_async` ignores them.
9. Real-time bars reuse `Bar` (`wap` becomes `average`), and barSize is fixed at 5, the only size IB allows.
10. `depthExchanges` is an id-less one-shot under a local key, and `aggGroup` is `Int?`.
11. Depth after 2152, decided from `liveMarketData.json`:
    - the depth stream ends with `.noMarketDataPermission(code: 2152, …)` and sends its cancel when the text before
      «Unknown market data permissions» names no `Depth:` exchange;
    - otherwise it stays open;
    - the global error table is unchanged.
12. `Ticker` shape:
    - named fields for bid, ask, last and their sizes, OHLC, volume, lastTimestamp, the five greeks, the request
      parameters and the depth book;
    - every other tick goes into `prices`, `sizes`, `generics`, `strings` or `efp`, keyed by its live field;
    - RT volume, fundamental ratios and dividends stay raw strings;
    - there are no `prev…` fields;
    - a bid or ask with size 0 has its price `nil`.
13. `tickers`:
    - it composes `marketData` and an optional `marketDepth`;
    - it yields the whole Ticker after every element, with no deduplication;
    - it buffers only the newest Ticker, like `marketDepth`;
    - any inner error ends it and cancels the other inner stream.
14. `tickers(for:)` sends every snapshot request first and returns in input order. It throws the first error and cancels
    the rest, where `ib_async` returns partial tickers.
15. BAG is accepted by `marketData` and `historicalData`, and so by `tickers`, `tickers(for:)` and `historicalSchedule`.
    `realTimeBars`, depth, tick-by-tick, historical ticks, the head timestamp and the histogram keep refusing it,
    because `ib_async` sends no legs there.
16. The schedule request sends formatDate 1, as `ib_async` does, and the schedule keeps IB's raw strings and time zone.
17. Historical ticks:
    - they return `[TickByTick]`;
    - the bid/ask mask and the midpoint size are dropped, as in tick-by-tick;
    - `whatToShow` is IB's string;
    - the dates go out in the library's `yyyyMMdd-HH:mm:ss` UTC format, where `ib_async` writes
      `yyyyMMdd HH:mm:ss UTC`.
18. `headTimeStamp` asks with formatDate 2 and returns a `Date` (an 8-character day is 00:00 UTC). It sends cancel 90
    after the answer, as `ib_async` does.
19. `histogramData` is a one-shot that sends 89 only for a cancelled caller, and its `count` is an `Int`, as in
    `ib_async`.
