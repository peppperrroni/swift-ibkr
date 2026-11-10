# Market-data layouts at server version 178

Source: `ib_async` commit `ab629f34c1823ea4c1542f32f07377208a86bdfd` (= current `main`, same pin as docs/protocol-178.md),
`client.py` (out), `decoder.py` + `wrapper.py` (in). Conventions as in docs/protocol-178.md
(frame, NUL-terminated ASCII fields, bool `1`/`0`, UNSET int/double -> `""`, `#` = field index, field 0 = msg id).
Only `ib_async` was read; nothing from IB's own client. Items marked **[not ib_async]** come from IB's public API docs / memory and
were not verified here.

ib_async has **no `MIN_SERVER_VER_*` constants**: it uses numeric `serverVersion() >= N` checks. Every market-data
message below has at most these gates: reqContractDetails `>=176`, symbolSamples `>=176`, contractData `<164` / `==163` / `>=164`,
error `>=166`. All resolved for 178 below.

## Contract block (shared)

`Client.send` formats a `Contract` as 12 fields via `str()`, **no UNSET mapping**, in this order:
`conId, symbol, secType, lastTradeDateOrContractMonth, strike, right, multiplier, exchange, primaryExchange, currency, localSymbol, tradingClass`.
This is **exactly rows 2-13 of placeOrder** (same order, `primaryExchange` included, `strike` as `str(double)`, default `0.0`).
reqMktData, reqHistoricalData, reqTickByTickData, reqContractDetails reuse it verbatim as "contract(12)".
reqMktDepth lists the same 12 fields by hand (same order); there `strike` goes through the float handler (default `0.0` -> `"0.0"`, identical result).
Plain STK, e.g. AAPL SMART USD: `0,AAPL,STK,,0.0,,,SMART,,USD,,` (conId 0, empty strings elsewhere).

## Outgoing

### reqMarketDataType (out 59) — `Client.reqMarketDataType`
| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | | `59` |
| 1 | version | int | `1` |
| 2 | marketDataType | int | 1 live, 2 frozen, 3 delayed, 4 delayed-frozen |

3 fields. Session-global (no reqId); applies to later reqMktData.

### reqMktData (out 1) — `Client.reqMktData`
No version gates at all. Plain STK layout:
| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | | `1` |
| 1 | version | int | `11` (constant) |
| 2 | reqId | int | |
| 3-14 | contract(12) | | see above |
| + | comboLegsCount | int | **only if secType == `BAG`**; then per leg `conId int, ratio int, action str, exchange str` (4 fields) |
| 15 | deltaNeutralContractPresent | bool | `0` for STK. If present: `+ conId int, delta double, price double` (3 fields) |
| 16 | genericTickList | string | comma list, `""` for default ticks (e.g. `233,165`) |
| 17 | snapshot | bool | |
| 18 | regulatorySnapshot | bool | |
| 19 | mktDataOptions | string | TagValue list as `tag=value;...`; `""` when empty (always sent, never omitted) |

20 fields for STK. Note: for a BAG the legs come BEFORE the delta-neutral flag. Nothing is a placeholder except mktDataOptions `""` / genericTickList `""`.
Snapshot + non-empty genericTickList is rejected by IB (error 321) **[not ib_async]**; ib_async's snapshot path sends `""` (`reqTickersAsync`).

### cancelMktData (out 2) — `Client.cancelMktData`
`2, 2, reqId` — version `2`; 3 fields.

### reqHistoricalData (out 20) — `Client.reqHistoricalData`
No version field at 178 (ib_async never sends one). Order differs from the Python arg order: **barSize before duration, useRTH before whatToShow**.
| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | | `20` |
| 1 | reqId | int | |
| 2-13 | contract(12) | | |
| 14 | includeExpired | bool | `contract.includeExpired`, default `0` |
| 15 | endDateTime | string | `""` = now; else `yyyyMMdd HH:mm:ss UTC` (ib_async `formatIBDatetime` converts datetimes to UTC, date -> 23:59:59 local->UTC); a user string is passed as is, no tz = TWS login tz |
| 16 | barSizeSetting | string | `1 secs`.. `1 min`, `1 hour`, `1 day`, `1 week`, `1 month` |
| 17 | durationStr | string | `60 S`, `30 D`, `13 W`, `6 M`, `10 Y` |
| 18 | useRTH | bool | |
| 19 | whatToShow | string | TRADES, MIDPOINT, BID, ASK, BID_ASK, ADJUSTED_LAST, ... |
| 20 | formatDate | int | 1 = text dates, 2 = epoch seconds (intraday) |
| + | comboLegsCount | int | only if BAG; per leg `conId, ratio, action, exchange` |
| 21 | keepUpToDate | bool | `1` requires endDateTime `""` |
| 22 | chartOptions | string | TagValue list, `""` when empty (always sent) |

23 fields for STK.

### cancelHistoricalData (out 25) — `Client.cancelHistoricalData`
`25, 1, reqId`; 3 fields. (Also the way to stop a keepUpToDate stream.)

### reqMktDepth (out 10) — `Client.reqMktDepth`
| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | | `10` |
| 1 | version | int | `5` |
| 2 | reqId | int | |
| 3-14 | contract(12) | | listed field by field |
| 15 | numRows | int | |
| 16 | isSmartDepth | bool | always sent at 178 |
| 17 | mktDepthOptions | string | TagValue list, `""` when empty |

18 fields. No BAG branch.

### cancelMktDepth (out 11) — `Client.cancelMktDepth`
`11, 1, reqId, isSmartDepth(bool)`; 4 fields. **Yes, isSmartDepth is sent on cancel** (must match the subscribe).

### reqTickByTickData (out 97) — `Client.reqTickByTickData`
| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | | `97` |
| 1 | reqId | int | |
| 2-13 | contract(12) | | |
| 14 | tickType | string | **text**: `Last`, `AllLast`, `BidAsk`, `MidPoint` (not the int that comes back in in-99) |
| 15 | numberOfTicks | int | `0` = unlimited streaming; >0 = historical-style burst (ib_async docs: 1000 max) |
| 16 | ignoreSize | bool | ignore bid/ask updates that change only size |

17 fields. No version field. Gates for numberOfTicks/ignoreSize are below 178 -> always sent.

### cancelTickByTickData (out 98) — `Client.cancelTickByTickData`
`98, reqId`; 2 fields. No version.

### reqMatchingSymbols (out 81) — `Client.reqMatchingSymbols`
`81, reqId, pattern`; 3 fields. No version.

### reqContractDetails (out 9) — `Client.reqContractDetails`
| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | | `9` |
| 1 | version | int | `8` |
| 2 | reqId | int | |
| 3-14 | contract(12) | | |
| 15 | includeExpired | bool | |
| 16 | secIdType | string | `""` unless searching by ISIN/CUSIP/FIGI.. |
| 17 | secId | string | |
| 18 | issuerId | string | **gate `>=176` -> taken** at 178; `""` normally |

19 fields.

Related, not asked: reqMarketRule out 91 (`91, marketRuleId`, 2 fields, no version), reqHeadTimeStamp 87, reqSmartComponents 83 (`83, reqId, bboExchange`), reqMktDepthExchanges 82 (`82` only).

## Incoming

All `wrap()`-decoded messages skip fields per the table below; "no version" means ib_async reads reqId at index 1.

### tickPrice (in 1) — `Decoder.priceSizeTick`
| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | | `1` |
| 1 | version | int | ignored (6) |
| 2 | reqId | int | |
| 3 | tickType | int | |
| 4 | price | double | **ib_async drops the message if this field is empty** (`if price:`) |
| 5 | size | decimal | meaningful for bid(1)/ask(2)/last(4) and delayed 66/67/68; else 0 |
| 6 | attribMask | int | **ib_async ignores it**. Bits, **[not ib_async: `TickAttrib` dataclass field order / IB docs]**: bit0 canAutoExecute, bit1 pastLimit, bit2 preOpen |

7 fields. ib_async treats the size as an implicit tickSize for the same side (types 1/66 bid, 2/67 ask, 4/68 last); `size == 0` on bid/ask means "no quote" (price then also -1 or 0).
IB's own client emits an extra synthetic tickSize here; no separate tickSize message follows in the wire protocol.

### tickSize (in 2) — `wrap("tickSize", [int,int,float])`
`2, version, reqId, tickType, size`; 5 fields. Types: 0 bidSize, 3 askSize, 5 lastSize, 8 volume, 21 avVolume, 22 openInterest, 27-30 option OI/volume, 34 auctionVolume, 36 auctionImbalance, 61 regulatoryImbalance, 63-65 volume rates, 69 delayed bidSize, 70 delayed askSize, 71 delayed lastSize, 74 delayed volume, 86, 87, 89 shortableShares.

### tickGeneric (in 45) — `wrap("tickGeneric", [int,int,float])`
`45, version, reqId, tickType, value(double)`; 5 fields. Types seen: 23 optHistVol, 24 optImpliedVol, 31 indexFuturePremium, 46 shortable (value 0-3), 49 halted (0/1/2..), 54 tradeCount, 55 tradeRate, 56 volumeRate, 58 rtHistVolatility, 60, 90 delayedHalted. ib_async maps value <= 0 to "unset".

### tickString (in 46) — `wrap("tickString", [int,int,str])`
`46, version, reqId, tickType, value(string)`; 5 fields. Types: 32 bidExchange, 33 askExchange, 84 lastExchange, 25/26 option exchanges, 45 lastTimestamp (epoch seconds as text), 88 delayedLastTimestamp, 47 fundamental ratios (`k=v;k=v;`), 48 RTVolume `price;size;time_ms;totalVolume;vwap;singleTrade`, 77 RTTradeVolume (same shape), 59 dividends `past12,next12,YYYYMMDD,nextAmount`, 85 lastRegTime, 91, 100.

### tickReqParams (in 81) — `wrap("tickReqParams", [int,float,str,int], skip=1)`
`81, reqId, minTick(double), bboExchange(string), snapshotPermissions(int)`; 5 fields. **No version field.** Arrives once per mktData subscription (also for plain STK), shortly after the request.

### marketDataType (in 58) — `wrap("marketDataType", [int,int])`
`58, version, reqId, marketDataType(int 1-4)`; 4 fields. Arrives per subscription with the type of data about to flow (3/4 = delayed). This is how a client learns "delayed is flowing".

### tickSnapshotEnd (in 57) — `wrap("tickSnapshotEnd", [int])`
`57, version, reqId`; 3 fields. Only after a `snapshot=1` request (ends it; no cancel needed).

### historicalData (in 17) — `Decoder.historicalData`
**No version field at 178**; and **the end marker is part of this message** (there is no in-108: ib_async has no handler for it; it exists only from server version 196).
| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | | `17` |
| 1 | reqId | int | |
| 2 | startDate | string | ib_async ignores (passes to `historicalDataEnd`); IB sends `YYYYMMDD  HH:MM:SS`-style text, present at 178 |
| 3 | endDate | string | same |
| 4 | numBars | int | |
| 5.. | numBars x bar | | 8 fields each |

Bar (8 fields): `date string, open, high, low, close, volume(decimal), average(wap), barCount(int)` — **order is O,H,L,C**.
Total = 5 + 8*numBars; the message IS the whole batch: emit bars, then treat as "end" in the same step. For keepUpToDate=1 this first 17 is the initial batch, then 90s follow.
Bar `date` text (`parseIBDatetime`):
- 8 chars `YYYYMMDD` -> a date (daily/weekly/monthly bars, either formatDate) — checked first, so also for formatDate=2 daily bars.
- all digits (formatDate=2 intraday) -> Unix epoch seconds, UTC.
- formatDate=1 intraday -> `YYYYMMDD  HH:MM:SS` (TWO spaces), in the TWS/login timezone (no zone in the text; the zone is only known from login/contract timeZoneId).
- also accepted by ib_async: `YYYYMMDD HH:MM:SS <ZoneId>` (e.g. `20221125 10:00:00 Europe/Amsterdam`) and `YYYY-MM-DD HH:MM:SS.0`.

### historicalDataUpdate (in 90) — `Decoder.historicalDataUpdate`
No version. `90, reqId, barCount, date, open, close, high, low, average, volume`; 10 fields.
**Field order differs from 17**: barCount FIRST, and **close before high/low** (O,C,H,L). Date text as above. A bar whose date equals the last bar's date replaces it; a later date appends; older is ignored (`wrapper.historicalDataUpdate`).

### updateMktDepth (in 12) — `wrap("updateMktDepth", [int,int,int,int,float,float])`
`12, version, reqId, position, operation, side, price, size`; 8 fields. operation 0 insert, 1 update, 2 delete; side 0 ask, 1 bid. (L1 depth, no market maker; used when isSmartDepth is not requested.)

### updateMktDepthL2 (in 13) — `wrap("updateMktDepthL2", [int,int,str,int,int,float,float,bool])`
`13, version, reqId, position, marketMaker(string), operation, side, price, size, isSmartDepth(bool)`; 10 fields. isSmartDepth is the **last** field, always present at 178.
ib_async keeps a position-indexed dict per side: insert/update = set `dict[position]`; delete = pop position. Positions may have gaps.

### tickByTick (in 99) — `Decoder.tickByTick`
No version. `99, reqId, tickType(int), time(int, Unix seconds), ...` then by type (exact counts; ib_async unpacks strictly):
| tickType | Name | Fields after time | Total |
|---|---|---|---|
| 1 | Last | price, size, attribMask, exchange, specialConditions | 9 |
| 2 | AllLast | same as 1 | 9 |
| 3 | BidAsk | bidPrice, askPrice, bidSize, askSize, attribMask | 9 |
| 4 | MidPoint | midPoint | 5 |

Masks: Last/AllLast bit0 pastLimit, bit1 unreported. BidAsk (live tick-by-tick) bit0 bidPastLow, bit1 askPastHigh. (ib_async's historicalTicksBidAsk uses the reverse bit order — ignore, not our message.) Tick type 1/2 `price == -1 && size == 0` is ib_async's "empty" marker.

### symbolSamples (in 79) — `Decoder.symbolSamples`
No version. `79, reqId, n`, then n entries; per entry:
`conId int, symbol, secType, primaryExchange, currency, numDerivativeSecTypes int, then that many derivativeSecType strings, description string, issuerId string`.
**description and issuerId are present at 178** (gate `>=176` taken). Entry size is variable (6 + m + 2). Entries have no exchange (only primaryExchange).

### contractData (in 10) — `Decoder.contractDetails`
At 178 (>=164): **no version field** (that pop happens only below 164) and **no mdSizeMultiplier** (also popped only below 164); field 1 is the reqId.
| # | Field | Type | Notes |
|---|---|---|---|
| 0 | msgId | | `10` |
| 1 | reqId | int | |
| 2 | symbol | string | |
| 3 | secType | string | |
| 4 | lastTimes | string | `lastTradeDateOrContractMonth`, optionally followed by lastTradeTime / timeZoneId; split on `-` if a `-` is present, else on whitespace. `""` for STK |
| 5 | strike | double | |
| 6 | right | string | `?` for non-options is possible (see docs/protocol-178.md openOrder note) |
| 7 | exchange | string | |
| 8 | currency | string | |
| 9 | localSymbol | string | |
| 10 | marketName | string | |
| 11 | tradingClass | string | |
| 12 | conId | int | |
| 13 | minTick | double | |
| 14 | multiplier | string | |
| 15 | orderTypes | string | comma list |
| 16 | validExchanges | string | comma list |
| 17 | priceMagnifier | int | |
| 18 | underConId | int | |
| 19 | longName | string | ib_async additionally runs `unicode-escape` decode on it |
| 20 | primaryExchange | string | goes to contract.primaryExchange |
| 21 | contractMonth | string | |
| 22 | industry | string | |
| 23 | category | string | |
| 24 | subcategory | string | |
| 25 | timeZoneId | string | e.g. `US/Eastern`; overridden by lastTimes[2] if present |
| 26 | tradingHours | string | `YYYYMMDD:HHMM-YYYYMMDD:HHMM;YYYYMMDD:CLOSED;...` in timeZoneId |
| 27 | liquidHours | string | same format (regular session) |
| 28 | evRule | string | |
| 29 | evMultiplier | double (ib_async types int) | |
| 30 | numSecIds | int | |
| + | secIdList | | numSecIds x (tag string, value string) |
| 31 | aggGroup | int | |
| 32 | underSymbol | string | |
| 33 | underSecType | string | |
| 34 | marketRuleIds | string | comma list, one id per valid exchange, same order |
| 35 | realExpirationDate | string | |
| 36 | stockType | string | `COMMON`, `ETF`.. |
| 37 | minSize | decimal | gate `>=164` taken |
| 38 | sizeIncrement | decimal | |
| 39 | suggestedSizeIncrement | decimal | (the `==163` special case is not taken) |
| 40.. | trailing | | ib_async reads nothing more (commented `minCashQtySize`); any further fields must be ignored by position, not length-checked |

Base size 40 (index 0-39) + 2 per secId. Bond (in 18) has a different layout; not for STK.
Fields empty => default (`parse`: int/float/bool default when `""`).

### contractDataEnd (in 52) — `wrap("contractDetailsEnd", [int])`
`52, version, reqId`; 3 fields.

### Others a market-data client may see (names only)
| id | Name | Decode (ib_async) | Plain-STK subscription receives it? |
|---|---|---|---|
| 21 | tickOptionComputation | `21, reqId, tickType, tickAttrib, impliedVol, delta, optPrice, pvDividend, gamma, vega, theta, undPrice` (no version, 12 fields) | no, options only |
| 91 | rerouteMktDataReq | `91, reqId, conId, exchange` (no version) | rarely (CFD/redirect cases); ib_async has no wrapper method for it, i.e. ignores it |
| 92 | rerouteMktDepthReq | `92, reqId, conId, exchange` | rarely; same |
| 93 | marketRule | `93, marketRuleId, n, (lowEdge, increment) x n` (no version, no reqId) | only after outgoing 91 reqMarketRule |
| 47 | tickEFP | `47, version, reqId, tickType, basisPoints, formattedBasisPoints, impliedFuture, holdDays, futureLastTradeDate, dividendImpact, dividendsToLastTradeDate` | no (futures) |
| 84 | tickNews | `84, reqId, tickType, timeStamp, providerCode, articleId, headline, extraData` | only with news generic tick 292 |
| 56 | deltaNeutralValidation | `56, version, reqId, conId, delta, price` | no |
| 106 | historicalSchedule | | only whatToShow=SCHEDULE |
| 82/80 | smartComponents / mktDepthExchanges | answers to out 83 / 82 | no |
| 88 | headTimestamp | `88, reqId, timestamp` | only after out 87 |
| 4 | error | see docs/protocol-178.md | yes, with reqId = the reqMktData id |

Delayed tick types (after reqMarketDataType 3/4): 66 bid, 67 ask, 68 last (tickPrice); 69 bidSize, 70 askSize, 71 lastSize, 74 volume (tickSize); 72 high, 73 low, 75 close, 76 open (tickPrice); 88 lastTimestamp (tickString). Live tick types: 1 bid, 2 ask, 4 last, 6 high, 7 low, 9 close, 14 open (tickPrice); 0,3,5,8 sizes.

## Error codes met on market data

ib_async knows only: warnings = {105, 110, 165, 321, 329, 399, 404, 434, 492, 10167} plus 2100-2199; everything else is an error. Special handling: 165 clears a scanner list; **317 clears the whole book**; **10225 re-issues the subscription** (cancel + request again). Meanings below are **[not ib_async: IB's published message-code list / memory; unverified here]**.

| Code | Meaning | IB severity | Data still flows? |
|---|---|---|---|
| 10167 | Requested market data is not subscribed. Displaying delayed market data. | warning | **yes, delayed** (only after reqMarketDataType 3/4) |
| 10168 | Requested market data is not subscribed. Delayed market data is not enabled. | error | no |
| 354 | Requested market data is not subscribed (no live subscription, delayed not requested) | error | no |
| 10089 | Requested market data requires additional subscription for API. (text may add "Delayed market data is available") | error | no live; **delayed may flow if the text says so and type 3 is set** |
| 10090 | Part of requested market data is not subscribed (some ticks only) | warning-like | partial |
| 10091 | Part of requested market data requires additional subscription for API | warning-like | partial |
| 10186 | ib_async comment "not listed"; meaning unverified (subscription-related) | unverified | unverified |
| 10197 | No market data during competing live session (another session holds the live feed) | error | no |
| 162 | Historical market data service error (also pacing violation, "no data", "no permissions") | error | no |
| 165 | Historical market data service query message | warning | n/a |
| 322 | Error processing request (server-side validation; e.g. too many simultaneous requests) | error | no |
| 420 | Invalid real-time query (e.g. historical/real-time session from a different IP) | error | no |
| 2119 | Market data farm is connecting | warning (2100-2199) | not yet; data follows |
| 2103/2104/2105/2106/2107/2108/2157/2158 | farm broken / OK / inactive status | warning | n/a (status only) |
| 200 | No security definition has been found for the request | error | no; request ends |
| 300 | Can't find EId with tickerId (cancel/lookup for an unknown reqId) | error | n/a |
| 366 | No historical data query found for ticker id (cancelHistoricalData for unknown id) | error | n/a |
| 317 | Market depth data has been RESET; empty the deep book before applying new entries | **warning-class, not terminal**; subscription stays alive | yes, book restarts empty |
| 10092 | Deep market data not supported for this security type / exchange combination | error | no |
| 10225 | Bust event: subscription deactivated; resubscribe real-time bars / keepUpToDate | error | stops until re-requested |
| 101 / 100 / 309 | max tickers / pacing / max depth requests reached | error | no |
| 1100 / 1101 / 1102 | connectivity lost / restored data lost (resubscribe) / restored data kept | warning-class | 1101 requires resubscribe |

"Delayed data is shown instead": **10167** (clearly). Possibly 10089 with delayed text. Delay shows reliably in in-58 marketDataType 3/4 and in tick types 66-76.

### Compare with `Sources/IBKR/Messages/ErrorCode.swift` (docs/DECISIONS.md)
Swift table: **notice** = 2100...2199, 10167, 399, 404, 161, 10147, 10148, 165, 1101, 1102; **orderCancelled** = 202; **fatal** = everything else ("fails the request it belongs to": `IBClient.routeToStream` finishes the stream with `.ib(code,text)`).
- Already notice: 10167 (delayed data), all 2100-2199 incl. 2104/2106/2119/2158, 165, 1101/1102.
- Fatal by default, which is right for: 354, 10168, 10197, 162, 200, 322, 420, 300, 366, 10092, 101, 309.
- **Needs a decision for stage 4:**
  - **317 is fatal today** -> would kill the depth stream; IB treats it as "clear the book and keep going". Make it a notice that also clears the book (needs a per-code effect, not just a kind).
  - **10225 is fatal today** -> kills a bar/keepUpToDate stream; ib_async re-subscribes. Either keep fatal and let the consumer resubscribe, or add a resubscribe path.
  - **10090 / 10091** (partial data) are fatal today -> would end a stream that still delivers part of its data; consider notice.
  - **10089** is fatal today -> ends the stream even when delayed data is offered; consider using the in-58 marketDataType to decide.
  - 10186 unknown: leave fatal until seen live.
  - Code 2104 etc. are NOT in the Swift sources as literals (only via the 2100...2199 range); a grep for "2104" in Sources finds nothing (only docs/KNOWN-GAPS.md mentions it).
