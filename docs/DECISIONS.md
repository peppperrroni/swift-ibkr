# Decisions

| Decision | Why | Rejected |
|---|---|---|
| `orderType` and `tif` stay IB's strings; `action` is an enum (BUY / SELL / SSHORT) | IB's order types and TIFs are a long, growing list; actions are closed | enums for orderType/tif |
| Order status is an open set (`struct OrderStatus: RawRepresentable`), unknown statuses are kept | IB adds statuses; dropping one loses state | closed enum |
| Outgoing text outside 0x20...0x7E throws `IBEncodingError.nonASCII(field:)` | IB's own client refuses it (error 579); Russian preset names cannot go into orderRef as is | silently transliterating or sending UTF-8 |
| Execution and order times stay IB's raw strings in stage 1 | formats vary by account and message | parsing into `Date` |
| Fills join by execId in either order; a correction (execId minus its last segment, higher suffix) replaces the fill in place; a lower or resent superseded execId is dropped; unmatched halves are kept for the session | an execution and its commission arrive as separate messages, in either order, and IB resends and corrects them | evicting unmatched halves: a day's volume is small |
| A fill is published only when execDetails and commissionReport are both present; correction key = execId without its last `.`-segment | commission arrives separately; corrections reuse the execId prefix | publishing fills without commission |
| Trackers publish only real changes; an identical repeat publishes nothing | IB repeats messages | publishing every message |
| Error codes: notice — 2100...2199, 10167, 399, 404, 161, 10147, 10148, 165; order cancelled — 202; everything else fatal | an explicit table instead of a generic rule: 10167 would kill delayed data, 202 would mark every cancel a rejection | generic rule by code range |
| Connect-time sync sends reqAllOpenOrders, reqCompletedOrders, reqExecutions and waits for their end markers (as `ib_async`) | state is complete before `connect` returns | lazy sync |
| Modify = re-sent placeOrder with the same orderId | that is how the protocol modifies | a separate modify message (none exists) |
| Depth and tick-by-tick without subscriptions count as done when they fail with a typed "no permission" error | those entitlements are absent on most accounts | requiring live data to pass |
| Protocol version pinned to 178 like `ib_async` | one field layout, no protobuf (starts at 201) | version branches, protobuf |
| placeOrder defaults follow `ib_async` (openClose "O", usePriceMgmtAlgo "0") | proven in practice; to be checked live in stage 2 | IB's own client defaults |
| One shared unset set (empty, 2147483647, 9223372036854775807, 1.7976931348623157E308, -9223372036854775808) for every optional reader | IB uses all of them as "no value"; per-reader sets drifted | per-type sentinel lists |
| placeOrder encodes only the base layout; secType BAG, PEG order types and exchange IBKRATS throw `.unsupported` | the table adds combo-leg / PEG / IBKRATS fields the encoder does not emit, which would misalign the bytes | emitting the base layout silently |
| OrderTracker takes the connection's client id at construction; an error matches only `.api(clientID: own, orderID: requestID)` | IB sends order errors only to the owning client, so another client's order with the same id must never be touched | guessing the client from the last `sent`, or taking a lone orderID candidate |

## Error-code table

| Kind | Codes | Effect |
|---|---|---|
| notice | 2100...2199, 10167, 399, 404, 161, 10147, 10148, 165 | informational, never fails a request |
| order cancelled | 202 | the cancel confirmation, not a rejection |
| fatal | everything else | fails the request it belongs to |

A message id that is not a number decodes as malformed with id 0: there is no id to report.
