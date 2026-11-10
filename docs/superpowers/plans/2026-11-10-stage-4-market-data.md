# swift-ibkr Stage 4: Market Data — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `IBClient` gives a consumer contract lookups (`contractDetails`, `matchingSymbols`), the market-data type switch, top-of-book ticks, historical bars with live updates, a depth book and tick-by-tick trades. IB's "no data permission" refusal arrives as its own typed error. All of it is checked on the fake gateway and once live on the owner's paper account.

**Architecture:** Every feature is one more request stream in the registry stage 3 built (`openStream` / `routeToStream`). The registry learns two things:
- **Streams that end themselves:** a one-shot answer, or history without `keepUpToDate`, ends with no cancel sent.
- **Routed notices:** a notice with a stream's reqId is handed to that stream, so the depth book hears 317.

Each feature is a codec task, then a client task, except where both are small.

**Tech Stack:** Swift 6.4.2, SwiftPM tools 6.0 (Swift 6 language mode), Foundation, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-09-swift-ibkr-design.md`: sections «Публичный API», «Сообщения» and «Этапы» item 4.

**Wire layouts:** `docs/superpowers/plans/2026-11-10-stage-4-layouts.md`.
- Researched 2026-11-10 from `ib_async`, at the same pin as `docs/protocol-178.md`. It is the field-order authority for this plan.
- Each task moves the sections it implements into `docs/protocol-178.md`, in that file's table style.
- Error-code meanings marked **[not ib_async]** there are unverified; the live run settles the ones this plan relies on.

## Global Constraints

- **Repository and build.** Work in `C:\Users\viohn\swift-ibkr`, on branch `stage-4-market-data` off `main` (119940e). Build with `swift build`, test with `swift test`.
- **Owner's «да».** Nothing is pushed to GitHub, and `main` is not moved, without it.
- **No dependencies.** Swift 6 strict concurrency, no warnings in `Sources/`.
- **No official ibapi code.** Never copy from it. The layouts file above is the field order.
- **The contract block.** Every outgoing contract (reqMktData, reqHistoricalData, reqMktDepth, reqTickByTickData, reqContractDetails) is the 12 fields placeOrder already writes (rows 2-13). Task 1 extracts them into one helper. A `BAG` contract throws `IBEncodingError.unsupported` everywhere.
- **One id counter.** Orders and requests share `IBClient.nextRequestID()`.
- **Number types.** Prices and sizes are `Decimal`. IB's unset markers read as `nil` through `FieldReader.optionalDecimal()`. Tests use `d("…")`.
- **Test helpers.** Tests use `@testable import IBKR`, `body(_:)`, `d(_:)`, `within2s` and `FakeGateway`. A test waits at most 2 s for an async event.
- **Commits.** One imperative sentence plus the reasoning. The last line is `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Docs of record.** `README.md`, `docs/DECISIONS.md`, `docs/KNOWN-GAPS.md` and `docs/protocol-178.md` change in the commit whose behaviour they describe.
- **Series check.** At the end, verify every commit with `git rebase --exec "swift test > /dev/null" main`.
- **Live runs.** Live tests run only with `IBKR_LIVE=1`, and only the controller runs them, on the paper account. Recordings redact every account id to `DU0000001`; the real account id never enters the repository.

## Decisions taken in this plan (owner can veto)

- **Typed refusal.**
  - `IBClientError` gains `case noMarketDataPermission(code: Int, text: String)`.
  - A fatal error for a stream's reqId ends that stream with this case when `ErrorCode.isNoMarketDataPermission(code:text:)` holds, and with `.ib(code:text:)` otherwise.
  - The set holds 354, 10089, 10168, 10186 and 10197, plus 162 only when its text contains `permission`, case-insensitive. 162 is IB's catch-all for history, which also covers pacing.
  - Whatever code the live run sees for depth and tick-by-tick without subscriptions joins the set in Task 8.
- **Error kinds.**
  - 317 (depth reset) becomes a notice: the depth stream empties its book and goes on.
  - 10090 and 10091 (part of the data not subscribed) become notices, because data still flows.
  - 10225 (bust event) stays fatal. The stream ends and the consumer subscribes again; `ib_async` resubscribes by itself, and that was rejected here as hidden traffic.
- **`setMarketDataType(_:)`** sends 59 and is not remembered. A reconnect starts at IB's default (real-time), so the consumer sets it again after `connect`. It is documented in README.
- **`marketData(_ contract:)`** sends no generic ticks and no snapshot. `Tick` keeps IB's field number in `TickField`. The tick-price attribute mask is read and dropped, as `ib_async` does.
  - `TickField.live` maps a delayed field to its real-time twin (66→1, 67→2, 68→4, 69→0, 70→3, 71→5, 72→6, 73→7, 74→8, 75→9, 76→14, 88→45). A consumer then reads bid/ask/last one way whichever type flows.
  - tickReqParams (81) is decoded but not put into the stream.
- **`historicalBars`.**
  - It sends `formatDate` 2.
  - `Bar.time` is a `Date`: epoch seconds for intraday bars, and 00:00 UTC of the given calendar day for `YYYYMMDD` bars.
  - `end: Date?` is sent as `yyyyMMdd-HH:mm:ss` in UTC, or `""` for now.
  - `duration`, `barSize` and `whatToShow` stay IB's strings, such as `"1 D"`, `"5 mins"` and `"TRADES"`.
  - The stream yields `.history([Bar])` once. Without `keepUpToDate` it then ends with no cancel; with it, every historicalDataUpdate follows as `.update(Bar)`, raw. A same-time update replaces the forming bar, and the consumer merges.
- **`marketDepth`** yields the whole `DepthBook` after every update; the spec sketch had `DepthUpdate`. The TWS port `OrderBookFeed` wants snapshots, and the book logic belongs in one place.
  - The book is position-indexed per side, as in `ib_async`: insert and update set the position, delete removes it, and the published arrays are sorted by position with gaps dropped.
  - Both 12 and 13 feed the book; 12 has an empty `marketMaker`.
  - `smart` defaults to `true` and is resent on cancel.
- **`tickByTick`** sends `numberOfTicks` 0 and `ignoreSize` false. `time` is a `Date` from epoch seconds.
- **`contractDetails` and `matchingSymbols`** are `async throws(IBClientError)` and collect until IB's end marker (52), or for 79 its single answer. They throw like streams end: a fatal error for their reqId, or the connection ending.
  - `ContractDetails` keeps the fields a trading UI needs.
  - `tradingHours` and `liquidHours` stay IB's raw strings; stage 5 parses them.
  - `longName` is not unicode-unescaped, the same open item as KNOWN-GAPS' escaped error text.
- **Not in this stage:**
  - snapshots (57) and generic tick lists;
  - real-time 5-second bars;
  - historical ticks;
  - market rules (91/93);
  - the reroute messages (91/92 in), which are decoded as `.unknown` and logged only.

## Review Focus

1. A depth reset (317) arrives mid-stream: the book is published empty, the stream stays alive, and later inserts rebuild it. Task 6 `depthResetEmptiesTheBookAndGoesOn`.
2. History without `keepUpToDate` ends by itself: the consumer's loop ends, no cancel 25 is sent (IB would answer 366) and the registry is empty. Task 5 `historyWithoutUpdatesEndsWithoutCancel`.
3. Delayed data: 10167 does not end the quote stream, and field 66 reads as `.bid` through `TickField.live`. Task 4 `delayedNoticeKeepsTheStreamAndMapsFields`.
4. A one-shot lookup when the connection drops: `contractDetails` throws `.connectionClosed` and does not hang. Task 2 `lookupThrowsWhenTheConnectionEnds`.
5. contractData with two secIds and extra trailing fields decodes, with each field taken by position. Task 1 `contractDataWithSecIdsAndTrailingFieldsDecodes`.

---

### Task 1: Codec for contract lookups, and the shared contract block

**Files:**
- Create: `Sources/IBKR/Models/MarketData.swift`, `Tests/IBKRTests/LookupCodecTests.swift`
- Modify: `IBMessage.swift`, `IBDecoder.swift`, `IBRequest.swift`, `docs/protocol-178.md`

**Interfaces:**
- **Produces:**
  - `public struct ContractDetails: Sendable, Equatable` with these fields:
    - `contract: Contract`, which holds conID, symbol, secType, lastTradeDateOrContractMonth, strike, right, multiplier, exchange, primaryExchange, currency, localSymbol and tradingClass;
    - `marketName: String`, `minTick: Decimal`, `priceMagnifier: Int`, `longName: String`, `stockType: String`;
    - `orderTypes: [String]` and `validExchanges: [String]`, both split on `,`;
    - `timeZoneID: String`, `tradingHours: String`, `liquidHours: String`;
    - `minSize: Decimal?`, `sizeIncrement: Decimal?`, `suggestedSizeIncrement: Decimal?`.
  - `public struct ContractDescription: Sendable, Equatable { contract: Contract; derivativeSecTypes: [String]; description: String; issuerID: String }`. Its contract carries conID, symbol, secType, primaryExchange and currency, with `exchange` `""`.
  - `IBMessage` cases: `.contractData(requestID: Int, ContractDetails)` (10), `.contractDataEnd(requestID: Int)` (52), `.symbolSamples(requestID: Int, [ContractDescription])` (79).
  - `IBRequest` cases: `.contractDetails(requestID: Int, contract: Contract)` (out 9: version 8, includeExpired 0, secIdType `""`, secId `""`, issuerId `""`) and `.matchingSymbols(requestID: Int, pattern: String)` (out 81).
  - A private `contract(_ w: inout FieldWriter, _ c: Contract)` writes the 12-field block. `placeOrder` uses it, and every later request does too.

- [ ] **Step 1: Write the failing tests.** `aapl` is the plain-AAPL block `"0","AAPL","STK","","0.0","","","SMART","","USD","",""`.
  - `contractDetailsEncodes`: `.contractDetails(requestID: 5, contract: Contract(symbol: "AAPL"))` encodes to `body("9","8","5", aapl…, "0","","","")`.
  - `matchingSymbolsEncodes`: `.matchingSymbols(requestID: 6, pattern: "AAP")` encodes to `body("81","6","AAP")`. A non-ASCII pattern throws `.nonASCII`.
  - `bagContractIsRefused`: a `secType "BAG"` contract throws `.unsupported` from `.contractDetails`.
  - `contractDataDecodes`: a 40-field AAPL frame (field values in the layouts file's table, including `minTick` `"0.01"`, `orderTypes` `"LMT,MKT"`, `validExchanges` `"SMART,NASDAQ"`, `timeZoneId` `"US/Eastern"`, and `tradingHours` `"20261110:0400-20261110:2000;20261111:CLOSED"`) decodes to the expected `ContractDetails`.
  - `contractDataWithSecIdsAndTrailingFieldsDecodes`: the same frame with `numSecIds` 2 (`ISIN`/`US0378331005`, `FIGI`/`BBG000B9XRY4`) and two extra trailing fields decodes to the same details.
  - `contractDataEndDecodes`: `["52","1","5"]` decodes to `.contractDataEnd(requestID: 5)`.
  - `symbolSamplesDecode`: `["79","6","2", "265598","AAPL","STK","NASDAQ","USD","2","OPT","WAR","APPLE INC","", "38708077","AAPL","STK","MEXI","MXN","0","APPLE INC",""]` decodes to two descriptions; the first has `derivativeSecTypes == ["OPT","WAR"]`.
  - `shortLookupFramesAreMalformed`: a contractData frame cut after `minTick`, and a symbolSamples frame that announces 2 entries but carries 1, both decode to `.malformed`.
- [ ] **Step 2: Run.** `swift test --filter LookupCodecTests` should fail to compile.
- [ ] **Step 3: Implement.** Placing `placeOrder` on the shared helper must leave `PlaceOrderTests` green.
- [ ] **Step 4: Run.** `swift test` should be all green.
- [ ] **Step 5: Commit.** Message: «Decode contract details and symbol samples, and encode their requests through one contract block».

### Task 2: One-shot lookups in `IBClient`, and self-ending streams

**Files:**
- Modify: `Sources/IBKR/Client/IBClient.swift`, `README.md`, `docs/DECISIONS.md`
- Test: `Tests/IBKRTests/IBClientLookupTests.swift`

**Interfaces:**
- **Consumes:** Task 1.
- **Produces:**
  - `RequestStream.route` becomes `(IBMessage) -> Bool`. It returns `true` when the stream finished itself; `routeToStream` then removes the entry and no cancel is sent.
  - `RequestStream.cancel` becomes `IBRequest?`.
  - `openStream` takes `cancel: IBRequest?`, and its `route` closure returns `Bool`. The stage-3 streams return `false`.
  - `routeToStream` also routes `.contractData`, `.contractDataEnd` and `.symbolSamples` by reqId.
  - `public func contractDetails(_ contract: Contract) async throws(IBClientError) -> [ContractDetails]`.
  - `public func matchingSymbols(_ pattern: String) async throws(IBClientError) -> [ContractDescription]`.
  - Both throw `.notConnected` and `.encoding` like the streams do, and rethrow a stream error as `IBClientError`.

- [ ] **Step 1: Write the failing tests.**
  - `contractDetailsCollectsUntilEnd`: the sent frame is out 9 with the next id; feed two contractData frames and the end. The call returns both, in order, and `requestStreamCount == 0`.
  - `matchingSymbolsReturnsTheSamples`: the sent frame is `["81",id,"AAP"]`; feed one symbolSamples frame. The call returns its entries, and nothing more is sent afterwards (no cancel).
  - `noSecurityDefinitionThrows`: an error `["4","2",id,"200","No security definition has been found for the request",""]` makes the call throw `.ib(code: 200, …)`.
  - `lookupThrowsWhenTheConnectionEnds`: a peer close while waiting makes the call throw the client's end error, within 2 s.
  - `lookupsNeedAConnection`: before `connect`, both calls throw `.notConnected`.
- [ ] **Step 2: Run.** `swift test --filter IBClientLookupTests` should fail.
- [ ] **Step 3: Implement.** README «Use» gains both calls. DECISIONS gains the self-ending stream row: route reports its own end, and the cancel was rejected because IB answers it with an error.
- [ ] **Step 4: Run.** `swift test` should be green; the stage-3 stream tests are unchanged.
- [ ] **Step 5: Commit.** Message: «Look up contract details and matching symbols as one-shot requests that end without a cancel».

### Task 3: Codec for top-of-book data

**Files:**
- Modify: `MarketData.swift`, `IBMessage.swift`, `IBDecoder.swift`, `IBRequest.swift`, `docs/protocol-178.md`
- Test: `Tests/IBKRTests/TickCodecTests.swift`

**Interfaces:**
- **Produces:**
  - `public enum MarketDataType: Int, Sendable { case realtime = 1, frozen, delayed, delayedFrozen }`.
  - `public struct TickField: RawRepresentable, Hashable, Sendable`, with `rawValue: Int`.
    - Statics: `bidSize` 0, `bid` 1, `ask` 2, `askSize` 3, `last` 4, `lastSize` 5, `high` 6, `low` 7, `volume` 8, `close` 9, `open` 14, `lastTimestamp` 45 and `halted` 49.
    - `var live: TickField` maps a delayed field to its twin, per the decisions; any other field maps to itself.
  - `public enum Tick: Sendable, Equatable` has these cases:
    - `price(TickField, price: Decimal?, size: Decimal?)`;
    - `size(TickField, Decimal?)`;
    - `generic(TickField, Decimal)`;
    - `string(TickField, String)`;
    - `dataType(MarketDataType)`.
  - `IBMessage` cases:
    - `.tick(requestID: Int, Tick)` covers in 1, 2, 45 and 46, and in 58 as `.dataType`;
    - `.tickRequestParameters(requestID: Int, minTick: Decimal?, bboExchange: String, snapshotPermissions: Int)` covers in 81.
  - `IBRequest` cases:
    - `.marketDataType(MarketDataType)` is `59,1,type`;
    - `.marketData(requestID: Int, contract: Contract)` is `1,11,id,contract…,"0","","0","0",""`, 20 fields;
    - `.cancelMarketData(requestID: Int)` is `2,2,id`.

- [ ] **Step 1: Write the failing tests.**
  - `tickPriceDecodes`: `["1","6","7","1","351.5","200","1"]` decodes to `.tick(requestID: 7, .price(.bid, price: d("351.5"), size: d("200")))`.
  - `tickSizeGenericStringDecode`:
    - `["2","6","7","8","1234567"]` decodes to `.size(.volume, d("1234567"))`;
    - `["45","6","7","49","0"]` decodes to `.generic(.halted, 0)`;
    - `["46","6","7","45","1794321000"]` decodes to `.string(.lastTimestamp, "1794321000")`.
  - `marketDataTypeDecodes`: `["58","1","7","3"]` decodes to `.tick(requestID: 7, .dataType(.delayed))`.
  - `tickReqParamsDecodes`: `["81","7","0.01","9c0001","3"]` decodes to `.tickRequestParameters(…)`.
  - `delayedFieldsMapToLive`: `TickField(rawValue: 66).live == .bid`, and `TickField(rawValue: 75).live == .close` and `TickField.bid.live == .bid`.
  - `marketDataRequestsEncode`:
    - `.marketDataType(.delayed)` encodes to `body("59","1","3")`;
    - `.marketData(requestID: 7, contract: aapl)` encodes to `body("1","11","7", aapl…, "0","","0","0","")`;
    - `.cancelMarketData(requestID: 7)` encodes to `body("2","2","7")`.
  - `shortTickFramesAreMalformed`: `["1","6","7","1"]` decodes to `.malformed`.
- [ ] **Step 2: Run.** It should fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** `swift test` should be green.
- [ ] **Step 5: Commit.** Message: «Decode top-of-book ticks and the market-data type, and encode their requests».

### Task 4: Quotes in `IBClient`, and the typed refusal

**Files:**
- Modify: `IBClient.swift`, `IBClientError.swift`, `ErrorCode.swift`, `Tests/IBKRTests/ErrorCodeTests.swift`, `README.md`, `docs/DECISIONS.md`
- Test: `Tests/IBKRTests/IBClientMarketDataTests.swift`

**Interfaces:**
- **Consumes:** Tasks 2 and 3.
- **Produces:**
  - `public func setMarketDataType(_ type: MarketDataType) throws(IBClientError)`.
  - `public func marketData(_ contract: Contract) throws(IBClientError) -> AsyncThrowingStream<Tick, any Error>`. It yields every `.tick` for its reqId and cancels with `.cancelMarketData` when stopped.
  - `IBClientError.noMarketDataPermission(code: Int, text: String)`.
  - `ErrorCode.isNoMarketDataPermission(code: Int, text: String) -> Bool`.
  - `routeToStream`:
    - finishes on a fatal error with the permission case when that function holds;
    - hands notices with a reqId to the stream's `route`, which ignores what it does not know.
  - The kind table makes 317, 10090 and 10091 notices.

- [ ] **Step 1: Write the failing tests.**
  - `marketDataYieldsTicks`: the sent frame is out 1. Feed a price, a size and a `58` frame; they come out in order. Stopping sends `["2","2",id]`.
  - `delayedNoticeKeepsTheStreamAndMapsFields`: after `setMarketDataType(.delayed)`, the sent frame is `["59","1","3"]`. A 10167 error for the reqId does not end the stream. A following field-66 price comes out, and its field's `.live` is `.bid`.
  - `noPermissionIsTyped`: error 354 for the reqId makes the stream throw `.noMarketDataPermission(code: 354, …)`.
  - `otherFatalStaysIB`: error 200 makes the stream throw `.ib(code: 200, …)`.
  - In `ErrorCodeTests`:
    - `noMarketDataPermissionCodes`: every code in the set is true. 162 with `"Historical Market Data Service error message:No market data permissions for NASDAQ STK"` is true; 162 with `"…:API historical data query cancelled: 1"` is false; 200 is false.
    - `kindTableAdditions`: 317, 10090 and 10091 are `.notice`.
- [ ] **Step 2: Run.** It should fail.
- [ ] **Step 3: Implement.**
  - README «Use» gains `setMarketDataType` (not kept across reconnects) and `marketData`.
  - DECISIONS gains the typed-refusal row, with its code set and the 162 text rule, and the error-kind changes, each with what was rejected.
- [ ] **Step 4: Run.** `swift test` should be green.
- [ ] **Step 5: Commit.** Message: «Stream top-of-book ticks per contract and end a refused subscription with a typed permission error».

### Task 5: Historical bars

**Files:**
- Modify: `MarketData.swift`, `IBMessage.swift`, `IBDecoder.swift`, `IBRequest.swift`, `IBClient.swift`, `docs/protocol-178.md`, `README.md`, `docs/DECISIONS.md`
- Test: `Tests/IBKRTests/HistoricalTests.swift`

**Interfaces:**
- **Produces:**
  - `public struct Bar: Sendable, Equatable { time: Date; open, high, low, close, volume: Decimal; average: Decimal?; count: Int }`.
  - `public enum BarEvent: Sendable, Equatable { case history([Bar]); case update(Bar) }`.
  - `IBMessage` cases: `.historicalData(requestID: Int, [Bar])` (17, which carries the whole batch) and `.historicalDataUpdate(requestID: Int, Bar)` (90, field order O,C,H,L).
  - `IBRequest` cases:
    - `.historicalData(requestID:contract:end:barSize:duration:rth:whatToShow:keepUpToDate:)`, 23 fields, `formatDate` `"2"`, chartOptions `""`;
    - `.cancelHistoricalData(requestID: Int)`, `25,1,id`.
  - The client call: `public func historicalBars(_ contract: Contract, end: Date? = nil, duration: String, barSize: String, whatToShow: String = "TRADES", rth: Bool = true, keepUpToDate: Bool = false) throws(IBClientError) -> AsyncThrowingStream<BarEvent, any Error>`.

- [ ] **Step 1: Write the failing tests.**
  - `historicalRequestEncodes`: `end` 2026-11-10 21:00:00 UTC, `"1 D"`, `"5 mins"`, `rth` true, `"TRADES"` encodes to `body("20",id, aapl…, "0","20261110-21:00:00","5 mins","1 D","1","TRADES","2","0","")`. With `end` nil the endDateTime field is `""`.
  - `historicalDataDecodes`:
    - `["17","9","20261110  09:30:00","20261110  16:00:00","2", "1794321000","351.0","352.0","350.5","351.5","1000","351.2","42", "20261110","350.0","353.0","349.0","352.5","90000","351.9","8000"]` decodes to two bars;
    - the first has time epoch 1794321000 and close 351.5;
    - the second has time 2026-11-10 00:00 UTC.
  - `historicalUpdateDecodes`: `["90","9","42","1794321300","351.5","351.7","351.9","351.4","351.6","300"]` decodes to a bar with open 351.5, close 351.7, high 351.9, low 351.4, count 42.
  - `badBarTimeIsMalformed`: a bar time of `"yesterday"` decodes to `.malformed`.
  - `historyWithoutUpdatesEndsWithoutCancel`: one `.history` element, then the loop ends. The frames sent hold no `25`, and `requestStreamCount == 0`.
  - `keepUpToDateStreamsUpdatesAndCancels`: `.history`, then two `.update`s. Stopping sends `["25","1",id]`.
  - `historyPermissionErrorIsTyped`: 162 with a permission text makes the stream throw `.noMarketDataPermission`.
- [ ] **Step 2: Run.** It should fail.
- [ ] **Step 3: Implement.** Do the protocol-178 sections, README «Use» and the DECISIONS row for `Bar.time` and daily bars.
- [ ] **Step 4: Run.** `swift test` should be green.
- [ ] **Step 5: Commit.** Message: «Stream historical bars, ending after the batch unless kept up to date».

### Task 6: Depth book

**Files:**
- Create: `Sources/IBKR/State/DepthBook.swift`
- Modify: `MarketData.swift`, `IBMessage.swift`, `IBDecoder.swift`, `IBRequest.swift`, `IBClient.swift`, `docs/protocol-178.md`, `README.md`, `docs/DECISIONS.md`
- Test: `Tests/IBKRTests/DepthTests.swift`

**Interfaces:**
- **Produces:**
  - `public struct DepthLevel: Sendable, Equatable { price: Decimal; size: Decimal; marketMaker: String }`.
  - `public struct DepthBook: Sendable, Equatable { bids: [DepthLevel]; asks: [DepthLevel] }`, with `mutating func apply(_ u: DepthUpdate)` and `mutating func reset()`. Position-indexed storage is internal.
  - `public struct DepthUpdate: Sendable, Equatable { position: Int; marketMaker: String; operation: Operation; side: Side; price: Decimal; size: Decimal }`.
    - `enum Operation: Int { insert = 0, update, delete }`;
    - `enum Side: Int { ask = 0, bid }`.
  - `IBMessage.depth(requestID: Int, DepthUpdate)` comes from both 12 and 13.
  - `IBRequest` cases:
    - `.marketDepth(requestID:contract:rows:smart:)`, `10,5,id,contract…,rows,smart,""`;
    - `.cancelMarketDepth(requestID:smart:)`, `11,1,id,smart`.
  - The client call: `public func marketDepth(_ contract: Contract, rows: Int, smart: Bool = true) throws(IBClientError) -> AsyncThrowingStream<DepthBook, any Error>`.

- [ ] **Step 1: Write the failing tests.**
  - `depthFramesDecode`: `["12","1","4","0","0","1","351.5","100"]` decodes to an insert on the bid at position 0 with market maker `""`. `["13","1","4","1","NSDQ","1","0","351.6","50","1"]` decodes to an update on the ask with market maker `NSDQ`.
  - `bookInsertUpdateDelete`: insert bid 0 and bid 1, update bid 0, then delete bid 1. The bids are one level holding the updated values.
  - `depthStreamYieldsWholeBooks`: each fed update yields a whole book. Stopping sends `["11","1",id,"1"]`.
  - `depthResetEmptiesTheBookAndGoesOn`: build a two-level book, then send error 317 for the reqId. The next element is an empty book. A following insert yields a one-level book, and the stream did not throw.
  - `depthRequestEncodes`: rows 10 and smart true encode to `body("10","5",id, aapl…, "10","1","")`.
- [ ] **Step 2: Run.** It should fail.
- [ ] **Step 3: Implement.** Do the protocol-178 sections, README «Use» and the DECISIONS whole-book row.
- [ ] **Step 4: Run.** `swift test` should be green.
- [ ] **Step 5: Commit.** Message: «Stream the depth book whole after each update, emptied on IB's reset».

### Task 7: Tick-by-tick

**Files:**
- Modify: `MarketData.swift`, `IBMessage.swift`, `IBDecoder.swift`, `IBRequest.swift`, `IBClient.swift`, `docs/protocol-178.md`, `README.md`
- Test: `Tests/IBKRTests/TickByTickTests.swift`

**Interfaces:**
- **Produces:**
  - `public enum TickByTickType: String, Sendable { case last = "Last", allLast = "AllLast", bidAsk = "BidAsk", midPoint = "MidPoint" }`.
  - `public enum TickByTick: Sendable, Equatable` has these cases:
    - `trade(time: Date, price: Decimal, size: Decimal, exchange: String, conditions: String, pastLimit: Bool, unreported: Bool)`;
    - `bidAsk(time: Date, bidPrice: Decimal, askPrice: Decimal, bidSize: Decimal, askSize: Decimal)`;
    - `midPoint(time: Date, price: Decimal)`.
  - `IBMessage.tickByTick(requestID: Int, TickByTick)` (99).
  - `IBRequest` cases: `.tickByTick(requestID:contract:type:)`, `97,id,contract…,type.rawValue,"0","0"`; and `.cancelTickByTick(requestID:)`, `98,id`.
  - The client call: `public func tickByTick(_ contract: Contract, _ type: TickByTickType) throws(IBClientError) -> AsyncThrowingStream<TickByTick, any Error>`.

- [ ] **Step 1: Write the failing tests.**
  - `tradeTickDecodes`: `["99","8","2","1794321000","351.5","100","2","NASDAQ","@ I"]` decodes to `.trade(…, pastLimit: false, unreported: true)`.
  - `bidAskTickDecodes`: a 9-field frame decodes to `.bidAsk`.
  - `midPointTickDecodes`: a 5-field frame decodes to `.midPoint`.
  - An unknown tick type 5 decodes to `.malformed`.
  - `tickByTickStreamsAndCancels`: the sent frame is `["97",id, aapl…, "AllLast","0","0"]`. Fed ticks come out, and stopping sends `["98",id]`.
- [ ] **Step 2: Run.** It should fail.
- [ ] **Step 3: Implement.** Do the protocol-178 section and README «Use».
- [ ] **Step 4: Run.** `swift test` should be green.
- [ ] **Step 5: Commit.** Message: «Stream tick-by-tick trades, quotes and midpoints».

### Task 8: Live check on paper, recordings, docs

The controller runs this task. The subagent writes the code and runs only `swift test`; the controller runs the live tests after the owner's go. Nothing here places an order.

**Files:**
- Modify: `Tests/IBKRTests/LiveTests.swift`, `Tests/IBKRTests/RecordedFrameTests.swift`, `ErrorCode.swift` (only if the run shows another refusal code), `README.md`, `docs/DECISIONS.md`, `docs/KNOWN-GAPS.md`
- Create (written by the live run): `Recorded/liveContractLookups.json` and `Recorded/liveMarketData.json`

- [ ] **Step 1: Live tests.** Each test waits at most 15 s per expectation. Each ends by leaving its loop, so the cancels go out.
  - `liveContractLookups`:
    - `contractDetails(AAPL SMART USD)` has one entry with conID 265598, `minTick > 0`, `timeZoneID` non-empty and `tradingHours` non-empty;
    - `matchingSymbols("AAPL")` holds conID 265598.
  - `liveMarketData`:
    - **Quotes.** `setMarketDataType(.delayed)`, then `marketData(AAPL)` yields a `.dataType` and at least one `.price` with a non-nil price. Outside US hours a close (9 or 75) is enough.
    - **History.** `historicalBars(AAPL, duration: "1 D", barSize: "5 mins")` either yields a non-empty `.history` or throws `.noMarketDataPermission`, and the test prints which.
    - **Depth and tick-by-tick.** `marketDepth(AAPL, rows: 5)` and `tickByTick(AAPL, .allLast)` each either yield or throw `.noMarketDataPermission`. Any other error fails the test, with its code printed.
- [ ] **Step 2: Run.** `swift test` (live tests skipped) should be green. Commit with the message «Check market data and contract lookups live on the paper account».
- [ ] **Step 3 (controller): Live run.** Run with `IBKR_LIVE=1`. If depth or tick-by-tick is refused with a code outside the set, add it to `isNoMarketDataPermission` with a test, and rerun. Check the recordings for the real account id; `grep` must find nothing.
- [ ] **Step 4: Recorded-frame tests** from the run:
  - `recordedContractDetailsDecodes`, checking AAPL's conID, minTick and timeZoneID;
  - `recordedDelayedTicksDecode`, checking the dataType value and the fields seen;
  - the refusal codes seen, pinned as typed errors.

  Exact values come from the recording.
- [ ] **Step 5: Docs.**
  - KNOWN-GAPS header becomes «after stage 4». It records what depth, tick-by-tick and history answered without subscriptions, and settles or keeps the [not ib_async] code meanings the run touched.
  - README status becomes «Stage 4 (done)».
  - Commit with the message «Record the live market-data frames and settle what the run showed».
