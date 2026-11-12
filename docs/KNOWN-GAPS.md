# Known gaps after stage 4

What stages 1 to 4 (codec and merging; socket, `IBClient`, a live paper run; positions, account summary, P&L; market
data and contract lookups) leave open. Delete a line when it
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
- The depth book uses `ib_async`'s set-at-position model; IB's own sample shifts rows on insert and delete. Check a
  mid-book insert and delete on the first live depth run with a subscription.
- `marketDepth` without depth permissions never yields and never throws: IB sends notice 2152 for the reqId and then
  nothing. A consumer cannot tell that from a quiet book. Decide in stage 5 whether 2152 on a depth request ends the
  stream (its text can list exchanges that do have permissions).

- Error text may arrive `\uXXXX`-escaped (IB's client unescapes it from server 153): unescape `text` and
  `advancedOrderRejectJson` if so, with a recorded frame as the test. None of the six recorded errors was escaped.
- Warning codes missing from the error table (e.g. 10349 «TIF set to DAY by preset»): an unlisted code is fatal,
  and before IB acknowledges an order a fatal error marks it inactive. The live run sent 2104, 2107, 2158 and 399
  («will not be placed until the open»), all already notices, and 202 on cancel. The stage-4 run added 2119 («farm is connecting») and 2152, both notices.
- Whether a rejected order shows up again in `completedOrders` (its tracker snapshot has permID 0, so it would be
  duplicated).
- Recorded (`Tests/IBKRTests/Recorded/`): the handshake and sync, one limit order placed and cancelled, and one
  BUY + SELL of 1 AAPL filled pre-market with the BUY's commission and a completedOrder. Still hand-built: a
  a bracket's three openOrders, an execution correction.
- `accountSummaryEnd` repeats? Whether it repeats after IB's 3-minute updates is unknown: the live test ends
  after the first set.
- A 202 can carry a refusal. IB's price cap cancels an over-aggressive limit with code 202 and the reason in the
  text («We cannot accept an order at a limit price at or more aggressive than ...»). The tracker marks the order
  `.cancelled` and drops the text, so a consumer cannot tell a refusal from a user cancel. Fix later: keep a 202's
  text as the snapshot's reason.
- A `Filled` snapshot can come with `filled` 0. The gateway sends openOrder with status Filled before the
  orderStatus that carries filled / avgFillPrice, so `orders()` first publishes `.filled` with `filled` 0 and
  `averageFillPrice` 0, then the full one (seen live: orders 9, 15, 17). A consumer must read fill numbers from the
  orderStatus-backed update, or the tracker should keep the status until orderStatus arrives. Decide in stage 5.
- IB's price cap is about 1.8% from the market in regular hours. The live fill test uses +-1% and prices the SELL
  off the BUY's fill.
- openOrder gives a plain stock LMT order contract `right` `?` and auxPrice `0.0`; the decoder keeps them as `"?"`
  and `0`, not `""` / nil, so a consumer must not read them as set.
- A filled order replayed by completedOrders (the connect-time sync) has `order.totalQuantity` 0: its size is only
  in `filled`. The tracker keeps the 0 and clamps `remaining` at 0; a consumer reads the size from `filled`.
- execDetails `time` comes in two formats: `20261110-11:56:31` (UTC, no zone) on a live fill and
  `20261110 06:56:31 US/Eastern` in the reqExecutions reply. It stays a raw string; a consumer parses both.

## To confirm on a Mac

- `TCPSocket`'s POSIX branch (Darwin) was written on Windows and has never been compiled or run: build and run
  `swift test` on macOS (the Mac build of the Darwin branch is unverified).
- EINTR from `poll` / `send` / `recv` is treated as a failure, not retried.

## To build later

- `connect` ignores the caller's task cancellation and runs until its deadline.
- `placeOrder` then an immediate `disconnect()` can drop the queued frame, and the order stays `.apiPending` in
  the stale snapshot.
- Subscriber buffers are `.unbounded` (orders, fills, the positions stream and every request stream) on purpose:
  each element counts (a tick, a bar, a trade, a lookup row), so none may be dropped. The one exception is
  `marketDepth`, which keeps only the newest book (`.bufferingNewest(1)`) because every element is a whole book.
- `frameAfterDisconnectIsIgnored` cannot catch a removed generation guard, because FakeGateway closes its stream;
  it needs a mode that stays open after close. The same goes for the generation guard in `IBClient`'s request-stream
  `stopped(...)`, which stops a late consumer-stop from an old connection cancelling a reused reqId.
- completedOrder's `parentPermId` is skipped: after an app restart a fresh tracker loses bracket links of
  completed orders.
- `rejectReason` is never cleared once set.
- `Frame.encode` does not enforce `Frame.maxLength`; an oversized header after a good frame is seen one `append`
  late.
- Pending execDetails / commission halves that never meet are kept for the client's lifetime (the execution
  tracker survives reconnects).
- Test gaps: the 0xFFFFFF frame boundary; `int()` / `decimal()` of `""`; `bool()`, `double()`, `skip()`; a contract
  with non-default fields in placeOrder; an unknown action or condition type in openOrder.
