# Parity with ib_async

Every public name of `ib_async` 2.1.0 (commit `ab629f34`) mapped to `swift-ibkr`. Private `_x` names are left out.
A row's status changes in the same commit as the code that changes it.

| Status | Meaning |
|---|---|
| `present` | in `swift-ibkr` under the Swift name given |
| `MISSING` | not available; the note gives the proposed Swift name and shape |
| `added` | implemented in stage 14 under the Swift name given; `present` keeps meaning "in 1.0.0" |
| `n/a` | has no Swift meaning: a synchronous wrapper, pandas, plotting, Qt/Jupyter/event-loop glue, or Python dunder/dataclass mechanics; the note says why |

Shapes: **one-shot** (`async throws`, answer collected to IB's end marker), **request stream**
(`AsyncThrowingStream`, leaving `for await` sends the cancel), **snapshot+stream** (always-on state synced at
connect), **model helper** (a computed property or method on a model), **factory** (a static constructor),
**parameter** (a new argument on an existing call), **field** (a new stored property).
`IBClient.` is left off the Swift names of calls on the client.

## `IB` (ib.py): events

| ib_async | swift-ibkr | Status | Note |
|---|---|---|---|
| `connectedEvent` | `states()` → `.connected(serverVersion:accounts:)` | present | |
| `disconnectedEvent` | `states()` → `.disconnected(_:)` | present | |
| `updateEvent` | `messages()` | present | one element per decoded message, where ib_async fires once per network packet |
| `pendingTickersEvent` | `pendingTickers()` → `AsyncStream<[Ticker]>` | added | a fresh stream per call; each fold step of any open `tickers(_:genericTicks:depthRows:smartDepth:tickByTick:options:)` stream yields `[ticker]`, the one it changed (per update, where ib_async fires the set of tickers changed by one packet) |
| `barUpdateEvent` | `barUpdates()` → `LiveBars` | added | a fresh stream per call of every change of any `realTimeBars` or `liveHistoricalBars` subscription: the whole `LiveBars` (request id, contract, bar size, whatToShow, `bars`, `hasNewBar`); not the first keepUpToDate batch, as in ib_async |
| `newOrderEvent` | `orders()` updates | present | the first `orders()` update of an id this client placed: the local `.pendingSubmit` snapshot `placeOrder` publishes at once (ib.py:812); `orders()` also fires on every later change, from any client |
| `orderModifyEvent` | `orderEvents()` → `OrderEvent.modified` | added | at `modifyOrder` of a known order that is not final; the snapshot's log ends `Modify` |
| `cancelOrderEvent` | `orderEvents()` → `OrderEvent.cancelRequested` | added | at `cancelOrder` of a known order that is not final, with the local `.pendingCancel` / `.cancelled` |
| `openOrderEvent` | `orders()` updates; `messages()` → `.openOrder` | present | |
| `orderStatusEvent` | `orders()` updates; `messages()` → `.orderStatus` | present | |
| `execDetailsEvent` | `executions()` updates; `messages()` → `.execDetails` | present | a `Fill` is published once its commission is in; join to the order by `execution.permID` |
| `commissionReportEvent` | `executions()` updates (`Fill.commission`) | present | |
| `updatePortfolioEvent` | `portfolio()` updates | present | whole sets, not one item |
| `positionEvent` | `positions()` updates | present | whole sets, not one position |
| `accountValueEvent` | `accountValues()` updates | present | |
| `accountSummaryEvent` | `accountSummary(tags:group:)` | present | whole sets per subscription |
| `pnlEvent` | `pnl(account:modelCode:)` | present | per subscription |
| `pnlSingleEvent` | `pnlSingle(account:conID:modelCode:)` | present | per subscription |
| `scannerDataEvent` | `scannerSubscription(_:options:filterOptions:)` | present | per subscription |
| `tickNewsEvent` | `marketData(_:…)` → `Tick.news` | present | per subscription |
| `newsBulletinEvent` | `newsBulletins(allMessages:)` | present | |
| `wshMetaEvent` | `wshMetaData()` | present | the answer is returned |
| `wshEvent` | `wshEventData(_:)` | present | the answer is returned |
| `errorEvent` | `messages()` → `.error(IBErrorMessage)`; thrown `IBClientError` | present | the message carries no contract |
| `timeoutEvent` | `idleTimeouts(after:)` → `AsyncStream<Duration>` | added | a fresh stream per call: while connected, the idle time once each time `after` passes with no incoming frame; the next frame re-arms it (ib_async re-arms by calling `setTimeout` again); the connection is left alone, where `ReconnectPolicy.probeAfter` probes and reconnects |

## `IB` (ib.py): class attributes and module names

| ib_async | swift-ibkr | Status | Note |
|---|---|---|---|
| `IB(defaults:)` | `IBClient()` | present | `defaults` is the `IBDefaults` row |
| `IB.events` | — | n/a | eventkit bookkeeping tuple |
| `IB.wrapper`, `IB.client` | `IBClient` | present | see the `Client` and `Wrapper` rows |
| `RequestTimeout` | — | n/a | timeout of the synchronous wrappers only; cancel the calling task |
| `RaiseRequestErrors` | thrown `IBClientError` | present | the `True` mode only; ib_async's default `False` (log, resolve empty or partial, wrapper.py:1647) is deliberately not offered (DECISIONS rows 61 and 74) |
| `MaxSyncedSubAccounts` | `ConnectOptions.maxSyncedSubAccounts` | added | 50: with more accounts the sync sends no reqAccountUpdatesMulti; with one account none goes out while reqAccountUpdates covers it (ib_async sends one for it too, DECISIONS) |
| `TimezoneTWS` | `ConnectOptions.gatewayTimeZone` | added | `TimeZone?`; reads an `Execution.time` that names no zone (IB's live `yyyyMMdd-HH:mm:ss`), UTC when `nil` where ib_async falls back to the machine's zone (DECISIONS) |
| `StartupFetch` | `StartupFetch` | added | `OptionSet` with `positions`, `ordersOpen`, `ordersComplete`, `accountUpdates`, `subAccountUpdates`, `executions`, as `ConnectOptions.fetch`; `.positions` gates reqPositions, which ib_async always sends |
| `StartupFetchALL`, `StartupFetchNONE` | `StartupFetch.all`, `StartupFetch.none` | added | `.none` is `[]`; in an optional context write `StartupFetch.none` |
| `__enter__`, `__exit__`, `__del__`, `__repr__` | — | n/a | Python dunders |

## `IB` (ib.py): methods

| ib_async | swift-ibkr | Status | Note |
|---|---|---|---|
| `connect` / `connectAsync` | `connect(host:port:clientID:timeout:reconnect:options:)` | present | waits for the whole sync like ib_async |
| `connect(readonly:account:raiseSyncErrors:fetchFields:)` | `connect(host:port:clientID:timeout:reconnect:options:)`, `ConnectOptions.readOnly`, `.account`, `.throwsOnSyncError`, `.fetch` | added | `readOnly` skips open and completed orders; `account` gets reqAccountUpdates (one of several accounts gets a portfolio); `throwsOnSyncError` defaults to `true` (ib_async's `raiseSyncErrors` to `false`): off, a failed sync request or the deadline with only sync markers due is logged at `.error` and `connect` succeeds |
| `connectAsync`: `reqAutoOpenOrders(True)` for clientId 0 | `connect(…)` with `clientID: 0` | added | sends `setAutoOpenOrders(true)` first in the sync (ib.py:2046) |
| `disconnect` | `disconnect()` | present | ib_async also returns a stats line (see `Client.connectionStats`) |
| `isConnected` | `states()` (current state first) | present | |
| `waitOnUpdate`, `loopUntil` | — | n/a | synchronous wrappers over `updateEvent`; `for await` on a stream |
| `setTimeout` | `idleTimeouts(after:)` | added | see `timeoutEvent` |
| `run`, `schedule`, `sleep` | — | n/a | event-loop glue (`util` aliases); `Task.sleep` |
| `timeRange`, `timeRangeAsync`, `waitUntil` | `IBClient.timeRange(from:to:every:)`, `IBClient.wait(until:)` | added | aliases of the `util` rows of the same names |
| `managedAccounts` | `managedAccounts()`; `states()` → `.connected(accounts:)` | present | Swift asks IB afresh; the state keeps the list seen at connect |
| `accountValues` | `accountValues()` | present | filter by account with `.filter { $0.account == a }` |
| `accountSummary` / `accountSummaryAsync` | `accountSummary(tags:group:)` | present | |
| `accountSummary` with no tags (cached, re-requested on 1102) | `accountSummary(tags:group:)`, `IBClient.defaultAccountSummaryTags` | added | request stream: `tags` default to ib_async's set (33 tags + `$LEDGER:ALL`, ib.py:2247-2258), `group` to All; on notice 1102 each open stream sends its cancel and its request again under its reqId (ib_async re-requests under a new reqId, ib.py:414); not cached: each call is its own subscription |
| `portfolio` | `portfolio()` | present | the account reqAccountUpdates follows: `ConnectOptions.account`, by default the only managed account, as ib_async |
| `positions` | `positions()` | present | |
| `pnl(account, modelCode)` | `pnlValues(account:modelCode:)` → `[AccountPnL]` | added | the latest value of each open `pnl(account:modelCode:)` stream, oldest first; an empty argument matches all (ib.py:554-570); a stream is listed once its first value arrives, where ib_async lists an all-NaN `PnL` from the request; an entry leaves when its stream ends (consumer stop, IB error, connection end) |
| `pnlSingle(account, modelCode, conId)` | `pnlSingleValues(account:modelCode:conID:)` → `[PnL]` | added | the same for `pnlSingle(account:conID:modelCode:)`; `conID` `nil` matches all, where ib_async's `0` does |
| `trades` | `orders().snapshot` | present | `OrderSnapshot` is `Trade` |
| `openTrades` | `orders().snapshot.filter { !$0.status.isFinal }` | present | |
| `orders` | `orders().snapshot.map(\.order)` | present | |
| `openOrders` | `orders().snapshot.filter { !$0.status.isFinal }.map(\.order)` | present | |
| `fills` | `executions().snapshot` | present | |
| `executions` | `executions().snapshot.map(\.execution)` | present | |
| `ticker(contract)` | `ticker(for:)` → `Ticker?` | added | the latest `Ticker` of an open `tickers(_:genericTicks:depthRows:smartDepth:tickByTick:options:)` stream, matched as ib_async's `__eq__` (contract.py:154-159): by the same non-zero `conID`, else field-wise `==`; two open streams for one contract are two tickers (ib_async shares one), and the older one's is returned |
| `tickers` | `activeTickers()` → `[Ticker]` | added | the latest `Ticker` of every open `tickers(_:genericTicks:depthRows:smartDepth:tickByTick:options:)` stream, oldest first, listed from the call (empty, as ib_async's `reqMktData` creates it) until the stream ends, however it ends; `tickers(for:regulatorySnapshot:)` snapshots are not listed |
| `pendingTickers` | `pendingTickers()` | added | a stream rather than ib_async's set of the last packet (see `pendingTickersEvent`) |
| `realtimeBars` | `liveBarSubscriptions()` → `[LiveBars]` | added | the open `realTimeBars` and `liveHistoricalBars` subscriptions by request id, with their bars so far; an entry leaves when its stream ends (consumer stop, IB error, connection end); `historicalBars(keepUpToDate: true)`, the raw stream, is not listed |
| `newsTicks` | `newsTicks()` → `(snapshot: [NewsTick], updates: AsyncStream<NewsTick>)` | added | every `Tick.news` on any reqId since the last manual `connect` (a reconnect keeps them; wrapper.py:1487), and a fresh stream of new ones; grows for the whole session, as in ib_async |
| `newsBulletins` | `receivedBulletins()` → `[NewsBulletin]` | added | every bulletin since the last manual `connect`, one per `msgID` (the last received wins) in first-seen order, as ib_async's `msgId2NewsBulletin` (wrapper.py:1509) |
| `reqTickers` / `reqTickersAsync` | `tickers(for:regulatorySnapshot:)` | present | Swift throws the first error where ib_async returns partial tickers (DECISIONS) |
| `qualifyContracts` / `qualifyContractsAsync(returnAll:)` | `qualifyContracts(_:)` | present | `.ambiguous` carries what `returnAll` returns |
| `bracketOrder` | `Order.bracket(_:quantity:limitPrice:takeProfitPrice:stopLossPrice:)` + `placeBracket(_:_:)` | present | ids are assigned at `placeBracket` |
| `oneCancelsAll` | `Order.oneCancelsAll(_:group:type:)` | present | |
| `whatIfOrder` / `whatIfOrderAsync` | `whatIfOrder(_:_:)` | present | |
| `placeOrder` (new) | `placeOrder(_:_:)` | present | returns the id; the live `Trade` is `orders()` |
| `placeOrder` (existing) | `modifyOrder(_:_:_:)` | present | |
| `placeOrder`: local `PendingSubmit` trade and log | `placeOrder(_:_:)`, `placeBracket(_:_:)`, `modifyOrder(_:_:_:)` → `orders()` | added | behaviour: a local `.pendingSubmit` snapshot with one `log` entry at placement; a modify of a known unfinished order replaces order and contract, clears `rejectReason` and logs `Modify`, and the next unchanged `Submitted` logs `Modified` (ib.py:790, wrapper.py:772); a modify of a final order changes nothing locally where `ib_async` asserts |
| `cancelOrder` | `cancelOrder(_:manualCancelOrderTime:)` | present | |
| `cancelOrder`: local `PendingCancel` / `Cancelled` | `cancelOrder(_:manualCancelOrderTime:)` → `orders()` | added | behaviour: a local `.pendingCancel`, or `.cancelled` for a `.pendingSubmit` order with `transmit` off, logged at the call (ib.py:830); an unknown or final order changes nothing |
| `reqGlobalCancel` | `cancelAllOrders()` | present | |
| `reqCurrentTime` / `reqCurrentTimeAsync` | `currentTime()` | present | |
| `reqAccountUpdates` / `reqAccountUpdatesAsync` | `portfolio()`, `accountValues()` (subscribed at connect) | present | choosing the account is `ConnectOptions.account` |
| `reqAccountUpdatesMulti` / `reqAccountUpdatesMultiAsync` | `accountUpdatesMulti(account:modelCode:ledgerAndNLV:)` | present | |
| `reqAccountSummary` / `reqAccountSummaryAsync` | `accountSummary(tags:group:)` | present | ib_async's fixed tag set is the `accountSummary` with no tags row |
| `reqAutoOpenOrders` | `setAutoOpenOrders(_:)` | present | |
| `reqOpenOrders` / `reqOpenOrdersAsync` | `fetchOpenOrders()` | added | one-shot (id-less) `-> [OrderSnapshot]`: reqOpenOrders 5 to openOrderEnd, the `orders()` snapshot of each order listed, in arrival order |
| `reqAllOpenOrders` / `reqAllOpenOrdersAsync` | `fetchAllOpenOrders()` | added | one-shot (id-less) `-> [OrderSnapshot]`: 16 to openOrderEnd, as `fetchOpenOrders()` |
| `reqCompletedOrders` / `reqCompletedOrdersAsync` | `completedOrders(apiOnly:)` | added | one-shot (id-less) `-> [OrderSnapshot]`: 99 to completedOrdersEnd, `apiOnly` defaulting to `false` |
| `reqExecutions` / `reqExecutionsAsync` | `executions(filter:)` | added | one-shot `-> [Fill]`: 7 with a reqId to execDetailsEnd, the joined fills of the executions listed; one still without its commission report is left out and logged (ib_async returns it with an empty report); no default filter, so `executions()` keeps its name |
| `reqPositions` / `reqPositionsAsync` | `positions()` | present | on for the whole connection unless `ConnectOptions.fetch` leaves out `.positions` (ib_async always sends it) |
| `reqPnL` / `cancelPnL` | `pnl(account:modelCode:)` | present | stopping the stream cancels |
| `reqPnLSingle` / `cancelPnLSingle` | `pnlSingle(account:conID:modelCode:)` | present | |
| `reqContractDetails` / `reqContractDetailsAsync` | `contractDetails(_:)` | present | |
| `reqMatchingSymbols` / `reqMatchingSymbolsAsync` | `matchingSymbols(_:)` | present | no 4 s timeout: cancel the task |
| `reqMarketRule` / `reqMarketRuleAsync` | `marketRule(_:)` | present | |
| `reqRealTimeBars` | `realTimeBars(_:whatToShow:rth:options:)` | present | bar size is IB's only one, 5 |
| `cancelRealTimeBars` | stop `realTimeBars` | present | |
| `reqRealTimeBars` / `reqHistoricalData(keepUpToDate)`: resubscribe on 10225 | `realTimeBars(_:whatToShow:rth:options:)`, `liveHistoricalBars(_:duration:barSize:whatToShow:rth:options:)`, `historicalBars(_:end:duration:barSize:whatToShow:rth:keepUpToDate:options:)` with `keepUpToDate` | added | on 10225 the client sends the cancel, then the same request (options included) under the same reqId, and the stream goes on (wrapper.py:1694-1721); `liveHistoricalBars` ignores the batch IB answers it with, as ib_async's popped `_results` does, while the raw `historicalBars` yields it as another `.history`; reverses the «10225 stays fatal» half of the DECISIONS row |
| `reqHistoricalData` / `reqHistoricalDataAsync` | `historicalBars(_:end:duration:barSize:whatToShow:rth:keepUpToDate:options:)` | present | `formatDate` is fixed (bars carry a `Date`); no 60 s timeout: cancel the task |
| `cancelHistoricalData` | stop `historicalBars` | present | |
| `reqHistoricalSchedule` / `reqHistoricalScheduleAsync` | `historicalSchedule(_:days:end:rth:)` | present | |
| `reqHistoricalTicks` / `reqHistoricalTicksAsync` | `historicalTicks(_:start:end:count:whatToShow:rth:ignoreSize:options:)` | present | |
| `reqMarketDataType` | `setMarketDataType(_:)` | present | |
| `reqHeadTimeStamp` / `reqHeadTimeStampAsync` | `headTimeStamp(_:whatToShow:rth:)` | present | `formatDate` fixed to 2 (`Date`) |
| `reqMktData` | `marketData(_:genericTicks:snapshot:regulatorySnapshot:options:)`; `tickers(_:genericTicks:depthRows:smartDepth:tickByTick:options:)` | present | raw ticks, or a whole `Ticker` after each |
| `cancelMktData` | stop the stream | present | |
| `reqTickByTickData` | `tickByTick(_:_:count:ignoreSize:)` | present | |
| `reqTickByTickData(numberOfTicks:ignoreSize:)` | `tickByTick(_:_:count:ignoreSize:)` | added | `count: Int = 0`, `ignoreSize: Bool = false`, sent as numberOfTicks and ignoreSize |
| `cancelTickByTickData` | stop `tickByTick` | present | |
| `reqSmartComponents` / `reqSmartComponentsAsync` | `smartComponents(_:)` | present | |
| `reqMktDepthExchanges` / `reqMktDepthExchangesAsync` | `depthExchanges()` | present | |
| `reqMktDepth` | `marketDepth(_:rows:smart:options:)`; `tickers(_:genericTicks:depthRows:smartDepth:tickByTick:options:)` with `depthRows` | present | Swift's `smart` defaults to true, ib_async's `isSmartDepth` to False |
| `cancelMktDepth` | stop the stream | present | |
| `mktDataOptions`, `chartOptions`, `realTimeBarsOptions`, `mktDepthOptions`, `miscOptions` | `options:` on `marketData`, `tickers`, `historicalBars`, `realTimeBars`, `marketDepth`, `historicalTicks` | added | `[TagValue] = []`, sent as `tag=value;` per pair (IB: internal use); `tickers` sends its options with the market-data request only |
| `reqHistogramData` / `reqHistogramDataAsync` | `histogramData(_:period:rth:)` | present | |
| `reqFundamentalData` / `reqFundamentalDataAsync` | `fundamentalData(_:reportType:options:)` | present | |
| `reqScannerData` / `reqScannerDataAsync` | `scannerData(_:options:filterOptions:)` | present | |
| `reqScannerSubscription` | `scannerSubscription(_:options:filterOptions:)` | present | |
| `reqScannerSubscription`: empty scan on 165 | `scannerSubscription` yields `[]`; `scannerData` returns `[]` | added | notice 165 («no items retrieved») empties the scan (wrapper.py:1670); the subscription stays open |
| `cancelScannerSubscription` | stop `scannerSubscription` | present | |
| `reqScannerParameters` / `reqScannerParametersAsync` | `scannerParameters()` | present | |
| `calculateImpliedVolatility` / `calculateImpliedVolatilityAsync` | `calculateImpliedVolatility(_:optionPrice:underPrice:options:)` | present | no 4 s timeout |
| `calculateOptionPrice` / `calculateOptionPriceAsync` | `calculateOptionPrice(_:volatility:underPrice:options:)` | present | no 4 s timeout |
| `reqSecDefOptParams` / `reqSecDefOptParamsAsync` | `optionChains(for:futFopExchange:)` | present | takes the underlying `Contract` |
| `exerciseOptions` | `exerciseOptions(_:action:quantity:account:override:)` | present | |
| `reqNewsProviders` / `reqNewsProvidersAsync` | `newsProviders()` | present | |
| `reqNewsArticle` / `reqNewsArticleAsync` | `newsArticle(providerCode:articleID:options:)` | present | |
| `reqHistoricalNews` / `reqHistoricalNewsAsync` | `historicalNews(conID:providerCodes:start:end:totalResults:options:)` | present | |
| `reqNewsBulletins` / `cancelNewsBulletins` | `newsBulletins(allMessages:)` | present | |
| `requestFA` / `requestFAAsync` | `faData(_:)` | present | |
| `replaceFA` | `replaceFA(_:xml:)` | present | |
| `reqWshMetaData` / `cancelWshMetaData` / `getWshMetaData` / `getWshMetaDataAsync` | `wshMetaData()` | present | |
| `reqWshEventData` / `cancelWshEventData` / `getWshEventData` / `getWshEventDataAsync` | `wshEventData(_:)` | present | |
| `reqUserInfo` / `reqUserInfoAsync` | `userInfo()` | present | |

## `Ticker` (ticker.py)

| ib_async | swift-ibkr | Status | Note |
|---|---|---|---|
| `Ticker` | `Ticker` | present | |
| `Ticker.updateEvent` | `tickers(_:genericTicks:depthRows:smartDepth:tickByTick:options:)` | present | yields the whole ticker after each update; a slow consumer gets the newest, carrying the `ticks`, `tickByTicks` and `domTicks` of every update it skipped |
| `Ticker.events`, `defaults`, `created`, `__post_init__`, `__eq__`, `__hash__`, `__repr__`, `__str__` | — | n/a | eventkit, dataclass and dunder mechanics; `defaults` is the `IBDefaults` row |
| `contract` | `Ticker.contract` | present | |
| `time` | `Ticker.time` | added | the time `tickers` folded in the latest update (wrapper.py:1739); one update is one message, not one TCP packet (DECISIONS) |
| `timestamp` | `Ticker.time` | added | the same instant as epoch seconds in ib_async; `Date` covers both |
| `marketDataType` | `Ticker.marketDataType` | present | |
| `minTick` | `Ticker.minTick` | present | |
| `bid`, `bidSize`, `ask`, `askSize`, `last`, `lastSize` | `Ticker.bid` … `Ticker.lastSize` | present | |
| `bidExchange`, `askExchange`, `lastExchange` | `Ticker.bidExchange`, `askExchange`, `lastExchange` | added | model helper: named `Ticker.bidExchange`, `askExchange`, `lastExchange` |
| `lastTimestamp` | `Ticker.lastTimestamp` | present | |
| `prevBid`, `prevBidSize`, `prevAsk`, `prevAskSize`, `prevLast`, `prevLastSize` | `Ticker.prevBid`, `Ticker.prevBidSize`, `Ticker.prevAsk`, `Ticker.prevAskSize`, `Ticker.prevLast`, `Ticker.prevLastSize` | added | set by `apply(_:at:)` (ticks and tick-by-tick events) before each bid/ask/last change, as wrapper.py:1000-1178 |
| `volume`, `open`, `high`, `low`, `close` | `Ticker.volume` … `Ticker.close` | present | |
| `vwap` | `Ticker.vwap` | added | parsed from RT volume (48/77, wrapper.py:482); the raw string stays in `strings` |
| `low13week`, `high13week`, `low26week`, `high26week`, `low52week`, `high52week` | `Ticker.low13Week` … `high52Week` | added | model helper: named properties |
| `bidYield`, `askYield`, `lastYield` | `Ticker.bidYield`, `askYield`, `lastYield` | added | model helper: named properties |
| `markPrice` | `Ticker.markPrice` | added | model helper |
| `halted` | `Ticker.halted` | added | model helper `Ticker.halted` |
| `rtHistVolatility` | `Ticker.rtHistVolatility` | added | model helper |
| `rtVolume`, `rtTradeVolume`, `rtTime` | `Ticker.rtVolume`, `Ticker.rtTradeVolume`, `Ticker.rtTime` | added | parsed from RT volume (wrapper.py:482), the raw string kept in `strings`; ib_async also moves `last`/`lastSize` from it, Swift keeps them from ticks 4/5 only (DECISIONS row kept; a documented difference); the trade is recorded in `Ticker.ticks` as ib_async records it |
| `avVolume` | `Ticker.averageVolume` | added | model helper |
| `tradeCount`, `tradeRate`, `volumeRate` | `Ticker.tradeCount`, `tradeRate`, `volumeRate` | added | model helper |
| `volumeRate3Min`, `volumeRate5Min`, `volumeRate10Min` | `Ticker.volumeRate3Min`, `volumeRate5Min`, `volumeRate10Min` | added | model helper |
| `shortable` | `Ticker.shortable` | added | model helper |
| `shortableShares` | `Ticker.shortableShares` | added | model helper |
| `indexFuturePremium` | `Ticker.indexFuturePremium` | added | model helper |
| `futuresOpenInterest` | `Ticker.futuresOpenInterest` | added | model helper |
| `putOpenInterest`, `callOpenInterest`, `putVolume`, `callVolume` | `Ticker.putOpenInterest`, `callOpenInterest`, `putVolume`, `callVolume` | added | model helper |
| `avOptionVolume` | `Ticker.averageOptionVolume` | added | model helper |
| `histVolatility`, `impliedVolatility` | `Ticker.histVolatility`, `impliedVolatility` | added | model helper |
| `openInterest` | `Ticker.openInterest` | added | model helper |
| `lastRthTrade` | `Ticker.lastRTHTrade` | added | model helper |
| `lastRegTime` | `Ticker.lastRegTime` | added | model helper |
| `optionBidExch`, `optionAskExch` | `Ticker.optionBidExchange`, `optionAskExchange` | added | model helper |
| `bondFactorMultiplier` | `Ticker.bondFactorMultiplier` | added | model helper |
| `creditmanMarkPrice`, `creditmanSlowMarkPrice` | `Ticker.creditmanMarkPrice`, `creditmanSlowMarkPrice` | added | model helper |
| `delayedLastTimestamp` | `Ticker.delayedLastTimestamp` | added | tick 88, kept apart from `lastTimestamp` as ib_async; 1.0.0 folded it into `lastTimestamp` (CHANGELOG, Changed) |
| `delayedHalted` | `Ticker.delayedHalted` | added | model helper |
| `reutersMutualFunds` | `Ticker.reutersMutualFunds` | added | model helper |
| `etfNavClose`, `etfNavPriorClose`, `etfNavBid`, `etfNavAsk`, `etfNavLast`, `etfFrozenNavLast`, `etfNavHigh`, `etfNavLow` | `Ticker.etfNavClose` … `etfNavLow` | added | model helper |
| `socialMarketAnalytics` | `Ticker.socialMarketAnalytics` | added | model helper |
| `estimatedIpoMidpoint`, `finalIpoLast` | `Ticker.estimatedIPOMidpoint`, `finalIPOLast` | added | model helper |
| `dividends` | `Ticker.dividends` | added | parsed as wrapper.py:1233; the raw string stays in `strings` |
| `fundamentalRatios` | `Ticker.fundamentalRatios` | added | parsed as wrapper.py:1208; the raw string stays in `strings` |
| `ticks` | `Ticker.ticks` | added | the price and size ticks of the latest `tickers` update with their time (`[TickData]`), recorded as wrapper.py:1046/1103/1262 |
| `tickByTicks` | `Ticker.tickByTicks` | added | the tick-by-tick events of the latest update (`tickers(…, tickByTick:)`), folded into bid/ask/last as wrapper.py:1111; each keeps IB's time where ib_async stamps the arrival time |
| `domBids`, `domAsks` | `Ticker.depth.bids`, `Ticker.depth.asks` | present | |
| `domBidsDict`, `domAsksDict` | `DepthBook.bidsByPosition`, `DepthBook.asksByPosition` | added | on `Ticker.depth` |
| `domTicks` | `Ticker.domTicks` | added | the depth updates of the latest update with their time (`[DepthTick]`); a delete carries the removed row's price, and the reset (317) one delete per row, as wrapper.py:1338/1681 |
| `bidGreeks`, `askGreeks`, `lastGreeks`, `modelGreeks`, `custGreeks` | `Ticker.bidGreeks` … `Ticker.custGreeks` | present | |
| `bidEfp`, `askEfp`, `lastEfp`, `openEfp`, `highEfp`, `lowEfp`, `closeEfp` | `Ticker.bidEFP` … `closeEFP` | added | model helper: named properties |
| `auctionVolume`, `auctionPrice`, `auctionImbalance`, `regulatoryImbalance` | `Ticker.auctionVolume`, `auctionPrice`, `auctionImbalance`, `regulatoryImbalance` | added | model helper |
| `bboExchange`, `snapshotPermissions` | `Ticker.bboExchange`, `Ticker.snapshotPermissions` | present | |
| `isUnset` | — | n/a | compares with the NaN placeholder; Swift's unset is `nil` |
| `hasBidAsk` | `Ticker.hasBidAsk` | added | model helper `Ticker.hasBidAsk: Bool` (ticker.py:263) |
| `midpoint` | `Ticker.midpoint` | added | model helper `Ticker.midpoint: Decimal?` (ticker.py:274) |
| `marketPrice` | `Ticker.marketPrice` | added | model helper `Ticker.marketPrice: Decimal?` (ticker.py:281) |

## ticker.py: tick filters and bar builders

| ib_async | swift-ibkr | Status | Note |
|---|---|---|---|
| `TickerUpdateEvent` | `AsyncSequence where Element == Ticker` (such as `IBClient.tickers(_:genericTicks:depthRows:smartDepth:tickByTick:options:)`) | added | the operators below are extensions on any `Sendable` sequence of `Ticker` |
| `TickerUpdateEvent.trades` | `trades()` | added | `TickPoint` (time, price, size) of ticks 4, 5, 48, 68, 71; a tick with no price is skipped, no size reads 0 |
| `TickerUpdateEvent.bids` | `bids()` | added | ticks 0, 1, 66, 69 |
| `TickerUpdateEvent.asks` | `asks()` | added | ticks 2, 3, 67, 70 |
| `TickerUpdateEvent.bidasks` | `bidAsks()` | added | ticks 0, 1, 66, 69, 2, 3, 67, 70 |
| `TickerUpdateEvent.midpoints` | `midpoints()` | added | `Ticker.time`, `Ticker.midpoint`, size 0 per ticker whose `ticks` is non-empty; a `nil` midpoint is skipped |
| `Tickfilter` | `AsyncThrowingStream<TickPoint, any Error>`, `TickPoint` | added | what the five above return; stopping it cancels the task reading its source |
| `Tickfilter.timebars` | `timeBars(timer:)` | added | the timer is any `AsyncSequence` of `Date` (ib_async's timer event); the first date only opens a bar; a bar with no tick takes the previous close, one with no previous bar is dropped where ib_async keeps a NaN bar |
| `Tickfilter.tickbars` | `tickBars(count:)` | added | yields when a bar completes |
| `Tickfilter.volumebars` | `volumeBars(volume:)` | added | yields when a bar's volume reaches `volume` |
| `Midpoints` | `AsyncThrowingStream<TickPoint, any Error>` from `midpoints()` | added | |
| `Bar` (ticker.py) | `Bar` | present | the builders can emit the existing `Bar` |
| `BarList` (+ `updateEvent`) | `BarList` (`bars`, `hasNewBar`) | added | each element of a builder's stream is one `updateEvent`; `bars` grows without bound, as in ib_async |
| `TimeBars`, `TickBars`, `VolumeBars` | `AsyncThrowingStream<BarList, any Error>` from `timeBars(timer:)`, `tickBars(count:)`, `volumeBars(volume:)` | added | |
| `on_source` of `Tickfilter`, `Midpoints`, `TimeBars`, `TickBars`, `VolumeBars` | — | n/a | eventkit `Op` override hooks; the logic belongs to the rows above |

## objects.py

| ib_async | swift-ibkr | Status | Note |
|---|---|---|---|
| `AccountValue` | `AccountValue` | present | |
| `BarData` | `Bar` | present | |
| `BarDataList` | `historicalBars(…)` → `BarEvent.history([Bar])` | present | the request parameters are the caller's own |
| `BarDataList.updateEvent` (keepUpToDate) | `liveHistoricalBars(_:duration:barSize:whatToShow:rth:options:)` → `BarList`, `BarList.apply(_:)` | added | the first batch (`hasNewBar` true), then the whole list after each update that changes it: an older bar is dropped, a later one appended (`hasNewBar` true), one at the last bar's time replaces it (`false`) unless identical (wrapper.py:923-942). Unlike ib_async (`if not bars: return`), an update after an empty batch is appended rather than dropped; updates before the batch are dropped as in ib_async. `historicalBars(…keepUpToDate: true)` still yields raw `BarEvent.update` |
| `CommissionReport` | `CommissionReport` | present | |
| `ConnectionStats` | `ConnectionStats` | added | `startTime`, `duration`, `bytesReceived`, `bytesSent`, `messagesReceived`, `messagesSent`; described with `formatSI` and raw message counts, as ib.py:394-398 |
| `DepthMktDataDescription` | `DepthMarketDataDescription` | present | |
| `Dividends` | `Dividends` | added | `past12Months`, `next12Months`, `nextDate` (00:00 UTC), `nextAmount`; see `Ticker.dividends` |
| `DOMLevel` | `DepthLevel` | present | |
| `Execution` | `Execution` | present | |
| `Execution.evRule`, `evMultiplier`, `modelCode` | `Execution.evRule`, `.evMultiplier`, `.modelCode` | added | decoded from execDetails (in 11) after `orderRef`; `evMultiplier` is `Decimal?` |
| `Execution.time` as datetime | `Execution.date` | added | `Date?` beside `Execution.time`, which stays IB's raw string; a text without a zone reads in `ConnectOptions.gatewayTimeZone` ?? UTC, a named zone wins (decoder.py:468) |
| `ExecutionFilter` | `ExecutionFilter` | present | |
| `FamilyCode` | `FamilyCode` | present | |
| `Fill` | `Fill` | present | |
| `Fill.time` | `Fill.time` | added | `Date?`: the arrival time for a live execDetails (reqId -1), `execution.date` for a replay or a reply (wrapper.py:821-823); `ExecutionTracker.apply(_:receivedAt:)` |
| `FundamentalRatios` | `FundamentalRatios` | added | IB's text per tag (`values`, subscript), `decimal(_:)` reads a number (`-99999.99` → `nil`); see `Ticker.fundamentalRatios` |
| `HistogramData` | `HistogramData` | present | |
| `HistoricalNews` | `HistoricalNews` | present | `time` stays IB's string (DECISIONS) |
| `HistoricalSchedule`, `HistoricalSession` | `HistoricalSchedule`, `HistoricalSession` | present | |
| `HistoricalTick` | `TickByTick.midPoint` | present | without `size` |
| `HistoricalTickBidAsk` | `TickByTick.bidAsk` | present | the attributes are its `bidPastLow`, `askPastHigh` (`TickAttribBidAsk` row) |
| `HistoricalTickLast` | `TickByTick.trade` | present | |
| `IBDefaults` | — | n/a | configures the NaN/-1/0 placeholders of Python's float fields (Swift models use `nil`) and `timezone`, the zone of the log-entry times (Swift's `Date` carries no zone); nothing to configure |
| `MktDepthData` | `DepthUpdate` (`messages()` → `.depth`) | present | no arrival time; `DepthTick` adds it in `Ticker.domTicks` |
| `NewsArticle` | `NewsArticle` | present | |
| `NewsBulletin` | `NewsBulletin` | present | |
| `NewsProvider` | `NewsProvider` | present | |
| `NewsTick` | `NewsTick` | present | |
| `OptionChain` | `OptionChain` | present | |
| `OptionComputation` | `OptionComputation` | present | |
| `OptionComputation.__add__`, `__sub__`, `__mul__` | `OptionComputation.+`, `.-`, `.*` (with a `Decimal`) | added | the six fields impliedVol, delta, optPrice, gamma, vega, theta with unset read as 0 (a result is never `nil` there); `pvDividend` dropped, `undPrice` from the left, `tickAttrib` 0 (objects.py:370-413) |
| `PnL` | `AccountPnL` | present | `account` and `modelCode` (stage 14) are the subscription's, set by the `pnl` stream; empty in a decoded message |
| `PnLSingle` | `PnL` | present | `account`, `modelCode` and `conID` (stage 14) are the subscription's, set by the `pnlSingle` stream; empty and 0 in a decoded message |
| `PortfolioItem` | `PortfolioItem` | present | |
| `Position` | `Position` | present | |
| `PriceIncrement` | `PriceIncrement` | present | |
| `RealTimeBar` | `Bar` | present | `wap` is `average` |
| `RealTimeBarList` (+ `updateEvent`) | `realTimeBars(_:whatToShow:rth:options:)`, `liveBarSubscriptions()` | present | every element of the stream is a new bar (`hasNewBar` is always true); the accumulated list is the stream's `LiveBars` in `liveBarSubscriptions()` (bar size `"5 secs"`), growing for the subscription's lifetime as in ib_async |
| `ScanDataList` (+ `updateEvent`) | `scannerSubscription(…)` | present | every element is the whole scan |
| `ScannerSubscription` | `ScannerSubscription` | present | |
| `SmartComponent` | `SmartComponent` | present | |
| `SoftDollarTier` | `SoftDollarTier` | present | |
| `SoftDollarTier.__bool__` | — | n/a | Python dunder |
| `TickAttrib` | `TickAttrib`, on `Tick.price(…, attributes:)` | added | `canAutoExecute`, `pastLimit`, `preOpen` (bits 0/1/2, from IB's API documentation, unseen live); ib_async exports it but its decoder drops the mask (decoder.py:201) |
| `TickAttribBidAsk` | `TickByTick.bidAsk(…bidPastLow:askPastHigh:)` | added | bits per message as ib_async's two decoders read them (they disagree: decoder.py:802, 864; protocol-178 Disagreements 10) |
| `TickAttribLast` | `TickByTick.trade(…pastLimit:unreported:)` | present | |
| `TickByTickAllLast` | `TickByTick.trade` | present | |
| `TickByTickBidAsk` | `TickByTick.bidAsk` | present | with `bidPastLow`, `askPastHigh` |
| `TickByTickMidPoint` | `TickByTick.midPoint` | present | |
| `TickData` | `TickData` | added | `time`, `field` (IB's raw tick type), `price`, `size`, in `Ticker.ticks`; the raw ticks stay `Tick` on `marketData` |
| `TradeLogEntry` | `TradeLogEntry` | added | `time`, `status`, `message`, `errorCode` (`nil` where ib_async has 0); an error entry's message is IB's text, not ib_async's `Warning 321, reqId 5: …` |
| `WshEventData` | `WshEventData` | present | |
| `EfpData` | `EFPData` | present | |
| `DynamicObject` | — | n/a | Python dynamic-attribute base class; `FlexRecord` and `FundamentalRatios` take its place |

## contract.py

| ib_async | swift-ibkr | Status | Note |
|---|---|---|---|
| `Contract` | `Contract` | present | |
| `Contract.includeExpired` | `Contract.includeExpired` | added | `false` by default; sent in contractDetails (9), historicalData (20), historicalTicks (96), headTimeStamp (87), histogram (88) |
| `Contract.issuerId` | `Contract.issuerID` | added | `""` by default; sent as the last field of contractDetails (9) at 176+; the received value is on `ContractDescription.issuerID` |
| `Contract.description` | `ContractDescription.description` | present | |
| `Contract.create` | `Contract(…secType:…)` | present | one struct for every type |
| `Contract.recreate` | — | n/a | turns a `Contract` into its Python subclass; Swift has no subclasses |
| `Contract.isHashable`, `__eq__`, `__hash__` | — | n/a | Python dunders; ib_async compares by `conId` when set (contract.py:145-161), Swift's `==` compares every field; the conID lookup is in the `ticker(contract)` row |
| `Stock`, `Option`, `Future`, `ContFuture`, `Forex`, `Index`, `CFD`, `Commodity`, `Bond`, `FuturesOption`, `MutualFund`, `Warrant`, `Bag`, `Crypto` | `Contract.stock`, `.option`, `.future`, `.contFuture`, `.forex`, `.index`, `.cfd`, `.commodity`, `.bond`, `.futuresOption`, `.mutualFund`, `.warrant`, `.bag`, `.crypto` | present | |
| `Forex.pair` | `Contract.pair` | added | `symbol + currency` on any `Contract` |
| `TagValue` | `TagValue` | present | |
| `ComboLeg` | `ComboLeg` | present | |
| `DeltaNeutralContract` | `DeltaNeutralContract` | present | |
| `TradingSession` | `TradingSession` | added | `TradingSession(start: Date, end: Date)` |
| `ContractDetails` | `ContractDetails` | present | `mdSizeMultiplier` is obsolete and skipped by both |
| `ContractDetails.tradingSessions` | `ContractDetails.tradingSessions` | added | read from `tradingHours` in `timeZoneID`; `CLOSED` days skipped, an unknown zone gives `[]`, and a malformed part or an hour `24` (`2400`) is skipped where ib_async raises (contract.py:599) |
| `ContractDetails.liquidSessions` | `ContractDetails.liquidSessions` | added | the same from `liquidHours` |
| `ContractDescription` | `ContractDescription` | present | |
| `ScanData` | `ScanData` | present | carries `contract` and `marketName`, all the frame has |

## order.py

| ib_async | swift-ibkr | Status | Note |
|---|---|---|---|
| `Order` | `Order` | present | ids live on `OrderSnapshot`; `faProfile` is obsolete (not sent at 178) |
| `Order.eTradeOnly`, `firmQuoteOnly`, `nbboPriceCap` | `Order.eTradeOnly`, `.firmQuoteOnly`, `.nbboPriceCap` | added | optional fields (`Bool?`, `Bool?`, `Decimal?`), `nil` keeps the wire default; deprecated by IB, a set value draws IB's rejection |
| `Order.__repr__`, `__str__`, `__eq__`, `__hash__` | — | n/a | Python dunders |
| `Order.filledQuantity` | `CompletedOrderMessage.filledQuantity` | present | |
| `LimitOrder`, `MarketOrder`, `StopOrder`, `StopLimitOrder` | `Order.limit`, `.market`, `.stop`, `.stopLimit` | present | |
| `OrderStatus` (the record) | `OrderStatusMessage` | present | |
| `OrderStatus.total` | `OrderSnapshot.total` | added | model helper: filled + remaining |
| `PendingSubmit`, `PendingCancel`, `PreSubmitted`, `Submitted`, `ApiPending`, `ApiCancelled`, `Cancelled`, `Filled`, `Inactive` | `OrderStatus.pendingSubmit` … `.inactive` | present | |
| `OrderStatus.ApiUpdate` | `OrderStatus.apiUpdate` | added | |
| `OrderStatus.ValidationError` | `OrderStatus.validationError` | added | active and working; set locally with a `log` entry (text and code) on a warning for an order that is not final, `rejectReason` still recorded (wrapper.py:1634). The warnings are the table's 105/321/329/434/492 (R4, P18); ib_async also counts 110 (unless PendingSubmit), 165, 399, 404, 10167 and 2100-2199, so e.g. a 399 on a live order leaves the status here where ib_async sets ValidationError |
| `OrderStatus.DoneStates` | `OrderStatus.isFinal` | present | |
| `OrderStatus.ActiveStates` | `OrderStatus.isActive` | added | model helper: pending submit, API pending, pre-submitted, submitted, validation error, API update |
| `OrderStatus.WaitingStates` | `OrderStatus.isWaiting` | added | model helper: pending submit, API pending, pre-submitted |
| `OrderStatus.WorkingStates` | `OrderStatus.isWorking` | added | model helper: submitted, validation error, API update |
| `OrderState` | `OrderState`; `status` on `OpenOrderMessage`, `completedTime`/`completedStatus` on `CompletedOrderMessage` | present | |
| `OrderState.numeric`, `OrderStateNumeric` | `OrderState` | present | its margins and commissions are already `Decimal?` |
| `OrderState.transform` | `OrderState.map(_:)` | added | model helper over the twelve numbers; `nil` stays `nil` |
| `OrderState.formatted` | `OrderState.formatted(digits:)` | added | model helper: `[String: String]` keyed by field name, `"300,000.21"`, rounded half-even; `""` for an unset value where ib_async gives `None` |
| `OrderComboLeg` | `OrderComboLeg` | present | |
| `Trade` | `OrderSnapshot` | present | |
| `Trade.contract`, `order`, `orderStatus` | `OrderSnapshot.contract`, `.order`, `.status` … `.whyHeld` | present | |
| `Trade.orderStatus.mktCapPrice` | `OrderSnapshot.marketCapPrice` | added | field, merged from `OrderStatusMessage.marketCapPrice` |
| `Trade.fills` | `OrderSnapshot.fills` | added | field: each whole fill (after its commission) joined by permID, else client and order id; a correction replaces the fill it corrects; the sync's replay joins a fresh tracker's orders too |
| `Trade.log` | `OrderSnapshot.log` | added | field: local states, status changes, `Modify`/`Modified`, `Fill <shares>@<price>` (Decimal's text), errors with their codes; an openOrder or completedOrder that changes a known order's status logs it too, since here openOrder sets the status |
| `Trade.advancedError` | `OrderSnapshot.advancedOrderRejectJSON` | present | |
| `Trade.statusEvent` | `orders()` updates for one `orderID` | present | |
| `Trade.modifyEvent` | `orderEvents()` → `OrderEvent.modified` for one `orderID` | added | see `orderModifyEvent` |
| `Trade.fillEvent` | `executions()` updates for one `orderID` | present | after the commission |
| `Trade.commissionReportEvent` | `executions()` updates for one `orderID` | present | |
| `Trade.filledEvent` | `orders()` updates whose status turns `.filled` | present | |
| `Trade.cancelEvent` | `orderEvents()` → `OrderEvent.cancelRequested` for one `orderID` | added | see `cancelOrderEvent` |
| `Trade.cancelledEvent` | `orders()` updates whose status turns `.cancelled` | present | |
| `Trade.events` | — | n/a | eventkit bookkeeping tuple |
| `Trade.isWaiting`, `isWorking`, `isActive` | `OrderSnapshot.isWaiting`, `OrderSnapshot.isWorking`, `OrderSnapshot.isActive` | added | model helpers through the `OrderStatus` sets |
| `Trade.isDone` | `OrderSnapshot.status.isFinal` | present | |
| `Trade.filled` | `OrderSnapshot.filled` | present | IB's figure; ib_async sums the fills, leaving out BAG legs |
| `Trade.remaining` | `OrderSnapshot.remaining` | present | IB's figure, clamped at 0 |
| `BracketOrder` | `BracketOrder` | present | |
| `OrderCondition` | `OrderCondition` | present | |
| `OrderCondition.createClass` | `OrderCondition` cases | present | the decoder picks the case by condition type |
| `OrderCondition.And`, `Or` | `OrderCondition.Conjunction.and`, `.or` | present | |
| `PriceCondition`, `TimeCondition`, `MarginCondition`, `ExecutionCondition`, `VolumeCondition`, `PercentChangeCondition` | `OrderCondition.price`, `.time`, `.margin`, `.execution`, `.volume`, `.percentChange` | present | |

## util.py

| ib_async | swift-ibkr | Status | Note |
|---|---|---|---|
| `globalErrorEvent` | `states()` → `.disconnected(error)`; thrown errors | present | |
| `EPOCH` | — | n/a | the default of Python dataclass date fields; Swift models have no placeholder dates |
| `UNSET_INTEGER`, `UNSET_DOUBLE` | `nil` (every unset value is an `Optional`, e.g. `Order.limitPrice`) | present | |
| `Time_t` | — | n/a | Python type alias for annotations |
| `df` | — | n/a | pandas |
| `dataclassAsDict`, `dataclassAsTuple`, `dataclassNonDefaults`, `dataclassUpdate`, `dataclassRepr` (and the `dict`/`tuple`/`update`/`nonDefaults` that `__init__` attaches) | — | n/a | dataclass mechanics |
| `isnamedtupleinstance` | — | n/a | Python type introspection |
| `tree` | — | added | synthesised `Encodable` (one-way to JSON, not `Decodable`) on every public model; `TickField` is `CodingKeyRepresentable` |
| `barplot` | — | n/a | plotting |
| `allowCtrlC` | — | n/a | event-loop glue: asyncio's SIGINT handling |
| `logToFile`, `logToConsole` | `IBClient.setLogHandler(_:)`, `IBLogLevel`, `IBLogHandler` | added | the caller's handler gets every line: `.debug` frames `>>>`/`<<<`, `.info` state changes, orders and fills, `.warning` warning codes, `.error` fatal errors; no dependency |
| `isNan` | — | n/a | NaN placeholder test; Swift's unset is `nil` |
| `formatSI` | `ConnectionStats.description` | added | internal `formatSI(_:)` for `Int` and `Double` (util.py:274-299), behind the description; a negative integer keeps its sign, which ib_async drops |
| `timeit` | — | n/a | Python context manager; `ContinuousClock().measure {}` |
| `run`, `schedule`, `sleep` | — | n/a | event-loop glue |
| `timeRange`, `timeRangeAsync` | `IBClient.timeRange(from:to:every:)` | added | `AsyncStream<Date>`: waits for each point and yields it, skipping past ones; stopping the consumer ends it |
| `waitUntil`, `waitUntilAsync` | `IBClient.wait(until:)` | added | `async throws`; returns at once for a past date, throws `CancellationError` on cancel |
| `patchAsyncio`, `getLoop`, `startLoop`, `useQt` | — | n/a | event-loop, Jupyter and Qt glue |
| `formatIBDatetime` | `IBDate.format(_:)` | added | `yyyyMMdd HH:mm:ss UTC` for a `Date`; ib_async's `date` form (23:59:59 local) and string pass-through are not offered |
| `parseIBDatetime` | `IBDate.parse(_:timeZone:)` | added | `yyyyMMdd` (that day's start), epoch seconds, `yyyyMMdd HH:mm:ss Zone`, `yyyyMMdd  HH:mm:ss`, `yyyy-MM-dd HH:mm:ss.0`; `timeZone` (UTC by default) stands where ib_async uses naive local time; `nil` for anything else |

## ibcontroller.py

| ib_async | swift-ibkr | Status | Note |
|---|---|---|---|
| `IBC` | `IBC` | added | actor in `IBKR`, on macOS, Linux and Windows only (an `#if os(…)` guard), starting IB Gateway or TWS through IBC with Foundation `Process` |
| `IBC.IbcLogLevel` | `IBC.logLevel` | added | the `IBLogLevel` (`.debug` by default) at which IBC's stdout lines go to the client's log handler |
| `IBC.twsVersion`, `gateway`, `tradingMode`, `twsPath`, `twsSettingsPath`, `ibcPath`, `ibcIni`, `javaPath`, `userid`, `password`, `fixuserid`, `fixpassword`, `on2fatimeout` | `IBC.twsVersion`, `.gateway`, `.tradingMode`, `.twsPath`, `.twsSettingsPath`, `.ibcPath`, `.ibcIni`, `.javaPath`, `.userID`, `.password`, `.fixUserID`, `.fixPassword`, `.on2FATimeout` | added | each non-empty one a command-line argument of `ibcstart.sh` / `StartIBC.bat` in ib_async's order (ibcontroller.py:129); `twsSettingsPath` bare on Windows, as ib_async; an empty `ibcPath` is `/opt/ibc` or `C:\IBC` |
| `IBC.start`, `startAsync` | `IBC.start(logTo:)` | added | a no-op while running; throws when the script cannot start |
| `IBC.terminate`, `terminateAsync` | `IBC.terminate()` | added | `taskkill /F /T /PID` of the launched child on Windows, SIGTERM to the script elsewhere, killed outright after 5 s; only while it runs; a no-op when not running |
| `IBC.monitorAsync` | `IBC.start(logTo:)` | added | an internal task reads the child's stdout line by line into the client's log handler |
| `IBC.__enter__`, `__exit__` | — | n/a | Python dunders |
| `Watchdog` | `Watchdog` | added | actor `Watchdog(controller:client:host:port:clientID:connectTimeout:options:appStartupTime:appTimeout:retryDelay:probeContract:probeTimeout:)`, on macOS, Linux and Windows only |
| `Watchdog.controller` | `Watchdog.controller` | added | the `IBC` |
| `Watchdog.ib` | `Watchdog.client` | added | an `IBClient` that must be disconnected; `Watchdog` connects it itself |
| `Watchdog.host`, `port`, `clientId`, `connectTimeout` | `Watchdog.host`, `.port`, `.clientID`, `.connectTimeout` | added | passed to `connect` on every round (127.0.0.1, 7497, 1, 2 s) |
| `Watchdog.readonly`, `account`, `raiseSyncErrors` | `Watchdog.options` | added | one `ConnectOptions` (`readOnly`, `account`, `throwsOnSyncError`, R12), passed to every connect |
| `Watchdog.appStartupTime` | `Watchdog.appStartupTime` | added | 30 s: pause after starting the app before connecting |
| `Watchdog.appTimeout` | `Watchdog.appTimeout` | added | 20 s: silence before the probe, on `idleTimeouts(after:)` |
| `Watchdog.retryDelay` | `Watchdog.retryDelay` | added | 2 s: pause after the app is terminated before it is started again; `ReconnectPolicy.delays` only spaces socket reconnects |
| `Watchdog.probeContract` | `Watchdog.probeContract` | added | `nil` (default) probes with `currentTime()`; a contract with ib_async's 30 S / 5 secs / MIDPOINT history request outside RTH, whose first batch must hold a bar (R8; ib_async defaults to EURUSD) |
| `Watchdog.probeTimeout` | `Watchdog.probeTimeout` | added | 4 s: how long either probe may take |
| `Watchdog.startingEvent` | `WatchdogEvent.starting` | added | on `Watchdog.events()`, from `start()` only |
| `Watchdog.startedEvent` | `WatchdogEvent.started` | added | a `Watchdog`-driven connect succeeded |
| `Watchdog.stoppingEvent` | `WatchdogEvent.stopping` | added | from `stop()` |
| `Watchdog.stoppedEvent` | `WatchdogEvent.stopped` | added | after each round's disconnect and `IBC.terminate()` |
| `Watchdog.softTimeoutEvent` | `WatchdogEvent.softTimeout` | added | the probe went out |
| `Watchdog.hardTimeoutEvent` | `WatchdogEvent.hardTimeout` | added | the probe got no answer; the app is restarted (`.disconnected(.timeout)` only reconnects) |
| `Watchdog.events` | — | n/a | eventkit bookkeeping list |
| `Watchdog.start` | `Watchdog.start()` | added | throws `.alreadyConnected` while running or unless the client is disconnected |
| `Watchdog.stop` | `Watchdog.stop()` | added | disconnects, ends the loop and returns once the app is terminated |
| `Watchdog.runAsync` | `Watchdog.start()` | added | the loop: start app, wait, connect, probe on silence, restart on no answer, 100/1100 or a disconnect; every round ends with disconnect, terminate, `.stopped` |

## flexreport.py

| ib_async | swift-ibkr | Status | Note |
|---|---|---|---|
| `FlexError` | `FlexError` | present | |
| `FlexReport` | `FlexReport` | present | |
| `FLEXREPORT_URL` | `FlexReport.defaultURL` | present | |
| `FlexReport(token, queryId)` / `download` | `FlexReport.download(token:queryID:url:…)` | present | |
| `FlexReport(path=)` / `load` | `FlexReport(data:)` | present | |
| `save` | `FlexReport.data` + `Data.write(to:)` | present | |
| `get_url` (`IB_FLEXREPORT_URL`) | `download(…url:)` | present | the caller reads the variable (DECISIONS) |
| `data` | `FlexReport.data` | present | |
| `root` | `FlexReport.elements` | added | public `[FlexElement]` (`name`, `attributes`, `depth`, `text`) in document order; the tree is flattened with depths |
| `topics` | `FlexReport.topics` | present | |
| `extract(topic, parseNumbers)` | `FlexReport.extract(_:)` + `FlexRecord.decimal(_:)` | present | strings with a strict `Decimal` accessor instead of guessing (DECISIONS) |
| `df` | — | n/a | pandas |

## client.py, wrapper.py, connection.py and the package

| ib_async | swift-ibkr | Status | Note |
|---|---|---|---|
| `Client` | `IBClient` | present | |
| `Client.MaxRequests`, `RequestsInterval` | `ConnectOptions.maxRequests`, `ConnectOptions.requestsInterval` | added | 45 per 1 s by default, `maxRequests` 0 turns the throttle off |
| `Client.MinClientVersion`, `MaxClientVersion` | `Handshake.version` | present | pinned to 178 |
| `Client.DISCONNECTED`, `CONNECTING`, `CONNECTED` | `ConnectionState` | present | |
| `Client.events` | — | n/a | eventkit bookkeeping tuple |
| `Client.apiStart`, `apiEnd`, `apiError` | `states()` | present | |
| `Client.throttleStart`, `throttleEnd` | `throttling()` → `AsyncStream<Bool>` | added | the current state first, then `true` when the writer starts waiting on the throttle and `false` when everything queued is written |
| `Client.host`, `port`, `clientId` | `endpoint()` → `(host: String, port: Int, clientID: Int)?` | added | `nil` when disconnected |
| `Client.optCapab` | `ConnectOptions.optionalCapabilities` | added | startApi's capabilities field, `""` by default |
| `Client.connectOptions`, `setConnectOptions` | `ConnectOptions.connectOptions` | added | appended to the handshake's version range after one space (`v100..178 +PACEAPI`) |
| `Client.reset` | `disconnect()` | present | |
| `Client.serverVersion` | `states()` → `.connected(serverVersion:)` | present | |
| `Client.run` | — | n/a | event-loop glue |
| `Client.isConnected`, `isReady` | `states()` | present | |
| `Client.connectionStats` | `connectionStats()` → `ConnectionStats` | added | throws `.notConnected` unless connected; counts both hellos as messages, as ib_async |
| `Client.getReqId` | `reserveOrderID(atLeast:)` | added | takes the next id from the shared sequence, for orders linked by `parentID` before placing; throws `.notConnected` as ib_async raises |
| `Client.updateReqId` | `reserveOrderID(atLeast:)` | added | its `atLeast` raises the sequence to at least that value before taking the id |
| `Client.getAccounts` | `states()` → `.connected(accounts:)` | present | |
| `Client.connect` / `connectAsync` | `connect(host:port:clientID:timeout:reconnect:options:)` | present | the sync runs as `ConnectOptions.fetch` asks; `fetch: StartupFetch.none` gives a bare connection |
| `Client.disconnect` | `disconnect()` | present | |
| `Client.send`, `sendMsg` | `send(_:)` | added | any `IBRequest`, through the throttled queue; answers on `messages()`, no tracker state (a `placeOrder` sent this way skips `orders()`'s local states) |
| `Client.wrapper`, `decoder` | `IBDecoder.decode(_:)`, `messages()` | present | |
| `Client.reqIds` | `nextOrderID()` | present | |
| `Client.reqManagedAccts` | `managedAccounts()` | present | |
| `Client.startApi` | `connect(…)` | present | sent by `connect` |
| `Client.reqPositions`, `cancelPositions` | `positions()`; `disconnect()` | present | sent by the sync unless `ConnectOptions.fetch` leaves out `.positions`; cancelled by a clean `disconnect()` |
| `Client.reqAccountUpdates(subscribe, acctCode)` | `portfolio()`, `accountValues()` | present | unsubscribing is `ConnectOptions.fetch` |
| `Client.reqPositionsMulti`, `cancelPositionsMulti` | `positionsMulti(account:modelCode:)` | present | |
| `Client.reqSoftDollarTiers` | `softDollarTiers()` | present | |
| `Client.reqFamilyCodes` | `familyCodes()` | present | |
| `Client.queryDisplayGroups` | `displayGroups()` | present | |
| `Client.subscribeToGroupEvents`, `unsubscribeFromGroupEvents` | `displayGroupUpdates(_:)` | present | |
| `Client.updateDisplayGroup` | `updateDisplayGroup(_:contractInfo:)` | present | |
| `Client.verifyRequest`, `verifyMessage`, `verifyAndAuthRequest`, `verifyAndAuthMessage` | `verifyRequest(apiName:apiVersion:)`, `verifyMessage(_:)`, `verifyAndAuthRequest(apiName:apiVersion:opaqueISVKey:)`, `verifyAndAuthMessage(_:xyzResponse:)` | present | |
| `Client.setServerLogLevel` | `setServerLogLevel(_:)` | present | |
| every other `Client.req…` / `cancel…` / `placeOrder` / `exerciseOptions` / `requestFA` / `replaceFA` / `calculate…` | the `IB` row of the same request | present | each is the wire half of an `IB` method above |
| `Wrapper` | `IBDecoder` + `IBMessage` + `messages()` | present | every wrapper callback is an `IBMessage` case |
| `RequestError` | `IBClientError.ib(code:text:)` | present | |
| `Connection` | — | n/a | asyncio `Protocol` glue; `IBClient` owns its socket |
| `Event` (eventkit re-export) | — | n/a | event-loop glue; Swift uses `AsyncStream` |
| `__version__`, `__version_info__` | `IBClient.libraryVersion` | added | the podspec's `s.version` (a test keeps them equal); no tuple form |

## Totals

Rows, where one row may carry several names: `present` 218 · `added` 165 · `MISSING` 0 · `n/a` 33.
