# Stage 6: Session and Account Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `IBClient` covers ib_async's session and account features: session one-shots and settings, an always-on
portfolio and account values synced at connect, the Multi and account-P&L subscriptions, a cancellable `connect`, a
clean disconnect, and opt-in reconnect. Error text is unescaped, and the warning table matches ib_async.

**Architecture:** First the error table and the decoder fix (Task 1), then the session requests (Task 2). Next come
the account codec (Task 3), an `AccountTracker` beside `PositionTracker` (Task 4), and its connect-time sync
(Task 5). Task 6 adds three request streams on the existing `openStream` registry. The last two tasks change the
connection's lifecycle: a cancellable `connect` and a draining `disconnect` (Task 7), then reconnect (Task 8), which
re-runs the same connect path from a task the actor owns.

**Tech Stack:** Swift 6 (tools 6.0), SwiftPM, Foundation, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-12-parity-and-1.0-design.md`: «Этапы» item 6, «Цели» 2 and 4,
«Перечень» rows Сессия and Счёт и портфель, and «Решения после проверки строителем» items 1 and 2. The base spec
is `docs/superpowers/specs/2026-11-09-swift-ibkr-design.md`.

## Global Constraints

- Repository `C:\Users\viohn\swift-ibkr`, branch `stage-6-session-account` off `main` (42256c0).
- No package dependencies; `Package.swift` keeps `// swift-tools-version: 6.0`.
- Money and quantities are `Decimal`. IB's unset markers read as `nil` through `FieldReader.optionalDecimal()`. Use
  `d("…")` in tests.
- Field orders come from ib_async 2.1.0 (`ab629f3`) and go into `docs/protocol-178.md` in its table style. Never
  copy code from IB's official `ibapi`.
- Orders and requests share ONE id counter (`IBClient.nextRequestID()`).
- Commit messages are one imperative sentence, then the reasoning. Read `git log` first. The last line is exactly
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- The documents of record (`README.md`, `docs/DECISIONS.md`, `docs/KNOWN-GAPS.md`, `docs/protocol-178.md`,
  `CHANGELOG.md`) change in the same commit as the behaviour they describe. Every public API change gets a
  CHANGELOG `Unreleased` line (Added / Changed).
- Every new public model gets a public memberwise `init` and is added to `PublicAPITests.everyPublicModelIsConstructible`
  (plain `import IBKR`).
- Run tests as `timeout 900 swift test`, in the foreground. A test waits on an async event for at most 2 s
  (`within2s`).
- CI (macOS, Linux 6.0 and latest, Windows, pod-lint) must be green. Push the branch
  (`git push -u origin stage-6-session-account`) and watch
  `gh run watch --exit-status $(gh run list --branch stage-6-session-account --limit 1 --json databaseId -q '.[0].databaseId')`.
  Moving and pushing `main` is the controller's job.
- The real paper account id never appears in the repo. Fixtures use `DU1`, `DU2`, and recordings `DU0000001`.

## Decisions taken in this plan (beyond the spec; record each in DECISIONS in its task's commit)

1. **Names.**
   - Session: `currentTime()`, `managedAccounts()`, `nextOrderID()`, `userInfo()`, `setServerLogLevel(_:)`,
     `setAutoOpenOrders(_:)`, `cancelAllOrders()`.
   - Account: `portfolio()`, `accountValues()`, `accountUpdatesMulti(account:modelCode:ledgerAndNLV:)`,
     `positionsMulti(account:modelCode:)`, `pnl(account:modelCode:)`.
   - Reconnect: `ReconnectPolicy`.
2. **Models.**
   - New: `PortfolioItem`, `AccountPnL` (account-level P&L has no position or value, so `PnL` does not fit) and
     `ServerLogLevel`.
   - `AccountValue` and `Position` gain `modelCode: String` with an init default of `""`, which keeps source
     compatibility.
3. **Stream shapes.**
   - `portfolio()` yields whole sets, like `positions()`.
   - `accountValues()` yields each changed value, like `executions()`: a single account has hundreds of tags, and
     IB resends all of them every 3 minutes.
4. **Several accounts.** With one managed account, `connect` sends reqAccountUpdates. With several, it sends one
   reqAccountUpdatesMulti per account, and `portfolio()` stays empty: IB's portfolio message (7) serves one account
   at a time, and `positions()` already covers holdings. reqAutoOpenOrders is not sent at connect (ib_async sends it
   for client 0): it rebinds TWS orders, so the consumer opts in.
5. **Errors.**
   - A new `ErrorKind.warning` holds ib_async's warnings missing from our table: 105, 321, 329, 434 and 492. An
     order a warning names stays live and records `rejectReason`. A request stream it names ends with `.ib`:
     ib_async's request would only time out, and our streams have no timeout.
   - 110 stays fatal. ib_async treats it as a warning only for an acknowledged order, and our tracker's
     `.apiPending` rule already does exactly that.
   - Only `text` is unescaped. `advancedOrderRejectJSON` is JSON, and its own `\u` escapes belong to the JSON parser.
6. **Id-less one-shots** (49, 15 and 9 have no reqId) wait in the existing request-stream registry under local keys
   counting down from −2, so that `end()` and task cancellation work for them unchanged.
7. **Disconnect and cancellation.**
   - `disconnect()` from `.connected` queues `cancelPositions`. The socket closes once the writer has drained the
     queue, or 2 s later at the latest. This also fixes the KNOWN-GAPS item «placeOrder then immediate disconnect
     drops the frame».
   - The account-update subscriptions are not cancelled; the socket close ends them.
   - A cancelled `connect` throws `.cancelled` and leaves `.disconnected(.cancelled)`.
8. **Reconnect.**
   - It starts only after a `connect` that succeeded. A first `connect` that fails throws as before.
   - Every error is retried. The state goes `.disconnected(error)` → `.connecting` and stays `.connecting` across
     attempts until it reaches `.connected` or gives up with `.disconnected(lastError)`. There is no new state case.
     `setState` no longer republishes an unchanged state.
   - The liveness probe is reqCurrentTime after `probeAfter` without a frame. If `probeAfter` passes again with
     nothing, the client drops the connection with `.timeout`.
   - Defaults: delays 1, 2, 5, 10, 30 s with the last repeating, unlimited attempts, `probeAfter` 30 s.
9. **Tests.** `FakeGateway.syncFrames` replaces the literal sent-frame counts, so the next sync change does not
   touch every test again. `Gateways` moves into `FakeGateway.swift` (Task 5), and Task 8 makes `next()` throw once
   the list is empty.

## Review Focus

1. **The gateway stays down after a drop** (a nightly restart). Attempts keep failing, the state stays
   `.connecting`, a `disconnect()` during a pause stops reconnecting for good, and nothing leaks. Tests: Task 8
   `disconnectStopsReconnecting` and `reconnectGivesUpAfterMaxAttempts`.
2. **A one-shot is in flight when the connection drops** (`currentTime()`). It throws `.connectionClosed` and does
   not hang. Test: Task 2 `currentTimeEndsWithTheConnection`.
3. **A login with several accounts** (FA or linked accounts). `connect` does not wait for an accountDownloadEnd
   that never comes. Values arrive through Multi, and the portfolio is empty. Test: Task 5
   `severalAccountsSyncThroughMulti`.
4. **A UI cancels the task running `connect`** while the gateway is slow. It throws `.cancelled` at once, the
   socket closes, and the next `connect` works. Test: Task 7 `connectHonoursCancellation`.
5. **Error text with a broken escape** (`\u12`, a lone surrogate, a trailing backslash). The text stays literal,
   with no crash and no `.malformed`. Test: Task 1 `malformedEscapesStayLiteral`.

---

### Task 1: Warning codes aligned with ib_async, escaped error text decoded

**Files:**
- Modify: `Sources/IBKR/Messages/ErrorCode.swift`, `Sources/IBKR/Messages/IBDecoder.swift` (case 4),
  `Sources/IBKR/State/OrderTracker.swift:112-120`, `Sources/IBKR/Client/IBClient.swift` (`routeToStream`, the
  connect-failure case in `handle`)
- Test: `Tests/IBKRTests/ErrorCodeTests.swift`, `DecoderTests.swift`, `OrderTrackerTests.swift`, `IBClientAccountTests.swift`
- Docs: DECISIONS (row «Error codes» and the error-code table: new `warning` line), KNOWN-GAPS (drop the `\uXXXX`
  and «warning codes missing» items), README «Errors», protocol-178 «error (in 4)» (one note: `errorString`
  `\uXXXX` is decoded, `advancedOrderRejectJson` is kept raw), CHANGELOG (Changed: `ErrorKind.warning`, the codes)

**Interfaces:**
- Produces:
  - `public enum ErrorKind: Sendable { case notice, warning, orderCancelled, fatal }`
  - `ErrorCode.kind`: `.warning` for 105, 321, 329, 434, 492. Every other code is unchanged, and 110 stays `.fatal`.
  - Internal `extension ErrorKind { var failsRequest: Bool }`, true for `.warning` and `.fatal`.
  - `routeToStream` ends a stream when `failsRequest` holds. The permission check stays as it is.
  - `connect` fails on a `.fatal` error with reqId −1, or on a `failsRequest` error with a sync request's id.
  - `OrderTracker` handles `.warning` like `.fatal`, except that it never sets `.inactive`.
  - Internal `func unescapeUnicode(_ s: String) -> String` in `IBDecoder.swift`:
    - every `\u` followed by exactly 4 hex digits becomes that scalar;
    - a high and a low surrogate in a row become one scalar;
    - anything else (short, non-hex, a lone surrogate, a trailing `\`) stays literal.
  - Decode 4 applies it to `text` only.

- [ ] **Step 1: Write the failing tests.** In the Swift literals below, `\\u` is a backslash on the wire.
  - `ErrorCodeTests.warningKinds`: `for c in [105, 321, 329, 434, 492] { #expect(ErrorCode.kind(c) == .warning) }`;
    `#expect(ErrorCode.kind(110) == .fatal)`.
  - `DecoderTests.escapedErrorTextIsDecoded`:
    `IBDecoder.decode(body("4","2","-1","2104","Connexion r\\u00e9ussie \\ud83d\\ude00","{\"t\":\"\\u0022\"}"))` ==
    `.error(IBErrorMessage(requestID: -1, code: 2104, text: "Connexion réussie 😀", advancedOrderRejectJSON: "{\"t\":\"\\u0022\"}"))`.
  - `DecoderTests.malformedEscapesStayLiteral`: text `"a\\u12 b\\uZZZZ c\\ud83d d\\"` decodes to the same string.
  - `OrderTrackerTests.warningKeepsAPendingOrderLive`: after `sent(orderID: 12, …)`,
    `apply(error(12, 321, "Error validating request"))` returns one snapshot with `status == .apiPending` and
    `rejectReason == "Error validating request"`.
  - `IBClientAccountTests.warningEndsARequestStream`: an `accountSummary` stream, fed
    `["4","2",id,"321","Error validating request",""]`, ends with `.ib(code: 321, text: "Error validating request")`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "ErrorCodeTests|DecoderTests|OrderTrackerTests|IBClientAccountTests"`.
  Expected: FAIL (`.warning` is missing; the text comes out escaped).
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS, including the unchanged
  `fatalErrorOnSyncRequestFailsConnect`, whose 321 is now a warning that still fails the sync request.
- [ ] **Step 5: Docs and commit** («Align the warning codes with ib_async and decode escaped error text»).

### Task 2: Session requests

**Files:**
- Create: `Sources/IBKR/Models/Session.swift` (`ServerLogLevel`), `Tests/IBKRTests/IBClientSessionTests.swift`
- Modify: `IBRequest.swift`, `IBMessage.swift`, `IBDecoder.swift`, `IBClient.swift`, `RequestTests.swift`, `DecoderTests.swift`, `PublicAPITests.swift`
- Docs: protocol-178 (out 49, 17, 104, 14, 58; in 107), README (new «Session» subsection under Guide), DECISIONS
  (id-less waiters; reqAutoOpenOrders not sent at connect), CHANGELOG

**Interfaces:**
- Produces:
  - `public enum ServerLogLevel: Int, Sendable { case system = 1, error, warning, information, detail }`
  - `IBRequest`: `.currentTime`, `.managedAccounts`, `.userInfo(requestID: Int)`, `.serverLogLevel(ServerLogLevel)`,
    `.globalCancel`. The existing `.requestIDs` and `.autoOpenOrders(Bool)` are reused.
  - `IBMessage`: `.userInfo(requestID: Int, whiteBrandingID: String)`.
  - `IBClient`. Every method throws `.notConnected` unless connected. The one-shots throw like `contractDetails`:
    the connection's error when it ends, `.cancelled` on task cancellation, and `userInfo` also on a fatal error
    for its reqId.
    - `public func currentTime() async throws(IBClientError) -> Date`
    - `public func managedAccounts() async throws(IBClientError) -> [String]` (it also refreshes the stored accounts)
    - `public func nextOrderID() async throws(IBClientError) -> Int`: sends reqIds and waits for nextValidId. It
      returns the id the next `placeOrder` takes, with IB's answer merged by `max` as at connect, and does not
      consume it.
    - `public func userInfo() async throws(IBClientError) -> String` (whiteBrandingId; `""` for most accounts)
    - `public func setServerLogLevel(_ level: ServerLogLevel) throws(IBClientError)`
    - `public func setAutoOpenOrders(_ autoBind: Bool) throws(IBClientError)`
    - `public func cancelAllOrders() throws(IBClientError)`; the outcome arrives through `orders()`.
  - Internal: id-less waiters go through `openStream` with `cancel: nil`, under keys from `nextLocalID` (−2, −3, …).
    `routeToStream` offers `.currentTime`, `.managedAccounts` and `.nextValidID` to those waiters, oldest (highest
    key) first, and only the first waiter that takes a message gets it.
- Wire:
  - out 49: `49`, `1`. out 17: `17`, `1`. out 104: `104`, reqId (no version). out 14: `14`, `1`, logLevel (int).
    out 58: `58`, `1`.
  - in 107: `107`, reqId, whiteBrandingId (no version).

- [ ] **Step 1: Write the failing tests**
  - Codec:
    - `RequestTests`: `.currentTime` → `body("49","1")`, `.managedAccounts` → `body("17","1")`,
      `.userInfo(requestID: 8)` → `body("104","8")`, `.serverLogLevel(.detail)` → `body("14","1","5")`,
      `.globalCancel` → `body("58","1")`.
    - `DecoderTests`: `body("107","8","IBKR")` → `.userInfo(requestID: 8, whiteBrandingID: "IBKR")`, and
      `body("107")` → `.malformed` with id 107.
  - `IBClientSessionTests`. The connected helper is as in `IBClientAccountTests`, and `onRequest` answers:
    - `currentTimeAsksAndDecodes`: sends `["49","1"]`; the answer `["49","1","1700000000"]` returns
      `Date(timeIntervalSince1970: 1_700_000_000)`.
    - `managedAccountsAsks`: sends `["17","1"]`; `["15","1","DU1,DU2"]` → `["DU1","DU2"]`.
    - `nextOrderIDMergesIBsAnswer`: sends `["8","1","1"]`; the answer `["9","1","40"]` returns 40, and a following
      `placeOrder` returns 40.
    - `userInfoAsksByReqId`: sends `["104", id]`; `["107", id, ""]` → `""`. An error
      `["4","2",id,"322","Error processing request",""]` throws `.ib(code: 322, …)`.
    - `currentTimeEndsWithTheConnection` (Review Focus 2): no answer; `gateway.close()` → throws
      `.connectionClosed` within 2 s; `requestStreamCount == 0`.
    - `currentTimeHonoursCancellation`: the calling task is cancelled → `.cancelled`, `requestStreamCount == 0`.
    - `twoCurrentTimeCallsTakeOneAnswerEach`: two concurrent calls. Once both `["49","1"]` are sent, feed
      `["49","1","1700000000"]` and `["49","1","1700000001"]` → both calls return, and the two dates differ.
    - `settingsSendTheirFrames`: `setServerLogLevel(.detail)` → `["14","1","5"]`; `setAutoOpenOrders(true)` →
      `["15","1","1"]`; `cancelAllOrders()` → `["58","1"]`.
    - `sessionCallsNeedAConnection`: each of the seven throws `.notConnected` before `connect`.
  - `PublicAPITests`: `ServerLogLevel(rawValue: 5) == .detail`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "IBClientSessionTests|RequestTests|DecoderTests"`. Expected:
  a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above, and add `.userInfo` to `routeToStream`'s reqId cases.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («Add the session requests: current time, accounts, next id, user info, log level, auto-bind, global cancel»).

### Task 3: Account codec

**Files:**
- Modify: `Sources/IBKR/Models/Account.swift`, `IBMessage.swift`, `IBDecoder.swift`, `IBRequest.swift`
- Test: `Tests/IBKRTests/AccountCodecTests.swift`, `PublicAPITests.swift`
- Docs: protocol-178 (in 6, 7, 8, 54, 71, 72, 73, 74, 94; out 6, 64, 74, 75, 76, 77, 92, 93), CHANGELOG

**Interfaces:**
- Produces:
  - `AccountValue` and `Position` each gain `public var modelCode: String`, as the last init parameter with a
    default of `""`.
  - `public struct PortfolioItem: Sendable, Equatable { account: String; contract: Contract; quantity: Decimal;
    marketPrice: Decimal; marketValue: Decimal; averageCost: Decimal; unrealizedPNL: Decimal?; realizedPNL: Decimal? }`
  - `public struct AccountPnL: Sendable, Equatable { daily: Decimal?; unrealized: Decimal?; realized: Decimal? }`
  - `IBMessage`:
    - `.accountValue(AccountValue)` (6), `.portfolioItem(PortfolioItem)` (7), `.accountTime(String)` (8),
      `.accountDownloadEnd(account: String)` (54);
    - `.positionMulti(requestID: Int, Position)` (71), `.positionMultiEnd(requestID: Int)` (72);
    - `.accountUpdateMulti(requestID: Int, AccountValue)` (73), `.accountUpdateMultiEnd(requestID: Int)` (74);
    - `.pnl(requestID: Int, AccountPnL)` (94).
  - `IBRequest`:
    - `.accountUpdates(subscribe: Bool, account: String)` (6), `.cancelPositions` (64);
    - `.positionsMulti(requestID: Int, account: String, modelCode: String)` (74), `.cancelPositionsMulti(requestID: Int)` (75);
    - `.accountUpdatesMulti(requestID: Int, account: String, modelCode: String, ledgerAndNLV: Bool)` (76),
      `.cancelAccountUpdatesMulti(requestID: Int)` (77);
    - `.pnl(requestID: Int, account: String, modelCode: String)` (92), `.cancelPnL(requestID: Int)` (93).
- Wire (incoming):
  - in 6: id, version, key, value, currency, accountName.
  - in 7: id, version, then an 11-field contract (conId, symbol, secType, lastTradeDateOrContractMonth, strike,
    right, multiplier, **primaryExchange**, currency, localSymbol, tradingClass), position, marketPrice,
    marketValue, averageCost, unrealizedPNL, realizedPNL, accountName. Total: 20 fields.
    - Read the contract with `contract(&r)`, then move its `exchange` into `primaryExchange` and set `exchange` to `""`.
  - in 8: id, version, timestamp. in 54: id, version, accountName.
  - in 71: id, version, reqId, account, the 11-field contract exactly as `contract(&r)` reads it (with exchange),
    position, avgCost, modelCode. Total: 18 fields.
  - in 72 and 74: id, version, reqId. in 73: id, version, reqId, account, modelCode, key, value, currency.
  - in 94: id, reqId, dailyPnL, unrealizedPnL, realizedPnL (no version; each may be unset).
- Wire (outgoing):
  - out 6: `6`, `2`, subscribe, acctCode. out 64: `64`, `1`.
  - out 74: `74`, `1`, reqId, account, modelCode. out 75: `75`, `1`, reqId.
  - out 76: `76`, `1`, reqId, account, modelCode, ledgerAndNLV. out 77: `77`, `1`, reqId.
  - out 92: `92`, reqId, account, modelCode. out 93: `93`, reqId.

- [ ] **Step 1: Write the failing tests** in `AccountCodecTests.swift`. Let `c` be AAPL with conID 265598,
  secType STK, strike 0, currency USD, localSymbol AAPL and tradingClass NMS.
  - `accountValueDecodes`: `["6","2","NetLiquidation","100000.50","USD","DU1"]` →
    `.accountValue(AccountValue(account: "DU1", tag: "NetLiquidation", value: "100000.50", currency: "USD"))`.
  - `portfolioItemDecodes`:
    `["7","8","265598","AAPL","STK","","0.0","","","NASDAQ","USD","AAPL","NMS","5","187.25","936.25","180.5","33.75","1.7976931348623157E308","DU1"]`
    → `.portfolioItem(PortfolioItem(account: "DU1", contract: c, quantity: 5, marketPrice: d("187.25"),
    marketValue: d("936.25"), averageCost: d("180.5"), unrealizedPNL: d("33.75"), realizedPNL: nil))`, where `c`
    has `primaryExchange == "NASDAQ"` and `exchange == ""`.
  - `accountTimeAndDownloadEndDecode`: `["8","1","14:35"]` → `.accountTime("14:35")`, and `["54","1","DU1"]` →
    `.accountDownloadEnd(account: "DU1")`.
  - `positionMultiDecodes`:
    `["71","1","5","DU1","265598","AAPL","STK","","0.0","","","NASDAQ","USD","AAPL","NMS","10","180.5","M1"]` →
    `.positionMulti(requestID: 5, Position(account: "DU1", contract: c′, quantity: 10, averageCost: d("180.5"), modelCode: "M1"))`,
    where `c′.exchange == "NASDAQ"`. Also `["72","1","5"]` → `.positionMultiEnd(requestID: 5)`.
  - `accountUpdateMultiDecodes`: `["73","1","6","DU1","M1","NetLiquidation","100000.50","USD"]` →
    `.accountUpdateMulti(requestID: 6, AccountValue(account: "DU1", tag: "NetLiquidation", value: "100000.50", currency: "USD", modelCode: "M1"))`.
    Also `["74","1","6"]` → `.accountUpdateMultiEnd(requestID: 6)`.
  - `accountPnLDecodes`: `["94","7","12.5","-3.25","1.7976931348623157E308"]` →
    `.pnl(requestID: 7, AccountPnL(daily: d("12.5"), unrealized: d("-3.25"), realized: nil))`.
  - `shortAccountUpdateFramesAreMalformed`: `["7","8","265598"]`, `["73","1","6"]` and `["94","7"]` decode to
    `.malformed` with ids 7, 73 and 94.
  - `accountUpdateRequestsEncode`:
    - `.accountUpdates(subscribe: true, account: "DU1")` → `body("6","2","1","DU1")`; `.cancelPositions` → `body("64","1")`.
    - `.positionsMulti(requestID: 5, account: "DU1", modelCode: "")` → `body("74","1","5","DU1","")`;
      `.cancelPositionsMulti(requestID: 5)` → `body("75","1","5")`.
    - `.accountUpdatesMulti(requestID: 6, account: "DU1", modelCode: "", ledgerAndNLV: false)` →
      `body("76","1","6","DU1","","0")`; `.cancelAccountUpdatesMulti(requestID: 6)` → `body("77","1","6")`.
    - `.pnl(requestID: 7, account: "DU1", modelCode: "")` → `body("92","7","DU1","")`; `.cancelPnL(requestID: 7)` → `body("93","7")`.
  - `PublicAPITests`: build a `PortfolioItem` and an `AccountPnL`, plus an `AccountValue` and a `Position` with a
    `modelCode`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter AccountCodecTests`. Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS, including `everyRecordedFrameDecodes`.
- [ ] **Step 5: Docs and commit** («Decode portfolio, account values, Multi updates and account P&L, and encode their requests»).

### Task 4: AccountTracker

**Files:**
- Create: `Sources/IBKR/State/AccountTracker.swift`, `Tests/IBKRTests/AccountTrackerTests.swift`

**Interfaces:**
- Consumes: Task 3's models and messages.
- Produces (internal, pure value, no I/O):
  - `struct AccountTracker: Sendable { init() }`, with:
    - `var portfolio: [PortfolioItem] { get }`, sorted by account, then conID;
    - `var values: [AccountValue] { get }`, sorted by account, modelCode, tag, currency.
  - `mutating func reload()`: from now on, portfolio items are collected aside, and they replace the visible set
    whole at `.accountDownloadEnd`, like `PositionTracker`.
  - `mutating func apply(_ message: IBMessage) -> AccountChange?`, where
    `enum AccountChange: Equatable { case portfolio([PortfolioItem]), value(AccountValue) }`.
    - `.accountValue` and `.accountUpdateMulti` upsert by (account, modelCode, tag, currency) and return
      `.value(v)` only when the value changed.
    - `.portfolioItem` upserts by (account, conID); quantity 0 removes. It returns `.portfolio(set)` when the
      visible set changed, or `nil` while reloading.
    - `.accountDownloadEnd` ends a reload and returns its set. Outside a reload it returns `nil`. Anything else
      returns `nil`.
    - The caller filters `.accountUpdateMulti` by reqId (Task 5).

- [ ] **Step 1: Write the failing tests.** Helpers: `item(_ account: String, _ conID: Int, _ qty: String) -> IBMessage`,
  `value(_ tag: String, _ v: String, model: String = "") -> IBMessage`.
  - `portfolioItemReplacesByAccountAndConID`: `item("DU1",1,"5")`, then `item("DU1",1,"3")` → a set of one, with
    quantity 3.
  - `zeroPortfolioItemIsRemoved`: after `item("DU1",1,"5")`, `item("DU1",1,"0")` → `.portfolio([])`.
  - `portfolioIsSortedByAccountThenConID`: applying `("DU2",1)`, `("DU1",2)`, `("DU1",1)` gives the order DU1/1,
    DU1/2, DU2/1.
  - `reloadPublishesThePortfolioOnlyAtDownloadEnd`: with `[DU1/1]` visible, `reload()`; then `item("DU1",2,"1")`
    → `nil`, and `portfolio` is still `[DU1/1]`; then `.accountDownloadEnd(account: "DU1")` → `.portfolio([DU1/2])`.
  - `accountValuePublishesOnlyChanges`: `value("NetLiquidation","100")` → `.value(…)`; the same again → `nil`;
    `"101"` → `.value(…)`; `values.count == 1`.
  - `modelCodeKeepsValuesApart`: the same tag with models `""` and `"M1"` → `values.count == 2`, `""` first.
  - `unrelatedMessagesChangeNothing`: `.positionEnd`, and an `.accountDownloadEnd` outside a reload → `nil`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter AccountTrackerTests`. Expected: a compile FAIL.
- [ ] **Step 3: Implement** with dictionaries; sort when publishing.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Commit** («Track the portfolio and account values, replacing the portfolio whole after a reload»).

### Task 5: Account sync at connect, `portfolio()` and `accountValues()`

**Files:**
- Modify: `Sources/IBKR/Client/IBClient.swift`, `Tests/IBKRTests/FakeGateway.swift` (also receives the `Gateways`
  actor, moved unchanged out of `IBClientConnectTests.swift`), and every client test that
  counts sent frames (`DepthTests`, `HistoricalTests`, `IBClientAccountTests`, `IBClientConnectTests`,
  `IBClientLookupTests`, `IBClientMarketDataTests`, `IBClientOrderTests`, `TickByTickTests`, `IBClientSessionTests`)
- Create: `Tests/IBKRTests/IBClientPortfolioTests.swift`
- Docs: README («Connecting»: what `connect` syncs; «Executions and positions» becomes «Executions, positions and
  portfolio»), DECISIONS (decisions 3–4, and the connect-time sync row extended), CHANGELOG

**Interfaces:**
- Consumes: `AccountTracker` (Task 4); `.accountUpdates`, `.accountUpdatesMulti` (Task 3).
- Produces:
  - `public func portfolio() -> (snapshot: [PortfolioItem], updates: AsyncStream<[PortfolioItem]>)`
  - `public func accountValues() -> (snapshot: [AccountValue], updates: AsyncStream<AccountValue>)`
  - `sync()` sends, after `.positions`:
    - with exactly one account: `.accountUpdates(subscribe: true, account: a)`, waiting for
      `.accountDownloadEnd(account: a)`. `connect` calls `accountTracker.reload()` only on this path.
    - otherwise, per account in order: `id = nextRequestID()`, then
      `.accountUpdatesMulti(requestID: id, account: a, modelCode: "", ledgerAndNLV: false)`, waiting for
      `.accountUpdateMultiEnd(requestID: id)`.
  - The Multi ids form `accountSyncIDs: Set<Int>`, reset at each connect. Only `.accountUpdateMulti` with one of
    those ids reaches the tracker.
  - A `failsRequest` error with one of those ids fails `connect`, like the reqExecutions one.
  - The tracker lives across connections.
  - `FakeGateway`:
    - a new init flag `answersAccountUpdates: Bool = true`;
    - it answers `6` with subscribe `1` by `["54","1",fields[3]]`, and `76` by `["74","1",fields[2]]`;
    - `static let syncFrames = 6` (71, 16, 99, 7, 61, 6 for one account).
    - Existing tests replace literal counts with it: `waitForSent(6)[5]` becomes
      `waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames]`.

- [ ] **Step 1: Write the failing tests** (position and portfolio frames as in Task 3)
  - `IBClientConnectTests.connectReachesConnectedAfterSync` now expects `["71","16","99","7","61","6"]`, with
    `sent[5] == ["6","2","1","DU1"]`.
  - `connectSyncsTheSingleAccount`: `onRequest` answers `6` with one `6` frame and one `7` frame → after
    `connect`, `accountValues().snapshot` is that value and `portfolio().snapshot` is that item.
  - `connectWaitsForAccountDownloadEnd`: `FakeGateway(answersAccountUpdates: false)` and
    `connect(timeout: .milliseconds(300))` → `.timeout`.
  - `severalAccountsSyncThroughMulti` (Review Focus 3): `FakeGateway(accounts: "DU1,DU2")`. The frames after `61`
    are `["76","1",id1,"DU1","","0"]` and `["76","1",id2,"DU2","","0"]`, and no `6`. `onRequest` answers each `76`
    with `["73","1",r[2],r[3],"","NetLiquidation","100","USD"]`. After `connect`, `accountValues().snapshot` has
    DU1 and DU2, and `portfolio().snapshot` is empty.
  - `fatalErrorOnAccountSyncFailsConnect`: accounts `"DU1,DU2"`, and `76` for DU2 is answered with
    `["4","2",r[2],"322","Error processing request",""]` → `connect` throws `.ib(code: 322, …)`.
  - `portfolioChangeIsPublishedAsAWholeSet`: connected with one item; subscribe; feed a second `7` → the next
    update holds 2 items.
  - `accountValueChangeIsPublishedOnce`: feed the same `6` frame twice, then a changed one → the updates are
    exactly the first value and the changed one.
  - `reconnectReplacesPortfolioWhole`: connect with DU1/1, subscribe, disconnect, then reconnect with DU1/2 (two
    gateways) → the next update is exactly `[DU1/2]`.
  - Every existing test uses `FakeGateway.syncFrames`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "IBClientPortfolioTests|IBClientConnectTests"`. Expected: FAIL.
- [ ] **Step 3: Implement** the Interfaces above, and add `.accountDownloadEnd` and the Multi end markers to
  `syncEnds`.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («Sync the portfolio and account values at connect and keep them streaming»).

### Task 6: Multi subscriptions and account P&L as request streams

**Files:**
- Modify: `Sources/IBKR/Client/IBClient.swift`, `Tests/IBKRTests/IBClientAccountTests.swift`
- Docs: README («Account summary and P&L» gains the three calls), DECISIONS (consumer Multi streams do not feed
  `accountValues()`), CHANGELOG

**Interfaces:**
- Consumes: Task 3's requests and messages; `openStream`; `accountSyncIDs` (Task 5).
- Produces:
  - `public func accountUpdatesMulti(account: String, modelCode: String = "", ledgerAndNLV: Bool = false) throws(IBClientError) -> AsyncThrowingStream<[AccountValue], any Error>`
    - The set is keyed and sorted by (account, modelCode, tag, currency).
    - It yields at IB's first end marker, then on every change, never repeating the last set (as `accountSummary`).
    - Cancel: `.cancelAccountUpdatesMulti`.
  - `public func positionsMulti(account: String, modelCode: String = "") throws(IBClientError) -> AsyncThrowingStream<[Position], any Error>`
    - The set is keyed by (account, modelCode, conID), and quantity 0 removes; it is sorted the same way.
    - It yields like `accountUpdatesMulti`. Cancel: `.cancelPositionsMulti`.
  - `public func pnl(account: String, modelCode: String = "") throws(IBClientError) -> AsyncThrowingStream<AccountPnL, any Error>`
    yields every update. Cancel: `.cancelPnL`.
  - `routeToStream` gains `.positionMulti`, `.positionMultiEnd`, `.accountUpdateMulti`, `.accountUpdateMultiEnd`
    and `.pnl`. The «set at end, then on change» rule is shared with `accountSummary` through one private helper.

- [ ] **Step 1: Write the failing tests**
  - `accountUpdatesMultiYieldsTheSetAtEnd`: sends `["76","1",id,"DU1","","0"]`. Feed BuyingPower and
    NetLiquidation `73` frames and `["74","1",id]` → the first element is both, BuyingPower first.
  - `positionsMultiYieldsTheSetAtEndAndDropsZero`: sends `["74","1",id,"DU1",""]`. Two `71` frames (conIDs 1 and
    2) and `["72","1",id]` → 2 positions. A `71` for conID 1 with quantity `0` → the next element is `[conID 2]`.
  - `pnlYieldsEachUpdate`: sends `["92",id,"DU1",""]`. Two `94` frames come out in order; an unset realized is `nil`.
  - `stoppingMultiStreamsSendsTheirCancels`: taking one element from each stream sends `["77","1",id]`,
    `["75","1",id]` and `["93",id]`; `requestStreamCount == 0`.
  - `accountPnLErrorEndsItsStream`: `["4","2",id,"322","Error processing request",""]` →
    `.ib(code: 322, text: "Error processing request")`.
  - `consumerMultiStreamDoesNotTouchAccountValues`: `accountUpdatesMulti(account: "DU1", modelCode: "M1")` fed a
    `73` with its id → the stream yields it, and `accountValues().snapshot` has no `M1` entry.
  - `requestStreamsNeedAConnection`: add the three calls.
- [ ] **Step 2: Run** `timeout 900 swift test --filter IBClientAccountTests`. Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («Stream Multi account updates, Multi positions and account P&L per request»).

### Task 7: Cancellable `connect`, draining `disconnect` with cancelPositions

**Files:**
- Modify: `Sources/IBKR/Client/IBClient.swift`, `Sources/IBKR/Client/IBClientError.swift` (the `.cancelled` doc
  also covers `connect`), `Tests/IBKRTests/FakeGateway.swift` (`func waitUntilClosed() async throws`, polling
  `isClosed` for at most 2 s), `IBClientConnectTests.swift`, `IBClientAccountTests.swift`
  (`disconnectEndsRequestStreams`)
- Docs: README («Connecting»: cancellation; what `disconnect` sends), DECISIONS (decision 7), KNOWN-GAPS (drop
  «connect ignores … cancellation» and «placeOrder then an immediate disconnect() can drop the queued frame»; add
  to the test gaps: «the 2 s close bound of a draining disconnect is untested; FakeGateway's write never blocks»),
  protocol-178 (out 64: sent only by `disconnect()` from `.connected`), CHANGELOG

**Interfaces:**
- Produces:
  - `connect` honours task cancellation, both while the connector runs and while the handshake and sync run.
    - It throws `.cancelled`, closes the transport, and leaves `.disconnected(.cancelled)`.
    - A connector that throws `CancellationError` maps to `.cancelled`, not `.transport`.
    - Approach: `withTaskCancellationHandler`, whose handler hops to the actor and calls `end(.cancelled)` if the
      generation is unchanged.
  - `disconnect()`:
    - From `.connected`, it queues `.cancelPositions` and finishes the outbox. The writer closes the transport after
      the last queued frame, and a timer closes it 2 s later at the latest.
    - From `.connecting`, it closes at once and sends no 64.
    - In both cases `.disconnected(nil)` is published and the request streams end immediately, as now.
  - A drop or an error end closes at once, as now.

- [ ] **Step 1: Write the failing tests** in `IBClientConnectTests`
  - `cleanDisconnectSendsCancelPositionsThenCloses`: `disconnect()` → the last frame of
    `waitForSent(FakeGateway.syncFrames + 1)` is `["64","1"]`, and `waitUntilClosed()` returns.
  - `queuedFramesLeaveBeforeTheClose`: `placeOrder` then `disconnect()` with no await between them → the sent
    frames end with the `3` frame, then `["64","1"]`.
  - `peerCloseSendsNoCancelPositions`: `gateway.close()` → after 100 ms, the sent count is still `syncFrames`.
  - `disconnectWhileConnectingSendsNoCancelPositions`: `FakeGateway(answersStartAPI: false)`; disconnect after
    `waitForSent(1)` → `connect` throws `.connectionClosed`; no `64` was sent.
  - `connectHonoursCancellation` (Review Focus 4): `FakeGateway(answersStartAPI: false)`; cancel the connecting
    task after `waitForSent(1)` → it throws `.cancelled` within 2 s; the state is `.disconnected(.cancelled)`;
    `gateway.isClosed`. A second `connect` through a fresh gateway reaches `.connected`.
  - `cancelWhileTheConnectorWaits`: a connector that does `try await Task.sleep(for: .seconds(5))` → cancelling
    throws `.cancelled` within 2 s.
  - Update `disconnectReportsNoError` (wait with `waitUntilClosed()` before `#expect(one.isClosed)`), and the
    `disconnect()` arm of `disconnectEndsRequestStreams`: the only frame after the end is `["64","1"]`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "IBClientConnectTests|IBClientAccountTests"`. Expected: FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («Let a cancelled task stop connect, and drain the queue and cancel positions on disconnect»).

### Task 8: Opt-in reconnect with a reqCurrentTime probe

**Files:**
- Create: `Sources/IBKR/Client/ReconnectPolicy.swift`, `Tests/IBKRTests/IBClientReconnectTests.swift`
- Modify: `Sources/IBKR/Client/IBClient.swift` (`connect`, `end`, `setState`, the class doc comment),
  `Tests/IBKRTests/FakeGateway.swift` (extend `Gateways`, moved there in Task 5),
  `PublicAPITests.swift`
- Docs: README («Connecting»: «No automatic reconnect» becomes «Reconnect is opt-in», with an example, and a note
  that request streams end and `setMarketDataType` must be set again), DECISIONS (rewrite row 32 «nothing reconnects
  automatically» to «reconnect is opt-in»; a new row with decision 8), CHANGELOG

**Interfaces:**
- Consumes: the connect path, `end()`, `.currentTime` (Task 2), and the draining `disconnect()` (Task 7).
- Produces:
  - ```swift
    public struct ReconnectPolicy: Sendable, Equatable {
        public var delays: [Duration]      // pause before attempt n is delays[min(n-1, count-1)]; empty = none
        public var maxAttempts: Int?       // per drop; nil = until disconnect()
        public var probeAfter: Duration?   // silence before a reqCurrentTime probe; nil = no probe
        public init(delays: [Duration] = [.seconds(1), .seconds(2), .seconds(5), .seconds(10), .seconds(30)],
                    maxAttempts: Int? = nil, probeAfter: Duration? = .seconds(30))
    }
    ```
  - `connect(host:port:clientID:timeout:reconnect: ReconnectPolicy? = nil)`. A successful `connect` stores the
    policy with host, port, clientID and timeout. `disconnect()` clears it and cancels a running reconnect task.
  - When a connection that reached `.connected` ends with an error while a policy is stored:
    - the client publishes `.disconnected(error)`, then `.connecting`;
    - an actor-owned task pauses and reruns the connect path, each attempt bounded by `timeout`;
    - a failed attempt publishes nothing;
    - success publishes `.connected`, and giving up after `maxAttempts` publishes `.disconnected(lastError)`;
    - `connect` during the loop throws `.alreadyConnected`;
    - `setState` skips a state equal to the current one.
  - Probe, only while `.connected` with a non-nil `probeAfter`:
    - after `probeAfter` with no incoming frame, the client sends `.currentTime`;
    - if another `probeAfter` passes with no frame, it ends with `.timeout`, which starts the reconnect.
  - Reconnect replays nothing outside the sync. Request streams end with the error at the drop (`end()` as now),
    and `setMarketDataType` is not resent.
  - Test helper: `actor Gateways { init(_ list: [FakeGateway]); var connects: Int { get }; func next() throws(IBClientError) -> FakeGateway; nonisolated var connector: Connector { get } }`.
    `next()` throws `.transport("refused")` once the list is empty.

- [ ] **Step 1: Write the failing tests** in `IBClientReconnectTests`. Use `policy = ReconnectPolicy(delays:
  [.milliseconds(10)], probeAfter: nil)` unless a test says otherwise. A `states()` stream is opened before the drop.
  - `dropReconnectsAndKeepsSubscribers`: gateways `[one, two]`. Subscribe to `positions()`; `one.close()`.
    - The states after the first `ready` are exactly `.disconnected(.connectionClosed)`, `.connecting`, `ready`.
    - `two` received the full sync.
    - A position frame fed on `two` reaches the subscriber taken before the drop.
  - `requestStreamsEndAndAreNotReplayed`: an open `accountSummary` stream and `setMarketDataType(.delayed)` before
    the drop → the stream ends with `.connectionClosed`; after `ready`, `two`'s sent frames hold no `62` and no `59`.
  - `reconnectGivesUpAfterMaxAttempts` (Review Focus 1): gateways `[one]` and `maxAttempts: 2` → the states after
    `ready` are exactly `.disconnected(.connectionClosed)`, `.connecting`, `.disconnected(.transport("refused"))`;
    `connects == 3`.
  - `disconnectStopsReconnecting` (Review Focus 1): gateways `[one]` and `delays: [.milliseconds(200)]`. After the
    drop and `.connecting`:
    - `connect` throws `.alreadyConnected`;
    - `disconnect()` → `.disconnected(nil)`;
    - after 400 ms, `connects == 1` and the state is still `.disconnected(nil)`.
  - `manualDisconnectDoesNotReconnect`: `disconnect()` from `.connected` → after 100 ms, `connects == 1`.
  - `firstConnectFailureIsNotRetried`: gateways `[]` → `connect(reconnect: policy)` throws `.transport("refused")`;
    after 100 ms, `connects == 1`.
  - `silentConnectionIsProbedThenDropped`: `probeAfter: .milliseconds(100)` and gateways `[one, two]`, where `one`
    never answers `49` →
    - `one` received `["49","1"]`, then closed;
    - the states show `.disconnected(.timeout)`, then `ready`.
  - `answeredProbeKeepsTheConnection`: `probeAfter: .milliseconds(50)`, and `one` answers `49` with
    `["49","1","1700000000"]` → after 400 ms the state is still `ready`, `one` is open, and at least two
    `["49","1"]` were sent.
  - `PublicAPITests`: `ReconnectPolicy().maxAttempts == nil` and `ReconnectPolicy(probeAfter: nil).probeAfter == nil`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter IBClientReconnectTests`. Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test` three times. Expected: PASS every time, since timing-based tests must
  not flake.
- [ ] **Step 5: Docs and commit** («Reconnect on request with paused attempts and a reqCurrentTime probe»).

### Stage close

- [ ] README «Status»:
  - a Session row: «current time, accounts, next id, user info, log level, auto-bind, global cancel, opt-in
    reconnect»;
  - the Account row adds «portfolio, account values, Multi, account P&L», marked as checked on the fake gateway (a
    live run is due in stage 13);
  - the KNOWN-GAPS heading becomes «Known gaps after stage 6».
  - Commit («Record stage 6 in the status table»).
- [ ] Verify the series: `git rebase --exec "timeout 900 swift test > /dev/null" main`.
- [ ] Push `stage-6-session-account` and watch CI with the command under Global Constraints. Expected: every job
  green. If a job fails, fix it at its root in a new commit, with no weakened test, and watch again.
