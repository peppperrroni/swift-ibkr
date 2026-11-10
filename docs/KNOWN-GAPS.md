# Known gaps after stage 2

What stages 1 and 2 (codec and merging; socket, `IBClient`, a live paper run) leave open. Delete a line when it
is settled.

## To confirm against a live gateway

The paper run of 2026-11-10 (no fill: outside US hours) settled the 178 pin, the placeOrder defaults and
openOrder's delta-neutral group (`docs/protocol-178.md`, Disagreements 9); the gateway did not reject
placeOrder's `openClose O` (its openOrder echo has `""` there, so that shows no more). Still open:

- The fill test (`liveMarketOrderFillsWithCommission`) still has to be run during US regular hours
  (14:30-21:00 UTC); it settles the commission and reqExecutions-clientID lines below, and
  `recordedFillHasCommission` replays its recording.
- A nil `ExecutionFilter.clientID` is sent as `"0"`: check that `reqExecutions` still returns every client's fills
  (`liveMarketOrderFillsWithCommission`, US regular hours only).
- Error text may arrive `\uXXXX`-escaped (IB's client unescapes it from server 153): unescape `text` and
  `advancedOrderRejectJson` if so, with a recorded frame as the test. None of the six recorded errors was escaped.
- Warning codes missing from the error table (e.g. 10349 «TIF set to DAY by preset»): an unlisted code is fatal,
  and before IB acknowledges an order a fatal error marks it inactive. The live run sent 2104, 2107, 2158 and 399
  («will not be placed until the open»), all already notices, and 202 on cancel.
- Whether a rejected order shows up again in `completedOrders` (its tracker snapshot has permID 0, so it would be
  duplicated).
- Recorded (`Tests/IBKRTests/Recorded/`): the handshake and sync, and one limit order placed and cancelled
  (openOrder, orderStatus, errors). Still hand-built: commissionReport with realized P&L, a bracket's three
  openOrders, an execution correction, a completedOrder (its 4-field delta-neutral group is expected present, as
  openOrder's 8 are), and every fill.
- openOrder gives a plain stock LMT order contract `right` `?` and auxPrice `0.0`; the decoder keeps them as `"?"`
  and `0`, not `""` / nil, so a consumer must not read them as set.

## To confirm on a Mac

- `TCPSocket`'s POSIX branch (Darwin) was written on Windows and has never been compiled or run: build and run
  `swift test` on macOS (the Mac build of the Darwin branch is unverified).

## To build later

- Orders and requests share one id sequence from `nextValidId` (see `docs/DECISIONS.md`).
- Public memberwise initialisers for the public value types, so consumers (the TWS adapter) can build test values;
  `OrderKey` is public but used by no public API.
- completedOrder's `parentPermId` is skipped: after an app restart a fresh tracker loses bracket links of
  completed orders.
- `rejectReason` is never cleared once set.
- `Frame.encode` does not enforce `Frame.maxLength`; an oversized header after a good frame is seen one `append`
  late.
- Pending execDetails / commission halves that never meet are kept for the session.
- Test gaps: the 0xFFFFFF frame boundary; `int()` / `decimal()` of `""`; `bool()`, `double()`, `skip()`; a contract
  with non-default fields in placeOrder; an unknown action or condition type in openOrder.
