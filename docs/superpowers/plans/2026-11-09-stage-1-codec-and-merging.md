# swift-ibkr Stage 1: Codec and Order / Execution Merging — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The wire layer of the TWS API at protocol version 178 (frames, fields, handshake, the order / execution / error messages in both directions) and the two trackers that turn openOrder + orderStatus into whole orders and execDetails + commissionReport into whole fills — all tested on byte fixtures, no socket, no gateway.

**Architecture:** One library target `IBKR`. `Wire/` turns bytes into frames and fields and back; `Messages/` turns fields into `enum IBMessage` (incoming) and `enum IBRequest` into fields (outgoing), one fixed field layout (version 178, no branches); `State/` holds `OrderTracker` and `ExecutionTracker`, plain value types the stage-2 actor will own. Stage 2 (socket, `IBClient` actor, throttle, snapshot+stream, live check) is planned after this stage.

**Tech Stack:** Swift 6.4.2, SwiftPM tools 6.0 (Swift 6 language mode), Foundation (`Decimal`) only, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-09-swift-ibkr-design.md` (sections «Устройство», «Сообщения (версия 178)», «Версия», «Тесты», «Этапы» item 1).

## Global Constraints

- Repository `C:\Users\viohn\swift-ibkr`, branch `main` (local only; nothing is pushed to GitHub without the owner's «да»). Build `swift build`, test `swift test` from the repository root. If the default build system fails on Windows, use `--build-system native` for both and record that in `README.md`.
- No dependencies. Library product and target `IBKR`; test target `IBKRTests`. `platforms: [.macOS(.v13)]`.
- Protocol version 178 only. Handshake advertises `v100..178`; any server version other than 178 is an error.
- Field order comes from `docs/protocol-178.md` (Task 1). Never copy code from the official `ibapi` (non-commercial license); `ib_async` (BSD-2-Clause) at commit `ab629f34c1823ea4c1542f32f07377208a86bdfd` is the reference for field order, read, not translated line by line.
- Prices and quantities are `Decimal`, parsed with `Decimal(string:)`; in tests use `Decimal(string: "…")!` or a `d("…")` helper, never float literals.
- "No value" is `nil` in public types. Incoming `""`, `2147483647`, `9223372036854775807`, `1.7976931348623157E308` in an optional field → `nil`.
- Every public type is `Sendable`; models are `Equatable`.
- Commits: one imperative sentence + reasoning (what was tried, what was rejected); last line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. `README.md` and `docs/DECISIONS.md` change in the commit whose behaviour they describe. Verify the series at the end with `git rebase --exec "swift test > /dev/null" <first stage-1 commit>~1`.

## Decisions taken in this plan (owner can veto)

- `orderType` and `tif` stay IB's strings (`"LMT"`, `"STP LMT"`, `"GTC"` …): IB has dozens, the consumer maps the few it uses. `action` is an enum (`BUY` / `SELL` / `SSHORT`).
- Order status is an open set: `struct OrderStatus: RawRepresentable` with constants for IB's nine names, so an unknown status from a newer gateway is kept, not rejected.
- An outgoing text field that is not printable ASCII (`0x20...0x7E`) makes encoding throw `IBEncodingError.nonASCII(field:)` — IB's own client refuses it (error 579). Consequence for TWS: Russian preset names cannot go in `orderRef` as is; the adapter decides (stage 5).
- Execution and order times stay IB's raw strings in stage 1; parsing to dates is decided with live samples in stage 2.
- A fill is published only when both halves (execDetails, commissionReport) are present. Correction key: the execId without its last `.`-segment.
- The trackers publish only real changes: a repeated identical openOrder / orderStatus publishes nothing.
- Error codes (Task 5): *notice* — 2100...2199, 10167, 399, 404, 161, 10147, 10148, 165; *order cancelled* — 202; everything else *fatal*. The table lives in `ErrorCode.kind(_:)` and `docs/DECISIONS.md`.

## Review Focus

1. A frame split across reads at any byte, including inside the 4-byte length prefix, and several frames in one read → Task 2 `readerReassemblesByteByByte`, `readerSplitsTwoFramesInOneChunk`.
2. A Cyrillic or other non-ASCII `orderRef` / symbol on the way out → typed throw, nothing half-encoded (Task 4 `placeOrderRefusesNonASCII`); non-ASCII UTF-8 on the way in (IB error text) decodes without loss (Task 2 `readerDecodesUTF8`).
3. The UNSET sentinels in incoming optional numbers (`avgFillPrice`, `lmtPrice`, `realizedPNL`) → `nil`, never 1.79e308 in a model (Task 2 `unsetSentinelsAreNil`, Task 6 `unsetPricesAreNil`, Task 8 `unsetRealizedPNLIsNil`).
4. IB repeats openOrder / orderStatus with nothing changed → no duplicate publish (Task 7 `identicalRepeatPublishesNothing`).
5. An error for an orderId the tracker has never seen (another session's order, or a cancel of an already filled order: 10148) → no order is created or changed (Task 7 `errorForUnknownOrderChangesNothing`, `cancelRejectionKeepsTheOrder`).

---

### Task 1: Protocol reference for version 178

**Files:**
- Create: `docs/protocol-178.md`

**Interfaces:**
- Produces: the field-order authority every later task encodes, decodes and builds fixtures from. Sections, one per message, named exactly: `startApi (out 71)`, `reqIds (out 8)`, `placeOrder (out 3)`, `cancelOrder (out 4)`, `reqOpenOrders (out 5)`, `reqAllOpenOrders (out 16)`, `reqAutoOpenOrders (out 15)`, `reqCompletedOrders (out 99)`, `reqExecutions (out 7)`, `orderStatus (in 3)`, `error (in 4)`, `openOrder (in 5)`, `nextValidId (in 9)`, `execDetails (in 11)`, `managedAccounts (in 15)`, `currentTime (in 49)`, `openOrderEnd (in 53)`, `execDetailsEnd (in 55)`, `commissionReport (in 59)`, `orderBound (in 100)`, `completedOrder (in 101)`, `completedOrdersEnd (in 102)`, plus `Handshake`.

- [ ] **Step 1: Write the handshake section** — the exact bytes: `API\0`, then a 4-byte big-endian length and the text `v100..178` with **no** trailing NUL; the server's first frame is two NUL-terminated fields, version and connection time; then startApi.
- [ ] **Step 2: Write every message section** from `ib_async` at commit `ab629f3` (`ib_async/client.py`, `ib_async/decoder.py`, and the model defaults in `order.py`, `contract.py`, `objects.py`) evaluated at `serverVersion == 178`: drop every field gated above 178, keep every field gated at or below. Per field one table row: index, name, type (`int`, `decimal`, `bool`, `string`, `double`), and for outgoing fields the value sent when the caller does not set it (copy `ib_async`'s default, e.g. empty string for UNSET). Repeated groups (combo legs, order conditions, tag-value lists, algo params) get their count field and the fields of one element. For `placeOrder` and `openOrder` / `completedOrder`, mark the fields `Contract` / `Order` model (Task 4) with ★.
- [ ] **Step 3: Cross-check** `placeOrder`, `openOrder`, `orderStatus`, `execDetails` and `commissionReport` against the official client's field order in the `deepentropy/ibapi` mirror (`ibapi/ibapi/client.py`, `decoder.py`, `orderdecoder.py`) at server version 178 — read only, no copying. Note every disagreement under a `Disagreements` heading with which source the table follows and why.
- [ ] **Step 4: Head the file** with the source line: field order derived from `ib_async` (BSD-2-Clause, © Ewald de Wit, Matt Stancliff) commit `ab629f34c1823ea4c1542f32f07377208a86bdfd`, cross-checked against IB's published client; not affiliated with Interactive Brokers.
- [ ] **Step 5: Commit** — `git add docs/protocol-178.md` and commit «Record the version-178 field order of every stage-1 message».

### Task 2: Package, frames and fields

**Files:**
- Create: `Package.swift`, `README.md`, `docs/DECISIONS.md`, `Sources/IBKR/Wire/Frame.swift`, `Sources/IBKR/Wire/Fields.swift`, `Sources/IBKR/Errors.swift`
- Test: `Tests/IBKRTests/FrameTests.swift`, `Tests/IBKRTests/FieldTests.swift`, `Tests/IBKRTests/Helpers.swift`

**Interfaces:**
- Produces:
  - `public enum IBProtocolError: Error, Equatable, Sendable { case frameTooLong(Int), missingField(index: Int), badNumber(String, index: Int), unsupportedServerVersion(Int), badHandshake }`
  - `public enum IBEncodingError: Error, Equatable, Sendable { case nonASCII(field: String) }`
  - `enum Frame { static let maxLength = 0xFF_FFFF; static func encode(_ body: [UInt8]) -> [UInt8] }` (length prefix + body)
  - `struct FrameReader { mutating func append(_ bytes: [UInt8]) throws(IBProtocolError); mutating func next() -> [UInt8]? }`
  - `struct FieldWriter { init(); mutating func add(_ value: String) throws(IBEncodingError); mutating func add(_ value: Int?); mutating func add(_ value: Decimal?); mutating func add(_ value: Bool); mutating func add(_ value: Double?); var body: [UInt8] }` — `nil` → empty field; `Bool` → `"1"` / `"0"`; `Decimal` via `description` (always `.`, no exponent).
  - `struct FieldReader { init(_ body: [UInt8]); var fields: [String]; var index: Int; mutating func string() throws -> String; mutating func int() throws -> Int /* "" → 0 */; mutating func optionalInt() throws -> Int?; mutating func decimal() throws -> Decimal /* "" → 0 */; mutating func optionalDecimal() throws -> Decimal?; mutating func bool() throws -> Bool; mutating func double() throws -> Double; mutating func optionalDouble() throws -> Double?; mutating func skip(_ count: Int = 1) throws; var isAtEnd: Bool }` — fields split on NUL and decoded as UTF-8.
  - Test helper `func body(_ fields: String...) -> [UInt8]` (each field + `\0`) and `func d(_ s: String) -> Decimal`.

- [ ] **Step 1: Write the package** — `Package.swift` (tools 6.0, product/target `IBKR`, test target `IBKRTests`, `.macOS(.v13)`), `README.md` (what the package is, the not-affiliated line, build and test commands, the version-178 pin), `docs/DECISIONS.md` with the decisions of this plan's «Decisions» section and the spec's «моё решение» items as a table *Decision | Why | Rejected*.
- [ ] **Step 2: Write the failing tests**
  - `frameEncodesLengthBigEndian`: `Frame.encode(Array("ab\0".utf8)) == [0,0,0,3] + Array("ab\0".utf8)`.
  - `readerReassemblesByteByByte`: feed `Frame.encode(body("3","5"))` one byte per `append`; `next()` is nil until the last byte, then equals `body("3","5")`, then nil.
  - `readerSplitsTwoFramesInOneChunk`: one `append` of two encoded frames → two `next()` results in order.
  - `readerRejectsOversizedFrame`: prefix `[0x01,0,0,0]` → `append` throws `.frameTooLong(16_777_216)`.
  - `writerEncodesEachKind`: adds `"BUY"`, `Int?(nil)`, `7`, `d("0.0001")`, `d("100")`, `true`, `false` → body `"BUY\0\07\00.0001\0100\01\00\0"`.
  - `writerRefusesNonASCII`: `add("Купить")` throws `.nonASCII(field: "Купить")`; `add("a\u{7}")` throws too.
  - `unsetSentinelsAreNil`: reader over `"", "2147483647", "9223372036854775807", "1.7976931348623157E308", "12.5"` → `optionalInt()`, `optionalInt()`, `optionalInt()`, `optionalDecimal()` are nil, `optionalDecimal() == d("12.5")`.
  - `readerDecodesUTF8`: `body("Ордер отклонён")` → `string() == "Ордер отклонён"`.
  - `readerThrowsPastTheEnd`: one field, two `string()` calls → second throws `.missingField(index: 1)`; `int()` on `"x"` throws `.badNumber("x", index: 0)`.
- [ ] **Step 3: Run** `swift test` — Expected: FAIL (types not defined).
- [ ] **Step 4: Implement** `Frame`, `FrameReader` (internal buffer; reads the length once 4 bytes are present; throws on a length above `maxLength`), `FieldWriter`, `FieldReader`, the error enums.
- [ ] **Step 5: Run** `swift test` — Expected: all PASS. Run `swift build` — no warnings in `Sources/`.
- [ ] **Step 6: Commit** «Frame and field the TWS API wire format».

### Task 3: Handshake and the small requests

**Files:**
- Create: `Sources/IBKR/Wire/Handshake.swift`, `Sources/IBKR/Messages/IBRequest.swift`, `Sources/IBKR/Models/ExecutionFilter.swift`
- Test: `Tests/IBKRTests/HandshakeTests.swift`, `Tests/IBKRTests/RequestTests.swift`

**Interfaces:**
- Consumes: `Frame`, `FieldWriter`, `FieldReader`, `IBProtocolError` (Task 2).
- Produces:
  - `public enum Handshake { public static let version = 178; static func hello() -> [UInt8]; static func parseServerHello(_ body: [UInt8]) throws(IBProtocolError) -> (serverVersion: Int, connectionTime: String) }` — any version ≠ 178 throws `.unsupportedServerVersion(v)`; not exactly two fields throws `.badHandshake`.
  - `public struct ExecutionFilter: Sendable, Equatable { clientID: Int?, account: String, time: String, symbol: String, secType: String, exchange: String, side: String }` with an all-empty `init()`.
  - `public enum IBRequest: Sendable, Equatable { case startAPI(clientID: Int, capabilities: String), requestIDs, cancelOrder(orderID: Int, manualCancelTime: String), openOrders, allOpenOrders, autoOpenOrders(Bool), completedOrders(apiOnly: Bool), executions(requestID: Int, filter: ExecutionFilter) }` plus `func body() throws(IBEncodingError) -> [UInt8]` (fields only; framing is the caller's). `placeOrder` is added in Task 4.

- [ ] **Step 1: Write the failing tests**
  - `helloIsPrefixAndVersionRange`: `Handshake.hello() == Array("API\0".utf8) + [0,0,0,9] + Array("v100..178".utf8)`.
  - `serverHelloParses`: `body("178", "20261109 10:41:35 Central European Standard Time")` → `(178, "20261109 10:41:35 Central European Standard Time")`.
  - `serverHelloOtherVersionThrows`: `body("176","t")` throws `.unsupportedServerVersion(176)`; `body("201","t")` throws `.unsupportedServerVersion(201)`; `body("178")` throws `.badHandshake`.
  - One test per request, `bodyMatchesProtocolTable_<name>`, comparing `IBRequest.<case>.body()` with `body(...)` built from the `docs/protocol-178.md` row list, e.g. `startAPI(clientID: 1, capabilities: "")` → `body("71","2","1","")`; `requestIDs` → `body("8","1","1")`; `executions(requestID: 7, filter: ExecutionFilter())` → the reqExecutions row list with `"7"` and empty filter fields.
- [ ] **Step 2: Run** `swift test` — Expected: FAIL.
- [ ] **Step 3: Implement** `Handshake` and `IBRequest.body()` for these cases, field order from `docs/protocol-178.md`.
- [ ] **Step 4: Run** `swift test` — Expected: PASS.
- [ ] **Step 5: Commit** «Encode the handshake and the order-listing requests at version 178».

### Task 4: Contract, Order and placeOrder

**Files:**
- Create: `Sources/IBKR/Models/Contract.swift`, `Sources/IBKR/Models/Order.swift`
- Modify: `Sources/IBKR/Messages/IBRequest.swift` (case `placeOrder`)
- Test: `Tests/IBKRTests/PlaceOrderTests.swift`

**Interfaces:**
- Consumes: `IBRequest`, `FieldWriter` (Tasks 2–3).
- Produces:
  - `public struct Contract: Sendable, Equatable, Hashable { conID: Int, symbol: String, secType: String, lastTradeDateOrContractMonth: String, strike: Decimal?, right: String, multiplier: String, exchange: String, primaryExchange: String, currency: String, localSymbol: String, tradingClass: String }`; `init(symbol:secType:exchange:currency:primaryExchange:)` with `secType "STK"`, `exchange "SMART"`, `currency "USD"`, others empty / 0 / nil.
  - `public enum OrderAction: String, Sendable { case buy = "BUY", sell = "SELL", shortSell = "SSHORT" }`
  - `public struct Order: Sendable, Equatable { action: OrderAction, totalQuantity: Decimal, orderType: String, limitPrice: Decimal?, auxPrice: Decimal?, tif: String, outsideRTH: Bool, parentID: Int, transmit: Bool, ocaGroup: String, ocaType: Int, orderRef: String, account: String }`; `init(action:quantity:orderType:limitPrice:auxPrice:tif:)` with `tif "DAY"`, `transmit true`, `parentID 0`, `ocaType 0`, strings empty.
  - `IBRequest.placeOrder(orderID: Int, contract: Contract, order: Order)`; its `body()` throws `.nonASCII` for any non-ASCII string field of contract or order.

- [ ] **Step 1: Write the failing tests**
  - `limitOrderMatchesProtocolTable`: `placeOrder(orderID: 12, contract: Contract(symbol: "AAPL"), order: Order(action: .buy, quantity: d("100"), orderType: "LMT", limitPrice: d("187.25")))` → equals `body(...)` written out from the `placeOrder` table (every field, defaults included).
  - `bracketChildCarriesParentAndTransmit`: a stop child with `parentID 12`, `transmit false`, `auxPrice d("180")`, `outsideRTH true` → the decoded field list (split the body on NUL) has `"12"` at the parentId index, `"0"` at transmit, `"180"` at auxPrice, `"1"` at outsideRth (indices from the table).
  - `modifyIsTheSameMessageWithTheSameID`: two `placeOrder` bodies for id 12 differing only in `limitPrice` differ only at the lmtPrice index.
  - `placeOrderRefusesNonASCII`: `orderRef "Купить 500"` → `body()` throws `.nonASCII(field: "Купить 500")`.
- [ ] **Step 2: Run** `swift test` — Expected: FAIL.
- [ ] **Step 3: Implement** the models and `placeOrder` encoding, every unmodelled field with its table default.
- [ ] **Step 4: Run** `swift test` — Expected: PASS.
- [ ] **Step 5: Commit** «Encode placeOrder at version 178 for stocks, brackets and modifications».

### Task 5: Decoding the small messages and the error table

**Files:**
- Create: `Sources/IBKR/Messages/IBMessage.swift`, `Sources/IBKR/Messages/Decoder.swift`, `Sources/IBKR/Messages/ErrorCode.swift`, `Sources/IBKR/Models/Execution.swift`, `Sources/IBKR/Models/OrderStatus.swift`
- Modify: `docs/DECISIONS.md` (the error table)
- Test: `Tests/IBKRTests/DecoderTests.swift`, `Tests/IBKRTests/ErrorCodeTests.swift`

**Interfaces:**
- Consumes: `FieldReader`, `Contract` (Tasks 2, 4).
- Produces:
  - `public struct OrderStatus: RawRepresentable, Sendable, Hashable { rawValue: String }` with `apiPending, pendingSubmit, pendingCancel, preSubmitted, submitted, apiCancelled, cancelled, filled, inactive` (IB's spellings) and `var isFinal: Bool` (cancelled, apiCancelled, filled, inactive).
  - `public struct OrderStatusMessage: Sendable, Equatable { orderID, status: OrderStatus, filled: Decimal, remaining: Decimal, averageFillPrice: Decimal?, permID: Int, parentID: Int, lastFillPrice: Decimal?, clientID: Int, whyHeld: String, marketCapPrice: Decimal? }`
  - `public struct IBErrorMessage: Sendable, Equatable { requestID: Int, code: Int, text: String, advancedOrderRejectJSON: String }`
  - `public struct Execution: Sendable, Equatable { execID, time: String, account, exchange, side: String /* BOT / SLD */, shares: Decimal, price: Decimal, permID: Int, clientID: Int, orderID: Int, liquidation: Int, cumulativeQuantity: Decimal, averagePrice: Decimal, orderRef: String, lastLiquidity: Int, pendingPriceRevision: Bool }`
  - `public struct CommissionReport: Sendable, Equatable { execID, commission: Decimal, currency: String, realizedPNL: Decimal?, yield: Decimal?, yieldRedemptionDate: Int? }`
  - `public enum IBMessage: Sendable, Equatable { case orderStatus(OrderStatusMessage), error(IBErrorMessage), nextValidID(Int), managedAccounts([String]), currentTime(Int), openOrderEnd, execDetails(requestID: Int, contract: Contract, execution: Execution), execDetailsEnd(requestID: Int), commissionReport(CommissionReport), orderBound(permID: Int, clientID: Int, orderID: Int), completedOrdersEnd, unknown(id: Int, fields: [String]), malformed(id: Int, fields: [String], reason: String) }` (Task 6 adds `openOrder`, `completedOrder`).
  - `public enum Decoder { public static func decode(_ body: [UInt8]) -> IBMessage }` — never throws: an unknown id → `.unknown`, a known id that fails to parse → `.malformed` with the thrown error's description.
  - `public enum ErrorKind: Sendable { case notice, orderCancelled, fatal }`, `public enum ErrorCode { public static func kind(_ code: Int) -> ErrorKind }`.

- [ ] **Step 1: Write the failing tests** — one per message, fixture from the `docs/protocol-178.md` rows:
  - `orderStatusDecodes`: fields for order 12, `"Submitted"`, filled `"0"`, remaining `"100"`, avgFillPrice `"0"`, permId `"918273001"`, parentId `"0"`, lastFillPrice `"0"`, clientId `"1"`, whyHeld `""`, mktCapPrice `"1.7976931348623157E308"` → `.orderStatus` with those values and `marketCapPrice == nil`.
  - `errorDecodes`: reqId `"12"`, code `"201"`, text `"Order rejected - reason:…"`, advancedOrderRejectJson `""` → `.error`; `errorWithMinusOneIsConnectionLevel` keeps `requestID == -1`.
  - `nextValidIDDecodes` (`"9","1","13"` → 13), `managedAccountsSplitsOnComma` (`"DU123456,DU654321"` → two accounts, a trailing comma adds nothing), `execDetailsDecodes` (contract AAPL and execution `0000e0d5.6556b5f0.01.01`, BOT 100 at 187.25, cumQty 100, avgPrice 187.25), `commissionReportDecodes` (commission `"1.0"`, currency `"USD"`, realizedPNL UNSET → nil), `endMarkersDecode` (53, 55 with reqId 7, 102), `orderBoundDecodes`, `currentTimeDecodes` (`"49","1","1762680000"` → 1762680000).
  - `unknownIDIsKept`: `body("999","x")` → `.unknown(id: 999, fields: ["999","x"])`.
  - `truncatedKnownMessageIsMalformed`: `body("3","12")` → `.malformed(id: 3, …)`.
  - `errorKinds`: `kind(2104) == .notice`, `kind(10167) == .notice`, `kind(399) == .notice`, `kind(10148) == .notice`, `kind(202) == .orderCancelled`, `kind(201) == .fatal`, `kind(200) == .fatal`, `kind(354) == .fatal`.
- [ ] **Step 2: Run** `swift test` — Expected: FAIL.
- [ ] **Step 3: Implement** the models, `IBMessage`, `Decoder.decode` dispatching on the first field, `ErrorCode.kind` with the table from «Decisions»; add the table to `docs/DECISIONS.md`.
- [ ] **Step 4: Run** `swift test` — Expected: PASS.
- [ ] **Step 5: Commit** «Decode order status, executions, commissions and errors at version 178».

### Task 6: Decoding openOrder and completedOrder

**Files:**
- Create: `Sources/IBKR/Messages/OrderDecoding.swift`
- Modify: `Sources/IBKR/Messages/IBMessage.swift`, `Sources/IBKR/Messages/Decoder.swift`
- Test: `Tests/IBKRTests/OpenOrderTests.swift`, `Tests/IBKRTests/Fixtures.swift`

**Interfaces:**
- Consumes: `Contract`, `Order`, `OrderStatus`, `FieldReader` (Tasks 2, 4, 5).
- Produces:
  - `public struct OpenOrderMessage: Sendable, Equatable { orderID: Int, clientID: Int, permID: Int, contract: Contract, order: Order, status: OrderStatus }`
  - `public struct CompletedOrderMessage: Sendable, Equatable { permID: Int, clientID: Int, orderID: Int, contract: Contract, order: Order, status: OrderStatus, completedTime: String, completedStatus: String }`
  - `IBMessage.openOrder(OpenOrderMessage)`, `IBMessage.completedOrder(CompletedOrderMessage)`.
  - In `Fixtures.swift`: `static func openOrderFields(orderID: Int, permID: Int, clientID: Int, symbol: String, action: String, quantity: String, orderType: String, limitPrice: String, auxPrice: String, tif: String, parentID: String, outsideRTH: String, orderRef: String, status: String) -> [String]` producing the full version-178 field list from the table (defaults for the rest); the same for `completedOrderFields`. Task 7 builds its sequences with these.

- [ ] **Step 1: Write the failing tests**
  - `openOrderDecodesModelledFields`: a limit buy AAPL 100 @ 187.25, DAY, orderRef `"preset-1"`, status `"Submitted"` → the decoded contract and order equal what was put in; `status == .submitted`.
  - `bracketChildDecodesParent`: parentId `"12"`, STP, auxPrice `"180"` → `order.parentID == 12`, `order.auxPrice == d("180")`.
  - `unsetPricesAreNil`: lmtPrice and auxPrice `"1.7976931348623157E308"` (a market order) → both nil.
  - `openOrderConsumesEveryField`: after decoding, the reader is at the end (assert through a decode of the fixture with one extra trailing field → still decodes, and a fixture missing its last field → `.malformed`).
  - `completedOrderDecodes`: a filled order with `completedTime "20261109 15:59:01"` and `completedStatus "Filled"` → values as given, `status == .filled`.
- [ ] **Step 2: Run** `swift test` — Expected: FAIL.
- [ ] **Step 3: Implement** the decoding of both messages per the table (shared contract/order-reading helpers, skipping unmodelled fields with `skip`, reading repeated groups by their count).
- [ ] **Step 4: Run** `swift test` — Expected: PASS.
- [ ] **Step 5: Commit** «Decode openOrder and completedOrder at version 178».

### Task 7: OrderTracker

**Files:**
- Create: `Sources/IBKR/State/OrderTracker.swift`
- Test: `Tests/IBKRTests/OrderTrackerTests.swift`

**Interfaces:**
- Consumes: `IBMessage`, `OpenOrderMessage`, `CompletedOrderMessage`, `OrderStatusMessage`, `IBErrorMessage`, `ErrorCode` (Tasks 5–6), `Fixtures` builders.
- Produces:
  - `public struct OrderSnapshot: Sendable, Equatable { orderID: Int, clientID: Int, permID: Int, contract: Contract, order: Order, status: OrderStatus, filled: Decimal, remaining: Decimal, averageFillPrice: Decimal?, lastFillPrice: Decimal?, whyHeld: String, rejectReason: String?, completedTime: String? }`
  - `public enum OrderKey: Hashable, Sendable { case api(clientID: Int, orderID: Int), permanent(Int) }` — `.api` when orderID > 0, else `.permanent(permID)`.
  - `public struct OrderTracker: Sendable { public init(); public var orders: [OrderSnapshot] /* first-seen order */; public mutating func sent(orderID: Int, clientID: Int, contract: Contract, order: Order); public mutating func apply(_ message: IBMessage) -> [OrderSnapshot] /* the snapshots this message changed */ }`

Rules (from the spec): openOrder sets contract, order and status; orderStatus sets status, filled, remaining, prices, permID, whyHeld; a permID seen in either links to the same key; an orderStatus for an order that has neither openOrder nor `sent` is held and applied when its openOrder arrives; with a `sent` record it publishes from that record; completedOrder updates the order with the same permID or adds one keyed `.permanent`; orderBound links its permID to `.api(clientID, orderID)`; an error whose `requestID` is a known order's id: `.orderCancelled` → status cancelled, `.fatal` → `rejectReason = text` and, unless the status is final, status inactive; `.notice` → nothing. Before openOrder, `remaining` is `order.totalQuantity`.

- [ ] **Step 1: Write the failing tests**
  - `openOrderThenStatusMerges`: openOrder (Submitted) → one snapshot; orderStatus (Filled, filled 100, remaining 0, avg 187.20) → one snapshot with the order fields from openOrder and the progress from orderStatus.
  - `statusBeforeOpenOrderIsHeld`: orderStatus first → `[]`; then openOrder → one snapshot already carrying the held status and progress.
  - `statusAfterSendPublishesFromTheSentOrder`: `sent(12, …)` then orderStatus PreSubmitted → one snapshot with the sent contract and order.
  - `identicalRepeatPublishesNothing`: the same openOrder twice, the same orderStatus twice → the second of each returns `[]`.
  - `rejectionBeforeOpenOrder`: `sent(12, …)`, error 201 on reqId 12 → one snapshot, status inactive, `rejectReason` the error text.
  - `cancelConfirmation`: open order, error 202 on its id → status cancelled, `rejectReason == nil`.
  - `cancelRejectionKeepsTheOrder`: filled order, error 10148 on its id → `[]`, snapshot unchanged.
  - `errorForUnknownOrderChangesNothing`: error 201 on reqId 99 with no such order → `[]`, `orders.isEmpty`.
  - `manualOrderKeyedByPermID`: openOrder with orderId 0, permId 5555 → key `.permanent(5555)`; orderStatus with orderId 0, permId 5555 → same snapshot updated.
  - `completedOrderJoinsByPermID`: openOrder 12 (permId 918273001), then completedOrder with permId 918273001 → the same snapshot, status filled, `completedTime` set; a completedOrder with an unknown permId → a new snapshot at the end of `orders`.
  - `orderBoundLinks`: openOrder orderId 0 permId 5555, then orderBound(5555, clientID 0, orderID 41), then orderStatus orderId 41 clientId 0 → updates that snapshot, `orders.count == 1`.
- [ ] **Step 2: Run** `swift test` — Expected: FAIL.
- [ ] **Step 3: Implement** `OrderTracker` (dictionary key → index into an array, a permID → key index, held statuses by orderID, sent orders by orderID).
- [ ] **Step 4: Run** `swift test` — Expected: PASS.
- [ ] **Step 5: Commit** «Merge openOrder, orderStatus and completedOrder into whole orders».

### Task 8: ExecutionTracker

**Files:**
- Create: `Sources/IBKR/State/ExecutionTracker.swift`
- Test: `Tests/IBKRTests/ExecutionTrackerTests.swift`

**Interfaces:**
- Consumes: `IBMessage.execDetails`, `.commissionReport`, `Execution`, `CommissionReport`, `Contract` (Task 5).
- Produces:
  - `public struct Fill: Sendable, Equatable { contract: Contract, execution: Execution, commission: CommissionReport }`
  - `public struct ExecutionTracker: Sendable { public init(); public var fills: [Fill]; public mutating func apply(_ message: IBMessage) -> [Fill] }`

- [ ] **Step 1: Write the failing tests**
  - `execThenCommissionPublishesOnce`: execDetails → `[]`; commissionReport same execId → one fill with both halves.
  - `commissionBeforeExecWaits`: commissionReport → `[]`; execDetails → one fill.
  - `repeatedExecPublishesNothing`: the same execDetails and commissionReport again (IB resends them for `reqExecutions`) → `[]`, `fills.count == 1`.
  - `correctionReplaces`: fill `0000e0d5.6556b5f0.01.01`, then execDetails + commission `0000e0d5.6556b5f0.01.02` with price 187.30 → one fill published, `fills.count == 1`, `fills[0].execution.price == d("187.30")`.
  - `unsetRealizedPNLIsNil`: a commission report with realizedPNL `1.7976931348623157E308` → `fills[0].commission.realizedPNL == nil`.
  - `otherMessagesIgnored`: orderStatus → `[]`.
- [ ] **Step 2: Run** `swift test` — Expected: FAIL.
- [ ] **Step 3: Implement** `ExecutionTracker` (pending execs and pending commissions by execId; fills indexed by the correction key).
- [ ] **Step 4: Run** `swift test` — Expected: PASS. Then the whole series: `git rebase --exec "swift test > /dev/null" <first stage-1 commit>~1` — Expected: every commit green.
- [ ] **Step 5: Update** `README.md` (what stage 1 delivers, what is next: stage 2 socket and `IBClient`, live check) and commit «Merge execDetails and commission reports into whole fills».
