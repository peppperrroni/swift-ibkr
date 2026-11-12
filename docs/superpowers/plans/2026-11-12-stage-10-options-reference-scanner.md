# Stages 10 and 11: Options, Reference Data, Scanner, News and Research Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every option, reference, scanner, news, fundamentals, WSH, FA, display-group and verify message `ib_async`
sends or decodes is in `IBRequest` / `IBMessage` with a codec test and a client call:
- contract factories, the full `ContractDetails` with bonds (in 18), and `qualifyContracts`;
- option chains (78 → 75/76) and option calculations (54–57 → 21);
- market rules, family codes and soft-dollar tiers (91, 80, 79 → 93, 78, 77);
- the scanner (22–24 → 19/20), as a stream and as a one-shot;
- news: providers, articles, historical news (85, 84, 86 → 85, 83, 86/87), bulletins (12/13 → 14), and news ticks
  through `marketData`;
- fundamentals (52/53 → 51), WSH (100–103 → 104/105), FA (18/19 → 16/103), display groups (67–70 → 67/68) and
  verify (65/66/72/73 → 65/66/69/70).

**Architecture:** The work follows the existing pattern: codec first, then a client call over `openStream`.
- Task 1 adds the contract factories, a pure value change.
- Task 2 completes `ContractDetails` and decodes bonds into the existing `.contractData`.
- Task 3 opens `IBClient+Reference.swift` (the client helpers become internal) and builds `qualifyContracts` on
  `contractDetails`.
- Tasks 4–6 add the rest of stage 10. `calculate…` reuses the `.tick` route by its own reqId; no new message case.
- Tasks 7–11 add stage 11 in `IBClient+Research.swift`.
- Task 12 closes the records and checks the series.

**Tech Stack:** Swift 6 (tools 6.0), SwiftPM, Foundation, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-12-parity-and-1.0-design.md`: «Этапы» items 10 and 11, «Перечень» rows
«Опционы и справочники» and «Сканер, новости, фундаментальные данные, WSH, FA, группы окон, verify», «Решения после
проверки строителем», and «На усмотрение строителя» (Swift verbs without `req`; the README name table). The base spec
is `docs/superpowers/specs/2026-11-09-swift-ibkr-design.md`.

## Global Constraints

- Repository `C:\Users\viohn\swift-ibkr`, branch `stage-10-options-reference` off `main` (741afd9).
- Protocol pinned to server version 178. No package dependencies; `Package.swift` keeps `// swift-tools-version: 6.0`.
- Money and quantities are `Decimal`. IB's unset markers read as `nil` through `FieldReader.optional…()`. No UNSET
  sentinel in a public type. Use `d("…")` in tests.
- Field orders come from `ib_async` 2.1.0 (`ab629f3`: `client.py`, `decoder.py`, `wrapper.py`, `ib.py`, `contract.py`,
  `objects.py`). Every array in this plan was checked against that source at 178. Never copy code from IB's `ibapi`.
- Orders and requests share ONE id counter (`IBClient.nextRequestID()`).
- Every new public value type is `Sendable, Equatable`, has a public memberwise init, and joins
  `PublicAPITests.everyPublicModelIsConstructible` (plain `import IBKR`).
- Every request stream sends its cancel when the consumer stops it, where IB has a cancel message. A stream the
  client finishes itself (an end marker, a one-shot answer) sends none, unless a task says otherwise.
- Every new request with a reqId gets a FakeGateway IB-error test. An id-less request has no IB-error path
  (DECISIONS, the `depthExchanges()` row): IB cannot address an error to it.
- IB's XML and JSON payloads (fundamentals, scanner parameters, FA, WSH) stay `String`; nothing parses them.
- New public calls go in `Sources/IBKR/Client/IBClient+Reference.swift` (Tasks 3–6) or
  `Sources/IBKR/Client/IBClient+Research.swift` (Tasks 7–11), as `extension IBClient`. `routeToStream` and stored
  state stay in `IBClient.swift`.
- The recorded live frames keep decoding: `everyRecordedFrameDecodes` and the `recorded…` tests stay green.
- The real paper account id never appears. Fixtures use `DU1`, and recordings use `DU0000001`.
- The documents of record (`README.md`, `docs/DECISIONS.md`, `docs/KNOWN-GAPS.md`, `docs/protocol-178.md`,
  `CHANGELOG.md`) change in the same commit as the behaviour they describe:
  - each task's decisions get their DECISIONS rows (numbers refer to «Decisions beyond the spec» at the end);
  - every public API change gets a CHANGELOG `Unreleased` line;
  - a new case in a public enum (`IBRequest`, `IBMessage`, `IBClientError`) is noted as breaking exhaustive switches.
- Commit messages are one imperative sentence, then the reasoning. Read `git log` first. The last line is exactly
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Run tests as `timeout 900 swift test`, in the foreground. A test waits on an async event for at most 2 s (`within2s`).
- CI (macOS, Linux 6.0 and latest, Windows, pod-lint) must be green. Push the branch
  (`git push -u origin stage-10-options-reference`) and watch
  `gh run watch --exit-status $(gh run list --branch stage-10-options-reference --limit 1 --json databaseId -q '.[0].databaseId')`.
  Moving and pushing `main` is the controller's job.

## Review Focus

1. **An ambiguous `qualifyContracts` answer.** Several contracts of the requested secType must come back as
   `.ambiguous` with every candidate, never as the first one; a secType filter that leaves exactly one must qualify
   it, keeping `SMART`. Tests: Task 3 `qualifyContractsReturnsEachOutcomeInOrder` and
   `qualifyContractsPicksTheRequestedSecType`.
2. **A calculation beside a quote stream.** Tick 21 for a `marketData` reqId must not answer a pending
   `calculateImpliedVolatility`, and the calculation's own 21 must not reach the quote stream. Test: Task 5
   `calculationTakesOnlyItsOwnTick`.
3. **Scanner end semantics.** The stream never ends by itself and yields each whole scan; the one-shot returns the
   first scan and then sends 23, but sends no 23 after IB's error. Tests: Task 7
   `scannerSubscriptionStreamsWholeScansAndCancels`, `scannerDataReturnsTheFirstScanThenCancels` and
   `scannerDataFailsOnItsErrorWithoutCancel`.
4. **The display-group stream and its update.** The reqId returned with the stream is the one `updateDisplayGroup`
   sends under, and stopping the stream sends 70 for that same id. Test: Task 11
   `displayGroupUpdatesStreamUpdateAndCancel`.
5. **A second news-bulletin stream.** IB holds one bulletin subscription per connection. A second stream must be
   refused rather than share it, because stopping either one would cut the other. Once the first stream stops, a new
   stream must work. Test: Task 9 `aSecondNewsBulletinsStreamIsRefused`.

## Shared test fixtures (added to `Tests/IBKRTests/Fixtures.swift` in Task 1)

```swift
/// The AAPL Dec 2026 200 call on SMART, and its 12-field contract block.
let aaplCall = Contract.option("AAPL", lastTradeDateOrContractMonth: "20261218", strike: 200, right: "C",
                               exchange: "SMART", currency: "USD")
let aaplCallBlock = ["0", "AAPL", "OPT", "20261218", "200.0", "C", "", "SMART", "", "USD", "", ""]

/// IB's error frame (in 4) for `reqID`.
func ibError(_ reqID: String, _ code: String, _ text: String) -> [String] { ["4", "2", reqID, code, text, ""] }
```

Each new test file declares its own private `connected(_:)` (a copy of the one in `IBClientLookupTests`, client id 7)
and, where it encodes one, the private `aapl = ["0", "AAPL", "STK", "", "0.0", "", "", "SMART", "", "USD", "", ""]`. The
first request after `connect` is `sent[FakeGateway.syncFrames]`, and `id` is read from it.

---

### Task 1: Contract factories (sonnet)

**Files:**
- Modify: `Sources/IBKR/Models/Contract.swift` (an `extension Contract` with the factories)
- Create: `Tests/IBKRTests/ContractFactoryTests.swift`
- Test: `Fixtures.swift`, `PublicAPITests.swift`
- Docs: DECISIONS (decision 3), CHANGELOG (Added: the fourteen factories)

**Interfaces:**
- Produces, all `public static func … -> Contract`, built on `Contract(symbol:secType:exchange:currency:primaryExchange:)`.
  Every parameter after the first has `ib_async`'s default, which is `""` except where noted:
  - `stock(_ symbol: String, exchange: String = "", currency: String = "", primaryExchange: String = "")`, `STK`;
  - `option(_ symbol: String, lastTradeDateOrContractMonth: String = "", strike: Decimal? = nil, right: String = "", exchange: String = "", multiplier: String = "", currency: String = "")`, `OPT`;
  - `futuresOption(…)` with the same parameters as `option`, `FOP`;
  - `future(_ symbol: String, lastTradeDateOrContractMonth: String = "", exchange: String = "", localSymbol: String = "", multiplier: String = "", currency: String = "")`, `FUT`;
  - `contFuture(_ symbol: String, exchange: String = "", localSymbol: String = "", multiplier: String = "", currency: String = "")`, `CONTFUT`;
  - `forex(_ pair: String, exchange: String = "IDEALPRO")`, `CASH`: the symbol is the first three characters of the pair
    and the currency is the rest;
  - `index`, `cfd`, `commodity`, `crypto`, `mutualFund` and `warrant`, each `(_ symbol: String, exchange: String = "", currency: String = "")`,
    with secTypes `IND`, `CFD`, `CMDTY`, `CRYPTO`, `FUND` and `WAR`;
  - `bond(secIDType: String = "", secID: String = "", exchange: String = "", currency: String = "")`, `BOND`, symbol `""`;
  - `bag(_ symbol: String, legs: [ComboLeg], exchange: String = "", currency: String = "")`, `BAG`, with
    `comboLegs = legs`.
- Fixtures: `aaplCall`, `aaplCallBlock` and `ibError` above.

- [ ] **Step 1: Write the failing tests** in `ContractFactoryTests`
  - `everyFactorySetsItsSecType`: the fourteen factories, called with `"X"` (`forex("EURUSD")`, `bond()`,
    `bag("X", legs: [])`), give `STK, OPT, FOP, FUT, CONTFUT, CASH, IND, CFD, CMDTY, CRYPTO, FUND, WAR, BOND, BAG`.
  - `factoriesKeepIbAsyncDefaults`:
    - `Contract.stock("AAPL")` has `exchange == ""` and `currency == ""`;
    - `Contract.forex("EURUSD")` has `symbol "EUR"`, `currency "USD"` and `exchange "IDEALPRO"`;
    - `Contract.option("AAPL")` has `strike == nil`.
  - `optionFactoryFillsItsFields`: `aaplCall` has `lastTradeDateOrContractMonth "20261218"`, `strike 200`, `right "C"`,
    `exchange "SMART"` and `currency "USD"`. Also
    `try IBRequest.contractDetails(requestID: 5, contract: aaplCall).body() == body(["9", "8", "5"] + aaplCallBlock + ["0", "", "", ""])`.
  - `bondAndBagFactories`:
    - `Contract.bond(secIDType: "ISIN", secID: "US459200HU86")` has `secIDType "ISIN"`, `secID "US459200HU86"` and
      `symbol ""`;
    - `Contract.bag("AAPL", legs: bagContract.comboLegs, exchange: "SMART", currency: "USD").comboLegs == bagContract.comboLegs`.
  - `PublicAPITests`: `Contract.stock("AAPL").secType == "STK"`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter ContractFactoryTests`. Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («Add ib_async's contract factories as static Contract builders»).

### Task 2: The full `ContractDetails` and bond details (in 18) (sonnet)

**Files:**
- Modify: `Sources/IBKR/Models/MarketData.swift` (`ContractDetails`), `Sources/IBKR/Messages/IBDecoder.swift`
  (`contractData` reads every field; a new `bondContractData` beside it)
- Test: `LookupCodecTests.swift`, `RecordedFrameTests.swift`, `IBClientLookupTests.swift`
- Docs:
  - protocol-178: the contractData table drops every «skipped» note and gives row 4 the split rule; there is a new
    section «bondContractData (in 18)».
  - DECISIONS: decisions 4 and 5.
  - CHANGELOG:
    - Added: the new `ContractDetails` fields, and bond details through `contractDetails`.
    - Changed: an option's or future's `lastTradeDateOrContractMonth` keeps only the date, and the time goes to
      `lastTradeTime`.

**Interfaces:**
- Produces: new `ContractDetails` fields. Each is declared with its default, and the init is unchanged, as `Order` was
  (DECISIONS, the flat `Order` and `Contract` row):
  ```swift
  public var underConID = 0
  public var contractMonth = "", industry = "", category = "", subcategory = ""
  public var evRule = ""
  public var evMultiplier: Decimal? = nil
  public var secIDList: [TagValue] = []
  public var aggGroup: Int? = nil
  public var underSymbol = "", underSecType = ""
  public var marketRuleIDs: [Int] = []
  public var realExpirationDate = "", lastTradeTime = ""
  // bonds (in 18)
  public var cusip = "", ratings = "", descAppend = "", bondType = "", couponType = ""
  public var coupon: Decimal? = nil
  public var convertible = false, callable = false, putable = false
  public var maturity = "", issueDate = "", nextOptionDate = "", nextOptionType = ""
  public var nextOptionPartial = false
  public var notes = ""
  ```
- The readers:
  - 10 (unchanged layout): it now reads `underConId` (int), `contractMonth`, `industry`, `category`, `subcategory`,
    `evRule`, `evMultiplier` (optionalDecimal), the secId pairs into `secIDList`, `aggGroup` (optionalInt),
    `underSymbol`, `underSecType`, `marketRuleIds` and `realExpirationDate`.
  - `marketRuleIds` is a comma list of ints; `""` is `[]`, and a non-number is `.malformed`.
  - lastTimes (field 4) is split as `ib_async` does: on `-` when it has one, else on runs of whitespace. Part 0 is
    `lastTradeDateOrContractMonth`, part 1 is `lastTradeTime`, and part 2, when present, replaces `timeZoneID`.
- 18, no version, 36 fields plus 2 per secId:
  `18, reqId, symbol, secType, cusip, coupon, lastTimes, issueDate, ratings, bondType, couponType, convertible, callable, putable, descAppend, exchange, currency, marketName, tradingClass, conId, minTick, orderTypes, validExchanges, nextOptionDate, nextOptionType, nextOptionPartial, notes, longName, evRule, evMultiplier, numSecIds, n × (tag, value), aggGroup, marketRuleIds, minSize, sizeIncrement, suggestedSizeIncrement`.
  - It decodes to `.contractData(requestID:, ContractDetails)`.
  - lastTimes part 0 goes to `maturity`; the contract's `lastTradeDateOrContractMonth` stays `""`.
  - `priceMagnifier` is 0, and `stockType`, `tradingHours` and `liquidHours` are `""`. `timeZoneID` is lastTimes part 2,
    or `""`.
  - The contract is `Contract(symbol:secType:)` with `exchange`, `currency`, `tradingClass` and `conID` from the frame.
  - `contractDetails(_:)` needs no change: it already collects every `.contractData` for its reqId.

- [ ] **Step 1: Write the failing tests**
  - `LookupCodecTests`:
    - `contractDataDecodes` and `contractDataWithSecIdsAndTrailingFieldsDecodes`: `expected` also sets
      `industry "Technology"`, `category "Computers"`, `subcategory "Computers"`, `evMultiplier 0`, `aggGroup 1` and
      `marketRuleIDs [26, 26]`. The secIds test also expects
      `secIDList == [TagValue(tag: "ISIN", value: "US0378331005"), TagValue(tag: "FIGI", value: "BBG000B9XRY4")]`.
    - `contractDataSplitsLastTimes`:
      - field 4 `"20261218 16:00 US/Central"` → date `"20261218"`, `lastTradeTime "16:00"`, `timeZoneID "US/Central"`;
      - `"20261218-16:00:00"` → `"20261218"`, `"16:00:00"`, and `timeZoneID` stays `"US/Eastern"`;
      - `"202612"` → `"202612"` and `lastTradeTime ""`.
    - `badMarketRuleIDsAreMalformed`: field 34 `"26,x"` → `.malformed` with id 10.
    - `bondContractDataDecodes`. The frame
      `["18", "7", "IBM", "BOND", "459200HU8", "3.45", "20270210", "20170210", "A2 A-", "FIXED", "FIXED", "0", "1", "0", "", "SMART", "USD", "IBM 3.45 02/10/27", "IBCID123", "123456789", "0.001", "LMT,MKT", "SMART", "", "", "0", "", "IBM 3.45 02/10/27", "", "", "0", "1", "239", "1", "1", "1"]`
      (36 fields) decodes to `.contractData(requestID: 7, x)`, where:
      - `x` is `ContractDetails(contract: c, marketName: "IBM 3.45 02/10/27", minTick: d("0.001"), priceMagnifier: 0, longName: "IBM 3.45 02/10/27", stockType: "", orderTypes: ["LMT", "MKT"], validExchanges: ["SMART"], timeZoneID: "", tradingHours: "", liquidHours: "", minSize: 1, sizeIncrement: 1, suggestedSizeIncrement: 1)`;
      - `c` is `Contract(symbol: "IBM", secType: "BOND")` with `conID 123456789` and `tradingClass "IBCID123"`;
      - `x` then sets `cusip "459200HU8"`, `coupon d("3.45")`, `maturity "20270210"`, `issueDate "20170210"`,
        `ratings "A2 A-"`, `bondType "FIXED"`, `couponType "FIXED"`, `callable true`, `aggGroup 1` and
        `marketRuleIDs [239]`.
    - `shortBondFrameIsMalformed`: the first 21 fields → `.malformed` with id 18.
  - `RecordedFrameTests.recordedContractDetailsDecodes` adds:
    - `details.secIDList == [TagValue(tag: "ISIN", value: "US0378331005")]`;
    - `details.marketRuleIDs.count == 27` and `details.marketRuleIDs.first == 4563`;
    - `details.industry == "Technology"`, `details.aggGroup == 1` and `details.evMultiplier == nil`.
  - `IBClientLookupTests.contractDetailsCollectsBonds`:
    1. `onRequest` answers a `"9"` frame `f` with the bond frame, using `f[2]` as the reqId, then `["52", "1", f[2]]`.
    2. `contractDetails(Contract.bond(secIDType: "CUSIP", secID: "459200HU8"))` returns one entry with
       `cusip "459200HU8"`.
    3. The sent frame's `[16...17] == ["CUSIP", "459200HU8"]`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "LookupCodecTests|RecordedFrameTests|IBClientLookupTests"`.
  Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above. Make `IBDecoder.list(_:)` reachable from the new reader. Both readers
  share one lastTimes split helper.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS, including `everyRecordedFrameDecodes`.
- [ ] **Step 5: Docs and commit** («Decode every contract detail field and bond details»).

### Task 3: `qualifyContracts` (opus)

**Files:**
- Create: `Sources/IBKR/Client/IBClient+Reference.swift`, `Sources/IBKR/Models/Reference.swift`,
  `Tests/IBKRTests/IBClientReferenceTests.swift`
- Modify: `Sources/IBKR/Client/IBClient.swift`: `requireConnected`, `openStream`, `answer`, `collect` and `nextLocalID`
  lose `private`, so the extensions can use them.
- Test: `PublicAPITests.swift`
- Docs: DECISIONS (decisions 2 and 6), CHANGELOG (Added: `qualifyContracts(_:)` and `ContractQualification`)

**Interfaces:**
- Consumes: `contractDetails(_:)` with Task 2's split dates; `Contract.stock`, `.future` and `.futuresOption` (Task 1).
- Produces:
  - In `Reference.swift`:
    ```swift
    public enum ContractQualification: Sendable, Equatable {
        case qualified(Contract)
        case ambiguous([Contract])
        case notFound
    }
    ```
  - `public func qualifyContracts(_ contracts: [Contract]) async throws(IBClientError) -> [ContractQualification]`,
    one result per input, in input order:
    1. A `BAG` among the inputs throws `.encoding(.unsupported("secType BAG"))` before anything is sent.
    2. Every `contractDetails` runs at once in a task group, as `ib_async` gathers them.
    3. `.ib(code: 200, …)` or an empty list gives `.notFound`.
    4. Exactly one detail gives `.qualified(detail.contract)`.
    5. With several, the candidates are those whose secType equals the input's, when the input's secType is not
       `""`; when none matches, all of them are candidates. Exactly one candidate gives `.qualified`; otherwise
       `.ambiguous(candidates)`, in IB's order.
    6. A qualified contract is the detail's contract with `exchange = "SMART"` when the input's exchange was `SMART`.
    7. Any other error is thrown. The group then cancels the rest, which sends nothing, since 9 has no cancel.

- [ ] **Step 1: Write the failing tests** in `IBClientReferenceTests`. The private helper
  `details(_ id: String, _ symbol: String, conID: String, secType: String = "STK", lastTimes: String = "", exchange: String = "SMART") -> [String]`
  returns
  `["10", id, symbol, secType, lastTimes, "0", "", exchange, "USD", symbol, "NMS", "NMS", conID, "0.01", "", "LMT", "SMART", "1", "0", symbol, "NASDAQ", "", "", "", "", "US/Eastern", "", "", "", "", "0"] + Array(repeating: "", count: 9)`
  (40 fields).
  - `qualifyContractsReturnsEachOutcomeInOrder` (Review Focus 1):
    1. `onRequest` answers `"9"` frames `f` by `f[4]`:
       - `"AAPL"` → `details(f[2], "AAPL", conID: "265598", exchange: "NASDAQ")`, then `["52", "1", f[2]]`;
       - `"ZZZZ"` → `ibError(f[2], "200", "No security definition has been found for the request")`;
       - `"ES"` → `details(f[2], "ES", conID: "1", secType: "FUT", lastTimes: "20261218")`,
         `details(f[2], "ES", conID: "2", secType: "FUT", lastTimes: "20270319")`, then `["52", "1", f[2]]`.
    2. Call `qualifyContracts([.stock("AAPL", exchange: "SMART", currency: "USD"), .stock("ZZZZ", exchange: "SMART", currency: "USD"), .future("ES", exchange: "CME")])`.
    3. Result `[0]` is `.qualified(c)` with `c.conID == 265598`, `c.exchange == "SMART"` and
       `c.primaryExchange == "NASDAQ"`.
    4. `[1] == .notFound`. `[2]` is `.ambiguous(list)` with `list.map(\.conID) == [1, 2]`.
    5. `requestStreamCount == 0`.
  - `qualifyContractsPicksTheRequestedSecType` (Review Focus 1):
    1. The input is
       `.futuresOption("ES", lastTradeDateOrContractMonth: "20261218", strike: 6000, right: "C", exchange: "CME")`.
    2. `onRequest` answers with `details(f[2], "ES", conID: "7", secType: "FOP", lastTimes: "20261218 15:00 US/Central", exchange: "CME")`,
       `details(f[2], "ES", conID: "8", secType: "OPT", lastTimes: "20261218", exchange: "CME")`, then the end.
    3. The result is `[.qualified(c)]`, with `c.conID == 7`, `c.exchange == "CME"` and
       `c.lastTradeDateOrContractMonth == "20261218"`.
  - `qualifyContractsThrowsAnyOtherError`:
    1. `onRequest` answers only the AAPL frame, with `ibError(f[2], "321", "Error validating request")`.
    2. `qualifyContracts([.stock("AAPL"), .stock("MSFT")])` throws `.ib(code: 321, text: "Error validating request")`.
    3. Within 2 s `requestStreamCount == 0`. After 50 ms the sent count is still `syncFrames + 2`.
  - `qualifyContractsRefusesABagBeforeSending`: `qualifyContracts([.stock("AAPL"), bagContract])` throws
    `.encoding(.unsupported("secType BAG"))`. After 50 ms the sent count is `syncFrames`.
  - `PublicAPITests`: `ContractQualification.notFound != .ambiguous([])`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter IBClientReferenceTests`. Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS. Run `qualifyContractsThrowsAnyOtherError` 20 times
  (`for i in $(seq 20); do timeout 900 swift test --filter qualifyContractsThrows > /dev/null || echo FAIL $i; done`)
  and expect no `FAIL`.
- [ ] **Step 5: Docs and commit** («Qualify contracts and report ambiguity with every candidate»).

### Task 4: Option chains (sonnet)

**Files:**
- Modify: `Reference.swift` (`OptionChain`), `IBRequest.swift`, `IBMessage.swift`, `IBDecoder.swift`,
  `IBClient+Reference.swift`, `IBClient.swift` (`routeToStream`)
- Create: `Tests/IBKRTests/ReferenceCodecTests.swift`
- Test: `IBClientReferenceTests.swift`, `PublicAPITests.swift`
- Docs:
  - protocol-178: «reqSecDefOptParams (out 78)», «securityDefinitionOptionParameter (in 75)» and
    «securityDefinitionOptionParameterEnd (in 76)».
  - DECISIONS: decision 7.
  - CHANGELOG: Added, `optionChains(for:futFopExchange:)`, `OptionChain`, and the new cases.

**Interfaces:**
- Produces:
  - `public struct OptionChain`, with fields `exchange: String`, `underlyingConID: Int`, `tradingClass: String`,
    `multiplier: String`, `expirations: [String]` and `strikes: [Decimal]`.
  - `IBRequest.secDefOptParams(requestID: Int, underlyingSymbol: String, futFopExchange: String, underlyingSecType: String, underlyingConID: Int)`
    → `78, reqId, underlyingSymbol, futFopExchange, underlyingSecType, underlyingConId`. There is no version.
  - `IBMessage.securityDefinitionOptionParameter(requestID: Int, OptionChain)` decodes from
    `75, reqId, exchange, underlyingConId, tradingClass, multiplier, nExp, nExp × expiration, nStrikes, nStrikes × strike`,
    with no version and both counts through `wireCount`.
  - `IBMessage.securityDefinitionOptionParameterEnd(requestID: Int)` decodes from `76, reqId`.
  - `public func optionChains(for underlying: Contract, futFopExchange: String = "") async throws(IBClientError) -> [OptionChain]`
    sends `underlying.symbol`, `futFopExchange`, `underlying.secType` and `underlying.conID`. It collects every 75 until
    76, with no cancel (IB has none).
  - `routeToStream` routes both new cases by reqId.

- [ ] **Step 1: Write the failing tests**
  - `ReferenceCodecTests.optionChainsCodec`:
    - `.secDefOptParams(requestID: 7, underlyingSymbol: "AAPL", futFopExchange: "", underlyingSecType: "STK", underlyingConID: 265598)`
      → `body("78", "7", "AAPL", "", "STK", "265598")`;
    - `body("75", "7", "SMART", "265598", "AAPL", "100", "2", "20261218", "20270115", "3", "190", "195", "200")` →
      `.securityDefinitionOptionParameter(requestID: 7, OptionChain(exchange: "SMART", underlyingConID: 265598, tradingClass: "AAPL", multiplier: "100", expirations: ["20261218", "20270115"], strikes: [190, 195, 200]))`;
    - `body("76", "7")` → `.securityDefinitionOptionParameterEnd(requestID: 7)`;
    - `body("75", "7", "SMART", "265598", "AAPL", "100", "-1")` → `.malformed`.
  - `IBClientReferenceTests`:
    - `optionChainsCollectUntilEnd`:
      1. `var u = Contract.stock("AAPL", exchange: "SMART", currency: "USD"); u.conID = 265598`.
      2. `onRequest` answers a `"78"` frame `f` with the 75 frame above under `f[1]`, then the same under `"CBOE"`,
         then `["76", f[1]]`.
      3. `optionChains(for: u)` → two chains, with exchanges `["SMART", "CBOE"]`.
      4. The sent frame is `["78", f[1], "AAPL", "", "STK", "265598"]`. After 50 ms nothing more has been sent, and
         `requestStreamCount == 0`.
    - `optionChainsFailOnTheirError`: the answer is
      `ibError(f[1], "200", "No security definition has been found for the request")` → throws `.ib(code: 200, …)`.
  - `PublicAPITests`: build one `OptionChain`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "ReferenceCodecTests|IBClientReferenceTests"`. Expected: a compile
  FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («Ask IB for option chains»).

### Task 5: Option calculations (opus)

**Files:**
- Modify: `IBRequest.swift` (and `PlaceOrderEncoding.swift`, whose orderMiscOptions line uses the new
  `tagValues`), `IBClient+Reference.swift`
- Test: `ReferenceCodecTests.swift`, `IBClientReferenceTests.swift`, `RequestTests.swift`
- Docs:
  - protocol-178: «calculateImpliedVolatility (out 54)», «calculateOptionPrice (out 55)»,
    «cancelCalculateImpliedVolatility (out 56)» and «cancelCalculateOptionPrice (out 57)». The tickOptionComputation
    section adds that 21 also answers 54 and 55 under their reqId.
  - DECISIONS: decisions 8 and 12.
  - CHANGELOG: Added, `calculateImpliedVolatility(_:optionPrice:underPrice:options:)`,
    `calculateOptionPrice(_:volatility:underPrice:options:)`, and the four `IBRequest` cases.

**Interfaces:**
- Consumes: `aaplCall` (Task 1); `Tick.optionComputation` and the `.tick` route (stage 8).
- Produces:
  - `static func tagValues(_ list: [TagValue]) -> String` in `IBRequest` gives `"tag=value;"` per pair, joined with
    no separator. placeOrder's orderMiscOptions uses it.
  - `IBRequest.calculateImpliedVolatility(requestID: Int, contract: Contract, optionPrice: Decimal, underPrice: Decimal, options: [TagValue])`
    → `54, 3, reqId, contract(12), optionPrice, underPrice, options.count, tagValues(options)`.
  - `IBRequest.calculateOptionPrice(requestID: Int, contract: Contract, volatility: Decimal, underPrice: Decimal, options: [TagValue])`
    → `55, 3, …` with the same layout.
  - In both, the prices go through `w.add(Decimal)` (`Decimal.description`), and BAG is refused.
  - `IBRequest.cancelCalculateImpliedVolatility(requestID: Int)` → `56, 1, reqId`, and
    `.cancelCalculateOptionPrice(requestID: Int)` → `57, 1, reqId`.
  - `public func calculateImpliedVolatility(_ contract: Contract, optionPrice: Decimal, underPrice: Decimal, options: [TagValue] = []) async throws(IBClientError) -> OptionComputation`
    and `public func calculateOptionPrice(_ contract: Contract, volatility: Decimal, underPrice: Decimal, options: [TagValue] = []) async throws(IBClientError) -> OptionComputation`:
    - each uses `openStream` with its cancel (56 or 57);
    - its route takes the first `.tick(_, .optionComputation(_, let c))`, yields `c`, finishes and returns `false`, so
      the termination hop sends the cancel after the answer, as `ib_async`'s `finally` does;
    - IB's error for it sends no cancel, except a permission refusal, which already sends one (`routeToStream`).
  - No new `IBMessage` case and no `routeToStream` change: 21 is already `.tick(requestID:, …)` and routed by reqId.

- [ ] **Step 1: Write the failing tests**
  - `ReferenceCodecTests.calculationsEncode`:
    - `.calculateImpliedVolatility(requestID: 7, contract: aaplCall, optionPrice: d("6.1"), underPrice: d("187.2"), options: [])`
      → `body(["54", "3", "7"] + aaplCallBlock + ["6.1", "187.2", "0", ""])`;
    - `.calculateOptionPrice(requestID: 7, contract: aaplCall, volatility: d("0.25"), underPrice: d("187.2"), options: [TagValue(tag: "a", value: "1"), TagValue(tag: "b", value: "2")])`
      → `body(["55", "3", "7"] + aaplCallBlock + ["0.25", "187.2", "2", "a=1;b=2;"])`;
    - `.cancelCalculateImpliedVolatility(requestID: 7)` → `body("56", "1", "7")`, and
      `.cancelCalculateOptionPrice(requestID: 7)` → `body("57", "1", "7")`.
  - `RequestTests.bagIsRefusedWhereIBSendsNoLegs` adds both calculations with `bagContract`.
  - `IBClientReferenceTests`, where `comp` is
    `OptionComputation(tickAttrib: 1, impliedVol: d("0.25"), delta: d("0.55"), optPrice: d("6.1"), pvDividend: 0, gamma: d("0.03"), vega: d("0.12"), theta: d("-0.05"), undPrice: d("187.2"))`
    and `t21(id, iv)` is `["21", id, "53", "1", iv, "0.55", "6.1", "0", "0.03", "0.12", "-0.05", "187.2"]`:
    - `calculateImpliedVolatilityAnswersThenCancels`:
      1. `onRequest` answers a `"54"` frame `f` with `t21(f[2], "0.25")`.
      2. `calculateImpliedVolatility(aaplCall, optionPrice: d("6.1"), underPrice: d("187.2"))` returns `comp`.
      3. The sent frame's `[15...18] == ["6.1", "187.2", "0", ""]`.
      4. Within 2 s the next sent frame is `["56", "1", f[2]]`, then `requestStreamCount == 0`.
    - `calculateOptionPriceRefusedForPermissionSendsItsCancel`: the `"55"` answer is
      `ibError(f[2], "354", "Requested market data is not subscribed.")`. The call throws
      `.noMarketDataPermission(code: 354, text: "Requested market data is not subscribed.")`, and `["57", "1", f[2]]`
      is sent.
    - `calculateFailsOnItsErrorWithoutCancel`: the `"54"` answer is
      `ibError(f[2], "200", "No security definition has been found for the request")` → throws `.ib(code: 200, …)`.
      After 50 ms the sent count is `syncFrames + 1`.
    - `calculationTakesOnlyItsOwnTick` (Review Focus 2):
      1. `quotes = marketData(Contract(symbol: "AAPL"))` takes id `q`. A task then calls
         `calculateImpliedVolatility(aaplCall, …)`, which takes id `c` from `sent[syncFrames + 1][2]`.
      2. Feed `t21(q, "0.25")`, then `t21(c, "0.3")`. The calculation returns `impliedVol == d("0.3")`.
      3. Feed `["1", "6", q, "1", "351.5", "200", "0"]`. `take(2, quotes)` →
         `[.optionComputation(TickField(rawValue: 53), comp), .price(.bid, price: d("351.5"), size: d("200"))]`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "ReferenceCodecTests|IBClientReferenceTests|RequestTests"`.
  Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS, including `PlaceOrderTests`.
- [ ] **Step 5: Docs and commit** («Calculate implied volatility and option prices through IB»).

### Task 6: Market rules, family codes and soft-dollar tiers (sonnet)

**Files:**
- Modify: `Reference.swift` (`PriceIncrement`, `FamilyCode`), `IBRequest.swift`, `IBMessage.swift`, `IBDecoder.swift`,
  `IBClient+Reference.swift`, `IBClient.swift` (`routeToStream`)
- Test: `ReferenceCodecTests.swift`, `IBClientReferenceTests.swift`, `PublicAPITests.swift`
- Docs:
  - protocol-178: «reqMarketRule (out 91)», «marketRule (in 93)», «reqFamilyCodes (out 80)», «familyCodes (in 78)»,
    «reqSoftDollarTiers (out 79)» and «softDollarTiers (in 77)».
  - DECISIONS: decisions 9 and 10. The id-less one-shots row adds `marketRule` and `familyCodes`.
  - CHANGELOG: Added, `marketRule(_:)`, `familyCodes()`, `softDollarTiers()`, `PriceIncrement`, `FamilyCode`, and the new
    cases.

**Interfaces:**
- Produces:
  - `public struct PriceIncrement`, with `lowEdge: Decimal` and `increment: Decimal`.
  - `public struct FamilyCode`, with `accountID: String` and `familyCodeStr: String`.
  - Requests, none with a version:
    - `IBRequest.marketRule(marketRuleID: Int)` → `91, marketRuleId`;
    - `IBRequest.familyCodes` → `80`;
    - `IBRequest.softDollarTiers(requestID: Int)` → `79, reqId`.
  - Messages, none with a version, every count through `wireCount`:
    - `IBMessage.marketRule(marketRuleID: Int, [PriceIncrement])` from `93, marketRuleId, n, n × (lowEdge, increment)`;
    - `IBMessage.familyCodes([FamilyCode])` from `78, n, n × (accountID, familyCodeStr)`;
    - `IBMessage.softDollarTiers(requestID: Int, [SoftDollarTier])` from `77, reqId, n, n × (name, val, displayName)`.
  - `public func marketRule(_ marketRuleID: Int) async throws(IBClientError) -> [PriceIncrement]`, through
    `answer(.marketRule(…))` with a pick that takes only its own `marketRuleID`.
  - `public func familyCodes() async throws(IBClientError) -> [FamilyCode]`, through `answer(.familyCodes)`.
  - `public func softDollarTiers() async throws(IBClientError) -> [SoftDollarTier]`, through `answer(…, id:)`.
  - `routeToStream`: `.marketRule` and `.familyCodes` join the id-less list, and `.softDollarTiers(let id, _)` is routed
    by reqId.

- [ ] **Step 1: Write the failing tests**
  - `ReferenceCodecTests.ruleFamilyAndTiersCodec`:
    - `.marketRule(marketRuleID: 26)` → `body("91", "26")`; `IBRequest.familyCodes` → `body("80")`;
      `.softDollarTiers(requestID: 7)` → `body("79", "7")`;
    - `body("93", "26", "2", "0", "0.01", "1000", "0.05")` →
      `.marketRule(marketRuleID: 26, [PriceIncrement(lowEdge: 0, increment: d("0.01")), PriceIncrement(lowEdge: 1000, increment: d("0.05"))])`;
    - `body("78", "2", "DU1", "F1", "DU2", "")` →
      `.familyCodes([FamilyCode(accountID: "DU1", familyCodeStr: "F1"), FamilyCode(accountID: "DU2", familyCodeStr: "")])`;
    - `body("77", "7", "1", "Tier1", "T1V", "Tier One")` →
      `.softDollarTiers(requestID: 7, [SoftDollarTier(name: "Tier1", value: "T1V", displayName: "Tier One")])`;
    - `body("93", "26", "-1")`, `body("78", "-1")` and `body("77", "7", "-1")` → `.malformed`.
  - `IBClientReferenceTests`:
    - `marketRulesAnswerTheirOwnID`:
      1. Task A calls `marketRule(26)`, then task B calls `marketRule(4563)`. The sent frames are `["91", "26"]` and
         `["91", "4563"]`.
      2. Feed `["93", "4563", "1", "0", "0.0001"]`, then `["93", "26", "1", "0", "0.01"]`.
      3. A → `[PriceIncrement(lowEdge: 0, increment: d("0.01"))]`; B → `[PriceIncrement(lowEdge: 0, increment: d("0.0001"))]`.
         `requestStreamCount == 0`.
    - `familyCodesAnswer`: `onRequest` answers `["80"]` with the 78 frame above → the two codes.
    - `softDollarTiersAnswer`: answers `"79"` with `["77", f[1], "1", "Tier1", "T1V", "Tier One"]` → one tier.
    - `softDollarTiersFailOnTheirError`: the answer is `ibError(f[1], "321", "Error validating request")` → throws
      `.ib(code: 321, text: "Error validating request")`.
  - `PublicAPITests`: build one `PriceIncrement` and one `FamilyCode`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "ReferenceCodecTests|IBClientReferenceTests"`. Expected: a compile
  FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («Ask for market rules, family codes and soft-dollar tiers»).

### Task 7: Scanner (opus)

**Files:**
- Create: `Sources/IBKR/Client/IBClient+Research.swift`, `Sources/IBKR/Models/Research.swift`,
  `Tests/IBKRTests/ResearchCodecTests.swift`, `Tests/IBKRTests/IBClientResearchTests.swift`
- Modify: `IBRequest.swift`, `IBMessage.swift`, `IBDecoder.swift`, `IBClient.swift` (`routeToStream`)
- Test: `PublicAPITests.swift`
- Docs:
  - protocol-178: «reqScannerSubscription (out 22)», «cancelScannerSubscription (out 23)», «reqScannerParameters
    (out 24)», «scannerParameters (in 19)» and «scannerData (in 20)».
  - DECISIONS: decision 11, and the newest-only buffering row names `scannerSubscription`.
  - CHANGELOG: Added, `scannerSubscription(_:options:filterOptions:)`, `scannerData(_:options:filterOptions:)`,
    `scannerParameters()`, `ScannerSubscription`, `ScanData`, and the new cases.

**Interfaces:**
- Consumes: `IBRequest.tagValues` (Task 5).
- Produces:
  - `public struct ScannerSubscription`. Its fields, in wire order:
    - `numberOfRows: Int?`, where `nil` goes out as `"-1"` (IB's default);
    - `instrument`, `locationCode` and `scanCode` (`String`);
    - `abovePrice`, `belowPrice` (`Decimal?`) and `aboveVolume: Int?`;
    - `marketCapAbove`, `marketCapBelow` (`Decimal?`);
    - `moodyRatingAbove`, `moodyRatingBelow`, `spRatingAbove`, `spRatingBelow`, `maturityDateAbove` and
      `maturityDateBelow` (`String`);
    - `couponRateAbove`, `couponRateBelow` (`Decimal?`), `excludeConvertible: Bool` and `averageOptionVolumeAbove: Int?`;
    - `scannerSettingPairs` and `stockTypeFilter` (`String`).

    Its init is `init(instrument: String = "", locationCode: String = "", scanCode: String = "", numberOfRows: Int? = nil, …every other field defaulted to nil, "" or false)`.
  - `public struct ScanData`, with `rank: Int`, `contract: Contract`, `marketName`, `distance`, `benchmark`,
    `projection` and `legsStr` (`String`).
  - `IBRequest.scannerSubscription(requestID: Int, subscription: ScannerSubscription, options: [TagValue], filterOptions: [TagValue])`
    has 25 fields: `22, reqId`, the 21 subscription fields in the order above, `tagValues(filterOptions)` and
    `tagValues(options)`. There is no version. `nil` numbers are `""`, and the Bool is `0`/`1`.
  - `IBRequest.cancelScannerSubscription(requestID: Int)` → `23, 1, reqId`. `IBRequest.scannerParameters` → `24, 1`.
  - `IBMessage.scannerParameters(String)` from `19, version, xml`.
  - `IBMessage.scannerData(requestID: Int, [ScanData])` from `20, version, reqId, n`, then n × 16 fields:
    `rank, conId, symbol, secType, lastTradeDateOrContractMonth, strike, right, exchange, currency, localSymbol, marketName, tradingClass, distance, benchmark, projection, legsStr`.
    The strike is optionalDecimal, and the count goes through `wireCount`.
  - `public func scannerSubscription(_ subscription: ScannerSubscription, options: [TagValue] = [], filterOptions: [TagValue] = []) throws(IBClientError) -> AsyncThrowingStream<[ScanData], any Error>`:
    - it uses `openStream` with cancel 23 and `buffering: .bufferingNewest(1)`;
    - it yields each whole scan and never ends itself.
  - `public func scannerData(_ subscription: ScannerSubscription, options: [TagValue] = [], filterOptions: [TagValue] = []) async throws(IBClientError) -> [ScanData]`:
    - its route yields the first scan, finishes and returns `false`, so the termination hop sends 23, as
      `ib_async`'s `reqScannerDataAsync` does;
    - IB's error sends no 23.
  - `public func scannerParameters() async throws(IBClientError) -> String`, through `answer(.scannerParameters)`.
  - `routeToStream`: `.scannerData(let id, _)` is routed by reqId, and `.scannerParameters` joins the id-less list.

- [ ] **Step 1: Write the failing tests**, with `top = ScannerSubscription(instrument: "STK", locationCode: "STK.US.MAJOR", scanCode: "TOP_PERC_GAIN")`
  and the two-row frame
  `scan(id) = ["20", "3", id, "2", "0", "265598", "AAPL", "STK", "", "0", "", "SMART", "USD", "AAPL", "NMS", "NMS", "", "", "", "", "1", "272093", "MSFT", "STK", "", "0", "", "SMART", "USD", "MSFT", "NMS", "NMS", "", "", "", ""]`.
  - `ResearchCodecTests`:
    - `scannerSubscriptionEncodes`:
      - `.scannerSubscription(requestID: 7, subscription: ScannerSubscription(), options: [], filterOptions: [])` →
        `body(["22", "7", "-1"] + Array(repeating: "", count: 16) + ["0"] + Array(repeating: "", count: 5))`;
      - with `ScannerSubscription(instrument: "STK", locationCode: "STK.US.MAJOR", scanCode: "TOP_PERC_GAIN", numberOfRows: 10, abovePrice: d("5"), aboveVolume: 100000)`
        and `filterOptions: [TagValue(tag: "marketCapAbove1e6", value: "1000")]` →
        `body(["22", "7", "10", "STK", "STK.US.MAJOR", "TOP_PERC_GAIN", "5", "", "100000"] + Array(repeating: "", count: 10) + ["0", "", "", "", "marketCapAbove1e6=1000;", ""])`.
    - `scannerSmallMessagesCodec`:
      - `.cancelScannerSubscription(requestID: 7)` → `body("23", "1", "7")`;
      - `IBRequest.scannerParameters` → `body("24", "1")`;
      - `body("19", "1", "<ScanParameterResponse/>")` → `.scannerParameters("<ScanParameterResponse/>")`.
    - `scannerDataDecodes`: `scan("7")` → `.scannerData(requestID: 7, [r0, r1])`, where:
      - `r0` is `ScanData(rank: 0, contract: c, marketName: "NMS", distance: "", benchmark: "", projection: "", legsStr: "")`;
      - `c` is `Contract(symbol: "AAPL")` with `conID 265598`, `strike 0`, `localSymbol "AAPL"` and
        `tradingClass "NMS"`;
      - `r1` is the same for MSFT, with `rank 1` and `conID 272093`.

      `body("20", "3", "7", "-1")` → `.malformed`.
  - `IBClientResearchTests`:
    - `scannerSubscriptionStreamsWholeScansAndCancels` (Review Focus 3):
      1. `scannerSubscription(top)` → the sent frame's `[0...5] == ["22", id, "-1", "STK", "STK.US.MAJOR", "TOP_PERC_GAIN"]`.
      2. Feed `scan(id)`, then the one-row frame `["20", "3", id, "1"] + scan(id)[4...19]`.
      3. A reader task reads until a scan has `count == 1`, and keeps the stream. Do not use `take(2)`: the newest-only
         buffer may drop the first scan.
      4. `reader.cancel()` → the next sent frame is `["23", "1", id]`, and `requestStreamCount == 0`.
    - `scannerDataReturnsTheFirstScanThenCancels` (Review Focus 3): `onRequest` answers `"22"` with `scan(f[1])`.
      `scannerData(top)` returns two rows. Within 2 s the next sent frame is `["23", "1", f[1]]`, and
      `requestStreamCount == 0`.
    - `scannerDataFailsOnItsErrorWithoutCancel` (Review Focus 3): the answer is
      `ibError(f[1], "162", "Historical Market Data Service error message:API scanner subscription cancelled: 1")` →
      throws `.ib(code: 162, …)`. After 50 ms no `"23"` has been sent.
    - `scannerParametersAnswer`: answers `["24", "1"]` with `["19", "1", "<xml/>"]` → `"<xml/>"`.
  - `PublicAPITests`: `ScannerSubscription().numberOfRows == nil`, and build one `ScanData`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "ResearchCodecTests|IBClientResearchTests"`. Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS. Run the three Review Focus 3 tests 20 times
  (`for i in $(seq 20); do timeout 900 swift test --filter "scannerSubscriptionStreams|scannerData" > /dev/null || echo FAIL $i; done`)
  and expect no `FAIL`.
- [ ] **Step 5: Docs and commit** («Scan the market as a stream or once, and fetch the scanner parameters»).

### Task 8: News providers, articles and historical news (sonnet)

**Files:**
- Modify: `Research.swift` (`NewsProvider`, `NewsArticle`, `HistoricalNews`), `IBRequest.swift`, `IBMessage.swift`,
  `IBDecoder.swift`, `IBClient+Research.swift`, `IBClient.swift` (`routeToStream`)
- Test: `ResearchCodecTests.swift`, `IBClientResearchTests.swift`, `PublicAPITests.swift`
- Docs:
  - protocol-178: «reqNewsProviders (out 85)», «newsProviders (in 85)», «reqNewsArticle (out 84)», «newsArticle
    (in 83)», «reqHistoricalNews (out 86)», «historicalNews (in 86)» and «historicalNewsEnd (in 87)».
  - DECISIONS: decision 13. The id-less one-shots row adds `newsProviders`.
  - CHANGELOG: Added, `newsProviders()`, `newsArticle(providerCode:articleID:options:)`,
    `historicalNews(conID:providerCodes:start:end:totalResults:options:)`, the three types, and the new cases.

**Interfaces:**
- Produces:
  - `public struct NewsProvider`, with `code` and `name`.
  - `public struct NewsArticle`, with `articleType: Int` and `articleText: String`.
  - `public struct HistoricalNews`, with `time`, `providerCode`, `articleID` and `headline`, all `String`. `time` is
    IB's raw text.
  - Requests, none with a version:
    - `IBRequest.newsProviders` → `85`;
    - `IBRequest.newsArticle(requestID: Int, providerCode: String, articleID: String, options: [TagValue])` →
      `84, reqId, providerCode, articleId, tagValues(options)`;
    - `IBRequest.historicalNews(requestID: Int, conID: Int, providerCodes: [String], start: Date?, end: Date?, totalResults: Int, options: [TagValue])`
      → `86, reqId, conId, providerCodes joined by "+", start, end, totalResults, tagValues(options)`, with the dates
      through `IBRequest.endFormat` and `nil` as `""`.
  - Messages, none with a version:
    - `IBMessage.newsProviders([NewsProvider])` from `85, n, n × (code, name)`, the count through `wireCount`;
    - `IBMessage.newsArticle(requestID: Int, NewsArticle)` from `83, reqId, articleType, articleText`;
    - `IBMessage.historicalNews(requestID: Int, HistoricalNews)` from
      `86, reqId, time, providerCode, articleId, headline`;
    - `IBMessage.historicalNewsEnd(requestID: Int, hasMore: Bool)` from `87, reqId, hasMore`.
  - The calls:
    - `public func newsProviders() async throws(IBClientError) -> [NewsProvider]`, through `answer(.newsProviders)`;
    - `public func newsArticle(providerCode: String, articleID: String, options: [TagValue] = []) async throws(IBClientError) -> NewsArticle`,
      through `answer(…, id:)`;
    - `public func historicalNews(conID: Int, providerCodes: [String], start: Date? = nil, end: Date? = nil, totalResults: Int, options: [TagValue] = []) async throws(IBClientError) -> [HistoricalNews]`.
      It collects every 86 until 87 and sends no cancel (IB has none). `hasMore` is dropped, as `ib_async` drops it.
  - `routeToStream`: `.newsProviders` joins the id-less list; `.newsArticle`, `.historicalNews` and
    `.historicalNewsEnd` are routed by reqId.

- [ ] **Step 1: Write the failing tests**
  - `ResearchCodecTests.newsLookupsCodec`:
    - `IBRequest.newsProviders` → `body("85")`;
    - `.newsArticle(requestID: 7, providerCode: "BRFG", articleID: "BRFG$12345", options: [])` →
      `body("84", "7", "BRFG", "BRFG$12345", "")`;
    - `.historicalNews(requestID: 7, conID: 265598, providerCodes: ["BRFG", "DJNL"], start: Date(timeIntervalSince1970: 1794321000), end: nil, totalResults: 10, options: [])`
      → `body("86", "7", "265598", "BRFG+DJNL", "20261110-14:30:00", "", "10", "")`;
    - `body("85", "2", "BRFG", "Briefing.com General Market Columns", "DJNL", "Dow Jones Newsletters")` →
      `.newsProviders([NewsProvider(code: "BRFG", name: "Briefing.com General Market Columns"), NewsProvider(code: "DJNL", name: "Dow Jones Newsletters")])`;
    - `body("83", "7", "0", "Apple beats estimates")` →
      `.newsArticle(requestID: 7, NewsArticle(articleType: 0, articleText: "Apple beats estimates"))`;
    - `body("86", "7", "2026-11-10 14:30:00.0", "BRFG", "BRFG$12345", "Apple headline")` →
      `.historicalNews(requestID: 7, HistoricalNews(time: "2026-11-10 14:30:00.0", providerCode: "BRFG", articleID: "BRFG$12345", headline: "Apple headline"))`;
    - `body("87", "7", "1")` → `.historicalNewsEnd(requestID: 7, hasMore: true)`;
    - `body("85", "-1")` → `.malformed`.
  - `IBClientResearchTests`:
    - `newsProvidersAnswer`: `onRequest` answers `["85"]` with the 85 frame → two providers.
    - `newsArticleAnswers`: answers `"84"` with `["83", f[1], "0", "Apple beats estimates"]` → that article. The sent
      frame is `["84", f[1], "BRFG", "BRFG$12345", ""]`.
    - `newsArticleFailsOnItsError`: the answer is `ibError(f[1], "10172", "Failed to request news article: No data available")`
      → throws `.ib(code: 10172, …)`.
    - `historicalNewsCollectsUntilEnd`:
      1. `onRequest` answers `"86"` with two 86 frames (articles `"A1"` and `"A2"`), then `["87", f[1], "0"]`.
      2. The call returns the two, in order.
      3. After 50 ms nothing more has been sent, and `requestStreamCount == 0`.
    - `historicalNewsFailsOnItsError`: the answer is
      `ibError(f[1], "10187", "Failed to request historical news:Unknown provider codes")` → throws
      `.ib(code: 10187, …)`.
  - `PublicAPITests`: build one of each new type.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "ResearchCodecTests|IBClientResearchTests"`. Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («Ask for news providers, articles and historical headlines»).

### Task 9: News bulletins and tagged generic ticks (opus)

**Files:**
- Modify: `Research.swift` (`NewsBulletin`), `MarketData.swift` (`GenericTick`), `IBClientError.swift`, `IBRequest.swift`,
  `IBMessage.swift`, `IBDecoder.swift`, `IBClient.swift` (`marketData`, `tickers`, `routeToStream`, a stored
  `newsBulletinKey: Int?`), `IBClient+Research.swift`
- Test: `ResearchCodecTests.swift`, `IBClientResearchTests.swift`, `TickCodecTests.swift`, `PublicAPITests.swift`
- Docs:
  - protocol-178: «reqNewsBulletins (out 12)», «cancelNewsBulletins (out 13)» and «updateNewsBulletin (in 14)». The
    reqMktData row 16 now says the list holds IB's numbers or tagged entries (`mdoff`, `292:BRFG`), comma-joined.
  - DECISIONS: decisions 14 and 15. The `genericTicks` `[Int]` row is rewritten as decision 15.
  - CHANGELOG:
    - Added: `newsBulletins(allMessages:)`, `NewsBulletin`, `GenericTick`, `IBClientError.alreadySubscribed`, and the
      new cases. A new case in a public enum: an exhaustive `switch` over `IBClientError` needs a new branch.
    - Changed: `genericTicks` is `[GenericTick]` in `marketData`, `tickers` and `IBRequest.marketData`. Integer and
      string literals both still compile; a `[Int]` variable needs `.map(GenericTick.init(integerLiteral:))`.

**Interfaces:**
- Produces:
  - ```swift
    /// One entry of reqMktData's generic tick list: IB's number (`233`) or a tagged entry (`"mdoff"`, `"292:BRFG"`).
    public struct GenericTick: RawRepresentable, Hashable, Sendable, ExpressibleByIntegerLiteral, ExpressibleByStringLiteral {
        public var rawValue: String
        public init(rawValue: String)
        public init(integerLiteral value: Int)    // rawValue = String(value)
        public init(stringLiteral value: String)
    }
    ```
    The marketData wire's field 16 becomes `genericTicks.map(\.rawValue).joined(separator: ",")`.
  - `public struct NewsBulletin`, with `msgID: Int`, `msgType: Int`, `message: String` and `origExchange: String`.
  - `IBRequest.newsBulletins(allMessages: Bool)` → `12, 1, allMessages`. `IBRequest.cancelNewsBulletins` → `13, 1`.
  - `IBMessage.newsBulletin(NewsBulletin)` from `14, version, msgId, msgType, message, origExchange`.
  - `IBClientError.alreadySubscribed`, documented as «a subscription IB allows once per connection is already open».
  - `public func newsBulletins(allMessages: Bool = false) throws(IBClientError) -> AsyncThrowingStream<NewsBulletin, any Error>`:
    - it throws `.alreadySubscribed` when `newsBulletinKey` names a key still in `requestStreams`, and sends nothing;
    - otherwise it opens the stream under `nextLocalID()` with cancel `.cancelNewsBulletins` and stores the key;
    - its route yields every bulletin and returns `false`. It never ends itself; stopping it sends 13.
  - `routeToStream`: `.newsBulletin` joins the id-less list. A route that returns `false` lets the loop go on, as
    today.

- [ ] **Step 1: Write the failing tests**
  - `ResearchCodecTests.newsBulletinsCodec`:
    - `.newsBulletins(allMessages: true)` → `body("12", "1", "1")`, and `IBRequest.cancelNewsBulletins` → `body("13", "1")`;
    - `body("14", "1", "3", "1", "Exchange halted", "NYSE")` →
      `.newsBulletin(NewsBulletin(msgID: 3, msgType: 1, message: "Exchange halted", origExchange: "NYSE"))`.
  - `TickCodecTests.marketDataSendsTaggedGenericTicks`:
    `.marketData(requestID: 7, contract: Contract(symbol: "AAPL"), genericTicks: [100, "292:BRFG+DJNL"])` →
    `body(["1", "11", "7"] + aapl + ["0", "100,292:BRFG+DJNL", "0", "0", ""])`. The existing
    `marketDataSendsItsParameters` stays unchanged.
  - `IBClientResearchTests`:
    - `newsBulletinsStreamAndCancel`:
      1. `newsBulletins()` → the sent frame is `["12", "1", "0"]`.
      2. Feed the 14 frame. `take(1)` → that bulletin.
      3. `reader.cancel()` → the next sent frame is `["13", "1"]`, and `requestStreamCount == 0`.
    - `aSecondNewsBulletinsStreamIsRefused` (Review Focus 5):
      1. With one stream open, `newsBulletins()` throws `.alreadySubscribed`, and after 50 ms only one `"12"` has
         been sent.
      2. Stop the first stream and wait for `["13", "1"]`.
      3. `newsBulletins(allMessages: true)` now succeeds and sends `["12", "1", "1"]`.
    - `newsBulletinsEndWithTheConnection`: `gateway.close()` → the stream throws `.connectionClosed`.
    - `newsTicksArriveThroughMarketData`:
      1. `marketData(Contract(symbol: "BRFG:BRFG_ALL", secType: "NEWS", exchange: "BRFG"), genericTicks: ["mdoff", "292"])`
         → the sent frame's `[16] == "mdoff,292"`.
      2. Feed `["84", id, "1794321000000", "BRFG", "BRFG$12345", "Apple headline", "A:800015:L:en"]`.
      3. `take(1)` → `[.news(NewsTick(timeStamp: 1794321000000, providerCode: "BRFG", articleID: "BRFG$12345", headline: "Apple headline", extraData: "A:800015:L:en"))]`.
  - `PublicAPITests`: `GenericTick(integerLiteral: 233).rawValue == "233"`, and build one `NewsBulletin`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "ResearchCodecTests|IBClientResearchTests|TickCodecTests"`.
  Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above. Every existing `genericTicks:` call site in `Sources` and `Tests`
  must still compile with literals. `grep -rn "genericTicks" Sources Tests` shows each one.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («Stream news bulletins one subscription at a time and send tagged generic ticks»).

### Task 10: Fundamentals and Wall Street Horizon (sonnet)

**Files:**
- Modify: `Research.swift` (`WshEventData`), `IBRequest.swift`, `IBMessage.swift`, `IBDecoder.swift`,
  `IBClient+Research.swift`, `IBClient.swift` (`routeToStream`)
- Test: `ResearchCodecTests.swift`, `IBClientResearchTests.swift`, `PublicAPITests.swift`
- Docs:
  - protocol-178:
    - «reqFundamentalData (out 52)», «cancelFundamentalData (out 53)» and «fundamentalData (in 51)»;
    - «reqWshMetaData (out 100)», «cancelWshMetaData (out 101)», «reqWshEventData (out 102)», «cancelWshEventData
      (out 103)», «wshMetaData (in 104)» and «wshEventData (in 105)».
  - DECISIONS: decisions 16 and 17.
  - CHANGELOG: Added, `fundamentalData(_:reportType:options:)`, `wshMetaData()`, `wshEventData(_:)`, `WshEventData`, and
    the new cases.

**Interfaces:**
- Produces:
  - `public struct WshEventData`, with `conID: Int?`, `filter: String`, `fillWatchlist`, `fillPortfolio` and
    `fillCompetitors` (`Bool`), `startDate`, `endDate` (`String`) and `totalLimit: Int?`. Every init parameter
    defaults (`nil`, `""` or `false`).
  - `IBRequest.fundamentalData(requestID: Int, contract: Contract, reportType: String, options: [TagValue])` has 13
    fields:
    `52, 2, reqId, conId, symbol, secType, exchange, primaryExchange, currency, localSymbol, reportType, options.count, tagValues(options)`.
  - `IBRequest.cancelFundamentalData(requestID: Int)` → `53, 1, reqId`.
  - `IBRequest.wshMetaData(requestID: Int)` → `100, reqId`, and `.cancelWshMetaData(requestID: Int)` → `101, reqId`.
  - `IBRequest.wshEventData(requestID: Int, data: WshEventData)` →
    `102, reqId, conId, filter, fillWatchlist, fillPortfolio, fillCompetitors, startDate, endDate, totalLimit`. A `nil`
    `conID` or `totalLimit` goes out as `"2147483647"`, as `ib_async` sends it with `makeEmpty=False`.
  - `IBRequest.cancelWshEventData(requestID: Int)` → `103, reqId`.
  - `IBMessage.fundamentalData(requestID: Int, String)` from `51, version, reqId, data`.
    `IBMessage.wshMetaData(requestID: Int, String)` from `104, reqId, dataJson`, and `.wshEventData(…)` from
    `105, reqId, dataJson`.
  - `public func fundamentalData(_ contract: Contract, reportType: String, options: [TagValue] = []) async throws(IBClientError) -> String`:
    - it uses `openStream` with cancel 53;
    - its route returns `true` on the answer, so 53 goes out only for a caller cancelled first.
  - `public func wshMetaData() async throws(IBClientError) -> String` and
    `public func wshEventData(_ data: WshEventData) async throws(IBClientError) -> String`:
    - each uses `openStream` with its cancel (101 or 103);
    - each route yields, finishes and returns `false`, so the cancel follows the answer.
  - `routeToStream` routes the three new cases by reqId.

- [ ] **Step 1: Write the failing tests**
  - `ResearchCodecTests.fundamentalsAndWshCodec`:
    - `.fundamentalData(requestID: 7, contract: Contract(symbol: "AAPL"), reportType: "ReportSnapshot", options: [])` →
      `body("52", "2", "7", "0", "AAPL", "STK", "SMART", "", "USD", "", "ReportSnapshot", "0", "")`;
    - `.cancelFundamentalData(requestID: 7)` → `body("53", "1", "7")`;
    - `.wshMetaData(requestID: 7)` → `body("100", "7")`, and `.cancelWshMetaData(requestID: 7)` → `body("101", "7")`;
    - `.wshEventData(requestID: 7, data: WshEventData(conID: 8314, startDate: "20261101", endDate: "20261201", totalLimit: 10))`
      → `body("102", "7", "8314", "", "0", "0", "0", "20261101", "20261201", "10")`;
    - `.wshEventData(requestID: 7, data: WshEventData(filter: "{\"watchlist\":[\"8314\"]}", fillWatchlist: true))` →
      `body("102", "7", "2147483647", "{\"watchlist\":[\"8314\"]}", "1", "0", "0", "", "", "2147483647")`;
    - `.cancelWshEventData(requestID: 7)` → `body("103", "7")`;
    - `body("51", "1", "7", "<ReportSnapshot/>")` → `.fundamentalData(requestID: 7, "<ReportSnapshot/>")`;
    - `body("104", "7", "{\"m\":1}")` → `.wshMetaData(requestID: 7, "{\"m\":1}")`;
    - `body("105", "7", "{}")` → `.wshEventData(requestID: 7, "{}")`.
  - `IBClientResearchTests`:
    - `fundamentalDataAnswers`: `onRequest` answers `"52"` with `["51", "1", f[2], "<ReportSnapshot/>"]` →
      `"<ReportSnapshot/>"`. After 50 ms no `"53"` has been sent, and `requestStreamCount == 0`.
    - `fundamentalDataFailsOnItsError`: the answer is
      `ibError(f[2], "430", "We are sorry, but fundamentals data for the security specified is not available.")` →
      throws `.ib(code: 430, …)`.
    - `fundamentalDataCancelledSendsItsCancel`: no answer. The calling task is cancelled → it throws `.cancelled`,
      and `["53", "1", id]` is sent.
    - `wshMetaDataAnswersThenCancels`: answers `"100"` with `["104", f[1], "{\"m\":1}"]` → that string. Within 2 s
      the next sent frame is `["101", f[1]]`.
    - `wshEventDataAnswersThenCancels`: the same, with `"102"`, `105` and `["103", f[1]]`.
    - `wshEventDataFailsOnItsError`: the answer is `ibError(f[1], "321", "Error validating request")` → throws. After
      50 ms no `"103"` has been sent.
  - `PublicAPITests`: `WshEventData().conID == nil`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "ResearchCodecTests|IBClientResearchTests"`. Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («Ask for fundamentals reports and Wall Street Horizon data as IB's text»).

### Task 11: FA, display groups and verify (opus)

**Files:**
- Modify: `Research.swift` (`FADataType`), `IBRequest.swift`, `IBMessage.swift`, `IBDecoder.swift`,
  `IBClient+Research.swift`, `IBClient.swift` (`routeToStream`)
- Test: `ResearchCodecTests.swift`, `IBClientResearchTests.swift`, `PublicAPITests.swift`
- Docs:
  - protocol-178:
    - «requestFA (out 18)», «replaceFA (out 19)», «receiveFA (in 16)» and «replaceFAEnd (in 103)»;
    - «queryDisplayGroups (out 67)», «subscribeToGroupEvents (out 68)», «updateDisplayGroup (out 69)»,
      «unsubscribeFromGroupEvents (out 70)», «displayGroupList (in 67)» and «displayGroupUpdated (in 68)»;
    - «verifyRequest (out 65)», «verifyMessage (out 66)», «verifyAndAuthRequest (out 72)», «verifyAndAuthMessage
      (out 73)», «verifyMessageAPI (in 65)», «verifyCompleted (in 66)», «verifyAndAuthMessageAPI (in 69)» and
      «verifyAndAuthCompleted (in 70)».
  - DECISIONS: decisions 18, 19 and 20. The id-less one-shots row adds `faData`.
  - KNOWN-GAPS: «`faData` on a login that is not an FA account waits until cancelled: IB's refusal carries no reqId»
    and «the verify requests go out after startApi, which `connect` sends itself; IB documents them before it».
  - CHANGELOG: Added, `faData(_:)`, `replaceFA(_:xml:)`, `FADataType`, `displayGroups()`, `displayGroupUpdates(_:)`,
    `updateDisplayGroup(_:contractInfo:)`, `verifyRequest(apiName:apiVersion:)`, `verifyMessage(_:)`,
    `verifyAndAuthRequest(apiName:apiVersion:opaqueISVKey:)`, `verifyAndAuthMessage(_:xyzResponse:)`, and the new cases.

**Interfaces:**
- Produces:
  - `public enum FADataType: Int, Sendable { case groups = 1, profiles = 2, aliases = 3 }`.
  - Requests (every outgoing id here has version 1):
    - `IBRequest.requestFA(FADataType)` → `18, 1, type`;
    - `IBRequest.replaceFA(requestID: Int, type: FADataType, xml: String)` → `19, 1, type, xml, reqId`;
    - `IBRequest.queryDisplayGroups(requestID: Int)` → `67, 1, reqId`;
    - `IBRequest.subscribeToGroupEvents(requestID: Int, groupID: Int)` → `68, 1, reqId, groupId`;
    - `IBRequest.updateDisplayGroup(requestID: Int, contractInfo: String)` → `69, 1, reqId, contractInfo`;
    - `IBRequest.unsubscribeFromGroupEvents(requestID: Int)` → `70, 1, reqId`;
    - `IBRequest.verifyRequest(apiName: String, apiVersion: String)` → `65, 1, apiName, apiVersion`;
    - `IBRequest.verifyMessage(apiData: String)` → `66, 1, apiData`;
    - `IBRequest.verifyAndAuthRequest(apiName: String, apiVersion: String, opaqueISVKey: String)` →
      `72, 1, apiName, apiVersion, opaqueIsvKey`;
    - `IBRequest.verifyAndAuthMessage(apiData: String, xyzResponse: String)` → `73, 1, apiData, xyzResponse`.
  - Messages:
    - `IBMessage.receiveFA(type: FADataType, xml: String)` from `16, version, faDataType, xml`; an unknown type is
      `.malformed`;
    - `IBMessage.replaceFAEnd(requestID: Int, String)` from `103, reqId, text`, with no version;
    - `IBMessage.displayGroupList(requestID: Int, String)` from `67, version, reqId, groups`, and
      `.displayGroupUpdated(requestID: Int, String)` from `68, version, reqId, contractInfo`;
    - `IBMessage.verifyMessageAPI(apiData: String)` from `65, version, apiData`;
    - `IBMessage.verifyCompleted(isSuccessful: Bool, errorText: String)` from `66, version, isSuccessful, errorText`;
    - `IBMessage.verifyAndAuthMessageAPI(apiData: String, xyzChallenge: String)` from `69, version, apiData, xyzChallenge`;
    - `IBMessage.verifyAndAuthCompleted(isSuccessful: Bool, errorText: String)` from `70, version, isSuccessful, errorText`.
  - The FA calls:
    - `public func faData(_ type: FADataType) async throws(IBClientError) -> String`, through `answer(.requestFA(type))`
      with a pick that takes only a `.receiveFA` of its own `type`;
    - `public func replaceFA(_ type: FADataType, xml: String) async throws(IBClientError) -> String` returns 103's text,
      through `answer(…, id:)`.
  - The display-group calls:
    - `public func displayGroups() async throws(IBClientError) -> String` returns IB's raw list (`"1|2|3"`), through
      `answer(…, id:)`;
    - `public func displayGroupUpdates(_ groupID: Int) throws(IBClientError) -> (requestID: Int, updates: AsyncThrowingStream<String, any Error>)`
      uses `openStream` with cancel `.unsubscribeFromGroupEvents(requestID: id)`, yields each `contractInfo` and never
      ends itself;
    - `public func updateDisplayGroup(_ requestID: Int, contractInfo: String) throws(IBClientError)` sends 69.
  - The verify calls, each sending its request (65, 66, 72 or 73) after `requireConnected()` and nothing else:
    `public func verifyRequest(apiName: String, apiVersion: String) throws(IBClientError)`,
    `verifyMessage(_ apiData: String)`, `verifyAndAuthRequest(apiName:apiVersion:opaqueISVKey:)` and
    `verifyAndAuthMessage(_ apiData: String, xyzResponse: String)`. Their answers reach `messages()` only.
  - `routeToStream`: `.receiveFA` joins the id-less list; `.replaceFAEnd`, `.displayGroupList` and
    `.displayGroupUpdated` are routed by reqId.

- [ ] **Step 1: Write the failing tests**
  - `ResearchCodecTests.faCodec`:
    - `.requestFA(.groups)` → `body("18", "1", "1")`;
    - `.replaceFA(requestID: 7, type: .aliases, xml: "<ListOfAccountAliases/>")` →
      `body("19", "1", "3", "<ListOfAccountAliases/>", "7")`;
    - `body("16", "1", "1", "<ListOfGroups/>")` → `.receiveFA(type: .groups, xml: "<ListOfGroups/>")`;
    - `body("16", "1", "9", "x")` → `.malformed`;
    - `body("103", "7", "FA aliases replaced")` → `.replaceFAEnd(requestID: 7, "FA aliases replaced")`.
  - `ResearchCodecTests.displayGroupsCodec`:
    - `.queryDisplayGroups(requestID: 7)` → `body("67", "1", "7")`;
    - `.subscribeToGroupEvents(requestID: 7, groupID: 1)` → `body("68", "1", "7", "1")`;
    - `.updateDisplayGroup(requestID: 7, contractInfo: "265598@SMART")` → `body("69", "1", "7", "265598@SMART")`;
    - `.unsubscribeFromGroupEvents(requestID: 7)` → `body("70", "1", "7")`;
    - `body("67", "1", "7", "1|2|3")` → `.displayGroupList(requestID: 7, "1|2|3")`;
    - `body("68", "1", "7", "265598@SMART")` → `.displayGroupUpdated(requestID: 7, "265598@SMART")`.
  - `ResearchCodecTests.verifyCodec`:
    - `.verifyRequest(apiName: "app", apiVersion: "1.0")` → `body("65", "1", "app", "1.0")`;
    - `.verifyMessage(apiData: "d")` → `body("66", "1", "d")`;
    - `.verifyAndAuthRequest(apiName: "app", apiVersion: "1.0", opaqueISVKey: "k")` → `body("72", "1", "app", "1.0", "k")`;
    - `.verifyAndAuthMessage(apiData: "d", xyzResponse: "r")` → `body("73", "1", "d", "r")`;
    - `body("65", "1", "d")` → `.verifyMessageAPI(apiData: "d")`;
    - `body("66", "1", "1", "")` → `.verifyCompleted(isSuccessful: true, errorText: "")`;
    - `body("69", "1", "d", "c")` → `.verifyAndAuthMessageAPI(apiData: "d", xyzChallenge: "c")`;
    - `body("70", "1", "0", "bad key")` → `.verifyAndAuthCompleted(isSuccessful: false, errorText: "bad key")`.
  - `IBClientResearchTests`:
    - `faDataAnswersByType`:
      1. Task A calls `faData(.groups)`, then task B calls `faData(.aliases)`.
      2. Feed `["16", "1", "3", "<aliases/>"]`, then `["16", "1", "1", "<groups/>"]`.
      3. A → `"<groups/>"` and B → `"<aliases/>"`. `requestStreamCount == 0`.
    - `replaceFAAnswers`: `onRequest` answers `"19"` with `["103", f[4], "done"]` → `"done"`.
    - `replaceFAFailsOnItsError`: the answer is `ibError(f[4], "321", "Error validating request")` → throws.
    - `displayGroupsAnswer`: answers `"67"` with `["67", "1", f[2], "1|2|3"]` → `"1|2|3"`.
    - `displayGroupsFailOnTheirError`: the answer is `ibError(f[2], "321", "Error validating request")` → throws.
    - `displayGroupUpdatesStreamUpdateAndCancel` (Review Focus 4):
      1. `let (rid, updates) = try await client.displayGroupUpdates(1)` → the sent frame is `["68", "1", "\(rid)", "1"]`.
      2. Feed `["68", "1", "\(rid)", "265598@SMART"]`. `take(1)` → `["265598@SMART"]`.
      3. `updateDisplayGroup(rid, contractInfo: "8314@SMART")` → the next sent frame is
         `["69", "1", "\(rid)", "8314@SMART"]`.
      4. `reader.cancel()` → the next sent frame is `["70", "1", "\(rid)"]`, and `requestStreamCount == 0`.
    - `displayGroupUpdatesEndOnTheirError`: feed `ibError("\(rid)", "321", "Error validating request")` → the stream
      throws `.ib(code: 321, …)`. After 50 ms no `"70"` has been sent.
    - `verifyCallsSendAndAnswersReachMessages`:
      1. Subscribe to `messages()`.
      2. `verifyRequest(apiName: "app", apiVersion: "1.0")` → the sent frame is `["65", "1", "app", "1.0"]`.
      3. Feed `["65", "1", "d"]`. `messages()` yields `.verifyMessageAPI(apiData: "d")`.
      4. `verifyAndAuthMessage("d", xyzResponse: "r")` → `["73", "1", "d", "r"]`.
  - `PublicAPITests`: `FADataType(rawValue: 3) == .aliases`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "ResearchCodecTests|IBClientResearchTests"`. Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («Read and replace FA data, follow display groups, and send the verify handshake»).

### Task 12: Documents, per-commit check, CI (sonnet)

**Files:**
- Modify: `README.md`, `CHANGELOG.md`, `docs/DECISIONS.md`, `docs/KNOWN-GAPS.md`

- [ ] **Step 1: README.**
  - «Contract lookup» gains the factories, `qualifyContracts` (with the three outcomes), and bonds through
    `contractDetails`.
  - New subsections, each with a short snippet in the style of «Market data»:
    - «Options and reference data»: `optionChains`, `calculateImpliedVolatility`, `calculateOptionPrice`,
      `marketRule`, `familyCodes` and `softDollarTiers`;
    - «Scanner»: the stream, the one-shot and the parameters XML;
    - «News»: providers, articles, historical news, bulletins, and news ticks through
      `marketData(…, genericTicks: ["mdoff", "292"])`;
    - «Research and advisors»: fundamentals, WSH, FA, display groups, and verify (answers in `messages()`).
  - The marketData snippet comment changes from `genericTicks: [Int]` to `[GenericTick]`, numbers or tagged entries.
  - A new section «ib_async names» holds a table «ib_async | swift-ibkr» with one row per call in decision 1, and
    the factories as one row (`Stock`, `Option`, … → `Contract.stock`, `.option`, …). Its intro says stage 13 extends
    it to every call.
  - The «Status» Contract lookup row reads «contract details with bonds, matching symbols, factories,
    qualifyContracts», with state «✅ details and symbols live-checked; the rest on the fake gateway, a live run is
    due in stage 13».
  - New rows:
    - «Options and reference»: «option chains, option calculations, market rules, family codes, soft-dollar tiers»;
    - «Scanner and research»: «scanner stream and one-shot, scanner parameters, news, bulletins, fundamentals, WSH,
      FA, display groups, verify».

    Both read «✅ on hand-built frames and the fake gateway; a live run is due in stage 13».
- [ ] **Step 2: KNOWN-GAPS.**
  - The heading and intro read «after stage 11».
  - A new bullet: every stage 10–11 call is checked only against hand-built frames. Fundamentals, WSH and news need
    subscriptions the paper account lacks, and scanner, FA and display groups need a live gateway (TWS, for display
    groups).

  Then commit («Record stages 10 and 11 in the README and the status table»).
- [ ] **Step 3: Check the records against this plan.**
  - Every line of «Decisions beyond the spec» has its DECISIONS row, plus decision 1 as one names row.
  - Every public API change has a CHANGELOG `Unreleased` line.
  - protocol-178 has a section for every message id in the spec's two rows (out 78, 54–57, 91, 80, 79, 22–24, 12/13,
    84–86, 52/53, 100–103, 18/19, 67–70, 65/66/72/73; in 75, 76, 93, 78, 77, 18, 19, 20, 14, 83, 85–87, 51, 104, 105,
    16, 103, 67, 68, 65, 66, 69, 70).
  - Fix any gap in a commit of its own.
- [ ] **Step 4: Verify the series commit by commit** in a detached worktree:
  ```bash
  git worktree add --detach ../swift-ibkr-check stage-10-options-reference
  git -C ../swift-ibkr-check rebase --exec "timeout 900 swift test > /dev/null" main
  git worktree remove ../swift-ibkr-check
  ```
  Expected: `Successfully rebased`. A failing commit is fixed on `stage-10-options-reference` and the check is run
  again.
- [ ] **Step 5: Push and watch CI** with the command under Global Constraints. Expected: every job is green. A failing
  job gets its root cause fixed in a new commit, with no weakened test, then push and watch again.

## Decisions beyond the spec

1. Names:
   - calls: `qualifyContracts(_:)`, `optionChains(for:futFopExchange:)`,
     `calculateImpliedVolatility(_:optionPrice:underPrice:options:)`, `calculateOptionPrice(_:volatility:underPrice:options:)`,
     `marketRule(_:)`, `familyCodes()`, `softDollarTiers()`, `scannerSubscription(_:options:filterOptions:)`,
     `scannerData(_:options:filterOptions:)`, `scannerParameters()`, `newsProviders()`,
     `newsArticle(providerCode:articleID:options:)`, `historicalNews(conID:providerCodes:start:end:totalResults:options:)`,
     `newsBulletins(allMessages:)`, `fundamentalData(_:reportType:options:)`, `wshMetaData()`, `wshEventData(_:)`,
     `faData(_:)`, `replaceFA(_:xml:)`, `displayGroups()`, `displayGroupUpdates(_:)`, `updateDisplayGroup(_:contractInfo:)`,
     `verifyRequest(apiName:apiVersion:)`, `verifyMessage(_:)`, `verifyAndAuthRequest(apiName:apiVersion:opaqueISVKey:)`,
     `verifyAndAuthMessage(_:xyzResponse:)`;
   - factories: `Contract.stock`, `.option`, `.future`, `.contFuture`, `.forex`, `.index`, `.cfd`, `.commodity`, `.bond`,
     `.futuresOption`, `.mutualFund`, `.warrant`, `.bag`, `.crypto`;
   - types: `ContractQualification`, `OptionChain`, `PriceIncrement`, `FamilyCode`, `ScannerSubscription`, `ScanData`,
     `NewsProvider`, `NewsArticle`, `HistoricalNews`, `NewsBulletin`, `GenericTick`, `WshEventData`, `FADataType`, and
     `IBClientError.alreadySubscribed`;
   - fields keep `ib_async`'s names with `Id` → `ID` (`underlyingConID`, `marketRuleIDs`, `secIDList`, `articleID`,
     `msgID`, `opaqueISVKey`). `familyCodeStr` and `legsStr` stay as they are.
   - `ib_async`'s `requestFA` becomes `faData`, because a Swift verb drops «request». `reqSecDefOptParams` becomes
     `optionChains`, after the `OptionChain` it returns. `subscribeToGroupEvents` with its unsubscribe becomes
     `displayGroupUpdates`, a stream. The calls that have no `req` keep `ib_async`'s name.
2. The new calls live in `IBClient+Reference.swift` and `IBClient+Research.swift`. `IBClient.swift` is already over
   1000 lines, and a split by topic keeps each file readable. So `requireConnected`, `openStream`, `answer`, `collect`
   and `nextLocalID` become internal. Rejected: growing `IBClient.swift`; a second registry.
3. The contract factories are static functions on `Contract`. They take `ib_async`'s parameters in its order, with its
   defaults: `""` for exchange and currency, and `IDEALPRO` for forex. So a factory value equals the `ib_async` one
   field for field, while `Contract(symbol:)` keeps its `SMART`/`USD`.
   - A strike is `Decimal?` (`nil` goes out as `0.0`), and the symbol is a required first argument.
   - `forex` splits the pair 3/3 and does not trap on a bad pair; IB then refuses it.
   - `bond`, `mutualFund`, `warrant` and `bag` have no positional `ib_async` arguments, so they take the fields that
     identify them (`secIDType`/`secID`, `symbol`, `legs`).

   Rejected: `ib_async`'s subclasses; `SMART`/`USD` defaults (a value would differ from `ib_async`'s).
4. `ContractDetails` gains every field `ib_async` decodes, bond fields included. Each is declared with its default and
   the init is unchanged, as with `Order`.
   - lastTimes is split as `ib_async` splits it: the date goes to `lastTradeDateOrContractMonth` (or `maturity` for a
     bond), the time to `lastTradeTime`, and a third part replaces `timeZoneID`. This reverses «kept whole», so a
     qualified option carries a plain date that IB accepts back.
   - `marketRuleIDs` is `[Int]`, so it feeds `marketRule(_:)` directly; a non-number is `.malformed`.
   - `secIDList` is `[TagValue]`.
5. bondContractDetails (18) decodes into `.contractData` with the bond fields set, as `ib_async`'s wrapper aliases it
   to `contractDetails`. So `contractDetails` returns bonds, with no new route. Rejected: a separate
   `IBMessage.bondContractData`.
6. `qualifyContracts` returns `[ContractQualification]` in input order: `.qualified`, `.ambiguous(candidates)` or
   `.notFound`.
   - `ib_async` returns `None` for both failures and logs the candidates, and the typed result keeps them.
   - Only 200 (or an empty answer) is `.notFound`. Any other error throws and cancels the rest, where `ib_async`
     returns `None`. A failed lookup is not an unknown contract.
   - The secType filter and the `SMART` exchange are `ib_async`'s; when the filter matches none, all candidates are
     kept.
   - A `BAG` throws before anything is sent.
7. `optionChains` takes the underlying `Contract` (symbol, secType, conID), so a qualified contract passes straight
   in, plus `futFopExchange`. Strikes are `Decimal`. It collects until 76 and sends no cancel.
8. The calculations:
   - The answer travels as the existing `.tick(requestID:, .optionComputation)` and is routed by the calculation's
     own reqId. There is no new `IBMessage` case, and no reqId is shared with a quote stream.
   - The first computation answers the call. The cancel follows the answer, as in `ib_async`'s `finally`. A
     permission refusal sends it too, as every refusal does, and any other IB error does not.
   - Prices go out as `Decimal.description`, the house rule, where `ib_async` writes `str(float)`.
9. `marketRule`, `familyCodes`, `scannerParameters`, `newsProviders` and `faData` are id-less one-shots under local
   keys. `marketRule` takes only its own `marketRuleID` and `faData` only its own type, so concurrent calls never
   swap answers. They have no IB-error path, like `depthExchanges()`.
10. `softDollarTiers` is a reqId one-shot and reuses the stage-7 `SoftDollarTier`.
11. The scanner:
    - `ScannerSubscription` uses `nil` for unset, and a `nil` `numberOfRows` goes out as `-1`, `ib_async`'s default.
    - `ScanData` carries `contract` and `marketName` instead of a mostly empty `ContractDetails`.
    - The stream yields each whole scan (one message 20), buffers only the newest, never ends itself, and sends 23
      when stopped.
    - `scannerData` returns the first scan and then sends 23, as `ib_async`'s `reqScannerDataAsync` does. After IB's
      error it sends no 23.
12. Tag-value lists go out as `"tag=value;"` through one `IBRequest.tagValues`, which placeOrder now shares. A count
    precedes the list only where `ib_async` sends one (fundamentals, calculations).
13. News:
    - `historicalNews` takes `Date?` bounds in the library's `yyyyMMdd-HH:mm:ss` UTC text, as `historicalTicks` does,
      and `providerCodes: [String]`, joined with `+`.
    - `HistoricalNews.time` stays IB's text, as execution times do.
    - `hasMore` is dropped, as `ib_async` drops it.
14. `newsBulletins` is a request stream under a local key.
    - IB has one bulletin subscription per connection, so a second open stream throws `.alreadySubscribed` instead of
      sharing it.
    - Stopping the stream sends 13.

    Rejected: reference counting; letting the second stream's stop cut the first; fire-and-forget calls with
    `messages()`.
15. `genericTicks` becomes `[GenericTick]`, which integer and string literals both build. News ticks need `mdoff` and
    `292:BRFG`, which `[Int]` cannot carry. Existing literal call sites keep compiling. This rewrites the `[Int]`
    DECISIONS row. Rejected: `[String]` (it breaks every caller); a separate `newsTicks` call.
16. `fundamentalData` is a reqId one-shot whose answer stays IB's XML `String`. It sends 53 only for a caller cancelled
    before the answer, as `histogramData` does.
17. WSH:
    - `wshMetaData` and `wshEventData` are one-shots that send their cancel (101, 103) after the answer.
      `ib_async` cancels the event request after its answer and the meta request only before the next one; ours leaves
      nothing open.
    - A `nil` `conID` or `totalLimit` goes out as `2147483647`, as `ib_async` sends with `makeEmpty=False`.
    - Meta-before-event is documented, not enforced.
18. FA:
    - `faData` waits for a 16 of its own type, and an unknown type is `.malformed`.
    - `replaceFA` waits for 103 by reqId and returns its text; `ib_async` does not wait.
    - A login that is not an FA account gets an error with no reqId, so `faData` waits until the caller cancels it
      (KNOWN-GAPS).
19. Display groups:
    - `displayGroups()` returns IB's raw `"1|2|3"`.
    - `displayGroupUpdates(_:)` returns `(requestID, updates)`, because `updateDisplayGroup(_:contractInfo:)` must send
      under the subscription's reqId. Stopping the stream sends 70.
    - `contractInfo` stays IB's text.
20. Verify: the four calls only send. Their answers (65, 66, 69, 70) reach `messages()` only, as `ib_async`'s wrapper
    has no handler for them. IB documents them before startApi, which `connect` sends itself (KNOWN-GAPS).
21. README gains an «ib_async names» table for the stage 10–11 calls; stage 13 extends it to every call.
