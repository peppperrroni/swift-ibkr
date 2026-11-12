# Stage 7: Orders, Complete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `placeOrder` sends every field `ib_async` sends, including conditions, algos, pegged orders, BAG combos,
delta neutral, scale, hedge, soft dollar tier, cash quantity and adjusted orders. `openOrder` and `completedOrder`
decode the same fields. A what-if order returns its `OrderState`, and `exerciseOptions` and the order helpers
(factories, bracket, OCA) are added. The order tracker closes the three stage-7 KNOWN-GAPS items: the 202 reason, the
early `.filled`, and `parentPermId`.

**Architecture:** The `placeOrder` table in `docs/protocol-178.md` is already complete, so the work is model plus
codec, one field group at a time:
- Task 1 encodes the plain rows and Task 2 decodes them.
- Task 3 adds the combo, delta-neutral, scale and hedge groups, and Task 4 adds algo, PEG, the conditions and the
  170 tail. Each task carries both directions, so `.unsupported` goes away group by group.
- Task 5 adds `OrderState` and `whatIfOrder` on top of the decoder.
- Task 6 changes only the pure `OrderTracker`.
- Tasks 7 and 8 add client calls (`cancelOrder`'s manual time, `exerciseOptions`, `placeBracket`) and the
  value-type helpers.
- Task 9 closes the stage.

**Tech Stack:** Swift 6 (tools 6.0), SwiftPM, Foundation, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-12-parity-and-1.0-design.md`: «Этапы» item 7, «Перечень» row Ордера, and
«Решения после проверки строителем» item 2 (stage 7). The base spec is `docs/superpowers/specs/2026-11-09-swift-ibkr-design.md`.

## Global Constraints

- Repository `C:\Users\viohn\swift-ibkr`, branch `stage-7-orders` off `main` (8a44c64).
- No package dependencies; `Package.swift` keeps `// swift-tools-version: 6.0`.
- Money and quantities are `Decimal`. IB's unset markers read as `nil` through `FieldReader.optional…()`. Use
  `d("…")` in tests.
- Field orders come from `ib_async` 2.1.0 (`ab629f3`, `client.py` `placeOrder`, `decoder.py` `openOrder` /
  `completedOrder`). They are already in `docs/protocol-178.md`, and this plan's test arrays restate them. Never
  copy code from IB's official `ibapi`. We always negotiate 178, so every field gated at or below 178 is on the wire.
- Orders and requests share ONE id counter (`IBClient.nextRequestID()`).
- Swift names are `ib_async`'s, with `Id` → `ID`, `Rth` → `RTH` and `lmt` → `limit`, as for the existing fields
  (`parentID`, `outsideRTH`, `limitPrice`).
- `Order` and `Contract` keep their existing inits. Every new stored property has a default in its declaration
  (`nil` for an unset number). Every new public value type gets a public memberwise init and joins
  `PublicAPITests.everyPublicModelIsConstructible` (plain `import IBKR`).
- `FieldWriter.addDouble(_ value: Decimal)` writes a `Double`'s text (`0` → `0.0`, `180.5` → `180.5`). It covers
  the `ib_async` floats whose default is not unset: contract strike, `discretionaryAmt`, `peggedChangeAmount`,
  `referenceChangeAmount`, a condition's `price` and `changePercent`, and the delta-neutral contract's `delta` and
  `price`. Every other `Decimal?` is written as its `description`, and `nil` as `""`.
- The recorded live frames keep decoding: `everyRecordedFrameDecodes` and the `recorded…` tests stay green. Their
  expectations change only where a task says so.
- Commit messages are one imperative sentence, then the reasoning. Read `git log` first. The last line is exactly
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- The documents of record (`README.md`, `docs/DECISIONS.md`, `docs/KNOWN-GAPS.md`, `docs/protocol-178.md`,
  `CHANGELOG.md`) change in the same commit as the behaviour they describe. Every public API change gets a
  CHANGELOG `Unreleased` line (Added / Changed). Task 9 rewrites the README Orders section and checks the rest.
- Run tests as `timeout 900 swift test`, in the foreground. A test waits on an async event for at most 2 s
  (`within2s`).
- CI (macOS, Linux 6.0 and latest, Windows, pod-lint) must be green. Push the branch
  (`git push -u origin stage-7-orders`) and watch
  `gh run watch --exit-status $(gh run list --branch stage-7-orders --limit 1 --json databaseId -q '.[0].databaseId')`.
  Moving and pushing `main` is the controller's job.
- The real paper account id never appears in the repo. Fixtures use `DU1` and `DU123456`, and recordings use `DU0000001`.

## Decisions taken in this plan (beyond the spec; record each in DECISIONS in its task's commit)

1. **Names.**
   - Calls: `whatIfOrder(_:_:)`, `exerciseOptions(_:action:quantity:account:override:)`, `placeBracket(_:_:)`, and
     `cancelOrder(_:manualOrderCancelTime:)`.
   - Helpers: `Order.market/limit/stop/stopLimit/bracket` and `Order.oneCancelsAll(_:group:type:)`.
   - Types: `TagValue`, `ComboLeg`, `OrderComboLeg`, `DeltaNeutralContract`, `SoftDollarTier`, `OrderCondition`,
     `CompeteOffset`, `OrderState`, `ExerciseAction` and `BracketOrder`.
2. **Model shape.**
   - `Order` and `Contract` stay one flat struct each, as in `ib_async`. There is no 120-parameter init.
   - Deprecated fields are not modelled: `sharesAllocation`, `eTradeOnly`, `firmQuoteOnly` and `nbboPriceCap`. They
     go out as the table's constants and are skipped on the way in. `faProfile` is absent at 178.
   - `ComboLeg.action` is an `OrderAction`, so an unknown one is `.malformed`, like the order's own action.
3. **Conditions** are one `enum OrderCondition` with six cases, each carrying its own `conjunction`.
   `competeAgainstBestOffset` is `CompeteOffset?` (`.offset(Decimal)` or `.upToMid`), because `Decimal` has no +∞
   and the wire sends `Infinite`.
4. **`OrderState`.**
   - It holds the nine margins, three commissions, `commissionCurrency` and `warningText`, all as `Decimal?` (or
     `String`). `ib_async` keeps the margins as strings.
   - It has no `status`, which stays on `OpenOrderMessage` and `OrderSnapshot`. `completedTime` and
     `completedStatus` stay on `CompletedOrderMessage`.
   - `OpenOrderMessage.state` carries it, and the snapshot does not.
5. **`volatility`** is sent only when `orderType` starts with `VOL`, else `""`, as `ib_async` does, because IB
   back-fills it into live orders and then rejects their modification.
6. **Decoded `None`.** Values a gateway sends are kept as sent: `deltaNeutralOrderType` and `adjustedOrderType`
   `None`, `openClose` `""`, `clearingIntent` `IB`. `modifyOrder` with a decoded order re-sends them as
   `ib_async` would, and the live check is a KNOWN-GAPS item.
7. **What-if.**
   - `whatIfOrder` sends placeOrder with `whatIf` set under a fresh id. It returns the `state` of the first whatIf
     openOrder for that id whose `initMarginChange` is set, as `ib_async` does.
   - It throws like `userInfo`.
   - WhatIf openOrders never reach `orders()`.
   - `placeOrder` and `modifyOrder` refuse `order.whatIf` with `.encoding(.unsupported("whatIf"))`: such an order
     would sit `.apiPending` forever.
8. **Tracker.**
   - A 202 keeps its text as `rejectReason` when non-blank text follows `reason:`, and a bare cancel keeps `nil`.
   - An openOrder with status Filled is held, unpublished, while the order has `filled` 0. The next orderStatus
     (or a completedOrder for its permID) publishes it.
   - A joined completedOrder also copies `parentPermID`.
   - `OrderSnapshot.advancedOrderRejectJSON` takes a non-empty JSON from any non-notice error for the order.
9. **`exerciseOptions`** is fire-and-forget and returns its reqId. IB answers success with nothing, so an error with
   that id reaches only `messages()`. `override` is a `Bool`.
10. **`placeBracket`** takes three consecutive ids and sets the children's `parentID` and the three `transmit`
    flags (false, false, true). It encodes all three before queuing any, so an encoding error sends nothing.
11. **`contractDetails`** sends the contract's `secIDType` and `secID`, which until now were constant `""`. Once
    `Contract` has them, ignoring them would be a silent trap.
12. **`orderBound` (in 100)** is decoded and merged since stage 2 (`OrderTrackerTests.orderBoundLinks`). Stage 7 adds
    only a client-level test.
13. **BAG** is accepted by `placeOrder` only. Every other request still throws `.unsupported("secType BAG")` until
    stages 8 and 9.

## Review Focus

1. **Modifying an order taken from `orders()`.** Its `order` was decoded from a live openOrder (`None`s,
   `clearingIntent` `IB`, back-filled `trailStopPrice`). It must encode without throwing, in the layout
   `ib_async` would send. Test: Task 3 `decodedLiveOrderReencodes`.
2. **A Filled openOrder whose orderStatus never comes** (an order filled while the client was away). It must not
   vanish, and the completedOrder for its permID shows it, filled. Test: Task 6
   `heldFilledOpenOrderShowsThroughCompletedOrder`.
3. **A what-if IB refuses** (error 201 for its id). `whatIfOrder` throws `.ib`, and no order appears in `orders()`.
   Test: Task 5 `whatIfOrderFailsOnItsError`.
4. **A bracket whose last leg fails to encode** (a non-ASCII `orderRef`). Nothing may go out: a parent queued with
   `transmit` false would sit at IB unseen. Test: Task 8 `placeBracketSendsNothingWhenALegFailsToEncode`.
5. **An openOrder with a condition type or conjunction this decoder does not know.** It is `.malformed` with a
   reason, with no crash and no misaligned fields. Test: Task 4 `unknownConditionIsMalformed`.

---

### Task 1: Plain placeOrder fields

**Files:**
- Create: `Sources/IBKR/Models/OrderParts.swift` (`TagValue`, `SoftDollarTier`; later tasks add the other value
  types here), `Sources/IBKR/Messages/PlaceOrderEncoding.swift` (the placeOrder encoder, moved out of
  `IBRequest.swift` as an internal `extension IBRequest`)
- Modify: `Sources/IBKR/Models/Order.swift`, `Sources/IBKR/Models/Contract.swift`, `Sources/IBKR/Wire/Fields.swift`,
  `Sources/IBKR/Messages/IBRequest.swift` (`contract(_:_:)` uses `addDouble`; `contractDetails` sends
  `secIDType`/`secID`)
- Test: `Tests/IBKRTests/PlaceOrderTests.swift`, `RequestTests.swift`, `PublicAPITests.swift`
- Docs: protocol-178 (the **★** convention line: ★ now marks every row the model carries, which is every
  placeOrder row except sharesAllocation, eTradeOnly, firmQuoteOnly and nbboPriceCap; row 62: sent only for `VOL`
  types), DECISIONS (decisions 2, 5 and 11; the names rule), KNOWN-GAPS (drop «a contract with non-default fields in
  placeOrder» from the test gaps), CHANGELOG (Added: the order fields; Changed: contractDetails sends secIdType/secId)

**Interfaces:**
- Produces:
  - `public struct TagValue: Sendable, Equatable, Hashable { public var tag: String; public var value: String }`
  - `public struct SoftDollarTier: Sendable, Equatable { public var name, value, displayName: String }`. Its init
    takes all three, each defaulting to `""`.
  - `Contract` gains `public var secIDType = ""` and `public var secID = ""` (placeOrder rows 14–15).
  - `Order` gains, declared in placeOrder row order (row numbers are the base-case table's):
    ```swift
    public var openClose = "O"                                   // 24
    public var origin = 0                                        // 25
    public var blockOrder = false, sweepToFill = false           // 29–30
    public var displaySize = 0, triggerMethod = 0                // 31–32
    public var hidden = false                                    // 34
    public var discretionaryAmt: Decimal = 0                     // 36, addDouble
    public var goodAfterTime = "", goodTillDate = ""             // 37–38
    public var faGroup = "", faMethod = "", faPercentage = ""    // 39–41
    public var modelCode = ""                                    // 42
    public var shortSaleSlot = 0, designatedLocation = "", exemptCode = -1   // 43–45
    public var rule80A = "", settlingFirm = ""                   // 47–48
    public var allOrNone = false                                 // 49
    public var minQty: Int?                                      // 50
    public var percentOffset: Decimal?                           // 51
    public var auctionStrategy = 0                               // 55
    public var startingPrice, stockRefPrice, delta, stockRangeLower, stockRangeUpper: Decimal?   // 56–60
    public var overridePercentageConstraints = false             // 61
    public var volatility: Decimal?                              // 62, "" unless orderType.hasPrefix("VOL")
    public var volatilityType: Int?                              // 63
    public var continuousUpdate = false                          // 66
    public var referencePriceType: Int?                          // 67
    public var trailStopPrice, trailingPercent: Decimal?         // 68–69
    public var scaleInitLevelSize, scaleSubsLevelSize: Int?      // 70–71
    public var scaleTable = "", activeStartTime = "", activeStopTime = ""   // 73–75
    public var optOutSmartRouting = false                        // 77
    public var clearingAccount = "", clearingIntent = ""         // 78–79
    public var notHeld = false                                   // 80
    public var algoID = ""                                       // 83
    public var whatIf = false                                    // 84
    public var orderMiscOptions: [TagValue] = []                 // 85, "tag=value;" joined in one field
    public var solicited = false, randomizeSize = false, randomizePrice = false   // 86–88
    public var adjustedOrderType = ""                            // 90
    public var triggerPrice, limitPriceOffset, adjustedStopPrice, adjustedStopLimitPrice, adjustedTrailingAmount: Decimal?  // 91–95
    public var adjustableTrailingUnit = 0                        // 96
    public var extOperator = ""                                  // 97
    public var softDollarTier = SoftDollarTier()                 // 98–99 name, value
    public var cashQty: Decimal?                                 // 100
    public var mifid2DecisionMaker = "", mifid2DecisionAlgo = "", mifid2ExecutionTrader = "", mifid2ExecutionAlgo = ""  // 101–104
    public var dontUseAutoPriceForHedge = false, isOmsContainer = false
    public var discretionaryUpToLimitPrice = false, usePriceMgmtAlgo = false   // 105–108
    public var duration: Int?, postToAts: Int?                   // 109–110
    public var autoCancelParent = false                          // 111
    public var advancedErrorOverride = "", manualOrderTime = ""  // 112–113
    ```
  - Rows that open a conditional group are still constants in this task: 64–65 `""`, 72 `""`, 76 `""`, 81 `0`,
    82 `""`, 89 `0`. Tasks 3 and 4 add those fields with their groups. The `.unsupported` checks stay as they are.
  - `mutating func addDouble(_ value: Decimal)` in `FieldWriter`.

- [ ] **Step 1: Write the failing tests** in `PlaceOrderTests.swift`
  - Move the 114-field array of `limitOrderMatchesProtocolTable` to file scope as `let base: [String]`. The test
    then compares against `base`, unchanged.
  - `everyPlainFieldIsSent`: order id 12, with this contract and order:
    ```swift
    var c = Contract(symbol: "AAPL", secType: "OPT", primaryExchange: "CBOE")
    c.conID = 12345; c.lastTradeDateOrContractMonth = "20261218"; c.strike = d("150"); c.right = "C"
    c.multiplier = "100"; c.localSymbol = "AAPL  261218C00150000"; c.tradingClass = "AAPL"
    c.secIDType = "ISIN"; c.secID = "US0378331005"
    var o = Order(action: .sell, quantity: d("100"), orderType: "VOL", limitPrice: d("187.25"), auxPrice: d("1.5"), tif: "GTC")
    o.ocaGroup = "g1"; o.account = "DU1"; o.openClose = "C"; o.origin = 1; o.orderRef = "r1"; o.transmit = false
    o.parentID = 9; o.blockOrder = true; o.sweepToFill = true; o.displaySize = 10; o.triggerMethod = 2
    o.outsideRTH = true; o.hidden = true; o.discretionaryAmt = d("0.05")
    o.goodAfterTime = "20261112 09:30:00"; o.goodTillDate = "20261113 16:00:00"
    o.faGroup = "G"; o.faMethod = "EqualQuantity"; o.faPercentage = "50"; o.modelCode = "M1"
    o.shortSaleSlot = 2; o.designatedLocation = "L"; o.exemptCode = 0; o.ocaType = 1; o.rule80A = "I"
    o.settlingFirm = "F"; o.allOrNone = true; o.minQty = 5; o.percentOffset = d("0.01"); o.auctionStrategy = 1
    o.startingPrice = d("1.1"); o.stockRefPrice = d("1.2"); o.delta = d("0.5"); o.stockRangeLower = 1
    o.stockRangeUpper = 2; o.overridePercentageConstraints = true; o.volatility = d("0.3"); o.volatilityType = 2
    o.continuousUpdate = true; o.referencePriceType = 1; o.trailStopPrice = 180; o.trailingPercent = 2
    o.scaleInitLevelSize = 10; o.scaleSubsLevelSize = 5; o.scaleTable = "T"
    o.activeStartTime = "20261112 09:30:00"; o.activeStopTime = "20261112 16:00:00"
    o.optOutSmartRouting = true; o.clearingAccount = "CA"; o.clearingIntent = "IB"; o.notHeld = true
    o.algoID = "A1"; o.whatIf = true; o.orderMiscOptions = [TagValue(tag: "a", value: "1"), TagValue(tag: "b", value: "2")]
    o.solicited = true; o.randomizeSize = true; o.randomizePrice = true
    o.adjustedOrderType = "STP"; o.triggerPrice = 185; o.limitPriceOffset = d("0.1"); o.adjustedStopPrice = 184
    o.adjustedStopLimitPrice = 183; o.adjustedTrailingAmount = 1; o.adjustableTrailingUnit = 1; o.extOperator = "X"
    o.softDollarTier = SoftDollarTier(name: "N", value: "V"); o.cashQty = 1000
    o.mifid2DecisionMaker = "DM"; o.mifid2DecisionAlgo = "DA"; o.mifid2ExecutionTrader = "ET"; o.mifid2ExecutionAlgo = "EA"
    o.dontUseAutoPriceForHedge = true; o.isOmsContainer = true; o.discretionaryUpToLimitPrice = true
    o.usePriceMgmtAlgo = true; o.duration = 60; o.postToAts = 1; o.autoCancelParent = true
    o.advancedErrorOverride = "8229"; o.manualOrderTime = "20261112-09:30:00"
    ```
    The body must equal, field for field (114 fields):
    ```swift
    ["3", "12",                                                                       // 0–1
     "12345", "AAPL", "OPT", "20261218", "150.0", "C", "100", "SMART", "CBOE", "USD",
     "AAPL  261218C00150000", "AAPL",                                                 // 2–13
     "ISIN", "US0378331005",                                                          // 14–15
     "SELL", "100", "VOL", "187.25", "1.5", "GTC", "g1", "DU1",                       // 16–23
     "C", "1", "r1", "0", "9",                                                        // 24–28
     "1", "1", "10", "2", "1", "1",                                                   // 29–34
     "", "0.05", "20261112 09:30:00", "20261113 16:00:00", "G", "EqualQuantity", "50", "M1",  // 35–42
     "2", "L", "0", "1", "I", "F",                                                    // 43–48
     "1", "5", "0.01", "0", "0", "",                                                  // 49–54
     "1", "1.1", "1.2", "0.5", "1", "2",                                              // 55–60
     "1", "0.3", "2", "", "",                                                         // 61–65
     "1", "1", "180", "2", "10", "5", "", "T",                                        // 66–73
     "20261112 09:30:00", "20261112 16:00:00", "",                                    // 74–76
     "1", "CA", "IB", "1", "0",                                                       // 77–81
     "", "A1", "1", "a=1;b=2;", "1", "1", "1",                                        // 82–88
     "0",                                                                             // 89
     "STP", "185", "0.1", "184", "183", "1", "1", "X",                                // 90–97
     "N", "V",                                                                        // 98–99
     "1000", "DM", "DA", "ET", "EA",                                                  // 100–104
     "1", "1", "1", "1",                                                              // 105–108
     "60", "1", "1", "8229", "20261112-09:30:00"]                                     // 109–113
    ```
  - `volatilityIsSentOnlyForVolOrders`: the same order with `orderType = "LMT"` → field 62 is `""`, and every other
    field is unchanged except 18.
  - `RequestTests.contractDetailsSendsSecID`: a contract with `secIDType "ISIN"`, `secID "US0378331005"` → the last
    four fields of `.contractDetails(requestID: 1, contract:)` are `"0", "ISIN", "US0378331005", ""`.
  - `PublicAPITests`: `TagValue(tag: "a", value: "1").tag == "a"`; `SoftDollarTier().displayName == ""`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "PlaceOrderTests|RequestTests"`. Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above. The encoder writes the rows of the table in order from the model;
  the base test pins that defaults still give the base array byte for byte.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS, including `limitOrderMatchesProtocolTable` and
  `modifyResendsPlaceOrderWithSameID`.
- [ ] **Step 5: Docs and commit** («Send every plain placeOrder field from the order and contract models»).

### Task 2: Plain fields in openOrder and completedOrder

**Files:**
- Modify: `Sources/IBKR/Models/Order.swift` (decoded-only fields), `Sources/IBKR/Messages/OrderDecoding.swift`
- Test: `Tests/IBKRTests/OpenOrderTests.swift`, `RecordedFrameTests.swift`, `Fixtures.swift` (`parentPermID:
  String = ""` for completedOrder index 88)
- Docs: protocol-178 (openOrder rows 27–68 and 103–121, completedOrder rows 25–57 and 76–88: «read into the
  model»), KNOWN-GAPS (the `right ?` line also names `None` in deltaNeutralOrderType / adjustedOrderType and
  clearingIntent `IB`, all kept as sent; drop «an unknown action» from the test gaps), DECISIONS (decision 6),
  CHANGELOG (Added: openOrder and completedOrder decode the order fields)

**Interfaces:**
- Consumes: Task 1's `Order` fields.
- Produces: `Order` gains `public var basisPoints: Decimal?`, `basisPointsType: Int?` (openOrder only),
  `autoCancelDate = ""`, `refFuturesConID: Int?`, `shareholder = ""`, `imbalanceOnly = false`,
  `routeMarketableToBbo = false` and `parentPermID: Int?` (completedOrder only).
  - The decoders read every field Task 1 models. They skip sharesAllocation (open 30), eTradeOnly, firmQuoteOnly and
    nbboPriceCap (open 54–56).
  - `trailStopPrice` is read twice, and the second occurrence wins (open 65 then 105, completed 56 then 76).
  - Not on the openOrder wire, so they keep their defaults: `transmit`, `algoID`, `orderMiscOptions`, `scaleTable`,
    `activeStartTime`, `activeStopTime`, `overridePercentageConstraints`, `extOperator`, the four `mifid2…`,
    `advancedErrorOverride` and `manualOrderTime`.
  - The conditional groups and the margins (86–99) are still skipped as now.

- [ ] **Step 1: Write the failing tests** in `OpenOrderTests.swift`
  - `openOrderDecodesEveryPlainField`: this 127-field frame
    ```swift
    ["5", "12",
     "265598", "AAPL", "STK", "", "0", "", "", "SMART", "USD", "AAPL", "NMS",          // 2–12
     "SELL", "100", "VOL", "187.25", "1.5", "GTC", "g1", "DU1", "C", "1", "r1",       // 13–23
     "7", "918273001", "1",                                                           // 24–26
     "1", "0.05", "20261112 09:30:00", "alloc", "G", "EqualQuantity", "50", "M1",     // 27–34
     "20261113 16:00:00", "I", "0.01", "F", "2", "L", "0", "1",                       // 35–42
     "1.1", "1.2", "0.5", "1", "2", "10", "1", "1", "1", "5",                         // 43–52
     "1", "0", "0", "", "9",                                                          // 53–57
     "2", "0.3", "2", "", "",                                                         // 58–62
     "1", "1", "179", "2", "3", "1",                                                  // 63–68
     "", "0", "0", "0", "10", "5", "", "",                                            // 69–76
     "1", "CA", "IB", "1", "0", "", "1", "0",                                         // 77–84
     "Submitted", "", "", "", "", "", "", "", "", "", "", "", "", "", "",             // 85–99
     "1", "1", "0",                                                                   // 100–102
     "STP", "185", "180", "0.1", "184", "183", "1", "1", "N", "V", "Display", "1000", // 103–114
     "1", "1", "1", "1", "60", "1", "1",                                              // 115–121
     "", "", "", "", ""]                                                              // 122–126
    ```
    decodes to `.openOrder(OpenOrderMessage(orderID: 12, clientID: 7, permID: 918273001, contract: c, order: o, status: .submitted))`.
    - `c` is `Contract(symbol: "AAPL")` with conID 265598, strike 0, localSymbol AAPL and tradingClass NMS.
    - `o` starts from `Order(action: .sell, quantity: 100, orderType: "VOL", limitPrice: d("187.25"), auxPrice: d("1.5"), tif: "GTC")` and sets:
      - `ocaGroup "g1"`, `account "DU1"`, `openClose "C"`, `origin 1`, `orderRef "r1"`, `outsideRTH`, `hidden`;
      - `discretionaryAmt 0.05`, `goodAfterTime "20261112 09:30:00"`, `faGroup "G"`, `faMethod "EqualQuantity"`,
        `faPercentage "50"`, `modelCode "M1"`, `goodTillDate "20261113 16:00:00"`, `rule80A "I"`,
        `percentOffset 0.01`, `settlingFirm "F"`;
      - `shortSaleSlot 2`, `designatedLocation "L"`, `exemptCode 0`, `auctionStrategy 1`, `startingPrice 1.1`,
        `stockRefPrice 1.2`, `delta 0.5`, `stockRangeLower 1`, `stockRangeUpper 2`;
      - `displaySize 10`, `blockOrder`, `sweepToFill`, `allOrNone`, `minQty 5`, `ocaType 1`, `parentID 9`,
        `triggerMethod 2`, `volatility 0.3`, `volatilityType 2`;
      - `continuousUpdate`, `referencePriceType 1`, `trailStopPrice 180`, `trailingPercent 2`, `basisPoints 3`,
        `basisPointsType 1`, `scaleInitLevelSize 10`, `scaleSubsLevelSize 5`;
      - `optOutSmartRouting`, `clearingAccount "CA"`, `clearingIntent "IB"`, `notHeld`, `solicited`,
        `randomizeSize`, `randomizePrice`;
      - `adjustedOrderType "STP"`, `triggerPrice 185`, `limitPriceOffset 0.1`, `adjustedStopPrice 184`,
        `adjustedStopLimitPrice 183`, `adjustedTrailingAmount 1`, `adjustableTrailingUnit 1`;
      - `softDollarTier SoftDollarTier(name: "N", value: "V", displayName: "Display")`, `cashQty 1000`;
      - `dontUseAutoPriceForHedge`, `isOmsContainer`, `discretionaryUpToLimitPrice`, `usePriceMgmtAlgo`,
        `duration 60`, `postToAts 1`, `autoCancelParent`.
  - `completedOrderDecodesEveryPlainField`: this 96-field frame
    ```swift
    ["101",
     "265598", "AAPL", "STK", "", "0", "", "", "SMART", "USD", "AAPL", "NMS",          // 1–11
     "SELL", "100", "LMT", "187.25", "1.5", "GTC", "g1", "DU1", "C", "1", "r1",       // 12–22
     "918273001", "1",                                                                // 23–24
     "1", "0.05", "20261112 09:30:00", "G", "EqualQuantity", "50", "M1",              // 25–31
     "20261113 16:00:00", "I", "0.01", "F", "2", "L", "0",                            // 32–38
     "1.1", "1.2", "0.5", "1", "2", "10", "1", "1", "5",                              // 39–47
     "1", "2", "0.3", "2", "", "",                                                    // 48–53
     "1", "1", "179", "2",                                                            // 54–57
     "", "0", "0", "0", "10", "5", "", "",                                            // 58–65
     "CA", "IB", "1", "0", "", "1",                                                   // 66–71
     "Filled", "1", "1", "0",                                                         // 72–75
     "180", "0.1", "1000", "1", "1", "20261231", "100", "495512551",                  // 76–83
     "1", "Not an insider or substantial shareholder", "1", "1", "918273000",         // 84–88
     "20261112 15:59:01", "Filled Size: 100",                                         // 89–90
     "", "", "", "", ""]                                                              // 91–95
    ```
    decodes to `CompletedOrderMessage(permID: 918273001, contract: c, order: o′, status: .filled,
    completedTime: "20261112 15:59:01", completedStatus: "Filled Size: 100", filledQuantity: 100)`.
    - `o′` is the open test's `o` with `orderType "LMT"`.
    - These stay at their defaults, since completedOrder lacks them: `auctionStrategy`, `blockOrder`, `parentID`,
      `basisPoints`, `basisPointsType`, `optOutSmartRouting`, every `adjusted…` field, `triggerPrice`,
      `adjustableTrailingUnit`, `softDollarTier`, `discretionaryUpToLimitPrice`, `usePriceMgmtAlgo`, `duration`
      and `postToAts`.
    - These are set: `autoCancelDate "20261231"`, `refFuturesConID 495512551`,
      `shareholder "Not an insider or substantial shareholder"`, `imbalanceOnly`, `routeMarketableToBbo` and
      `parentPermID 918273000`.
  - `unknownActionIsMalformed`: `openFields()` with `f[13] = "HOLD"` → `.malformed` with id 5.
  - Update the existing expectations, which now decode fields the fixtures always carried:
    - `openOrderDecodesModelledFields` and `completedOrderDecodes` add `o.volatilityType = 0`,
      `o.referencePriceType = 0` and `o.clearingIntent = "IB"`.
    - `RecordedFrameTests.recordedOpenOrderDecodes` adds exactly `o.openClose = ""`, `o.volatilityType = 0`,
      `o.referencePriceType = 0`, `o.trailStopPrice = 2`, `o.clearingIntent = "IB"`, `o.adjustedOrderType = "None"`,
      `o.cashQty = 0` and `o.dontUseAutoPriceForHedge = true`. deltaNeutralOrderType `None` waits for Task 3.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "OpenOrderTests|RecordedFrameTests"`. Expected: FAIL.
- [ ] **Step 3: Implement** the Interfaces above. `orderHead` reads openClose and origin; the comments that list
  skipped indices shrink to the fields still skipped.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS, including `everyRecordedFrameDecodes` and both
  `…SkipsEveryConditionalGroup` tests.
- [ ] **Step 5: Docs and commit** («Decode every plain order field in openOrder and completedOrder»).

### Task 3: Combo legs, delta neutral, scale and hedge, both ways

**Files:**
- Modify: `Sources/IBKR/Models/OrderParts.swift`, `Order.swift`, `Contract.swift`, `PlaceOrderEncoding.swift`,
  `IBRequest.swift` (`contract(_:_:allowBag:)`), `OrderDecoding.swift`
- Test: `PlaceOrderTests.swift`, `OpenOrderTests.swift`, `RequestTests.swift`, `Helpers.swift` (move `inserting` out
  of `OpenOrderTests`, add `replacing(_ f: [String], _ changes: [Int: String]) -> [String]`), `PublicAPITests.swift`
- Docs: protocol-178 (placeOrder intro: BAG, the delta-neutral, scale and hedge groups are sent; the legs come from
  `contract.comboLegs`), DECISIONS (rewrite row «placeOrder encodes only the base layout»: BAG and the
  delta-neutral, scale and hedge groups are encoded, PEG and IBKRATS still throw, and BAG is refused by every other
  request; decision 13), KNOWN-GAPS (new: «a modify that re-sends an order decoded from a live openOrder
  (deltaNeutralOrderType `None` with its 8 fields, adjustedOrderType `None`) is unchecked live»), CHANGELOG
  (Added: BAG combos, delta-neutral orders and contracts, scale and hedge orders)

**Interfaces:**
- Produces:
  - `public struct ComboLeg: Sendable, Equatable, Hashable`:
    - fields `conID: Int`, `ratio: Int`, `action: OrderAction`, `exchange: String`, `openClose: Int`,
      `shortSaleSlot: Int`, `designatedLocation: String`, `exemptCode: Int`;
    - `init(conID:ratio:action:exchange:openClose: = 0, shortSaleSlot: = 0, designatedLocation: = "", exemptCode: = -1)`.
  - `public struct OrderComboLeg: Sendable, Equatable { public var price: Decimal? }`
  - `public struct DeltaNeutralContract: Sendable, Equatable, Hashable { public var conID: Int; public var delta: Decimal; public var price: Decimal }`.
    `delta` and `price` go out through `addDouble`.
  - `Contract` gains `public var comboLegs: [ComboLeg] = []`, `comboLegsDescrip = ""` (decoded only) and
    `deltaNeutralContract: DeltaNeutralContract?`.
  - `Order` gains:
    - `orderComboLegs: [OrderComboLeg] = []` and `smartComboRoutingParams: [TagValue] = []`;
    - `deltaNeutralOrderType = ""`, `deltaNeutralAuxPrice: Decimal?`, `deltaNeutralConID = 0`,
      `deltaNeutralSettlingFirm = ""`, `deltaNeutralClearingAccount = ""`, `deltaNeutralClearingIntent = ""`,
      `deltaNeutralOpenClose = ""`, `deltaNeutralShortSale = false`, `deltaNeutralShortSaleSlot = 0` and
      `deltaNeutralDesignatedLocation = ""`;
    - `scalePriceIncrement: Decimal?`, `scalePriceAdjustValue: Decimal?`, `scalePriceAdjustInterval: Int?`,
      `scaleProfitOffset: Decimal?`, `scaleAutoReset = false`, `scaleInitPosition: Int?`, `scaleInitFillQty: Int?`
      and `scaleRandomPercent = false`;
    - `hedgeType = ""` and `hedgeParam = ""`.
  - Encoding rules (as `ib_async`):
    - BAG groups only when `secType == "BAG"`. Each list goes out as its count, then the elements, and smart
      routing params go out as tag, value pairs.
    - The 8-field delta-neutral group only when `deltaNeutralOrderType != ""`.
    - The 7 scale fields only when `scalePriceIncrement > 0`.
    - `hedgeParam` only when `hedgeType != ""`.
    - Row 81 is `1` plus conID, delta and price when `deltaNeutralContract != nil`, else `0`.
  - `contract(_:_:allowBag: Bool = false)` throws `.unsupported("secType BAG")` unless `allowBag`, which only
    placeOrder passes.
  - Decoding reads the same groups:
    - openOrder's 8-field delta-neutral group, and completedOrder's 4-field one (conID, shortSale, shortSaleSlot,
      designatedLocation);
    - the legs and their prices, the smart params, the scale group, `hedgeParam`, and the delta-neutral contract.
    - Algo params are still skipped.

- [ ] **Step 1: Write the failing tests.** In `PlaceOrderTests`, each scenario uses order id 12 and the `base`
  order, `Order(action: .buy, quantity: d("100"), orderType: "LMT", limitPrice: d("187.25"))`, on
  `Contract(symbol: "AAPL")`. The expected array is `base` with `replacing`, then `inserting` (indices are
  base-case ones).
  - `bagSendsLegsPricesAndRoutingParams`:
    - Setup: `secType "BAG"`, `c.comboLegs = [ComboLeg(conID: 265598, ratio: 1, action: .buy, exchange: "SMART"),
      ComboLeg(conID: 272093, ratio: 2, action: .sell, exchange: "SMART", openClose: 1, shortSaleSlot: 2,
      designatedLocation: "L", exemptCode: 0)]`, `o.orderComboLegs = [OrderComboLeg(price: d("1.25")),
      OrderComboLeg(price: nil)]`, `o.smartComboRoutingParams = [TagValue(tag: "NonGuaranteed", value: "1")]`.
    - Expected: `replacing(base, [4: "BAG"])`, inserting after 34
      `["2", "265598", "1", "BUY", "SMART", "0", "0", "", "-1", "272093", "2", "SELL", "SMART", "1", "2", "L", "0",
      "2", "1.25", "", "1", "NonGuaranteed", "1"]`. That is 137 fields.
  - `bagWithoutLegsSendsThreeZeroCounts`: secType BAG only → after 34 `["0", "0", "0"]`.
  - `deltaNeutralOrderSendsItsGroup`:
    - Setup: `deltaNeutralOrderType "MKT"`, `deltaNeutralAuxPrice 0.1`, `deltaNeutralConID 265598`,
      `deltaNeutralSettlingFirm "SF"`, `deltaNeutralClearingAccount "CA"`, `deltaNeutralClearingIntent "IB"`,
      `deltaNeutralOpenClose "O"`, `deltaNeutralShortSale true`, `deltaNeutralShortSaleSlot 1`,
      `deltaNeutralDesignatedLocation "DL"`.
    - Expected: `replacing(base, [64: "MKT", 65: "0.1"])`, after 65
      `["265598", "SF", "CA", "IB", "O", "1", "1", "DL"]`.
  - `scaleIncrementSendsItsGroup`:
    - Setup: `scalePriceIncrement 0.05`, `scalePriceAdjustValue 0.01`, `scalePriceAdjustInterval 60`,
      `scaleProfitOffset 0.1`, `scaleAutoReset true`, `scaleInitPosition 100`, `scaleInitFillQty 10`,
      `scaleRandomPercent true`.
    - Expected: `[72: "0.05"]`, after 72 `["0.01", "60", "0.1", "1", "100", "10", "1"]`.
  - `hedgeTypeSendsItsParam`: `hedgeType "D"`, `hedgeParam "0.5"` → `[76: "D"]`, after 76 `["0.5"]`.
  - `deltaNeutralContractIsSent`: `c.deltaNeutralContract = DeltaNeutralContract(conID: 265598, delta: d("0.5"),
    price: d("187.25"))` → `[81: "1"]`, after 81 `["265598", "0.5", "187.25"]`.
  - `decodedLiveOrderReencodes` (Review Focus 1). Decode the first `5` frame of the recording
    `liveLimitOrderPlacesAndCancels`, then encode `.placeOrder(orderID: 2, contract: m.contract, order: m.order)`:
    - it does not throw;
    - the fields number 122 (114 plus the 8-field `None` group);
    - `f[64] == "None"`, `f[24] == ""` and `f[62] == ""` (volatility is dropped for LMT);
    - the recorded `trailStopPrice` 2.0 goes out as `"2"` at index 76 (row 68 plus the 8-field shift).
  - `RequestTests.bagIsStillRefusedOutsidePlaceOrder`: `.marketData(requestID: 1, contract: bag)` throws
    `.unsupported("secType BAG")`. Delete the BAG line from `placeOrderRefusesLayoutsItCannotEncode`.
  - Decoding:
    - Rename `openOrderSkipsEveryConditionalGroup` to `openOrderDecodesEveryConditionalGroup` and add these checks
      on its frame:
      - `deltaNeutralOrderType "LMT"`, `deltaNeutralConID 265598`, `deltaNeutralOpenClose "O"`;
      - `contract.comboLegs == [ComboLeg(conID: 265598, ratio: 1, action: .buy, exchange: "SMART")]`;
      - `orderComboLegs == [OrderComboLeg(price: 187)]` and
        `smartComboRoutingParams == [TagValue(tag: "NonGuaranteed", value: "1")]`;
      - `scalePriceIncrement 0.05`, `scalePriceAdjustValue 0.01`, `scalePriceAdjustInterval 60`,
        `scaleProfitOffset 0.1`, `scaleInitPosition 0`;
      - `hedgeType "D"`, `hedgeParam "0.5"`, and
        `contract.deltaNeutralContract == DeltaNeutralContract(conID: 265598, delta: 0.5, price: 187)`.
    - `completedOrderSkipsEveryConditionalGroup` becomes `completedOrderDecodesEveryConditionalGroup`. It checks the
      same items, except that its delta-neutral group (`["265598", "0", "0", ""]`) gives `deltaNeutralConID 265598`
      and `deltaNeutralShortSale false`.
    - `recordedOpenOrderDecodes` adds `o.deltaNeutralOrderType = "None"` and `o.deltaNeutralOpenClose = "?"`.
  - `PublicAPITests`: build a `ComboLeg`, an `OrderComboLeg` and a `DeltaNeutralContract`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "PlaceOrderTests|OpenOrderTests|RequestTests|RecordedFrameTests"`.
  Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («Send and decode BAG combos, delta-neutral, scale and hedge orders»).

### Task 4: Algos, pegged orders, conditions and the 170 tail, both ways

**Files:**
- Create: `Sources/IBKR/Models/OrderCondition.swift`
- Modify: `OrderParts.swift` (`CompeteOffset`), `Order.swift`, `PlaceOrderEncoding.swift`, `OrderDecoding.swift`
- Test: `PlaceOrderTests.swift`, `OpenOrderTests.swift`, `PublicAPITests.swift`
- Docs: protocol-178 (placeOrder intro: no layout is refused any more; the condition element: Swift case names),
  DECISIONS (row «placeOrder encodes only the base layout» now reads: every group `ib_async` sends is encoded, and
  BAG is refused outside placeOrder; decision 3), KNOWN-GAPS (drop «or condition type» from the test gaps; new:
  «conditions, algos, PEG and combo orders are checked on hand-built frames only»), CHANGELOG (Added: algos, PEG
  BENCH, BEST and MID, conditions and IBKRATS; Removed: the `.unsupported` refusals of placeOrder)

**Interfaces:**
- Produces:
  - ```swift
    public enum OrderCondition: Sendable, Equatable {
        public enum Conjunction: String, Sendable { case and = "a", or = "o" }
        case price(conID: Int, exchange: String, isMore: Bool, price: Decimal, triggerMethod: Int = 0, conjunction: Conjunction = .and)  // 1
        case time(isMore: Bool, time: String, conjunction: Conjunction = .and)                                                       // 3
        case margin(isMore: Bool, percent: Int, conjunction: Conjunction = .and)                                                     // 4
        case execution(secType: String, exchange: String, symbol: String, conjunction: Conjunction = .and)                           // 5
        case volume(conID: Int, exchange: String, isMore: Bool, volume: Int, conjunction: Conjunction = .and)                        // 6
        case percentChange(conID: Int, exchange: String, isMore: Bool, changePercent: Decimal, conjunction: Conjunction = .and)      // 7
    }
    ```
    The wire order of each element is in protocol-178's «Order condition element». `price` and `changePercent` go
    out through `addDouble`.
  - `public enum CompeteOffset: Sendable, Equatable { case offset(Decimal), upToMid }`. `.upToMid` is the wire's
    `Infinite`.
  - `Order` gains:
    - `algoStrategy = ""` and `algoParams: [TagValue] = []`;
    - `referenceContractID = 0`, `isPeggedChangeAmountDecrease = false`, `peggedChangeAmount: Decimal = 0`,
      `referenceChangeAmount: Decimal = 0` and `referenceExchangeID = ""`;
    - `conditions: [OrderCondition] = []`, `conditionsIgnoreRTH = false` and `conditionsCancelOrder = false`;
    - `minTradeQty: Int?`, `minCompeteSize: Int?`, `competeAgainstBestOffset: CompeteOffset?`,
      `midOffsetAtWhole: Decimal?` and `midOffsetAtHalf: Decimal?`.
  - Encoding (as `ib_async`):
    - The algo params go out as count and pairs, only when `algoStrategy != ""`.
    - The 5 PEG BENCH fields go out for `PEG BENCH` and `PEGBENCH`.
    - The conditions go out as their count, the elements, then both flags, the flags only when the count is above 0.
    - After row 113: `minTradeQty` when `contract.exchange == "IBKRATS"`. Then, for `PEG BEST` and `PEGBEST`,
      `minCompeteSize` and `competeAgainstBestOffset`, plus both mid offsets when it is `.upToMid`. For `PEG MID`
      and `PEGMID`, both mid offsets.
    - placeOrder no longer throws `.unsupported`.
  - Decoding:
    - It reads the algo params, the PEG BENCH fields and the conditions.
    - It reads the 5 tail fields: `Infinite` → `.upToMid`, a number → `.offset`, unset → `nil`.
    - An unknown condition type or conjunction throws `unexpectedValue`, so the frame is `.malformed`.

- [ ] **Step 1: Write the failing tests** (same setup and helpers as Task 3)
  - `algoSendsItsParams`: `algoStrategy "Adaptive"`, `algoParams [adaptivePriority=Normal]` → `[82: "Adaptive"]`,
    after 82 `["1", "adaptivePriority", "Normal"]`. With no params, after 82 is `["0"]`.
  - `pegBenchSendsItsFields`: `orderType "PEG BENCH"`, `referenceContractID 265598`,
    `isPeggedChangeAmountDecrease true`, `peggedChangeAmount 0.5`, `referenceChangeAmount 1`,
    `referenceExchangeID "ISLAND"` → `[18: "PEG BENCH"]`, after 88 `["265598", "1", "0.5", "1.0", "ISLAND"]`. With
    only the order type, after 88 is `["0", "0", "0.0", "0.0", ""]`.
  - `conditionsAreSentWithTheirFlags`. The order carries:
    ```swift
    o.conditions = [
        .price(conID: 265598, exchange: "SMART", isMore: true, price: d("180.5"), triggerMethod: 2),
        .time(isMore: false, time: "20261112 15:00:00", conjunction: .or),
        .margin(isMore: true, percent: 30),
        .execution(secType: "STK", exchange: "SMART", symbol: "AAPL"),
        .volume(conID: 265598, exchange: "SMART", isMore: true, volume: 100000),
        .percentChange(conID: 265598, exchange: "SMART", isMore: false, changePercent: d("2.5")),
    ]
    o.conditionsIgnoreRTH = true
    ```
    → `[89: "6"]`, after 89:
    ```swift
    ["1", "a", "1", "180.5", "265598", "SMART", "2",
     "3", "o", "0", "20261112 15:00:00",
     "4", "a", "1", "30",
     "5", "a", "STK", "SMART", "AAPL",
     "6", "a", "1", "100000", "265598", "SMART",
     "7", "a", "0", "2.5", "265598", "SMART",
     "1", "0"]
    ```
  - `tailFieldsFollowExchangeAndOrderType`. Each case appends after 113:
    - `PEG BEST` with `minCompeteSize 100` and `.offset(0.02)` → `["100", "0.02"]`;
    - `PEGBEST` with `.upToMid`, `midOffsetAtWhole 0.01` and `midOffsetAtHalf 0.005` → `["100", "Infinite", "0.01", "0.005"]`;
    - `PEG MID` with the same mids → `["0.01", "0.005"]`;
    - exchange `IBKRATS` with `minTradeQty 50` → `["50"]`;
    - `IBKRATS` and `PEGMID` → `["50", "0.01", "0.005"]`.
  - Delete `placeOrderRefusesLayoutsItCannotEncode`.
  - Decoding. `openOrderDecodesEveryConditionalGroup` also sets `f[122...126] = ["50", "100", "Infinite", "0.01", "0.005"]`
    and checks:
    - `algoStrategy "Adaptive"`, `algoParams [adaptivePriority=Normal]`;
    - `referenceContractID 265598`, `isPeggedChangeAmountDecrease false`, `peggedChangeAmount 1`,
      `referenceChangeAmount 1`, `referenceExchangeID "ISLAND"`;
    - `conditions == [.price(conID: 265598, exchange: "SMART", isMore: true, price: d("180.5")),
      .time(isMore: false, time: "20261109 15:00:00", conjunction: .or)]`, with both flags false;
    - `minTradeQty 50`, `minCompeteSize 100`, `competeAgainstBestOffset .upToMid`, `midOffsetAtWhole 0.01`,
      `midOffsetAtHalf 0.005`.
  - `completedOrderDecodesEveryConditionalGroup` checks `conditions == [.execution(secType: "STK", exchange: "SMART",
    symbol: "AAPL"), .margin(isMore: true, percent: 30)]`.
  - `unknownConditionIsMalformed` (Review Focus 5): `openFields()` with `f[102] = "1"` and, inserted after 102,
    `["2", "a", "1", "0", "0"]`, decodes to `.malformed` with id 5. So does a price condition whose conjunction is `"x"`.
  - `PublicAPITests`: `OrderCondition.margin(isMore: true, percent: 30) != .margin(isMore: false, percent: 30)`;
    `CompeteOffset.upToMid != .offset(0)`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "PlaceOrderTests|OpenOrderTests"`. Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above. The skip helpers in `OrderDecoding.swift` are gone at the end of
  this task, and every field is read into the model.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («Send and decode algos, pegged orders, conditions and the IBKRATS and PEG tail»).

### Task 5: OrderState and `whatIfOrder`

**Files:**
- Create: `Sources/IBKR/Models/OrderState.swift`, `Tests/IBKRTests/IBClientWhatIfTests.swift`
- Modify: `OrderDecoding.swift` (margins 86–99 into `OpenOrderMessage.state`), `State/OrderTracker.swift` (skip
  whatIf openOrders), `Client/IBClient.swift`
- Test: `OpenOrderTests.swift`, `OrderTrackerTests.swift`, `PublicAPITests.swift`
- Docs: protocol-178 (openOrder 86–99: read into `OrderState`, sentinels → nil), README («Orders»: one what-if
  line, to be rewritten in Task 9), DECISIONS (decisions 4 and 7), KNOWN-GAPS (new: «what-if is unchecked live»),
  CHANGELOG (Added: `OrderState`, `OpenOrderMessage.state`, `whatIfOrder`; Changed: `placeOrder`/`modifyOrder`
  refuse `whatIf`)

**Interfaces:**
- Consumes: `Order.whatIf` (Task 1); `answer(_:id:pick:)`; `routeToStream`.
- Produces:
  - `public struct OrderState: Sendable, Equatable` with `initMarginBefore`, `maintMarginBefore`,
    `equityWithLoanBefore`, `initMarginChange`, `maintMarginChange`, `equityWithLoanChange`, `initMarginAfter`,
    `maintMarginAfter`, `equityWithLoanAfter`, `commission`, `minCommission` and `maxCommission`, all `Decimal?`,
    plus `commissionCurrency: String` and `warningText: String`. Its init takes every field, defaulting to `nil` or `""`.
  - `OpenOrderMessage` gains `public var state: OrderState`, as a last init parameter defaulting to `OrderState()`.
  - `OrderTracker.apply(.openOrder(m))` returns `[]` and changes nothing when `m.order.whatIf`.
  - `public func whatIfOrder(_ contract: Contract, _ order: Order) async throws(IBClientError) -> OrderState`:
    - it requires `.connected` and takes `id = nextRequestID()`;
    - it sends `.placeOrder(orderID: id, …)` with `whatIf = true` through `answer(…, id: id)`, without
      `orderTracker.sent`;
    - it picks the first `.openOrder(m)` with `m.order.whatIf && m.state.initMarginChange != nil` and returns
      `m.state`.
  - `routeToStream` routes `.openOrder(let m) where m.order.whatIf` to `requestStreams[m.orderID]`.
  - `placeOrder` and `modifyOrder` throw `.encoding(.unsupported("whatIf"))` before sending when `order.whatIf`.

- [ ] **Step 1: Write the failing tests**
  - `OpenOrderTests.openOrderDecodesTheWhatIfState`: `openFields()` with `f[84] = "1"` and `f[86...99] = ["1000", "800",
    "10000", "250.5", "200.25", "-1.5", "1250.5", "1000.25", "9998.5", "1.25", "1", "1.5", "USD", "margin warning"]`
    → `m.order.whatIf` and `m.state == OrderState(initMarginBefore: 1000, maintMarginBefore: 800,
    equityWithLoanBefore: 10000, initMarginChange: d("250.5"), maintMarginChange: d("200.25"),
    equityWithLoanChange: d("-1.5"), initMarginAfter: d("1250.5"), maintMarginAfter: d("1000.25"),
    equityWithLoanAfter: d("9998.5"), commission: d("1.25"), minCommission: 1, maxCommission: d("1.5"),
    commissionCurrency: "USD", warningText: "margin warning")`. `recordedOpenOrderDecodes` stays unchanged: its
    sentinels give `OrderState()`.
  - `OrderTrackerTests.whatIfOpenOrderLeavesTheTrackerAlone`: an openOrder with `f[84] = "1"` → `[]`, and `orders` is
    empty.
  - `IBClientWhatIfTests` (connected helper as in `IBClientOrderTests`). `onRequest` answers a `3` frame with two
    openOrders for `orderID Int(f[1])!`, both with `f[84] = "1"`: the first has the margins empty, the second has
    `f[89] = "250.5"`.
    - `whatIfOrderReturnsTheState`: returns a state with `initMarginChange == d("250.5")`. The sent `3` frame has
      `[84] == "1"`, `orders().snapshot` is empty, and `requestStreamCount == 0`.
    - `whatIfOrderFailsOnItsError` (Review Focus 3): the answer is
      `["4", "2", f[1], "201", "Order rejected - reason:Insufficient margin", ""]` → throws
      `.ib(code: 201, text: "Order rejected - reason:Insufficient margin")`. `orders().snapshot` is empty, and
      `requestStreamCount == 0`.
    - `whatIfOrderEndsWithTheConnection`: no answer; `gateway.close()` → `.connectionClosed` within 2 s.
    - `placeOrderRefusesWhatIf`: `placeOrder` and `modifyOrder` with `whatIf = true` throw
      `.encoding(.unsupported("whatIf"))`. A following `cancelOrder(1)` is the next frame sent.
    - `whatIfOrderNeedsAConnection`: `.notConnected` before `connect`.
  - `PublicAPITests`: `OrderState().commission == nil`; an `OpenOrderMessage` built with `state:`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "OpenOrderTests|OrderTrackerTests|IBClientWhatIfTests"`.
  Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («Decode the order state and answer what-if orders with margin and commission»).

### Task 6: Tracker: the 202 reason, the early Filled, `parentPermID` and the advanced reject

**Files:**
- Modify: `Sources/IBKR/State/OrderTracker.swift`
- Test: `Tests/IBKRTests/OrderTrackerTests.swift` (the `error` helper gains `json: String = ""`),
  `RecordedFrameTests.swift`, `Fixtures.swift` (parentPermID, added in Task 2)
- Docs: DECISIONS (decision 8; row «A completedOrder joined to an existing order updates only status and
  completedTime» adds parentPermID; a 202 row), KNOWN-GAPS (drop «A 202 can carry a refusal», «A Filled snapshot
  can come with filled 0» and «completedOrder's parentPermId is skipped»), CHANGELOG (Added:
  `OrderSnapshot.advancedOrderRejectJSON`; Changed: a 202 keeps its reason, and a Filled openOrder waits for its
  orderStatus)

**Interfaces:**
- Consumes: `Order.parentPermID` (Task 2), `IBErrorMessage.advancedOrderRejectJSON` (stage 6).
- Produces:
  - `OrderSnapshot` gains `public var advancedOrderRejectJSON: String?`, as a last init parameter defaulting to `nil`.
    A non-notice error for the order sets it when its JSON is non-empty.
  - 202 (`.orderCancelled`) sets `.cancelled`. It sets `rejectReason = e.text` only when the text after the first
    `reason:` is non-blank. Otherwise `rejectReason` is untouched.
  - A Filled openOrder is held, unpublished. It is held when `m.status == .filled` and the snapshot it would publish,
    after merging any held orderStatus, has `filled == 0`.
    - It is kept per key, the newest one winning.
    - The next orderStatus for that key or permID applies the held openOrder's contract and order, then merges the
      status, and publishes once.
    - A held order counts as known for that orderStatus.
    - A completedOrder for its permID publishes as now.
  - A completedOrder joined to an existing snapshot also sets `s.order.parentPermID = m.order.parentPermID`.

- [ ] **Step 1: Write the failing tests** in `OrderTrackerTests` (`open(status: "Filled")` is the existing helper)
  - `cancelReasonOf202IsKept`: `open()`, then `error(12, 202, "Order Canceled - reason:We cannot accept an order at a
    limit price at or more aggressive than 357.97385.")` → `.cancelled`, `rejectReason` is that text.
  - `bareCancelHasNoReason`: `error(12, 202, "Order Canceled - reason:")` → `.cancelled`, `rejectReason == nil`.
  - `filledOpenOrderWaitsForOrderStatus`: `open(status: "Filled")` → `[]` and `orders` is empty. Then
    `status(.filled, filled: "100", remaining: "0", avg: "187.20")` → one snapshot:
    - `.filled`, filled 100, `averageFillPrice 187.20`;
    - `order.limitPrice == d("187.25")`, `contract.symbol == "AAPL"`.
  - `filledOpenOrderOfAKnownOrderWaits`: `open()` (Submitted); `open(status: "Filled")` → `[]`, and `orders[0].status
    == .submitted`. Then `status(.filled, filled: "100", remaining: "0")` → one `.filled` snapshot with filled 100.
  - `filledOpenOrderAfterTheFillPublishes`: `open()`, `status(.filled, filled: "100", remaining: "0")`, then
    `open(status: "Filled")` → `[]` (identical), with no hold.
  - `heldFilledOpenOrderShowsThroughCompletedOrder` (Review Focus 2):
    - `open(status: "Filled")` → `[]`;
    - `completed(permID: 918273001, filledQuantity: "100")` → one `.filled` snapshot with filled 100;
    - a later `status(.filled, filled: "100", remaining: "0")` → `orders.count == 1`.
  - `advancedRejectIsKept`: `sent(…)`, then `error(12, 201, "Order rejected", json: "{\"r\":1}")` →
    `advancedOrderRejectJSON == "{\"r\":1}"`. An error with an empty JSON leaves it `nil`.
  - `completedOrderCarriesParentPermID`:
    - a fresh tracker given a completed order with `parentPermID: "918273000"` → `order.parentPermID == 918273000`;
    - after `open(13, parentID: 12)`, the same completed order joined → `parentPermID 918273000` and `parentID 12`.
  - Update the three tests that start from `open(status: "Filled")`: `cancelRejectionKeepsTheOrder`,
    `fatalErrorKeepsAFinalStatus` and `openOrderDoesNotReviveAFinalStatus`. Each applies
    `status(.filled, filled: "100", remaining: "0")` right after it, and its assertions stay.
  - `RecordedFrameTests`: `recordedPriceCapCancelEndsCancelled` expects `last.rejectReason?.contains("357.97385") ==
    true`; `recordedLimitOrderEndsCancelled` adds `rejectReason == nil`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "OrderTrackerTests|RecordedFrameTests"`. Expected: FAIL.
- [ ] **Step 3: Implement** the Interfaces above (a `heldOpen: [OrderKey: OpenOrderMessage]` beside `held`).
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS, including the recorded fill tests.
- [ ] **Step 5: Docs and commit** («Keep the 202 reason, hold a Filled openOrder until its fill, and carry parentPermId»).

### Task 7: Manual cancel time, `exerciseOptions`, and `orderBound` through the client

**Files:**
- Modify: `Sources/IBKR/Models/Order.swift` (`ExerciseAction`), `Messages/IBRequest.swift`, `Client/IBClient.swift`
- Test: `RequestTests.swift`, `IBClientOrderTests.swift`, `PublicAPITests.swift`
- Docs: protocol-178 (new «exerciseOptions (out 21)» table; cancelOrder row 3: from `cancelOrder`'s
  `manualOrderCancelTime`), README («Orders»: exercise and the manual cancel time), DECISIONS (decisions 9 and 12),
  KNOWN-GAPS (new: «exerciseOptions is unchecked live: the paper account holds no options»), CHANGELOG (Added:
  `exerciseOptions`, `cancelOrder(_:manualOrderCancelTime:)`)

**Interfaces:**
- Produces:
  - `public enum ExerciseAction: Int, Sendable { case exercise = 1, lapse = 2 }`
  - `IBRequest.exerciseOptions(requestID: Int, contract: Contract, action: ExerciseAction, quantity: Int, account: String, override: Bool)`.
    Its wire form is these 18 fields: `21`, `2`, reqId, conId, symbol, secType, lastTradeDateOrContractMonth,
    strike (`addDouble`), right, multiplier, exchange, currency, localSymbol, tradingClass, exerciseAction,
    exerciseQuantity, account, override. There is no primaryExchange.
  - `@discardableResult public func exerciseOptions(_ contract: Contract, action: ExerciseAction, quantity: Int, account: String, override: Bool = false) throws(IBClientError) -> Int`
    takes `nextRequestID()`, sends, and returns the id.
  - `public func cancelOrder(_ orderID: Int, manualOrderCancelTime: String = "") throws(IBClientError)`. The existing
    `cancelOrder(_:)` call sites keep compiling.

- [ ] **Step 1: Write the failing tests.** Let `opt` be Task 1's option contract: conID 12345, `OPT`, `20261218`,
  strike 150, right `C`, multiplier `100`, SMART, USD, `AAPL  261218C00150000`, tradingClass `AAPL`.
  - `RequestTests.exerciseOptionsEncodes`: `.exerciseOptions(requestID: 5, contract: opt, action: .exercise,
    quantity: 2, account: "DU1", override: false)` → `body("21", "2", "5", "12345", "AAPL", "OPT", "20261218",
    "150.0", "C", "100", "SMART", "USD", "AAPL  261218C00150000", "AAPL", "1", "2", "DU1", "0")`.
  - `IBClientOrderTests`:
    - `exerciseOptionsSendsItsFrame`: `exerciseOptions(opt, action: .lapse, quantity: 1, account: "DU1",
      override: true)` returns `id`. The next sent frame is the 18 fields above, with reqId `id`, action `"2"`,
      quantity `"1"` and override `"1"`.
    - `cancelOrderSendsTheManualCancelTime`: `cancelOrder(101, manualOrderCancelTime: "20261112-15:00:00")` →
      `["4", "1", "101", "20261112-15:00:00"]`.
    - `orderBoundRebindsAManualOrder` (client id 7):
      - feed an openOrder fixture with orderID 0, permID 5555 and clientID 0;
      - feed `["100", "5555", "7", "41"]`;
      - feed `["3", "41", "Filled", "1", "0", "1", "5555", "0", "1", "7", "", "0"]`;
      - the last update has `orderID == 41` and `.filled`, and `orders().snapshot.count == 1`.
    - `requestBeforeConnectThrows` adds `exerciseOptions`.
  - `PublicAPITests`: `ExerciseAction(rawValue: 2) == .lapse`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "RequestTests|IBClientOrderTests"`. Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («Add exerciseOptions and the manual cancel time, and check orderBound through the client»).

### Task 8: Order factories, bracket and OCA helpers, `placeBracket`

**Files:**
- Create: `Sources/IBKR/Models/OrderHelpers.swift`, `Tests/IBKRTests/OrderHelperTests.swift`
- Modify: `Client/IBClient.swift` (`placeBracket`; `send` splits into encode and enqueue)
- Test: `IBClientOrderTests.swift`, `PublicAPITests.swift`
- Docs: DECISIONS (decision 10; the helpers row), CHANGELOG (Added: the factories, `BracketOrder`, `Order.bracket`,
  `oneCancelsAll` and `placeBracket`)

**Interfaces:**
- Produces (in `extension Order`):
  - `public static func market(_ action: OrderAction, quantity: Decimal) -> Order` (`MKT`)
  - `public static func limit(_ action: OrderAction, quantity: Decimal, price: Decimal) -> Order` (`LMT`, limitPrice)
  - `public static func stop(_ action: OrderAction, quantity: Decimal, stopPrice: Decimal) -> Order` (`STP`, auxPrice)
  - `public static func stopLimit(_ action: OrderAction, quantity: Decimal, limitPrice: Decimal, stopPrice: Decimal) -> Order` (`STP LMT`)
  - `public static func bracket(_ action: OrderAction, quantity: Decimal, limitPrice: Decimal, takeProfitPrice: Decimal, stopLossPrice: Decimal) -> BracketOrder`:
    - the parent is a limit with `transmit` false;
    - the take-profit is a limit on the reverse side with `transmit` false;
    - the stop-loss is a stop on the reverse side with `transmit` true;
    - the reverse of `.buy` is `.sell`, and of `.sell` and `.shortSell` it is `.buy`.
  - `public static func oneCancelsAll(_ orders: [Order], group: String, type: Int) -> [Order]` sets `ocaGroup` and
    `ocaType` on each order.
  - `public struct BracketOrder: Sendable, Equatable { public var parent, takeProfit, stopLoss: Order }`, with
    `init(parent:takeProfit:stopLoss:)`.
  - `IBClient.placeBracket(_ contract: Contract, _ bracket: BracketOrder) throws(IBClientError) -> (parent: Int, takeProfit: Int, stopLoss: Int)`:
    - it requires `.connected` and takes three ids from `nextRequestID()`;
    - it sets both children's `parentID` to the parent id, and `transmit` to false, false and true;
    - it encodes all three bodies, then queues them in order and records each with `orderTracker.sent`;
    - it refuses `whatIf` like `placeOrder`.

- [ ] **Step 1: Write the failing tests**
  - `OrderHelperTests`:
    - `factoriesSetTypeAndPrices`:
      - `Order.limit(.buy, quantity: 100, price: 180) == Order(action: .buy, quantity: 100, orderType: "LMT", limitPrice: 180)`;
      - `market` gives `"MKT"` with no prices;
      - `stop(.sell, quantity: 100, stopPrice: 175)` gives `"STP"` with `auxPrice 175`;
      - `stopLimit(.buy, quantity: 1, limitPrice: 181, stopPrice: 180)` gives `"STP LMT"`, limit 181 and aux 180.
    - `bracketReversesTheChildren`:
      - `Order.bracket(.buy, quantity: 100, limitPrice: 180, takeProfitPrice: 190, stopLossPrice: 175)` gives a
        parent LMT BUY 180 with `transmit` false;
      - the take-profit is LMT SELL 190 with `transmit` false;
      - the stop-loss is STP SELL with `auxPrice 175` and `transmit` true;
      - with `.sell`, both children are `.buy`.
    - `oneCancelsAllSetsGroupAndType`: two orders → both have `ocaGroup "g"` and `ocaType 1`, with every other field
      unchanged.
  - `IBClientOrderTests`:
    - `placeBracketLinksAndTransmitsLast` (`nextValidID: 100`):
      - it returns `(101, 102, 103)`;
      - the three frames after the sync begin `["3", "101"]`, `["3", "102"]` and `["3", "103"]`;
      - field 28 (parentId) reads `"0"`, `"101"`, `"101"`, and field 27 (transmit) reads `"0"`, `"0"`, `"1"`.
    - `placeBracketSendsNothingWhenALegFailsToEncode` (Review Focus 4):
      - the stop-loss has `orderRef = "Стоп"`, so the call throws `.encoding(.nonASCII(field: "Стоп"))`;
      - then `cancelOrder(1)`: the only frame after the sync is that `4`;
      - `orders().snapshot` is empty.
  - `PublicAPITests`: a `BracketOrder` built with `init(parent:takeProfit:stopLoss:)`.
- [ ] **Step 2: Run** `timeout 900 swift test --filter "OrderHelperTests|IBClientOrderTests"`. Expected: a compile FAIL.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 5: Docs and commit** («Add order factories, bracket and OCA helpers, and placeBracket»).

### Task 9: Documents, per-commit check, CI

**Files:**
- Modify: `README.md`, `CHANGELOG.md`, `docs/DECISIONS.md`, `docs/KNOWN-GAPS.md`

- [ ] **Step 1: README «Orders»** is rewritten around the new API:
  - the factories in place of the hand-built `Order(…)`;
  - `Order.bracket` with `placeBracket` in place of the manual bracket, and `oneCancelsAll`;
  - one condition and one algo example (`conditions`, `algoStrategy` / `algoParams`);
  - `whatIfOrder` and `exerciseOptions`;
  - a note that `orderType` and `tif` stay IB's strings;
  - the ASCII rule, kept.

  The README «Status» Orders row reads «place, modify, cancel, every placeOrder field (conditions, algos, pegged,
  combos, delta neutral), brackets, OCA, what-if, exercise, open and completed orders merged». Its state:
  «✅ plain orders live-checked; the rest on hand-built frames, a live run is due in stage 13». The KNOWN-GAPS
  heading and intro read «after stage 7».
- [ ] **Step 2: Check the records against this plan.**
  - Every decision in the preamble has its DECISIONS row.
  - Every public API change has a CHANGELOG `Unreleased` line.
  - protocol-178 no longer says any layout is refused by placeOrder.
  - Fix any gap, then commit («Record stage 7 in the README and the status table»).
- [ ] **Step 3: Verify the series commit by commit** in a detached worktree, so the working tree stays free:
  ```bash
  git worktree add --detach ../swift-ibkr-check stage-7-orders
  git -C ../swift-ibkr-check rebase --exec "timeout 900 swift test > /dev/null" main
  git worktree remove ../swift-ibkr-check
  ```
  Expected: `Successfully rebased`, with every commit's tests run. If a commit fails, fix it on `stage-7-orders`
  (a fixup commit, or an edit of that commit followed by a rebase of the branch), and run the check again.
- [ ] **Step 4: Push and watch CI** with the command under Global Constraints. Expected: every job is green (macOS,
  Linux 6.0 and latest, Windows, pod-lint). If a job fails, fix its root cause in a new commit, with no weakened
  test, push, and watch again.
