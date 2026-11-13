# Known gaps after stage 14

What stages 1 to 14 (codec and merging; socket, `IBClient`, a live paper run; positions, account summary, P&L; market
data and contract lookups; session requests, the account stream and reconnect; the full order field set, what-if
and exercise; market data and history in full; options, reference data, scanner, news and research; Flex reports;
the 1.0 release; parity with `ib_async` 2.1.0) leave open. Every line under «To confirm against a live gateway»
needs something CI does not have and says which: a live gateway (a paper IB Gateway or TWS login), a market-data
subscription, a Flex token, or an IBC install. «Not covered by CI» and «Owner steps» are standing facts about CI and
the owner's accounts, not open checks. Delete a line when it is settled.

## To confirm against a live gateway

The paper runs of 2026-11-10 settled the 178 pin, the placeOrder defaults and openOrder's delta-neutral group
(`docs/protocol-178.md`, Disagreements 9); the gateway did not reject placeOrder's `openClose O` (its openOrder echo
has `""` there, so that shows no more). The pre-market fill run (marketable limits with `outsideRTH`) settled the
fill and its commission, completedOrder's layout (a cancelled order replayed by the sync, with its 4-field
delta-neutral group present), and `ExecutionFilter.clientID` nil sent as `"0"`: client 78 saw client 77's fill. The
stage-3 runs of 2026-11-10 settled: positions 0 -> 1 -> 0, with IB's 0 row for a closed position dropped; the
account summary's first set, in GBP; pnlSingle values (all set, none unset); and the closing SELL's commission with
realized P&L. The stage-4 run of 2026-11-11 (paper account, no market-data subscription) settled contractDetails
(AAPL: one entry, conID 265598, minTick 0.01, US/Eastern) and matchingSymbols. Still open:

- **Live gateway.** The end-of-stage-13 live run did not happen: no paper IB Gateway was listening on
  127.0.0.1:4002. Rerun `LiveTests` (connect and sync, a limit order placed and cancelled, the account summary, the
  contract lookups, the market data refusals); it is the first live sight of every call README's Status marks «not
  yet run live».
- **Market-data subscription.** Market data is unchecked live: the paper account has no data subscription, so every
  request was refused or silent. Quotes (with `.delayed` set) got 10197 «No market data during competing live
  session»; history got 162 «Trading TWS session is connected from a different IP address»; tick-by-tick got 10189
  «... No market data permissions for ISLAND STK». All three end the stream with `.noMarketDataPermission`, though no
  other session was open: IB's texts for 10197 and 162 name a cause that was not there. The tick, bar, depth and
  tick-by-tick decoders, and every stage 8–9 call (`tickers`, `realTimeBars`, `depthExchanges`, `smartComponents`,
  `historicalTicks`, `headTimeStamp`, `histogramData`, `historicalSchedule`), are cross-checked against ib_async 2.1.0
  (decode and encode), unseen live. Rerun `liveMarketData` once there is a subscription. Error 420 («Invalid Real-time Query:No market data
  permissions ...») for `realTimeBars` is typed from ib_async's text and unseen live.
- **Market-data subscription.** The `TickAttrib` bits of tickPrice (canAutoExecute, pastLimit, preOpen as bits 0, 1,
  2, from IB's API documentation: `ib_async` drops the mask, so the oracle cannot check it) and the two
  `TickAttribBidAsk` layouts (protocol-178, Disagreements) are unseen live.
- **Market-data subscription.** IB's 10225 (bust event), on which `realTimeBars`, `liveHistoricalBars` and
  `historicalBars(keepUpToDate: true)` resend their request under the same reqId, has never been received.
- **Market-data subscription.** The depth book uses `ib_async`'s set-at-position model; IB's own sample shifts rows
  on insert and delete. Check a mid-book insert and delete on the first live depth run.
- **Market-data subscription.** `marketDepth` ends on a 2152 whose granted part names no `Depth:` exchange
  (docs/DECISIONS.md, the `marketDepth` 2152 row). The recorded grant is `Top: IBEOS; OVERNIGHT`, venues closed in
  regular hours, so both cases are unseen live: a 2152 that grants `Depth:` on some exchanges keeps the book open;
  one that grants `Top:` only on regular venues ends it.
- **Live gateway; subscriptions for fundamentals, WSH and news; TWS for display groups.** Stages 10–11 are cross-checked
  against ib_async 2.1.0 and run on the fake gateway, unseen live. Check on the first live run: WSH meta request handling (the
  meta request stays open until the next `wshMetaData()`, and IB may refuse event data otherwise), an IB error on
  `updateDisplayGroup` ending the stream with `.ib` and no 70, bond details (18), and the news date format
  (`historicalNews` sends `yyyyMMdd HH:mm:ss UTC`).
- **Live gateway.** The verify requests go out after startApi, which `connect` sends itself; IB documents them
  before it.
- **Live gateway.** A scan with no results: the client reads IB's 165 on a scanner reqId as an empty scan (`[]`), as
  `ib_async` does; the live text and timing are unrecorded.
- **Live gateway, with an option position.** `exerciseOptions` is unchecked live: the paper account holds no
  options.
- **Live gateway.** Whether a rejected order shows up again in `completedOrders` (its tracker snapshot has permID 0,
  so it would be duplicated).
- **Live gateway.** Recorded (`Tests/IBKRTests/Recorded/`): the handshake and sync, one limit order placed and
  cancelled, and one BUY + SELL of 1 AAPL filled pre-market with the BUY's commission and a completedOrder. Still
  hand-built: a bracket's three openOrders, an execution correction.
- **Live gateway.** Whether `accountSummaryEnd` repeats after IB's 3-minute updates: the live test ends after the
  first set.
- **Live gateway.** IB's price cap is about 1.8% from the market in regular hours. The live fill test uses +-1% and
  prices the SELL off the BUY's fill.
- **Live gateway.** A modify that re-sends an order decoded from a live openOrder (deltaNeutralOrderType `None` with
  its 8 fields, adjustedOrderType `None`) is unchecked live; it is cross-checked against ib_async 2.1.0, which sends
  the same values except displaySize: swift-ibkr sends `0` where `ib_async` sends `""` (the gateway's `2147483647`
  decodes to 0; protocol-178 Disagreements 15).
- **Live gateway.** Conditions, algos, PEG and combo orders are cross-checked against ib_async 2.1.0 both ways,
  unseen live: no live order has carried one.
- **Live gateway.** What-if is unchecked live: `whatIfOrder` is tested on hand-built frames only; the request and the
  margin / commission decoding are cross-checked against ib_async 2.1.0, unseen live, so the margin text format of a
  real answer (and whether IB echoes the order first) is unconfirmed.
- **Live gateway.** The local `.validationError` is checked on hand-built frames only: no live order has drawn a
  warning (105, 321, 329, 434, 492), so IB's status messages after one are unrecorded.
- **Live gateway, logged in another zone.** execDetails `time` comes in two formats: `20261110-11:56:31` (UTC, no
  zone) on a live fill and `20261110 06:56:31 US/Eastern` in the reqExecutions reply. `Execution.date` reads both;
  the live format's UTC is evidence from one recording, so a gateway whose login zone differs needs
  `ConnectOptions.gatewayTimeZone` (unverified).
- **Live gateway; TWS for the auto-bind; an advisor login for the sub-accounts.** `ConnectOptions` is checked on the
  fake gateway only: the read-only API mode (`readOnly`), `+PACEAPI` in `connectOptions`, a non-empty
  `optionalCapabilities`, client 0's auto-bind with TWS's manual orders, and more than 50 sub-accounts
  (`maxSyncedSubAccounts`) have not been seen live.
- **Flex token.** `IBKRFlex` has never run against IB's Flex Web Service: the v3 «in progress» answer (`ErrorCode`
  1019) is taken from IB's documentation, not recorded, and `urlSession`'s non-2xx path is never exercised (the live
  test checks only success).
- **IBC install.** `IBC` and `Watchdog` never ran against one: the tests drive the loop with a fake launcher and the
  fake gateway, and run the real launcher only on a stand-in script (`/bin/sh` or a `.bat`). IBC's real stdout, a
  Gateway's startup time against `appStartupTime`, the history probe's answer from a real app and `taskkill /T` on
  IBC's Java child are unconfirmed. A password with `cmd.exe` metacharacters (`&`, `^`, `%`) may not survive
  `StartIBC.bat`'s command line; IBC's `config.ini` avoids it. On macOS and Linux `terminate()` signals only the
  launched script, as `ib_async` does: if `ibcstart.sh` dies without taking its Java child along, the Gateway can
  outlive it, keep the API port, and keep the stdout reader thread waiting.

## Not covered by CI

CI (`.github/workflows/ci.yml`) builds and tests on macOS, Linux and Windows and builds for iOS. It does not:

- run any test on iOS: the package is only compiled for it, so the socket's Darwin branch is tested on macOS only;
- run the live tests: `IBKR_LIVE`, `IBKR_FLEX_TOKEN` and `IBKR_FLEX_QUERY` are never set, so nothing in CI talks to a
  gateway or to IB's Flex Web Service;
- try other Swift versions than 6.0 and the latest image on Linux (Ubuntu, x86_64), 6.4.2 on Windows, and the
  runner's Xcode on macOS (6.3 at the time of writing), or any ARM Linux;
- build the DocC docs anywhere but macOS, or build `Examples/IBKRExample` on Windows.

## Owner steps

These need the owner's accounts:

- `pod trunk push SwiftIBKR.podspec` from the 1.0.0 tag (needs a CocoaPods trunk registration; trunk is announced
  to turn read-only on 2 December 2026, after which the pod installs from the git tag only).
- Submit the package to the Swift Package Index (a pull request to its package list); `.spi.yml` is ready.
- Live checks: market data once there is a subscription, `IBKRFlex` with a real token, `IBC` and `Watchdog` with an
  IBC install.
