# Known gaps after stage 1

What stage 1 (codec and merging, byte fixtures only) leaves open. Stage 2 (socket, `IBClient`, live paper
account) closes or confirms each line; delete a line when it is settled.

## To confirm against a live gateway

- The server answers `v100..178` with exactly 178 (else the pin is wrong).
- placeOrder defaults taken from ib_async: `openClose "O"`, `usePriceMgmtAlgo "0"`; unset numbers sent as `""`
  where IB's own client sends the sentinel text.
- A nil `ExecutionFilter.clientID` is sent as `"0"`: check that `reqExecutions` still returns every client's fills.
- openOrder's `deltaNeutralOrderType` arrives as `""` (if it arrives as `"None"`, every later field misreads).
- Error text may arrive `\uXXXX`-escaped (IB's client unescapes it from server 153): unescape `text` and
  `advancedOrderRejectJson` if so, with a recorded frame as the test.
- Warning codes missing from the error table (e.g. 10349 «TIF set to DAY by preset»): an unlisted code is fatal,
  and before IB acknowledges an order a fatal error marks it inactive.
- Whether a rejected order shows up again in `completedOrders` (its tracker snapshot has permID 0, so it would be
  duplicated).
- Replace the hand-built fixtures with recorded frames (commissionReport with realized P&L, a bracket's three
  openOrders, an execution correction).

## To confirm on a Mac

- `TCPSocket`'s POSIX branch (Darwin) was written on Windows and has never been compiled or run: build and run
  `swift test` on macOS.

## To build in stage 2

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
