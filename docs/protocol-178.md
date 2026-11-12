# TWS API socket protocol at server version 178

Field order derived from `ib_async` (BSD-2-Clause, © Ewald de Wit, Matt Stancliff) commit
`ab629f34c1823ea4c1542f32f07377208a86bdfd`, cross-checked against IB's published client; not
affiliated with Interactive Brokers.

Every table below is `ib_async`'s `client.py` / `decoder.py` evaluated at `serverVersion == 178`:
fields gated above 178 are dropped, fields gated at or below are kept. Defaults come from
`ib_async`'s `order.py`, `contract.py` and `objects.py`, passed through `Client.send`.

## Conventions

- **Frame.** Every message after the handshake is a 4-byte big-endian payload length, then the
  payload. The payload is a run of ASCII fields, each terminated by one NUL (`\0`), including
  the last. Field 0 is the message id as decimal text (`"3"`), never a binary int — the binary
  id only starts at server version 201.
- **Index.** `#` counts fields inside the payload, field 0 being the message id. The absolute
  indices are those of the **base case**: every conditional group absent. A conditional group
  is listed where it sits with `+` in the `#` column; when present it shifts every later index
  by its size.
- **Outgoing encoding** (`ib_async` `Client.send`): `bool` → `"1"` / `"0"`; `int` equal to
  UNSET_INTEGER (2147483647) → `""`; `double` equal to UNSET_DOUBLE (1.7976931348623157e308) →
  `""`; `double` +∞ → `"Infinite"`; other numbers → Python `str()` (`0.0` → `"0.0"`, `100` →
  `"100"`); `None` → `""`; a `TagValue` list in one field → `"tag=value;"` concatenated.
  Contract fields go through `str()` unconditionally (no UNSET mapping).
- **Incoming unset values.** A field may arrive empty or as a sentinel: `2147483647`,
  `9223372036854775807`, `1.7976931348623157E308` (IB's own decoder treats all three, and
  `-9223372036854775808`, as unset for decimals). Decode them as "no value".
- **"Version" fields.** Some messages still carry a per-message version number at 178; where
  they do it is a row of its own. Its value is constant on the way out and ignored on the way in.
- **Types.** `int` is a signed integer as text (`permId` can exceed Int32 — use 64 bits);
  `decimal` is a quantity sent as text (`"100"`, `"0.5"`); `double` a price as text; `bool`
  `"1"`/`"0"` (empty decodes as false); `string` as is.
- **★** marks a `placeOrder` row the `Contract` / `Order` model carries. Unstarred rows are sent
  with the default shown: msgId and orderId, the deprecated sharesAllocation, eTradeOnly,
  firmQuoteOnly and nbboPriceCap (never modelled).
  In `openOrder` and `completedOrder`, ★ marks a field read into the model; unstarred fields are
  skipped or land on the message (ids, status, filledQuantity, completedTime / Status).

## Handshake

Client → server, one write:

| Bytes | Content |
|---|---|
| 4 | `41 50 49 00` — the text `API` and one NUL, **not** length-prefixed |
| 4 | big-endian length of the version text: `00 00 00 09` |
| 9 | `v100..178` (`76 31 30 30 2E 2E 31 37 38`) — **no** trailing NUL |

`ib_async` itself sends `v157..178`; a connect option, when used, is appended after one space
(`v100..178 +PACEAPI`) and counted in the length.

Server → client, first frame: a normal length-prefixed frame of **two** NUL-terminated fields
and no message id.

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | serverVersion | int | the version the server picked, ≤ 178 here |
| 1 | connectionTime | string | server-local time text, e.g. `20261109 09:30:00 EST` (format illustrative) |

IB's own client loops until it sees a two-field frame (it notes other traffic may precede it);
`ib_async` treats the first two-field frame received before a version is known as the reply.

Then the client sends `startApi`. The connection is ready once both `nextValidId (in 9)` and
`managedAccounts (in 15)` have arrived (`ib_async` waits for both); other messages (e.g. `error`
notices about data farms) may interleave.

## Outgoing messages

### startApi (out 71)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `71` |
| 1 | version | int | `2` |
| 2 | clientId | int | (caller) |
| 3 | optionalCapabilities | string | `""` |

Total: 4 fields.

### reqIds (out 8)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `8` |
| 1 | version | int | `1` |
| 2 | numIds | int | (caller; the reply is `nextValidId (in 9)`) |

Total: 3 fields.

### placeOrder (out 3)

No version field at 178 (it stopped at server version 145). Base case: not `BAG`, no delta-neutral
order type, no scale increment, no hedge, no algo, not PEG BENCH / PEG BEST / PEG MID, no
conditions, exchange not `IBKRATS`. Every group `ib_async` sends is sent and no layout is refused;
the legs come from `contract.comboLegs`. Only marketData (reqMktData) and historicalData (reqHistoricalData) also send a `BAG`'s legs; every other request refuses a `BAG` contract.

| # | Field | Type | Default sent | Notes |
|---|---|---|---|---|
| 0 | msgId | int | `3` | |
| 1 | orderId | int | (caller) | |
| 2 | conId ★ | int | `0` | |
| 3 | symbol ★ | string | `""` | |
| 4 | secType ★ | string | `""` | |
| 5 | lastTradeDateOrContractMonth ★ | string | `""` | |
| 6 | strike ★ | double | `0.0` | `str()`, not UNSET-mapped |
| 7 | right ★ | string | `""` | |
| 8 | multiplier ★ | string | `""` | |
| 9 | exchange ★ | string | `""` | |
| 10 | primaryExchange ★ | string | `""` | |
| 11 | currency ★ | string | `""` | |
| 12 | localSymbol ★ | string | `""` | |
| 13 | tradingClass ★ | string | `""` | |
| 14 | secIdType ★ | string | `""` | |
| 15 | secId ★ | string | `""` | |
| 16 | action ★ | string | `""` | `BUY` / `SELL` / `SSHORT` |
| 17 | totalQuantity ★ | decimal | `0.0` | |
| 18 | orderType ★ | string | `""` | |
| 19 | lmtPrice ★ | double | `""` | UNSET |
| 20 | auxPrice ★ | double | `""` | UNSET |
| 21 | tif ★ | string | `""` | |
| 22 | ocaGroup ★ | string | `""` | |
| 23 | account ★ | string | `""` | |
| 24 | openClose ★ | string | `O` | see Disagreements |
| 25 | origin ★ | int | `0` | |
| 26 | orderRef ★ | string | `""` | |
| 27 | transmit ★ | bool | `1` | |
| 28 | parentId ★ | int | `0` | |
| 29 | blockOrder ★ | bool | `0` | |
| 30 | sweepToFill ★ | bool | `0` | |
| 31 | displaySize ★ | int | `0` | |
| 32 | triggerMethod ★ | int | `0` | |
| 33 | outsideRth ★ | bool | `0` | |
| 34 | hidden ★ | bool | `0` | |
| + | comboLegsCount ★ | int | `0` | only if secType == `BAG` (with the next 2 counts) |
| + | ↳ leg.conId ★ | int | | × comboLegsCount, 8 fields per leg |
| + | ↳ leg.ratio ★ | int | | |
| + | ↳ leg.action ★ | string | | |
| + | ↳ leg.exchange ★ | string | | |
| + | ↳ leg.openClose ★ | int | `0` | |
| + | ↳ leg.shortSaleSlot ★ | int | `0` | |
| + | ↳ leg.designatedLocation ★ | string | `""` | |
| + | ↳ leg.exemptCode ★ | int | `-1` | |
| + | orderComboLegsCount ★ | int | `0` | only if `BAG` |
| + | ↳ orderComboLeg.price ★ | double | `""` | × orderComboLegsCount |
| + | smartComboRoutingParamsCount ★ | int | `0` | only if `BAG` |
| + | ↳ tag ★ | string | | × count, 2 fields per element |
| + | ↳ value ★ | string | | |
| 35 | sharesAllocation | string | `""` | deprecated, always empty |
| 36 | discretionaryAmt ★ | double | `0.0` | |
| 37 | goodAfterTime ★ | string | `""` | |
| 38 | goodTillDate ★ | string | `""` | |
| 39 | faGroup ★ | string | `""` | |
| 40 | faMethod ★ | string | `""` | |
| 41 | faPercentage ★ | string | `""` | faProfile follows only below 177 — dropped |
| 42 | modelCode ★ | string | `""` | |
| 43 | shortSaleSlot ★ | int | `0` | |
| 44 | designatedLocation ★ | string | `""` | |
| 45 | exemptCode ★ | int | `-1` | |
| 46 | ocaType ★ | int | `0` | |
| 47 | rule80A ★ | string | `""` | |
| 48 | settlingFirm ★ | string | `""` | |
| 49 | allOrNone ★ | bool | `0` | |
| 50 | minQty ★ | int | `""` | UNSET |
| 51 | percentOffset ★ | double | `""` | UNSET |
| 52 | eTradeOnly | bool | `0` | deprecated, always false |
| 53 | firmQuoteOnly | bool | `0` | deprecated, always false |
| 54 | nbboPriceCap | double | `""` | deprecated, always UNSET |
| 55 | auctionStrategy ★ | int | `0` | |
| 56 | startingPrice ★ | double | `""` | UNSET |
| 57 | stockRefPrice ★ | double | `""` | UNSET |
| 58 | delta ★ | double | `""` | UNSET |
| 59 | stockRangeLower ★ | double | `""` | UNSET |
| 60 | stockRangeUpper ★ | double | `""` | UNSET |
| 61 | overridePercentageConstraints ★ | bool | `0` | |
| 62 | volatility ★ | double | `""` | sent only when orderType starts with `VOL`, else `""` (as `ib_async`) |
| 63 | volatilityType ★ | int | `""` | UNSET |
| 64 | deltaNeutralOrderType ★ | string | `""` | |
| 65 | deltaNeutralAuxPrice ★ | double | `""` | UNSET |
| + | deltaNeutralConId ★ | int | `0` | only if deltaNeutralOrderType ≠ `""`; 8 fields |
| + | deltaNeutralSettlingFirm ★ | string | `""` | |
| + | deltaNeutralClearingAccount ★ | string | `""` | |
| + | deltaNeutralClearingIntent ★ | string | `""` | |
| + | deltaNeutralOpenClose ★ | string | `""` | |
| + | deltaNeutralShortSale ★ | bool | `0` | |
| + | deltaNeutralShortSaleSlot ★ | int | `0` | |
| + | deltaNeutralDesignatedLocation ★ | string | `""` | |
| 66 | continuousUpdate ★ | bool | `0` | |
| 67 | referencePriceType ★ | int | `""` | UNSET |
| 68 | trailStopPrice ★ | double | `""` | UNSET |
| 69 | trailingPercent ★ | double | `""` | UNSET |
| 70 | scaleInitLevelSize ★ | int | `""` | UNSET |
| 71 | scaleSubsLevelSize ★ | int | `""` | UNSET |
| 72 | scalePriceIncrement ★ | double | `""` | UNSET |
| + | scalePriceAdjustValue ★ | double | `""` | only if 0 < scalePriceIncrement < UNSET; 7 fields |
| + | scalePriceAdjustInterval ★ | int | `""` | |
| + | scaleProfitOffset ★ | double | `""` | |
| + | scaleAutoReset ★ | bool | `0` | |
| + | scaleInitPosition ★ | int | `""` | |
| + | scaleInitFillQty ★ | int | `""` | |
| + | scaleRandomPercent ★ | bool | `0` | |
| 73 | scaleTable ★ | string | `""` | |
| 74 | activeStartTime ★ | string | `""` | |
| 75 | activeStopTime ★ | string | `""` | |
| 76 | hedgeType ★ | string | `""` | |
| + | hedgeParam ★ | string | `""` | only if hedgeType ≠ `""` |
| 77 | optOutSmartRouting ★ | bool | `0` | |
| 78 | clearingAccount ★ | string | `""` | |
| 79 | clearingIntent ★ | string | `""` | |
| 80 | notHeld ★ | bool | `0` | |
| 81 | deltaNeutralContractPresent ★ | bool | `0` | |
| + | deltaNeutralContract.conId ★ | int | | only if present = `1`; 3 fields |
| + | deltaNeutralContract.delta ★ | double | | |
| + | deltaNeutralContract.price ★ | double | | |
| 82 | algoStrategy ★ | string | `""` | |
| + | algoParamsCount ★ | int | `0` | only if algoStrategy ≠ `""` |
| + | ↳ tag ★ | string | | × algoParamsCount, 2 fields per element |
| + | ↳ value ★ | string | | |
| 83 | algoId ★ | string | `""` | |
| 84 | whatIf ★ | bool | `0` | |
| 85 | orderMiscOptions ★ | string | `""` | TagValue list as `tag=value;…` in one field |
| 86 | solicited ★ | bool | `0` | |
| 87 | randomizeSize ★ | bool | `0` | |
| 88 | randomizePrice ★ | bool | `0` | |
| + | referenceContractId ★ | int | `0` | only if orderType is `PEG BENCH` / `PEGBENCH`; 5 fields |
| + | isPeggedChangeAmountDecrease ★ | bool | `0` | |
| + | peggedChangeAmount ★ | double | `0.0` | |
| + | referenceChangeAmount ★ | double | `0.0` | |
| + | referenceExchangeId ★ | string | `""` | |
| 89 | conditionsCount ★ | int | `0` | |
| + | ↳ one condition ★ | | | × conditionsCount — see [Order condition element](#order-condition-element) |
| + | conditionsIgnoreRth ★ | bool | `0` | only if conditionsCount > 0 |
| + | conditionsCancelOrder ★ | bool | `0` | only if conditionsCount > 0 |
| 90 | adjustedOrderType ★ | string | `""` | |
| 91 | triggerPrice ★ | double | `""` | UNSET |
| 92 | lmtPriceOffset ★ | double | `""` | UNSET |
| 93 | adjustedStopPrice ★ | double | `""` | UNSET |
| 94 | adjustedStopLimitPrice ★ | double | `""` | UNSET |
| 95 | adjustedTrailingAmount ★ | double | `""` | UNSET |
| 96 | adjustableTrailingUnit ★ | int | `0` | |
| 97 | extOperator ★ | string | `""` | |
| 98 | softDollarTier.name ★ | string | `""` | |
| 99 | softDollarTier.value ★ | string | `""` | |
| 100 | cashQty ★ | double | `""` | UNSET |
| 101 | mifid2DecisionMaker ★ | string | `""` | |
| 102 | mifid2DecisionAlgo ★ | string | `""` | |
| 103 | mifid2ExecutionTrader ★ | string | `""` | |
| 104 | mifid2ExecutionAlgo ★ | string | `""` | |
| 105 | dontUseAutoPriceForHedge ★ | bool | `0` | |
| 106 | isOmsContainer ★ | bool | `0` | |
| 107 | discretionaryUpToLimitPrice ★ | bool | `0` | |
| 108 | usePriceMgmtAlgo ★ | bool | `0` | see Disagreements |
| 109 | duration ★ | int | `""` | UNSET (gate 158) |
| 110 | postToAts ★ | int | `""` | UNSET (gate 160) |
| 111 | autoCancelParent ★ | bool | `0` | gate 162 |
| 112 | advancedErrorOverride ★ | string | `""` | gate 166 |
| 113 | manualOrderTime ★ | string | `""` | gate 169 |
| + | minTradeQty ★ | int | `""` | gate 170; only if contract.exchange == `IBKRATS` |
| + | minCompeteSize ★ | int | `""` | gate 170; only if orderType `PEG BEST` / `PEGBEST` |
| + | competeAgainstBestOffset ★ | double | `""` | same condition; +∞ is sent as `Infinite` |
| + | midOffsetAtWhole ★ | double | `""` | if PEG BEST with competeAgainstBestOffset = +∞, or orderType `PEG MID` / `PEGMID` |
| + | midOffsetAtHalf ★ | double | `""` | same condition |

Total: 114 fields in the base case (indices 0–113). Nothing follows `manualOrderTime` at 178
(customerAccount 183, professionalCustomer 184, includeOvernight 189, manualOrderIndicator 192,
imbalanceOnly 199 are all above).

### cancelOrder (out 4)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `4` |
| 1 | version | int | `1` |
| 2 | orderId | int | (caller) |
| 3 | manualOrderCancelTime | string | `""` (gate 169); from `cancelOrder`'s `manualCancelOrderTime` |

Total: 4 fields. The version field is still sent at 178 (it goes away at 192).

### exerciseOptions (out 21)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `21` |
| 1 | version | int | `2` |
| 2 | reqId | int | (client) |
| 3-13 | conId, symbol, secType, lastTradeDateOrContractMonth, strike (double), right, multiplier, exchange, currency, localSymbol, tradingClass | | as the contract block, **without primaryExchange** |
| 14 | exerciseAction | int | (caller) 1 exercise, 2 lapse |
| 15 | exerciseQuantity | int | (caller) |
| 16 | account | string | (caller) |
| 17 | override | bool | `0` |

Total: 18 fields. A `BAG` contract is refused.

### reqOpenOrders (out 5)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `5` |
| 1 | version | int | `1` |

Total: 2 fields.

### reqAllOpenOrders (out 16)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `16` |
| 1 | version | int | `1` |

Total: 2 fields.

### reqAutoOpenOrders (out 15)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `15` |
| 1 | version | int | `1` |
| 2 | autoBind | bool | (caller; `ib_async`'s `IB.reqAutoOpenOrders` defaults to `1`) |

Total: 3 fields. Meaningful only for clientId 0 (per `ib_async`'s docstring).

### reqCurrentTime (out 49)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `49` |
| 1 | version | int | `1` |

Total: 2 fields. The reply is `currentTime (in 49)`.

### reqManagedAccts (out 17)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `17` |
| 1 | version | int | `1` |

Total: 2 fields. The reply is `managedAccounts (in 15)`.

### reqUserInfo (out 104)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `104` |
| 1 | reqId | int | (caller; no version field) |

Total: 2 fields. The reply is `userInfo (in 107)`; an error for the reqId fails it.

### setServerLogLevel (out 14)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `14` |
| 1 | version | int | `1` |
| 2 | logLevel | int | (caller; 1 system, 2 error, 3 warning, 4 information, 5 detail) |

Total: 3 fields. No reply.

### reqGlobalCancel (out 58)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `58` |
| 1 | version | int | `1` |

Total: 2 fields. No reply; each cancelled order reports through `orderStatus (in 3)`.

### reqCompletedOrders (out 99)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `99` |
| 1 | apiOnly | bool | (caller) |

Total: 2 fields. No version field.

### reqExecutions (out 7)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `7` |
| 1 | version | int | `3` |
| 2 | reqId | int | (caller) |
| 3 | filter.clientId | int | `0` |
| 4 | filter.acctCode | string | `""` |
| 5 | filter.time | string | `""` |
| 6 | filter.symbol | string | `""` |
| 7 | filter.secType | string | `""` |
| 8 | filter.exchange | string | `""` |
| 9 | filter.side | string | `""` |

Total: 10 fields. (lastNDays / specificDates start at 200.)

### reqPositions (out 61)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `61` |
| 1 | version | int | `1` |

Total: 2 fields. No reqId: one subscription per connection.

### reqAccountSummary (out 62)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `62` |
| 1 | version | int | `1` |
| 2 | reqId | int | (caller) |
| 3 | group | string | (caller; `All` for every account) |
| 4 | tags | string | (caller; comma-joined) |

Total: 5 fields.

### cancelAccountSummary (out 63)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `63` |
| 1 | version | int | `1` |
| 2 | reqId | int | (caller) |

Total: 3 fields.

### reqPnLSingle (out 94)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `94` |
| 1 | reqId | int | (caller) |
| 2 | account | string | (caller) |
| 3 | modelCode | string | `""` |
| 4 | conId | int | (caller) |

Total: 5 fields. No version field.

### cancelPnLSingle (out 95)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `95` |
| 1 | reqId | int | (caller) |

Total: 2 fields. No version field.

### reqAccountUpdates (out 6)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `6` |
| 1 | version | int | `2` |
| 2 | subscribe | bool | (caller) |
| 3 | acctCode | string | (caller) |

Total: 4 fields.

### cancelPositions (out 64)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `64` |
| 1 | version | int | `1` |

Total: 2 fields. Sent only by `disconnect()` from `.connected`, queued behind every pending frame.

### reqPositionsMulti (out 74)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `74` |
| 1 | version | int | `1` |
| 2 | reqId | int | (caller) |
| 3 | account | string | (caller) |
| 4 | modelCode | string | `""` |

Total: 5 fields.

### cancelPositionsMulti (out 75)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `75` |
| 1 | version | int | `1` |
| 2 | reqId | int | (caller) |

Total: 3 fields.

### reqAccountUpdatesMulti (out 76)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `76` |
| 1 | version | int | `1` |
| 2 | reqId | int | (caller) |
| 3 | account | string | (caller) |
| 4 | modelCode | string | `""` |
| 5 | ledgerAndNLV | bool | `0` |

Total: 6 fields.

### cancelAccountUpdatesMulti (out 77)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `77` |
| 1 | version | int | `1` |
| 2 | reqId | int | (caller) |

Total: 3 fields.

### reqPnL (out 92)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `92` |
| 1 | reqId | int | (caller) |
| 2 | account | string | (caller) |
| 3 | modelCode | string | `""` |

Total: 4 fields. No version field.

### cancelPnL (out 93)

| # | Field | Type | Default sent |
|---|---|---|---|
| 0 | msgId | int | `93` |
| 1 | reqId | int | (caller) |

Total: 2 fields.

### reqContractDetails (out 9)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `9` |
| 1 | version | int | `8` |
| 2 | reqId | int | |
| 3-14 | contract | | the 12-field contract block (rows 2-13 of placeOrder); `BAG` is refused |
| 15 | includeExpired | bool | `0` |
| 16 | secIdType | string | the contract's `secIDType` |
| 17 | secId | string | the contract's `secID` |
| 18 | issuerId | string | `""` |

Total: 19 fields.

### reqMatchingSymbols (out 81)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `81` |
| 1 | reqId | int | |
| 2 | pattern | string | |

Total: 3 fields. No version.

### reqMarketDataType (out 59)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `59` |
| 1 | version | int | `1` |
| 2 | marketDataType | int | 1 real-time, 2 frozen, 3 delayed, 4 delayed-frozen |

Total: 3 fields. Session-global, no reqId; not remembered across a reconnect.

### reqMktData (out 1)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `1` |
| 1 | version | int | `11` |
| 2 | reqId | int | |
| 3-14 | contract | | the 12-field contract block |
| + | comboLegsCount | int | only if secType == `BAG` |
| + | conId, ratio, action, exchange | int, int, string, string | per leg, only for `BAG` |
| 15 | deltaNeutralContractPresent | bool | `0`, or `1` when `Contract.deltaNeutralContract` is set |
| + | conId, delta, price | int, double, double | only after a `1` in row 15 |
| 16 | genericTickList | string | `genericTicks` comma-joined, `""` when none |
| 17 | snapshot | bool | `0` |
| 18 | regulatorySnapshot | bool | `0` |
| 19 | mktDataOptions | string | `""`, always sent |

Row numbers are for a plain contract: 20 fields. A `BAG` adds the count and 4 fields per leg after row 14, and a
delta-neutral contract adds 3 fields after row 15.

### cancelMktData (out 2)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `2` |
| 1 | version | int | `2` |
| 2 | reqId | int | |

Total: 3 fields.

Sent when the consumer stops the stream, and when IB refuses it for want of permission (354, 10089, 10168, 10186,
10197): IB keeps a refused subscription open.

### Order condition element

One element of the `placeOrder` / `openOrder` / `completedOrder` conditions group. The same
layout both ways; `ib_async` sends a condition dataclass's fields in declaration order.

| # | Field | Type | Default sent | Present for type |
|---|---|---|---|---|
| c0 | conditionType | int | | all: 1 Price, 3 Time, 4 Margin, 5 Execution, 6 Volume, 7 PercentChange |
| c1 | conjunction | string | `a` | all: `a` = and, `o` = or |
| c2 | isMore | bool | `1` | 1, 3, 4, 6, 7 |
| c3 | value | | | 1 price (double), 3 time (string), 4 percent (int), 6 volume (int), 7 changePercent (double) |
| c4 | conId | int | `0` | 1, 6, 7 |
| c5 | exchange | string | `""` | 1, 6, 7 |
| c6 | triggerMethod | int | `0` | 1 only |

Execution (5) has instead, after the conjunction: secType (string), exchange (string), symbol
(string). Element sizes: Price 7, Time 4, Margin 4, Execution 5, Volume 6, PercentChange 6.

In Swift each type is a case of `OrderCondition`: 1 `.price`, 3 `.time`, 4 `.margin`, 5 `.execution`,
6 `.volume`, 7 `.percentChange`; the conjunction is `OrderCondition.Conjunction` (`.and`, `.or`).
`ib_async`'s `exch` is `exchange`. On the way in, any other type or conjunction makes the frame
malformed.

## Incoming messages

### orderStatus (in 3)

No version field at 178 (it stopped at 131).

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `3` |
| 1 | orderId | int | 0 for orders placed by hand in TWS (design spec) |
| 2 | status | string | |
| 3 | filled | decimal | |
| 4 | remaining | decimal | |
| 5 | avgFillPrice | double | |
| 6 | permId | int | |
| 7 | parentId | int | |
| 8 | lastFillPrice | double | |
| 9 | clientId | int | |
| 10 | whyHeld | string | |
| 11 | mktCapPrice | double | |

Total: 12 fields.

### error (in 4)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `4` |
| 1 | version | int | ignored (removed at 194) |
| 2 | reqId | int | order id / request id; -1 when not order-related (`ib_async` wrapper comment) |
| 3 | errorCode | int | |
| 4 | errorString | string | `\uXXXX` escapes are decoded (surrogate pairs joined, malformed ones kept literal) |
| 5 | advancedOrderRejectJson | string | gate 166; usually empty; kept raw, not unescaped |

Total: 6 fields. errorTime arrives only from 194.

### openOrder (in 5)

No version field at 178 (it stopped at 145). Base case as for `placeOrder`, and no combo legs,
no smart-routing params.

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `5` |
| 1 | orderId | int | |
| 2 | conId ★ | int | |
| 3 | symbol ★ | string | |
| 4 | secType ★ | string | |
| 5 | lastTradeDateOrContractMonth ★ | string | |
| 6 | strike ★ | double | |
| 7 | right ★ | string | |
| 8 | multiplier ★ | string | |
| 9 | exchange ★ | string | |
| 10 | currency ★ | string | no primaryExchange here |
| 11 | localSymbol ★ | string | |
| 12 | tradingClass ★ | string | |
| 13 | action ★ | string | |
| 14 | totalQuantity ★ | decimal | |
| 15 | orderType ★ | string | |
| 16 | lmtPrice ★ | double | |
| 17 | auxPrice ★ | double | |
| 18 | tif ★ | string | |
| 19 | ocaGroup ★ | string | |
| 20 | account ★ | string | |
| 21 | openClose ★ | string | |
| 22 | origin ★ | int | |
| 23 | orderRef ★ | string | |
| 24 | clientId | int | |
| 25 | permId | int | |
| 26 | outsideRth ★ | bool | |
| 27 | hidden ★ | bool | |
| 28 | discretionaryAmt ★ | double | |
| 29 | goodAfterTime ★ | string | |
| 30 | sharesAllocation | string | deprecated, skip |
| 31 | faGroup ★ | string | |
| 32 | faMethod ★ | string | |
| 33 | faPercentage ★ | string | faProfile only below 177 — absent |
| 34 | modelCode ★ | string | |
| 35 | goodTillDate ★ | string | |
| 36 | rule80A ★ | string | |
| 37 | percentOffset ★ | double | |
| 38 | settlingFirm ★ | string | |
| 39 | shortSaleSlot ★ | int | |
| 40 | designatedLocation ★ | string | |
| 41 | exemptCode ★ | int | `""` → `-1` |
| 42 | auctionStrategy ★ | int | |
| 43 | startingPrice ★ | double | |
| 44 | stockRefPrice ★ | double | |
| 45 | delta ★ | double | |
| 46 | stockRangeLower ★ | double | |
| 47 | stockRangeUpper ★ | double | |
| 48 | displaySize ★ | int | |
| 49 | blockOrder ★ | bool | |
| 50 | sweepToFill ★ | bool | |
| 51 | allOrNone ★ | bool | |
| 52 | minQty ★ | int | |
| 53 | ocaType ★ | int | |
| 54 | eTradeOnly | bool | deprecated, skip |
| 55 | firmQuoteOnly | bool | deprecated, skip |
| 56 | nbboPriceCap | double | deprecated, skip |
| 57 | parentId ★ | int | |
| 58 | triggerMethod ★ | int | |
| 59 | volatility ★ | double | |
| 60 | volatilityType ★ | int | |
| 61 | deltaNeutralOrderType ★ | string | |
| 62 | deltaNeutralAuxPrice ★ | double | |
| + | deltaNeutralConId ★ | int | only if deltaNeutralOrderType ≠ `""`; 8 fields. The live gateway sends `None` for a plain order, so the group is present (Disagreements 9) |
| + | deltaNeutralSettlingFirm ★ | string | |
| + | deltaNeutralClearingAccount ★ | string | |
| + | deltaNeutralClearingIntent ★ | string | |
| + | deltaNeutralOpenClose ★ | string | |
| + | deltaNeutralShortSale ★ | bool | |
| + | deltaNeutralShortSaleSlot ★ | int | |
| + | deltaNeutralDesignatedLocation ★ | string | |
| 63 | continuousUpdate ★ | bool | |
| 64 | referencePriceType ★ | int | |
| 65 | trailStopPrice ★ | double | overwritten by #105 in both clients |
| 66 | trailingPercent ★ | double | |
| 67 | basisPoints ★ | double | |
| 68 | basisPointsType ★ | int | |
| 69 | comboLegsDescrip ★ | string | |
| 70 | comboLegsCount ★ | int | always present |
| + | ↳ leg: conId int, ratio int, action string, exchange string, openClose int, shortSaleSlot int, designatedLocation string, exemptCode int ★ | | × comboLegsCount, 8 fields per leg |
| 71 | orderComboLegsCount ★ | int | always present |
| + | ↳ price ★ | double | × orderComboLegsCount |
| 72 | smartComboRoutingParamsCount ★ | int | always present |
| + | ↳ tag, value ★ | string, string | × count, 2 fields per element |
| 73 | scaleInitLevelSize ★ | int | |
| 74 | scaleSubsLevelSize ★ | int | |
| 75 | scalePriceIncrement ★ | double | |
| + | scalePriceAdjustValue double, scalePriceAdjustInterval int, scaleProfitOffset double, scaleAutoReset bool, scaleInitPosition int, scaleInitFillQty int, scaleRandomPercent bool ★ | | only if 0 < scalePriceIncrement < UNSET; 7 fields |
| 76 | hedgeType ★ | string | |
| + | hedgeParam ★ | string | only if hedgeType ≠ `""` |
| 77 | optOutSmartRouting ★ | bool | |
| 78 | clearingAccount ★ | string | |
| 79 | clearingIntent ★ | string | |
| 80 | notHeld ★ | bool | |
| 81 | deltaNeutralContractPresent ★ | bool | |
| + | conId int, delta double, price double ★ | | only if present; 3 fields |
| 82 | algoStrategy ★ | string | |
| + | algoParamsCount ★ | int | only if algoStrategy ≠ `""` |
| + | ↳ tag, value ★ | string, string | × algoParamsCount |
| 83 | solicited ★ | bool | |
| 84 | whatIf ★ | bool | |
| 85 | status | string | OrderState.status |
| 86 | initMarginBefore ★ | string | `OrderState`, `Decimal?`; `""`, the sentinels and unparseable text → nil (`ib_async` keeps it a string) |
| 87 | maintMarginBefore ★ | string | `OrderState`, as 86 |
| 88 | equityWithLoanBefore ★ | string | `OrderState`, as 86 |
| 89 | initMarginChange ★ | string | `OrderState`, as 86 |
| 90 | maintMarginChange ★ | string | `OrderState`, as 86 |
| 91 | equityWithLoanChange ★ | string | `OrderState`, as 86 |
| 92 | initMarginAfter ★ | string | `OrderState`, as 86 |
| 93 | maintMarginAfter ★ | string | `OrderState`, as 86 |
| 94 | equityWithLoanAfter ★ | string | `OrderState`, as 86 |
| 95 | commission ★ | double | `OrderState`, `Decimal?`; `""` and the sentinels → nil |
| 96 | minCommission ★ | double | `OrderState`, as 95 |
| 97 | maxCommission ★ | double | `OrderState`, as 95 |
| 98 | commissionCurrency ★ | string | `OrderState` |
| 99 | warningText ★ | string | `OrderState`; (the outside-RTH margin block starts at 195 — absent) |
| 100 | randomizeSize ★ | bool | |
| 101 | randomizePrice ★ | bool | |
| + | referenceContractId int, isPeggedChangeAmountDecrease bool, peggedChangeAmount double, referenceChangeAmount double, referenceExchangeId string ★ | | only if orderType `PEG BENCH` / `PEGBENCH`; 5 fields |
| 102 | conditionsCount ★ | int | |
| + | ↳ one condition ★ | | × conditionsCount — see [Order condition element](#order-condition-element) |
| + | conditionsIgnoreRth, conditionsCancelOrder ★ | bool, bool | only if conditionsCount > 0 |
| 103 | adjustedOrderType ★ | string | |
| 104 | triggerPrice ★ | double | |
| 105 | trailStopPrice ★ | double | second occurrence |
| 106 | lmtPriceOffset ★ | double | |
| 107 | adjustedStopPrice ★ | double | |
| 108 | adjustedStopLimitPrice ★ | double | |
| 109 | adjustedTrailingAmount ★ | double | |
| 110 | adjustableTrailingUnit ★ | int | |
| 111 | softDollarTier.name ★ | string | |
| 112 | softDollarTier.value ★ | string | |
| 113 | softDollarTier.displayName ★ | string | |
| 114 | cashQty ★ | double | |
| 115 | dontUseAutoPriceForHedge ★ | bool | |
| 116 | isOmsContainer ★ | bool | |
| 117 | discretionaryUpToLimitPrice ★ | bool | |
| 118 | usePriceMgmtAlgo ★ | bool | |
| 119 | duration ★ | int | |
| 120 | postToAts ★ | int | |
| 121 | autoCancelParent ★ | bool | |
| 122 | minTradeQty ★ | int | gate 170, always present |
| 123 | minCompeteSize ★ | int | |
| 124 | competeAgainstBestOffset ★ | double | `Infinite` = +∞ |
| 125 | midOffsetAtWhole ★ | double | |
| 126 | midOffsetAtHalf ★ | double | |

Total: 127 fields in the base case (indices 0–126).

### nextValidId (in 9)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `9` |
| 1 | version | int | ignored |
| 2 | orderId | int | next usable order id |

Total: 3 fields.

### execDetails (in 11)

No version field at 178 (it stopped at 136).

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `11` |
| 1 | reqId | int | a reqId with no pending `reqExecutions` is a live fill (`ib_async`) |
| 2 | orderId | int | |
| 3 | conId | int | |
| 4 | symbol | string | |
| 5 | secType | string | |
| 6 | lastTradeDateOrContractMonth | string | |
| 7 | strike | double | |
| 8 | right | string | |
| 9 | multiplier | string | |
| 10 | exchange | string | contract exchange |
| 11 | currency | string | |
| 12 | localSymbol | string | |
| 13 | tradingClass | string | |
| 14 | execId | string | |
| 15 | time | string | `20261110-11:56:31` (UTC) live, `20261110 06:56:31 US/Eastern` in the reqExecutions reply |
| 16 | acctNumber | string | |
| 17 | exchange | string | execution exchange |
| 18 | side | string | `BOT` / `SLD` |
| 19 | shares | decimal | |
| 20 | price | double | |
| 21 | permId | int | |
| 22 | clientId | int | |
| 23 | liquidation | int | |
| 24 | cumQty | decimal | |
| 25 | avgPrice | double | |
| 26 | orderRef | string | |
| 27 | evRule | string | |
| 28 | evMultiplier | double | |
| 29 | modelCode | string | |
| 30 | lastLiquidity | int | |
| 31 | pendingPriceRevision | bool | gate 178 — present |

Total: 32 fields. submitter arrives only from 198.

### managedAccounts (in 15)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `15` |
| 1 | version | int | ignored |
| 2 | accountsList | string | comma-separated; may end in a comma — drop empty items |

Total: 3 fields.

### currentTime (in 49)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `49` |
| 1 | version | int | ignored |
| 2 | time | int | Unix seconds |

Total: 3 fields.

### userInfo (in 107)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `107` |
| 1 | reqId | int | no version field |
| 2 | whiteBrandingId | string | `""` for most accounts |

Total: 3 fields.

### openOrderEnd (in 53)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `53` |
| 1 | version | int | ignored |

Total: 2 fields.

### execDetailsEnd (in 55)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `55` |
| 1 | version | int | ignored |
| 2 | reqId | int | |

Total: 3 fields.

### commissionReport (in 59)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `59` |
| 1 | version | int | ignored |
| 2 | execId | string | |
| 3 | commission | double | |
| 4 | currency | string | |
| 5 | realizedPNL | double | may be the UNSET sentinel |
| 6 | yield | double | may be the UNSET sentinel |
| 7 | yieldRedemptionDate | int | empty decodes as 0 (`ib_async`) |

Total: 8 fields.

### position (in 61)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `61` |
| 1 | version | int | ignored |
| 2 | account | string | |
| 3-13 | contract | | conId, symbol, secType, lastTradeDateOrContractMonth, strike, right, multiplier, exchange, currency, localSymbol, tradingClass (no primaryExchange) |
| 14 | position | double | |
| 15 | avgCost | double | |

Total: 16 fields.

### positionEnd (in 62)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `62` |
| 1 | version | int | ignored |

Total: 2 fields.

### accountSummary (in 63)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `63` |
| 1 | version | int | ignored |
| 2 | reqId | int | |
| 3 | account | string | |
| 4 | tag | string | |
| 5 | value | string | text for some tags (`AccountType`) |
| 6 | currency | string | |

Total: 7 fields.

### accountSummaryEnd (in 64)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `64` |
| 1 | version | int | ignored |
| 2 | reqId | int | |

Total: 3 fields.

### pnlSingle (in 95)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `95` |
| 1 | reqId | int | |
| 2 | pos | double | |
| 3 | dailyPnL | double | may be the UNSET sentinel |
| 4 | unrealizedPnL | double | may be the UNSET sentinel |
| 5 | realizedPnL | double | may be the UNSET sentinel |
| 6 | value | double | may be the UNSET sentinel |

Total: 7 fields. No version field.

### updateAccountValue (in 6)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `6` |
| 1 | version | int | ignored |
| 2 | key | string | |
| 3 | value | string | text for some keys |
| 4 | currency | string | |
| 5 | accountName | string | |

Total: 6 fields.

### updatePortfolio (in 7)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `7` |
| 1 | version | int | ignored |
| 2-12 | contract | | conId, symbol, secType, lastTradeDateOrContractMonth, strike, right, multiplier, **primaryExchange**, currency, localSymbol, tradingClass; read as the exchange slot, then moved to `primaryExchange` (`exchange` is `""`) |
| 13 | position | double | |
| 14 | marketPrice | double | |
| 15 | marketValue | double | |
| 16 | averageCost | double | |
| 17 | unrealizedPNL | double | may be the UNSET sentinel |
| 18 | realizedPNL | double | may be the UNSET sentinel |
| 19 | accountName | string | |

Total: 20 fields.

### updateAccountTime (in 8)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `8` |
| 1 | version | int | ignored |
| 2 | timestamp | string | |

Total: 3 fields.

### accountDownloadEnd (in 54)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `54` |
| 1 | version | int | ignored |
| 2 | accountName | string | |

Total: 3 fields.

### positionMulti (in 71)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `71` |
| 1 | version | int | ignored |
| 2 | reqId | int | |
| 3 | account | string | |
| 4-14 | contract | | conId, symbol, secType, lastTradeDateOrContractMonth, strike, right, multiplier, exchange, currency, localSymbol, tradingClass (as in position, in 61) |
| 15 | position | double | |
| 16 | avgCost | double | |
| 17 | modelCode | string | |

Total: 18 fields.

### positionMultiEnd (in 72)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `72` |
| 1 | version | int | ignored |
| 2 | reqId | int | |

Total: 3 fields.

### accountUpdateMulti (in 73)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `73` |
| 1 | version | int | ignored |
| 2 | reqId | int | |
| 3 | account | string | |
| 4 | modelCode | string | |
| 5 | key | string | |
| 6 | value | string | |
| 7 | currency | string | |

Total: 8 fields.

### accountUpdateMultiEnd (in 74)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `74` |
| 1 | version | int | ignored |
| 2 | reqId | int | |

Total: 3 fields.

### pnl (in 94)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `94` |
| 1 | reqId | int | |
| 2 | dailyPnL | double | may be the UNSET sentinel |
| 3 | unrealizedPnL | double | may be the UNSET sentinel |
| 4 | realizedPnL | double | may be the UNSET sentinel |

Total: 5 fields. No version field.

### orderBound (in 100)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `100` |
| 1 | permId | int | `ib_async`'s wrapper calls it `reqId`; IB's client `permId` |
| 2 | apiClientId | int | |
| 3 | apiOrderId | int | |

Total: 4 fields. No version field.

### completedOrder (in 101)

**There is no orderId field at version 178** — the message starts directly with the contract.
The Swift side uses orderId 0 and keys completed orders by permId. There is no clientId either.
No version field. Base case as for `openOrder`.

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `101` |
| 1 | conId ★ | int | |
| 2 | symbol ★ | string | |
| 3 | secType ★ | string | |
| 4 | lastTradeDateOrContractMonth ★ | string | |
| 5 | strike ★ | double | |
| 6 | right ★ | string | |
| 7 | multiplier ★ | string | |
| 8 | exchange ★ | string | |
| 9 | currency ★ | string | |
| 10 | localSymbol ★ | string | |
| 11 | tradingClass ★ | string | |
| 12 | action ★ | string | |
| 13 | totalQuantity ★ | decimal | |
| 14 | orderType ★ | string | |
| 15 | lmtPrice ★ | double | |
| 16 | auxPrice ★ | double | |
| 17 | tif ★ | string | |
| 18 | ocaGroup ★ | string | |
| 19 | account ★ | string | |
| 20 | openClose ★ | string | |
| 21 | origin ★ | int | |
| 22 | orderRef ★ | string | |
| 23 | permId | int | the key |
| 24 | outsideRth ★ | bool | |
| 25 | hidden ★ | bool | |
| 26 | discretionaryAmt ★ | double | |
| 27 | goodAfterTime ★ | string | no sharesAllocation here |
| 28 | faGroup ★ | string | |
| 29 | faMethod ★ | string | |
| 30 | faPercentage ★ | string | faProfile only below 177 — absent |
| 31 | modelCode ★ | string | |
| 32 | goodTillDate ★ | string | |
| 33 | rule80A ★ | string | |
| 34 | percentOffset ★ | double | |
| 35 | settlingFirm ★ | string | |
| 36 | shortSaleSlot ★ | int | |
| 37 | designatedLocation ★ | string | |
| 38 | exemptCode ★ | int | `""` → `-1`; no auctionStrategy here |
| 39 | startingPrice ★ | double | |
| 40 | stockRefPrice ★ | double | |
| 41 | delta ★ | double | |
| 42 | stockRangeLower ★ | double | |
| 43 | stockRangeUpper ★ | double | |
| 44 | displaySize ★ | int | no blockOrder here |
| 45 | sweepToFill ★ | bool | |
| 46 | allOrNone ★ | bool | |
| 47 | minQty ★ | int | |
| 48 | ocaType ★ | int | no eTradeOnly / firmQuoteOnly / nbboPriceCap / parentId here |
| 49 | triggerMethod ★ | int | |
| 50 | volatility ★ | double | |
| 51 | volatilityType ★ | int | |
| 52 | deltaNeutralOrderType ★ | string | |
| 53 | deltaNeutralAuxPrice ★ | double | |
| + | deltaNeutralConId int, deltaNeutralShortSale bool, deltaNeutralShortSaleSlot int, deltaNeutralDesignatedLocation string ★ | | only if deltaNeutralOrderType ≠ `""`; **4** fields (no settlingFirm / clearing / openClose); expect it present (`None`, Disagreements 9) |
| 54 | continuousUpdate ★ | bool | |
| 55 | referencePriceType ★ | int | |
| 56 | trailStopPrice ★ | double | overwritten by #76 in both clients |
| 57 | trailingPercent ★ | double | no basisPoints here |
| 58 | comboLegsDescrip ★ | string | |
| 59 | comboLegsCount ★ | int | always present |
| + | ↳ leg: 8 fields as in `openOrder` ★ | | × comboLegsCount |
| 60 | orderComboLegsCount ★ | int | always present |
| + | ↳ price ★ | double | × orderComboLegsCount |
| 61 | smartComboRoutingParamsCount ★ | int | always present |
| + | ↳ tag, value ★ | string, string | × count |
| 62 | scaleInitLevelSize ★ | int | |
| 63 | scaleSubsLevelSize ★ | int | |
| 64 | scalePriceIncrement ★ | double | |
| + | the 7 scale fields as in `openOrder` ★ | | only if 0 < scalePriceIncrement < UNSET |
| 65 | hedgeType ★ | string | |
| + | hedgeParam ★ | string | only if hedgeType ≠ `""` |
| 66 | clearingAccount ★ | string | no optOutSmartRouting here |
| 67 | clearingIntent ★ | string | |
| 68 | notHeld ★ | bool | |
| 69 | deltaNeutralContractPresent ★ | bool | |
| + | conId int, delta double, price double ★ | | only if present |
| 70 | algoStrategy ★ | string | |
| + | algoParamsCount, then tag/value pairs ★ | | only if algoStrategy ≠ `""` |
| 71 | solicited ★ | bool | no whatIf here |
| 72 | status | string | OrderState.status; no margin / commission block |
| 73 | randomizeSize ★ | bool | |
| 74 | randomizePrice ★ | bool | |
| + | the 5 PEG BENCH fields as in `openOrder` ★ | | only if orderType `PEG BENCH` / `PEGBENCH` |
| 75 | conditionsCount ★ | int | |
| + | ↳ one condition ★ | | × conditionsCount — see [Order condition element](#order-condition-element) |
| + | conditionsIgnoreRth, conditionsCancelOrder ★ | bool, bool | only if conditionsCount > 0 |
| 76 | trailStopPrice ★ | double | second occurrence; no adjusted-order block here |
| 77 | lmtPriceOffset ★ | double | |
| 78 | cashQty ★ | double | no softDollarTier here |
| 79 | dontUseAutoPriceForHedge ★ | bool | |
| 80 | isOmsContainer ★ | bool | |
| 81 | autoCancelDate ★ | string | |
| 82 | filledQuantity | decimal | |
| 83 | refFuturesConId ★ | int | |
| 84 | autoCancelParent ★ | bool | |
| 85 | shareholder ★ | string | |
| 86 | imbalanceOnly ★ | bool | always present in completedOrder (unlike placeOrder / openOrder) |
| 87 | routeMarketableToBbo ★ | bool | |
| 88 | parentPermId ★ | int | |
| 89 | completedTime | string | |
| 90 | completedStatus | string | |
| 91 | minTradeQty ★ | int | gate 170, always present |
| 92 | minCompeteSize ★ | int | |
| 93 | competeAgainstBestOffset ★ | double | |
| 94 | midOffsetAtWhole ★ | double | |
| 95 | midOffsetAtHalf ★ | double | |

Total: 96 fields in the base case (indices 0–95). customerAccount (183), professionalCustomer
(184) and submitter (198) are above 178.

### completedOrdersEnd (in 102)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `102` |

Total: 1 field. No version field.

### contractData (in 10)

No version field and no mdSizeMultiplier at 178; field 1 is the reqId.

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `10` |
| 1 | reqId | int | |
| 2 | symbol | string | |
| 3 | secType | string | |
| 4 | lastTimes | string | kept whole in `lastTradeDateOrContractMonth` (empty for STK), not split |
| 5 | strike | double | |
| 6 | right | string | kept as sent (`?` for non-options is possible) |
| 7 | exchange | string | |
| 8 | currency | string | |
| 9 | localSymbol | string | |
| 10 | marketName | string | |
| 11 | tradingClass | string | |
| 12 | conId | int | |
| 13 | minTick | double | |
| 14 | multiplier | string | |
| 15 | orderTypes | string | comma list; `""` is `[]` |
| 16 | validExchanges | string | comma list; `""` is `[]` |
| 17 | priceMagnifier | int | |
| 18 | underConId | int | skipped |
| 19 | longName | string | not unicode-unescaped |
| 20 | primaryExchange | string | |
| 21-24 | contractMonth, industry, category, subcategory | string | skipped |
| 25 | timeZoneId | string | |
| 26 | tradingHours | string | raw |
| 27 | liquidHours | string | raw |
| 28-29 | evRule, evMultiplier | | skipped |
| 30 | numSecIds | int | |
| + | secIdList | | numSecIds x (tag, value), skipped |
| 31 | aggGroup | int | skipped |
| 32-35 | underSymbol, underSecType, marketRuleIds, realExpirationDate | string | skipped |
| 36 | stockType | string | |
| 37 | minSize | decimal | unset reads as nil |
| 38 | sizeIncrement | decimal | |
| 39 | suggestedSizeIncrement | decimal | |

Total: 40 fields plus 2 per secId. Fields past 39 are ignored by position.

### contractDataEnd (in 52)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `52` |
| 1 | version | int | ignored |
| 2 | reqId | int | |

Total: 3 fields.

### symbolSamples (in 79)

`79, reqId, n`, then n entries. No version.

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | conId | int | |
| 1 | symbol | string | |
| 2 | secType | string | |
| 3 | primaryExchange | string | the contract's `exchange` stays `""` |
| 4 | currency | string | |
| 5 | numDerivativeSecTypes | int | m |
| 6.. | derivativeSecType | string | m of them |
| next | description | string | |
| next | issuerId | string | |

Entry size is 8 + m fields.

### tickPrice (in 1)

| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | int | `1` |
| 1 | version | int | ignored |
| 2 | reqId | int | |
| 3 | tickType | int | kept whole as a `TickField` |
| 4 | price | decimal | empty/unset is `nil`; IB's `-1` stays `-1` |
| 5 | size | decimal | empty/unset is `nil` |
| 6 | attribMask | int | read and dropped |

Total: 7 fields.

### tickSize (in 2)

`2, version, reqId, tickType, size`; 5 fields. `size` empty/unset is `nil`.

### tickGeneric (in 45)

`45, version, reqId, tickType, value`; 5 fields. `value` is a double on the wire, read as a decimal.

### tickString (in 46)

`46, version, reqId, tickType, value`; 5 fields.

### marketDataType (in 58)

`58, version, reqId, marketDataType`; 4 fields. A value outside 1-4 is malformed.

### tickSnapshotEnd (in 57)

`57, version, reqId`; 3 fields. Ends a snapshot request: the stream finishes and sends no cancel.

### tickReqParams (in 81)

`81, reqId, minTick, bboExchange, snapshotPermissions`; 5 fields. No version. Decoded as a tick
(`Tick.requestParameters`) and yielded by `marketData`. `minTick` empty/unset is `nil`.

### tickOptionComputation (in 21)

No version. 12 fields: `21, reqId, tickType, tickAttrib, impliedVol, delta, optPrice, pvDividend, gamma, vega,
theta, undPrice`. Every value is a double on the wire, read as an optional decimal (empty/unset is `nil`). IB's
"not computed" is `nil` too: `-1` for impliedVol, optPrice, pvDividend and undPrice, `-2` for delta, gamma, vega and
theta. The delayed greek fields 80-83 map to 10-13 through `TickField.live`.

### tickEFP (in 47)

11 fields: `47, version, reqId, tickType, basisPoints, formattedBasisPoints, impliedFuture, holdDays,
futureLastTradeDate, dividendImpact, dividendsToLastTradeDate`. The version is ignored; holdDays is an int, the
decimals and holdDays are `nil` when empty/unset, the two strings are kept as sent.

### tickNews (in 84)

No version. 7 fields: `84, reqId, timeStamp, providerCode, articleId, headline, extraData`. `timeStamp` is kept as
IB's raw int, its unit undocumented.

### deltaNeutralValidation (in 56)

6 fields: `56, version, reqId, conId, delta, price`. The version is ignored; `delta` and `price` are read with
`decimal()` (`ib_async` reads `float(x or 0)`). IB sends it when a delta-neutral contract given to `reqMktData` is
accepted; it reaches `messages()` only.

### rerouteMktDataReq (in 91)

4 fields: `91, reqId, conId, exchange`, no version. IB answers a `reqMktData` it serves from another contract (for
example an IDEALPRO one) with it, and then sends the ticks under the same reqId; it reaches `messages()` only.

### rerouteMktDepthReq (in 92)

Same layout as 91 (`92, reqId, conId, exchange`), for `reqMktDepth`; it reaches `messages()` only.

### reqHistoricalData (out 20)

No version field. 23 fields: `20, reqId, contract(12), includeExpired (0), endDateTime, barSize, duration, useRTH,
whatToShow, formatDate, keepUpToDate, chartOptions`. Barsize comes before duration and useRTH before whatToShow.
`formatDate` is `1` for `whatToShow` `SCHEDULE` (text times) and `2` otherwise; `chartOptions` always `""`.
`endDateTime` is `yyyyMMdd-HH:mm:ss` in UTC, or `""` for now (`keepUpToDate` needs `""`). A `BAG` adds
`comboLegsCount` and 4 fields per leg (`conId, ratio, action, exchange`) after `formatDate`, before `keepUpToDate`.
`historicalBars` refuses `SCHEDULE` (its answer is 106, not 17); use `historicalSchedule`.

### cancelHistoricalData (out 25)

`25, 1, reqId`; 3 fields. Sent when the consumer stops a stream still registered, including a keepUpToDate one. Also sent when IB refuses the stream for want of permission (162 with a permission text): IB keeps a refused subscription open.

### historicalData (in 17)

No version. `17, reqId, startDate, endDate, numBars`, then `numBars` bars of 8 fields in the order O,H,L,C:
`date, open, high, low, close, volume, average, barCount`. startDate and endDate are read and dropped. The message is the
whole batch and its own end marker (there is no in-108 at 178). `average` is `nil` when unset; `volume` keeps IB's `-1`.
A bar `date` of 8 characters is that day at 00:00 UTC (checked first: daily bars are dates under either formatDate); all
digits is epoch seconds; anything else (formatDate 1 text) is malformed. A negative count (17's numBars, 79's
n and m, 10's numSecIds) makes the frame malformed, as everywhere in the decoder.

### historicalSchedule (in 106)

No version. `106, reqId, startDateTime, endDateTime, timeZone, count`, then `count` sessions of 3 fields:
`startDateTime, endDateTime, refDate`. All are kept as IB's text (`yyyyMMdd-HH:mm:ss`, `refDate` `yyyyMMdd`). It is the
answer to reqHistoricalData with `whatToShow` `SCHEDULE`, `barSize` `1 day` and `duration` `"N D"`; a refusal is the
usual error, and a permission refusal needs the cancel (25). A negative count makes the frame malformed.

### reqHistoricalTicks (out 96)

No version. 22 fields: `96, reqId, contract(12), includeExpired (0), startDateTime, endDateTime, numberOfTicks,
whatToShow, useRth, ignoreSize, miscOptions ("")`. Each date is `yyyyMMdd-HH:mm:ss` UTC, or `""` for unset. A BAG contract
is refused. IB has no cancel for it.

### historicalTicks / historicalTicksBidAsk / historicalTicksLast (in 96, 97, 98)

No version, one reqId; the same frame shape: `id, reqId, n, n rows, done`, with `done` a bool that ends the answer.
Rows: 96 (midpoint) `time, unused, price, size`; 97 (bid/ask) `time, mask, bidPrice, askPrice, bidSize, askSize`;
98 (last) `time, mask, price, size, exchange, specialConditions`. `time` is Unix seconds. The 96 size and the 97 mask are
read and dropped; the 98 mask is bit 0 pastLimit, bit 1 unreported. A negative `n` makes the frame malformed.

### reqHeadTimeStamp (out 87)

No version. 18 fields: `87, reqId, contract(12), includeExpired (0), useRth, whatToShow, formatDate (2)`. A BAG
contract is refused.

### cancelHeadTimeStamp (out 90)

`90, reqId`. Sent after the answer too (as `ib_async` does), and when the caller is cancelled first.

### headTimestamp (in 88)

No version. `88, reqId, headTimestamp`: epoch seconds, or an 8-character `yyyyMMdd` day (00:00 UTC). Any other text
(formatDate 1 style, `yyyyMMdd  HH:mm:ss`) makes the frame malformed.

### reqHistogramData (out 88)

No version. 17 fields: `88, reqId, contract(12), includeExpired (0), useRth, timePeriod`. A BAG contract is refused.

### cancelHistogramData (out 89)

`89, reqId`. Sent only when the caller is cancelled before the answer.

### histogramData (in 89)

No version. `89, reqId, n, n x (price, count)`; `count` is an integer. A negative `n` or `count` makes the frame malformed.

### historicalDataUpdate (in 90)

No version. `90, reqId, barCount, date, open, close, high, low, average, volume`; 10 fields. The order is O,C,H,L, unlike 17.
`date` as above.

### reqRealTimeBars (out 50)

`50, 3, reqId, contract(12), barSize, whatToShow, useRTH, realTimeBarsOptions`; 19 fields. `barSize` is always `5` (the
only size IB offers), `realTimeBarsOptions` always `""`. A BAG contract is refused.

### cancelRealTimeBars (out 51)

`51, 1, reqId`; 3 fields. Sent when the consumer stops the stream, and when IB refuses it for want of permission (420
with a permission text): IB keeps a refused subscription open.

### realtimeBar (in 50)

`50, version, reqId, time, open, high, low, close, volume, wap, count`; 11 fields, order O,H,L,C. `time` is epoch
seconds; `wap` becomes `Bar.average` (`nil` when unset). MIDPOINT, BID and ASK bars carry -1 volume, wap and count,
kept as historical bars keep them. The reqId routes it to its stream; the stream never ends itself.

### reqMktDepthExchanges (out 82)

`82`; 1 field, no version and no reqId.

### mktDepthExchanges (in 80)

`80, n, n x (exchange, secType, listingExch, serviceDataType, aggGroup)`; no version and no reqId. `aggGroup` is
`nil` when unset (2147483647). A negative `n` is malformed. Answers `depthExchanges()`, oldest waiter first.

### reqSmartComponents (out 83)

`83, reqId, bboExchange`; 3 fields.

### smartComponents (in 82)

`82, reqId, n, n x (bitNumber, exchange, exchangeLetter)`; no version. A negative `n` is malformed. The reqId routes
it to `smartComponents(_:)`.

### reqMktDepth (out 10)

`10, 5, reqId, contract(12), numRows, isSmartDepth, mktDepthOptions`; 18 fields. `mktDepthOptions` is always `""`.
A BAG contract is refused.

### cancelMktDepth (out 11)

`11, 1, reqId, isSmartDepth`; 4 fields. `isSmartDepth` is sent on cancel and must match the subscribe.

### updateMktDepth (in 12)

`12, version, reqId, position, operation, side, price, size`; 8 fields. operation 0 insert, 1 update, 2 delete; side 0 ask,
1 bid. No market maker (decoded as `""`). An operation or side outside those ranges is malformed.

### updateMktDepthL2 (in 13)

`13, version, reqId, position, marketMaker, operation, side, price, size, isSmartDepth`; 10 fields. `isSmartDepth` is read
and dropped. Both 12 and 13 become `.depth`. Error 317 (depth reset, a notice) empties the book; the stream goes on.
Without depth permissions the gateway answers reqMktDepth with notice 2152 for the reqId («Unknown market data
permissions - Depth: NASDAQ; ...») and then nothing (paper run 2026-11-11). The client ends the depth stream with
`.noMarketDataPermission(code: 2152, text:)` and sends the cancel when the text before "Unknown market data
permissions" names no `Depth:` exchange; a 2152 without that phrase, or one that grants `Depth:`, leaves the book open.
A typed end is recoverable, silence is not. The recorded grant (`Top: IBEOS; OVERNIGHT`) covers only venues closed in
regular hours, so a `Depth:` grant and a `Top:` grant on regular venues are both unseen live.

### reqTickByTickData (out 97)

`97, reqId, contract(12), tickType, numberOfTicks, ignoreSize`; 17 fields. **No version field.** `tickType` is text: `Last`,
`AllLast`, `BidAsk` or `MidPoint`. We send `numberOfTicks` 0 (unlimited) and `ignoreSize` false. A BAG contract is refused.

### cancelTickByTickData (out 98)

`98, reqId`; 2 fields. No version. Sent when the consumer stops the stream, and when IB refuses it for want of
permission (10189 with a permission text): IB keeps a refused subscription open.

### tickByTick (in 99)

`99, reqId, tickType, time, ...`; no version. `tickType` is an int, unlike the request: 1 Last and 2 AllLast
(price, size, attribMask, exchange, specialConditions; 9 fields), 3 BidAsk (bidPrice, askPrice, bidSize, askSize,
attribMask; 9), 4 MidPoint (midPoint; 5). `time` is Unix seconds; a non-numeric one is malformed. Any other tickType is
malformed. Trade mask: bit 0 pastLimit, bit 1 unreported. The BidAsk mask is read and dropped. The reqId routes it to
its stream; the stream never ends itself.

## Disagreements

Cross-check of `placeOrder`, `openOrder`, `completedOrder`, `orderStatus`, `execDetails` and
`commissionReport` (and, in passing, every other section) against IB's published Python client
at server version 178. **Field order agrees in every message.** The order-condition element
agrees type by type. The differences are in default values and value formatting only:

1. **placeOrder `openClose` default.** `ib_async` sends `O`; IB's client sends `""` (its
   default has been empty since server version 155, "no default open/close"). The table follows
   `ib_async` as the brief requires. For an individual stock account the field is not expected to
   matter; the live paper gateway did not reject `O` (item 9; its openOrder echo has `""` there, so that shows no more).
2. **placeOrder `usePriceMgmtAlgo` default.** `ib_async` sends `0` (its default is `False`); IB's
   client sends `""` (default `None` → unset, i.e. "Gateway decides"). `0` explicitly opts out of
   IB's price-management algo. The table follows `ib_async`; worth a decision in Task 4.
3. **placeOrder unset numbers.** For triggerPrice, lmtPriceOffset, adjustedStopPrice,
   adjustedStopLimitPrice, adjustedTrailingAmount, cashQty, duration and postToAts IB's client
   sends the raw sentinel text (`1.7976931348623157e+308`, `2147483647`), not `""`, because it
   uses the plain field writer there. `ib_async` sends `""` for every unset number. The table
   follows `ib_async`, which runs against 178 Gateways in this form; how the Gateway parses
   the sentinel text is not verified here.
4. **Number formatting.** `ib_async` formats floats with Python `str()` (`100.0`, `0.0`), IB's
   client sends quantities as `Decimal` text (`100`) and `discretionaryAmt` as `0`. Position is
   unaffected; the Swift encoder may write `100` / `0`.
5. **Decimal vs double.** IB's client decodes `totalQuantity`, `filled`, `remaining`, `shares`,
   `cumQty` and `filledQuantity` as `Decimal`; `ib_async` as `float`. The tables say `decimal`,
   following IB's client, because the Swift models hold quantities as `Decimal`.
6. **orderBound field 1 name.** `ib_async`'s wrapper names it `reqId`; IB's client `permId`. The
   table follows IB's client (it is the order's permId); position is the same.
7. **Version gates differ below 178, not at it.** `ib_async` gates openOrder's `duration` at
   159, IB's client at 158; both are present at 178. `ib_async` advertises `v157..178`, IB's
   client `v100..<max>`; the handshake above uses `v100..178` per the design.
8. **Incoming text decoding.** `ib_async` decodes the whole frame as UTF-8 with backslash
   replacement. IB's client decodes `errorString` and `advancedOrderRejectJson` with Python's
   `unicode-escape` codec from server version 153. Not a field-order matter; noted for the reader.
9. **Settled by the live paper gateway (stage 2, Task 5).** The tables are the base case, but a
   real gateway never sends it for openOrder: for a plain AAPL LMT order it sent
   deltaNeutralOrderType `None`, so the 8-field delta-neutral group follows and the frame has
   135 fields, not 127. Field order otherwise matched this table exactly (status at 93 =
   85 + 8). Also seen: contract `right` `?` and deltaNeutralOpenClose `?` for a stock,
   auxPrice `0.0` (not unset), the sentinels `2147483647` / `1.7976931348623157E308` rather than
   `""`. The gateway accepted placeOrder as encoded here (items 1–3: `openClose` `O`, not rejected, echoed back as `""`;
   `usePriceMgmtAlgo` `0`, unset numbers `""`, deltaNeutralOrderType `""` with no group), and
   answered the handshake with 178. Recorded frames: `Tests/IBKRTests/Recorded/`.

No row in this document is unverified: every table was checked line by line against the
verbatim source of both clients.
