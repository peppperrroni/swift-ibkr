# Changelog

The format follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- `Encodable` (never `Decodable`) on every public model of `IBKR` and on `FlexRecord`, ib_async's `util.tree`: `TickField` is `CodingKeyRepresentable`, so the `Ticker` dictionaries encode as JSON objects; `IBClient`, the trackers, `IBRequest`, the error enums, `ConnectionState`, `ReconnectPolicy` and `ErrorKind` are left out.
- `Order.eTradeOnly`, `.firmQuoteOnly` and `.nbboPriceCap`, IB's deprecated placeOrder rows 52-54 (openOrder fields 54-56) as optionals: `nil` sends the wire default as before and the default decodes back to `nil`.
- `Contract.includeExpired` (sent by reqContractDetails, reqHistoricalData, reqHeadTimeStamp, reqHistogramData and reqHistoricalTicks) and `Contract.issuerID` (sent by reqContractDetails), both defaulted (`false`, `""`).
- An `options: [TagValue] = []` parameter on `marketData`, `tickers` (passed to the market-data request only), `historicalBars`, `realTimeBars`, `marketDepth` and `historicalTicks`, sent as IB's market-data, chart, real-time-bar, depth and misc options; `tickByTick(_:_:count:ignoreSize:)` sends IB's numberOfTicks and ignoreSize.
- `TickAttrib` (`canAutoExecute`, `pastLimit`, `preOpen`, with `init(mask:)`), decoded from tickPrice's mask after IB's documentation (ib_async drops it), and `bidPastLow`/`askPastHigh` on `TickByTick.bidAsk`, decoded from tickByTick (99) and historicalTicks (97) with the opposite bit orders ib_async uses.
- `Execution.evRule`, `.evMultiplier` and `.modelCode`, decoded from execDetails (in 11) instead of skipped; defaulted init parameters.
- Notice 165 («no items retrieved») on a scanner yields an empty scan `[]`: `scannerSubscription` stays open, `scannerData` returns `[]`.
- Every named field of `ib_async`'s `Ticker` that reads a tick — exchanges, 13/26/52-week ranges, yields, mark and ETF NAV prices, open interest and volume sizes, auction fields, volume rates, shortable, halted, implied and historical volatility, the EFP quotes — as a computed property of `Ticker` (`Ticker.low52Week`, `.bidExchange`, `.bidEFP`, …), plus `hasBidAsk`, `midpoint` and `marketPrice`. Generic ticks of 0 or less read `nil`, as `ib_async` (so `halted` 0 is `nil`).
- `ib_async`'s stateful `Ticker` fields: `time` (when `tickers` folded the update in), `prevBid`, `prevBidSize`, `prevAsk`, `prevAskSize`, `prevLast`, `prevLastSize`, `rtVolume`, `rtTradeVolume`, `rtTime` and `vwap` parsed from RT volume (48, 77; `last` still comes from tick 4 only), `delayedLastTimestamp` (88), `dividends` (59, `Dividends`) and `fundamentalRatios` (47, `FundamentalRatios`, IB's text per tag with `decimal(_:)`), and the per-update lists `ticks` (`TickData`), `tickByTicks` and `domTicks` (`DepthTick`). `Ticker.apply(_:at:)` stamps what it records with the given time, and its new `TickByTick` overload folds a tick-by-tick event in as `ib_async` does. The raw strings stay in `strings`.
- `tickers(_:genericTicks:depthRows:smartDepth:tickByTick:options:)`: `tickByTick` folds IB's tick-by-tick events of that type into the ticker (opened after `marketData`, cancelled with it). Each element now carries its update's `ticks`, `tickByTicks` and `domTicks` and its `time`; a slow consumer still gets only the newest ticker, but it carries the lists of every update the consumer skipped, so no tick is lost or delivered twice.
- `DepthBook.bidsByPosition` and `.asksByPosition`, the book keyed by position (`ib_async`'s `domBidsDict` / `domAsksDict`).

### Changed
- **Breaking:** `Tick.price` gains a fourth associated value, `attributes: TickAttrib = TickAttrib()`. Constructing it compiles as before; a pattern such as `case .price(let f, let p, let s)` needs a fourth binding (`case .price(let f, let p, let s, _)`). `==` on a decoded `Tick.price` now also compares its attributes, so a non-zero mask no longer equals a value built without them.
- **Breaking:** `TickByTick.bidAsk` gains `bidPastLow: Bool = false, askPastHigh: Bool = false`. Construction compiles as before; a pattern with five bindings needs seven. `==` on a decoded `bidAsk` now also compares the two flags, so a non-zero mask no longer equals a value built without them.
- **Breaking:** the `IBRequest` cases `marketData`, `historicalData`, `realTimeBars`, `marketDepth` and `historicalTicks` gain `options: [TagValue] = []`, and `tickByTick` gains `count: Int = 0, ignoreSize: Bool = false`. Construction compiles as before; a pattern with the old number of bindings does not.
- **Breaking:** `marketData`, `tickers(_:…)`, `historicalBars`, `realTimeBars`, `marketDepth`, `historicalTicks` and `tickByTick` gain defaulted parameters, last. Calls compile as before; a reference by full name (`IBClient.tickByTick(_:_:)`, a DocC link) needs the new labels (`tickByTick(_:_:count:ignoreSize:)`).
- **Breaking:** `tickers(_:genericTicks:depthRows:smartDepth:)` is now `tickers(_:genericTicks:depthRows:smartDepth:tickByTick:options:)` and `Ticker.apply(_:)` is now `apply(_:at:)` (`at` defaults to now). Calls compile as before; a reference by full name needs the new one. `Ticker`'s `==` and its JSON now include the new fields, so two `tickers` elements with the same quotes differ by `time` and their lists.
- The delayed last timestamp (tick 88) sets `Ticker.delayedLastTimestamp` instead of `lastTimestamp`, as `ib_async` does; code reading `lastTimestamp` on delayed data reads `delayedLastTimestamp` now.
- `Execution`'s memberwise init gains `evRule`, `evMultiplier` and `modelCode`, defaulted and last, so existing calls compile.

## [1.0.0] - 2026-11-12

### Added
- Doc comments on every public declaration of `IBKR` and `IBKRFlex`, checked by `Scripts/doc-coverage.py`, which reads the compiler's symbol graph.
- DocC catalogs for `IBKR` (articles: Getting Started, Orders, Market Data, Migrating from ib_async) and `IBKRFlex`, built with warnings as errors on every push by `.github/workflows/docs.yml` and published to GitHub Pages from `main` at <https://peppperrroni.github.io/swift-ibkr/>.
- `.spi.yml`, so the Swift Package Index builds the documentation of both modules.
- `Examples/IBKRExample`, a read-only console example (server time, accounts, positions, account summary), built by CI on macOS and Linux.
- `CONTRIBUTING.md` and GitHub issue templates for bug reports and feature requests.
- `FlexReport.download(token:queryID:url:pollInterval:transport:)`, IB's two-step Flex Web Service request polling until the statement is ready (an already-cancelled caller sends nothing), with `FlexTransport`, `FlexReport.urlSession` and `FlexReport.defaultURL`.
- `IBKRFlex`, a new library product (Swift Package Manager only): `FlexReport(data:)` parses a Flex Web Service report, `topics` and `extract(_:)` give its elements as `FlexRecord`s (IB's attribute strings, with `decimal(_:)` for numbers), and `FlexError`.
- `faData(_:)`, an FA configuration as IB's XML text (each call takes only the answer of its own type), `replaceFA(_:xml:)`, which waits for IB's confirmation text, `FADataType`, `displayGroups()`, IB's raw group list, `displayGroupUpdates(_:)`, a stream of a display group's `contractInfo` with its reqId (70 sent when stopped), `updateDisplayGroup(_:contractInfo:)`, and the send-only `verifyRequest(apiName:apiVersion:)`, `verifyMessage(_:)`, `verifyAndAuthRequest(apiName:apiVersion:opaqueISVKey:)` and `verifyAndAuthMessage(_:xyzResponse:)`, with `IBRequest.requestFA`, `.replaceFA`, `.queryDisplayGroups`, `.subscribeToGroupEvents`, `.updateDisplayGroup`, `.unsubscribeFromGroupEvents`, `.verifyRequest`, `.verifyMessage`, `.verifyAndAuthRequest`, `.verifyAndAuthMessage` (out 18, 19, 65-70, 72, 73) and `IBMessage.receiveFA`, `.replaceFAEnd`, `.displayGroupList`, `.displayGroupUpdated`, `.verifyMessageAPI`, `.verifyCompleted`, `.verifyAndAuthMessageAPI`, `.verifyAndAuthCompleted` (in 16, 103, 65-70). New cases in public enums: an exhaustive `switch` over `IBRequest` or `IBMessage` needs new branches.
- `fundamentalData(_:reportType:options:)`, one fundamentals report as IB's XML text (53 sent only for a cancelled caller; refuses a `BAG` with `.unsupported`), `wshMetaData()` and `wshEventData(_:)`, Wall Street Horizon's JSON text (event data followed by IB's cancel 103; the meta request held open until the next `wshMetaData()` sends 101 for it, as `ib_async`), with `WshEventData`, `IBRequest.fundamentalData`, `.cancelFundamentalData`, `.wshMetaData`, `.cancelWshMetaData`, `.wshEventData`, `.cancelWshEventData` (out 52, 53, 100-103) and `IBMessage.fundamentalData`, `.wshMetaData`, `.wshEventData` (in 51, 104, 105). New cases in public enums: an exhaustive `switch` over `IBRequest` or `IBMessage` needs new branches.
- `newsBulletins(allMessages:)`, IB's news bulletins as a stream that never ends itself and sends 13 when stopped, with `NewsBulletin`, `GenericTick`, `IBRequest.newsBulletins`, `.cancelNewsBulletins` (out 12, 13), `IBMessage.newsBulletin` (in 14) and `IBClientError.alreadySubscribed`, thrown by a second `newsBulletins` while one is open (IB holds one bulletin subscription per connection). New cases in public enums: an exhaustive `switch` over `IBRequest`, `IBMessage` or `IBClientError` needs new branches.
- `newsProviders()`, `newsArticle(providerCode:articleID:options:)` and `historicalNews(conID:providerCodes:start:end:totalResults:options:)` (headlines read to IB's end marker, no cancel), with `NewsProvider`, `NewsArticle` and `HistoricalNews`, `IBRequest.newsProviders`, `.newsArticle`, `.historicalNews` (out 85, 84, 86) and `IBMessage.newsProviders`, `.newsArticle`, `.historicalNews`, `.historicalNewsEnd` (in 85, 83, 86, 87). New cases in public enums: an exhaustive `switch` over `IBRequest` or `IBMessage` needs new branches.
- `scannerSubscription(_:options:filterOptions:)`, a market scan yielded whole on every refresh (newest kept, never ending itself, 23 sent when stopped), `scannerData(_:options:filterOptions:)`, the first scan followed by IB's cancel, and `scannerParameters()`, IB's scanner XML, with `ScannerSubscription` and `ScanData`, `IBRequest.scannerSubscription`, `.cancelScannerSubscription`, `.scannerParameters` (out 22, 23, 24) and `IBMessage.scannerParameters`, `.scannerData` (in 19, 20). New cases in public enums: an exhaustive `switch` over `IBRequest` or `IBMessage` needs new branches.
- `marketRule(_:)`, `familyCodes()` and `softDollarTiers()`, with `PriceIncrement` and `FamilyCode`, `IBRequest.marketRule`, `.familyCodes`, `.softDollarTiers` (out 91, 80, 79) and `IBMessage.marketRule`, `.familyCodes`, `.softDollarTiers` (in 93, 78, 77); `marketRule(_:)` takes only its own rule's answer. New cases in public enums: an exhaustive `switch` over `IBRequest` or `IBMessage` needs new branches.
- `calculateImpliedVolatility(_:optionPrice:underPrice:options:)` and `calculateOptionPrice(_:volatility:underPrice:options:)`, IB's option computation for a given price or volatility as an `OptionComputation`, with `IBRequest.calculateImpliedVolatility`, `.calculateOptionPrice`, `.cancelCalculateImpliedVolatility` and `.cancelCalculateOptionPrice` (out 54-57); the answer is the existing tick 21 under the call's own reqId. New cases in a public enum: an exhaustive `switch` over `IBRequest` needs new branches.
- `optionChains(for:futFopExchange:)`, every option chain IB lists for an underlying (one `OptionChain` per exchange and trading class), with `IBRequest.secDefOptParams` (out 78) and `IBMessage.securityDefinitionOptionParameter` / `.securityDefinitionOptionParameterEnd` (in 75/76). New cases in public enums: an exhaustive `switch` over `IBRequest` or `IBMessage` needs new branches.
- `qualifyContracts(_:)`, every lookup at once, with `ContractQualification` (`.qualified`, `.ambiguous` with every candidate, `.notFound`) per input in input order; IB's 200 is `.notFound`, any other error throws, and a `BAG` is refused before sending.
- `ContractDetails` carries every field `ib_async` decodes (`underConID`, `contractMonth`, `industry`, `category`, `subcategory`, `evRule`, `evMultiplier`, `secIDList`, `aggGroup`, `underSymbol`, `underSecType`, `marketRuleIDs`, `realExpirationDate`, `lastTradeTime`), and bond details (in 18) come back through `contractDetails` with `cusip`, `coupon`, `maturity`, `issueDate`, `ratings`, `bondType`, `couponType`, `convertible`, `callable`, `putable`, `descAppend`, `nextOptionDate`, `nextOptionType`, `nextOptionPartial` and `notes`.
- `Contract.stock`, `.option`, `.futuresOption`, `.future`, `.contFuture`, `.forex`, `.index`, `.cfd`, `.commodity`, `.crypto`, `.mutualFund`, `.warrant`, `.bond` and `.bag`, `ib_async`'s contract factories, with its defaults (`""` for exchange and currency, `IDEALPRO` for forex).
- `headTimeStamp(_:whatToShow:rth:)` (the earliest data date) and `histogramData(_:period:rth:)` (trade counts by price), with `HistogramData`, `IBRequest.headTimeStamp`, `.cancelHeadTimeStamp`, `.histogramData`, `.cancelHistogramData` (out 87, 90, 88, 89) and `IBMessage.headTimeStamp`, `.histogramData` (in 88, 89). New cases in public enums: an exhaustive `switch` over `IBRequest` or `IBMessage` needs new branches.
- `historicalTicks(_:start:end:count:whatToShow:rth:ignoreSize:)`, historical midpoint, bid/ask or trade ticks as `[TickByTick]`, with `IBRequest.historicalTicks` (out 96) and `IBMessage.historicalTicks` (in 96, 97, 98). New cases in public enums: an exhaustive `switch` over `IBRequest` or `IBMessage` needs new branches.
- `historicalSchedule(_:days:end:rth:)`, a contract's trading sessions, with `HistoricalSchedule` and `HistoricalSession`, and `IBMessage.historicalSchedule` (in 106); BAG history: `historicalBars` sends a `BAG`'s legs. A new case in a public enum: an exhaustive `switch` over `IBMessage` needs a new branch.
- `tickers(_:genericTicks:depthRows:smartDepth:)`, a stream of whole `Ticker`s folding `marketData` and, with `depthRows`, `marketDepth`; the newest is kept for a slow consumer, the first inner error ends it, and any end cancels both requests.
- `tickers(for:regulatorySnapshot:)`, one snapshot `Ticker` per contract in input order, every request sent before any is read; the first error is thrown and the requests still open are cancelled.
- `Ticker`, a contract's market data as one value, with `apply(_:)` folding each `Tick` into it after `ib_async`'s wrapper: named bid, ask, last, OHLC, volume, last timestamp, greeks and request parameters; every other tick in `prices`, `sizes`, `generics`, `strings` or `efp` by its live field; and a `DepthBook`.
- `depthExchanges()` and `smartComponents(_:)`, with `DepthMarketDataDescription` and `SmartComponent`, and the matching `IBRequest` and `IBMessage` cases (out 82/83, in 80/82). New cases in public enums: an exhaustive `switch` over `IBRequest` or `IBMessage` needs new branches.
- `realTimeBars(_:whatToShow:rth:)`, IB's five-second bars as a stream, with `IBRequest.realTimeBars`, `.cancelRealTimeBars` and `IBMessage.realTimeBar`; error 420 with a permission text ends it with `.noMarketDataPermission`. New cases in public enums: an exhaustive `switch` over `IBRequest` or `IBMessage` needs new branches.
- `marketData`'s `genericTicks`, `snapshot` and `regulatorySnapshot`; BAG and delta-neutral contracts in
  `marketData`; and `IBMessage.tickSnapshotEnd(requestID:)`, which ends a snapshot stream with no cancel. A new case in
  a public enum: an exhaustive `switch` over `IBMessage` needs a new branch.
- `Tick.optionComputation`, `.efp`, `.requestParameters` and `.news`, with the new types `OptionComputation`, `EFPData`
  and `NewsTick`: `marketData` yields option computations (21), EFP quotes (47), request parameters (81) and news
  ticks (84). An uncomputed greek is `nil`, and `TickField.live` maps the delayed greeks 80-83 to 10-13 and the delayed yields 103/104 to 50/51. New cases in
  a public enum: an exhaustive `switch` over `Tick` needs new branches.
- `IBMessage.deltaNeutralValidation`, `.rerouteMarketData` and `.rerouteMarketDepth` (56, 91, 92), decoded and
  delivered to `messages()` only; the market data stream stays open through a reroute. New cases in a public enum: an
  exhaustive `switch` over `IBMessage` needs new branches.
- Order factories `Order.market/limit/stop/stopLimit`, `Order.bracket` (a `BracketOrder`), `Order.oneCancelsAll` and
  `IBClient.placeBracket`, which links and transmits the three legs and sends none if any fails to encode.
- `exerciseOptions` with the new `ExerciseAction`, and `cancelOrder(_:manualCancelOrderTime:)`. `IBRequest` gains the
  case `exerciseOptions`: an exhaustive `switch` over the public enum needs a new branch.
- Opt-in reconnect: `connect(reconnect: ReconnectPolicy)` retries a dropped connection with paused attempts until
  `disconnect()` or `maxAttempts`, and probes a silent connection with reqCurrentTime, dropping it with `.timeout`
  when the probe goes unanswered. The order, position and portfolio snapshots stay visible while it retries.
- `accountUpdatesMulti`, `positionsMulti` and `pnl` request streams (account values and positions per account and
  model code, and account-level P&L).
- `portfolio()` and `accountValues()`, always on: `connect` subscribes to the account updates of a single account,
  or to each account's values through `Multi` when there are several, and waits for them.
- Wire codec for the account stream: account values, portfolio items, account time, the `Multi` position and account
  updates, and account-level P&L, with their requests. `Position` and `AccountValue` gain `modelCode`.
- Session requests: `currentTime()`, `managedAccounts()`, `nextOrderID()`, `userInfo()`, `setServerLogLevel(_:)`,
  `setAutoOpenOrders(_:)` and `cancelAllOrders()`.
- Public memberwise initializers on all models.
- iOS 16 as a supported platform, next to macOS 13.
- CI on every push and pull request: tests on macOS, Linux (Swift 6.0 and the latest) and Windows, and an iOS build.
- A `SwiftIBKR.podspec` (pod `SwiftIBKR`, module `IBKR`), linted in CI; trunk publication is pending.

- `placeOrder` sends every plain field of the order and contract: `Order` gains the rest of IB's placeOrder fields
  (open/close, origin, display size, discretionary amount, good-after / good-till times, FA fields, volatility,
  trailing, adjusted-order, MiFID II, cash quantity, soft dollar tier, misc options and more) and `Contract` gains
  `secIDType` / `secID`. New value types `TagValue` and `SoftDollarTier`. `volatility` goes out only for `VOL` order
  types.
- openOrder and completedOrder decode the order fields: every plain field `placeOrder` sends, plus the decoded-only
  `basisPoints` / `basisPointsType` (openOrder) and `autoCancelDate`, `refFuturesConID`, `shareholder`,
  `imbalanceOnly`, `routeMarketableToBbo` and `parentPermID` (completedOrder). Values are kept as the gateway sends
  them (`None`, `clearingIntent` `IB`).
- BAG combos, delta-neutral orders and contracts, scale and hedge orders: `placeOrder` sends and openOrder /
  completedOrder decode `Contract.comboLegs` and `deltaNeutralContract`, and the `Order` combo-leg prices, smart
  routing params, delta-neutral, scale and hedge fields. New value types `ComboLeg`, `OrderComboLeg` and
  `DeltaNeutralContract`. Every request other than `placeOrder`, `marketData` and `historicalBars` still refuses a `BAG` contract.
- Algos, PEG BENCH, BEST and MID, conditions and IBKRATS: `placeOrder` sends and openOrder / completedOrder decode
  `algoStrategy` / `algoParams`, the PEG BENCH reference fields, `conditions` with `conditionsIgnoreRTH` /
  `conditionsCancelOrder`, `minTradeQty`, `minCompeteSize`, `competeAgainstBestOffset` and the mid offsets. New types
  `OrderCondition` and `CompeteOffset`.
- `whatIfOrder(_:_:)` returns IB's margin and commission for an order without placing it, as a new `OrderState`
  (nine margins and three commissions as `Decimal?`, an unparseable margin `nil`, `commissionCurrency`,
  `warningText`). openOrder decodes it into
  the new `OpenOrderMessage.state`; what-if openOrders never reach `orders()`.
- `OrderSnapshot.advancedOrderRejectJSON`: the raw advanced-reject JSON of the last error for the order that had one.

### Changed
- The podspec version is 1.0.0, and README installs from the 1.0.0 tag.
- `genericTicks` is `[GenericTick]` in `marketData`, `tickers` and `IBRequest.marketData`, so a news tick list (`["mdoff", "292:BRFG"]`) can be sent. Integer and string literals both still compile; a `[Int]` variable needs `.map(GenericTick.init(integerLiteral:))`.
- An option's or future's `lastTradeDateOrContractMonth` in `contractDetails` keeps only the date (`20261218`), and the time goes to the new `ContractDetails.lastTradeTime`; before, the whole lastTimes text was kept.
- A third lastTimes part in contractData (10) and bond details (18), IB's time zone, now replaces `ContractDetails.timeZoneID`.
- `ContractDetails.longName` from contractData (10) has its `\uXXXX` escapes decoded, as `ib_async` does; bond details keep it raw.
- `historicalBars` accepts a `BAG` and refuses `whatToShow` "SCHEDULE" (`.encoding(.unsupported)`): use `historicalSchedule`.
- `marketDepth` ends with `.noMarketDataPermission(code: 2152, text:)` and sends its cancel when IB's 2152 lists its unknown permissions and grants no `Depth:` exchange, instead of staying silent; a 2152 that grants some depth keeps the book open.
- tickReqParams (81) is a tick, `Tick.requestParameters`, and `marketData` yields it.
- `marketData` sends `Contract.deltaNeutralContract`. `IBRequest.marketData` gains three associated values
  (`genericTicks`, `snapshot`, `regulatorySnapshot`) whose defaults keep construction compiling; a `switch`/`case` on
  `.marketData` needs the new bindings.
- `contractDetails` sends the contract's `secIDType` and `secID` instead of empty fields.
- `connect` sends one more sync request (reqAccountUpdates, or one reqAccountUpdatesMulti per account) and returns
  only after its end marker.
- `connect` honours task cancellation: it throws `.cancelled` and leaves `.disconnected(.cancelled)`.
- `disconnect()` from `.connected` sends cancelPositions and closes the socket only after the queued frames are out
  (within 2 s), so an order placed just before it is no longer dropped.
- `ErrorKind.warning` for 105, 321, 329, 434 and 492, as in `ib_async`: it ends the request stream it names, but never
  marks an unacknowledged order inactive. Error `text` has its `\uXXXX` escapes decoded.
- A write that finds the peer gone throws `.connectionClosed`, not `.transport("send: ...")`, whether or not the
  reader has seen the close yet. A peer reset seen by the reader is `.connectionClosed` too.
- `placeOrder` and `modifyOrder` refuse an order with `whatIf` set (`.encoding(.unsupported("whatIf"))`): use
  `whatIfOrder`.
- A 202 keeps its reason: when IB cancels an order with text after `reason:` (its price cap), that text becomes the
  snapshot's `rejectReason`. A plain cancel still leaves it `nil`.
- A Filled openOrder waits for its orderStatus or its completedOrder: `orders()` no longer publishes `.filled` with
  `filled` 0 first, nor a part-filled order's `.filled` with the earlier fill. A completedOrder takes the waiting
  openOrder's ids and order, and the fill size when it is larger than the snapshot's. A completedOrder joined to a
  known order also copies `order.parentPermID`, and a later openOrder keeps it.

### Removed
- `IBMessage.tickRequestParameters`: 81 now decodes as `.tick(requestID:, .requestParameters(…))`.
- `OrderKey` is no longer public; the public API never used it.
- The `.unsupported` refusals of `placeOrder` for PEG order types and exchange IBKRATS: it now encodes every layout.

## [0.4.0] - 2026-11-11

### Added
- Connection: handshake, server-version gating, request throttle.
- Orders: place, modify and cancel, brackets, open and completed orders merged.
- Executions with commissions.
- Positions.
- Account summary and per-position P&L.
- Contract details and matching symbols.
- Market data: quotes, historical bars with keepUpToDate, depth book, tick-by-tick, typed no-permission refusal.
