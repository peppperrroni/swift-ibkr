# Known gaps after stage 3

What stages 1 and 2 (codec and merging; socket, `IBClient`, a live paper run) leave open. Delete a line when it
is settled.

## To confirm against a live gateway

The paper runs of 2026-11-10 settled the 178 pin, the placeOrder defaults and openOrder's delta-neutral group
(`docs/protocol-178.md`, Disagreements 9); the gateway did not reject placeOrder's `openClose O` (its openOrder echo
has `""` there, so that shows no more). The pre-market fill run (marketable limits with `outsideRTH`) settled the
fill and its commission, completedOrder's layout (a cancelled order replayed by the sync, with its 4-field
delta-neutral group present), and `ExecutionFilter.clientID` nil sent as `"0"`: client 78 saw client 77's fill. The stage-3 runs of 2026-11-10 settled: positions 0 -> 1 -> 0, with IB's 0 row
for a closed position dropped; the account summary's first set, in GBP; pnlSingle values (all set, none unset);
and the closing SELL's commission with realized P&L.
Still open:

- Error text may arrive `\uXXXX`-escaped (IB's client unescapes it from server 153): unescape `text` and
  `advancedOrderRejectJson` if so, with a recorded frame as the test. None of the six recorded errors was escaped.
- Warning codes missing from the error table (e.g. 10349 «TIF set to DAY by preset»): an unlisted code is fatal,
  and before IB acknowledges an order a fatal error marks it inactive. The live run sent 2104, 2107, 2158 and 399
  («will not be placed until the open»), all already notices, and 202 on cancel.
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
- Subscriber buffers are `.unbounded` (orders, fills, the positions stream and the account-summary / P&L request
  streams): fine for these volumes, revisit before stage 4 market data.
- `frameAfterDisconnectIsIgnored` cannot catch a removed generation guard, because FakeGateway closes its stream;
  it needs a mode that stays open after close. The same goes for the generation guard in `IBClient`'s request-stream
  `stopped(...)`, which stops a late consumer-stop from an old connection cancelling a reused reqId.
- Public memberwise initialisers for the public value types, so consumers (the TWS adapter) can build test values;
  `OrderKey` is public but used by no public API.
- completedOrder's `parentPermId` is skipped: after an app restart a fresh tracker loses bracket links of
  completed orders.
- `rejectReason` is never cleared once set.
- `Frame.encode` does not enforce `Frame.maxLength`; an oversized header after a good frame is seen one `append`
  late.
- Pending execDetails / commission halves that never meet are kept for the client's lifetime (the execution
  tracker survives reconnects).
- Test gaps: the 0xFFFFFF frame boundary; `int()` / `decimal()` of `""`; `bool()`, `double()`, `skip()`; a contract
  with non-default fields in placeOrder; an unknown action or condition type in openOrder.
