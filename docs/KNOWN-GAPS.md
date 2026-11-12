# Known gaps after stage 7

What stages 1 to 7 (codec and merging; socket, `IBClient`, a live paper run; positions, account summary, P&L; market
data and contract lookups; session requests, the account stream and reconnect; the full order field set, what-if
and exercise) leave open. Delete a line when it
is settled.

## To confirm against a live gateway

The paper runs of 2026-11-10 settled the 178 pin, the placeOrder defaults and openOrder's delta-neutral group
(`docs/protocol-178.md`, Disagreements 9); the gateway did not reject placeOrder's `openClose O` (its openOrder echo
has `""` there, so that shows no more). The pre-market fill run (marketable limits with `outsideRTH`) settled the
fill and its commission, completedOrder's layout (a cancelled order replayed by the sync, with its 4-field
delta-neutral group present), and `ExecutionFilter.clientID` nil sent as `"0"`: client 78 saw client 77's fill. The stage-3 runs of 2026-11-10 settled: positions 0 -> 1 -> 0, with IB's 0 row
for a closed position dropped; the account summary's first set, in GBP; pnlSingle values (all set, none unset);
and the closing SELL's commission with realized P&L. The stage-4 run of 2026-11-11 (paper account, no market-data
subscription) settled contractDetails (AAPL: one entry, conID 265598, minTick 0.01, US/Eastern) and matchingSymbols.
Still open:

- Market data is unchecked live: the paper account has no data subscription, so every request was refused or
  silent. Quotes (with `.delayed` set) got 10197 «No market data during competing live session»; history got 162
  «Trading TWS session is connected from a different IP address»; tick-by-tick got 10189 «... No market data
  permissions for ISLAND STK». All three end the stream with `.noMarketDataPermission`, though no other session was
  open: IB's texts for 10197 and 162 name a cause that was not there. The tick, bar, depth and tick-by-tick
  decoders are checked only against hand-built frames. Rerun `liveMarketData` once there is a subscription.
  Error 420 («Invalid Real-time Query:No market data permissions ...») for `realTimeBars` is typed from ib_async's text and unseen live.
- The depth book uses `ib_async`'s set-at-position model; IB's own sample shifts rows on insert and delete. Check a
  mid-book insert and delete on the first live depth run with a subscription.
- `marketDepth` without depth permissions never yields and never throws: IB sends notice 2152 for the reqId and then
  nothing. A consumer cannot tell that from a quiet book. Decide in stage 8 (from recorded live frames) whether 2152 on a depth request ends the
  stream (its text can list exchanges that do have permissions).

- Whether a rejected order shows up again in `completedOrders` (its tracker snapshot has permID 0, so it would be
  duplicated).
- Recorded (`Tests/IBKRTests/Recorded/`): the handshake and sync, one limit order placed and cancelled, and one
  BUY + SELL of 1 AAPL filled pre-market with the BUY's commission and a completedOrder. Still hand-built: a
  a bracket's three openOrders, an execution correction.
- `accountSummaryEnd` repeats? Whether it repeats after IB's 3-minute updates is unknown: the live test ends
  after the first set.
- IB's price cap is about 1.8% from the market in regular hours. The live fill test uses +-1% and prices the SELL
  off the BUY's fill.
- openOrder gives a plain stock LMT order contract `right` `?` and auxPrice `0.0`; the decoder keeps them as `"?"`
  and `0`, not `""` / nil, so a consumer must not read them as set. The same holds for `None` in
  deltaNeutralOrderType / adjustedOrderType and clearingIntent `IB`: all kept as sent.
- A modify that re-sends an order decoded from a live openOrder (deltaNeutralOrderType `None` with its 8 fields,
  adjustedOrderType `None`) is unchecked live. It also sends displaySize `0` where `ib_async` sends `""` (the
  gateway's `2147483647` decodes to 0).
- Conditions, algos, PEG and combo orders are checked on hand-built frames only: no live order has carried one.
- What-if is unchecked live: `whatIfOrder` and the margin / commission decoding are tested on hand-built frames
  only, so the margin text format of a real answer (and whether IB echoes the order first) is unconfirmed.
- A filled order replayed by completedOrders (the connect-time sync) has `order.totalQuantity` 0: its size is only
  in `filled`. The tracker keeps the 0 and clamps `remaining` at 0; a consumer reads the size from `filled`.
- execDetails `time` comes in two formats: `20261110-11:56:31` (UTC, no zone) on a live fill and
  `20261110 06:56:31 US/Eastern` in the reqExecutions reply. It stays a raw string; a consumer parses both.

## Not covered by CI

CI (`.github/workflows/ci.yml`) builds and tests on macOS, Linux and Windows and builds for iOS. It does not:

- run any test on iOS: the package is only compiled for it, so the socket's Darwin branch is tested on macOS only;
- run the live tests: `IBKR_LIVE` is never set, so nothing in CI talks to a gateway;
- try other Swift versions than 6.0 and the latest image on Linux (Ubuntu, x86_64), 6.4.2 on Windows, and the
  runner's Xcode on macOS (6.3 at the time of writing), or any ARM Linux.

## Sockets

- EINTR from `poll` / `send` / `recv` is treated as a failure, not retried.

## To build later

- A cancel while `TCPSocket.connect` blocks publishes `.disconnected(.cancelled)` at once, but `connect` returns only
  when the socket attempt ends (within its timeout): the blocking connect thread does not see the cancel.
- Subscriber buffers are `.unbounded` (orders, fills, the positions stream and every request stream) on purpose:
  each element counts (a tick, a bar, a trade, a lookup row), so none may be dropped. The one exception is
  `marketDepth`, which keeps only the newest book (`.bufferingNewest(1)`) because every element is a whole book.
- `frameAfterDisconnectIsIgnored` cannot catch a removed generation guard, because FakeGateway closes its stream;
  it needs a mode that stays open after close. The same goes for the generation guard in `IBClient`'s request-stream
  `stopped(...)`, which stops a late consumer-stop from an old connection cancelling a reused reqId.
- `rejectReason` is never cleared once set.
- A fatal error on one of the sync's reqAccountUpdatesMulti ids after `connect` returned goes only to `messages()`:
  `accountValues()` then silently stops updating for that account until the next connect.
- `Frame.encode` does not enforce `Frame.maxLength`; an oversized header after a good frame is seen one `append`
  late.
- Pending execDetails / commission halves that never meet are kept for the client's lifetime (the execution
  tracker survives reconnects).
- Test gaps: the 0xFFFFFF frame boundary; `int()` / `decimal()` of `""`; `bool()`, `double()`, `skip()`; the 2 s close bound of a
  draining disconnect (FakeGateway's write never blocks).
- `exerciseOptions` is unchecked live: the paper account holds no options.
