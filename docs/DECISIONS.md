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
| Error codes: notice — 2100...2199, 10167, 399, 404, 161, 10147, 10148, 165, 1101, 1102; order cancelled — 202; everything else fatal | an explicit table instead of a generic rule: 10167 would kill delayed data, 202 would mark every cancel a rejection | generic rule by code range |
| Connect-time sync sends reqAllOpenOrders, reqCompletedOrders, reqExecutions and waits for their end markers (as `ib_async`) | state is complete before `connect` returns | lazy sync |
| Modify = re-sent placeOrder with the same orderId | that is how the protocol modifies | a separate modify message (none exists) |
| Depth and tick-by-tick without subscriptions count as done when they fail with a typed "no permission" error | those entitlements are absent on most accounts | requiring live data to pass |
| Protocol version pinned to 178 like `ib_async` | one field layout, no protobuf (starts at 201) | version branches, protobuf |
| placeOrder defaults follow `ib_async` (openClose "O", usePriceMgmtAlgo "0") | proven in practice; to be checked live in stage 2 | IB's own client defaults |
| One shared unset set (empty, 2147483647, 9223372036854775807, 1.7976931348623157E308, -9223372036854775808) for every optional reader | IB uses all of them as "no value"; per-reader sets drifted | per-type sentinel lists |
| placeOrder encodes only the base layout; secType BAG, PEG order types and exchange IBKRATS throw `.unsupported` | the table adds combo-leg / PEG / IBKRATS fields the encoder does not emit, which would misalign the bytes | emitting the base layout silently |
| OrderTracker takes the connection's client id at construction; an error matches only `.api(clientID: own, orderID: requestID)` | IB sends order errors only to the owning client, so another client's order with the same id must never be touched | guessing the client from the last `sent`, or taking a lone orderID candidate |
| Orders and requests share ONE id sequence seeded from `nextValidId` (as `ib_async` does) | IB reports both orderId and reqId errors in the same field; stage 2's `IBClient` must never number requests from a separate counter | separate counters: an error on request N would hit order N |
| A fatal error sets an order `.inactive` only while IB has not acknowledged it (status still `.apiPending`); otherwise it records `rejectReason` and leaves the status to IB's orderStatus/openOrder | IB keeps an acknowledged order working when a modification (re-sent placeOrder) is rejected with 110 or 201, or on a warning missing from the table | `.inactive` on every non-final order |
| An `openOrder` never revives a final status | a late or replayed openOrder must not undo Filled/Cancelled | taking the openOrder status as is |
| A fatal error after a final status keeps the status and records `rejectReason` | the final status came from IB; the error is a late reply | overwriting the status |
| A `completedOrder` joined to an existing order updates only status and completedTime | v178 completedOrder lacks parentID etc.; the existing snapshot's contract/order (e.g. bracket parentID) are fuller | replacing contract and order |
| `completedOrder` has no orderId/clientId at 178; it joins by permID. A new snapshot from it takes `filled` from field 82 (filledQuantity) and `remaining = totalQuantity - filledQuantity` | a cancelled order can be part-filled, so status alone says nothing about the fill | Filled implies filled = total |
| A nil `ExecutionFilter.clientID` is sent as "0" (`ib_async` default) | to confirm live in stage 2 | omitting the field |
| `IBClient`'s streams (`states()`, `messages()`, later `orders()`, `executions()`) are fresh on every call; `states()` yields the current state first | any number of consumers can listen, and a late one still learns where the connection stands | one shared stream |
| `messages()` carries every decoded incoming message, including those routed to the trackers | a superset loses nothing and needs no filter | only the messages no request claimed (the spec's wording) |
| One timeout covers the whole `connect` (TCP, handshake, readiness, order / fill sync), 10 s by default | the caller waits for one thing, "ready", and bounds it once | separate timeouts per phase |
| `connect` after a disconnect starts fresh trackers; subscribers stay subscribed; streams end only when their consumer stops; nothing reconnects automatically | the client id may differ between connects; consumers should not have to resubscribe | auto-reconnect; finishing streams on disconnect |
| During `connect`, a fatal error with reqId −1 (e.g. 326 "client id already in use") fails `connect` with `.ib(code:text:)`; after `connect` it only goes to `messages()` | IB refuses a client this way and then closes; reporting the code beats a bare "connection closed" | failing on the close that follows |
| Requests leave through one FIFO writer task that applies the throttle (45 per sliding second) | a cancel can never overtake its order, even when the throttle delays both | a per-call sleep under actor reentrancy, which does not keep call order |
| `Transport` is internal; consumers get `IBClient()` over TCP, tests inject a fake through an internal init | no transport API to support before anyone needs one | a public transport protocol |
| `TCPSocket.close()` only shuts the socket down; the reader thread closes the handle once `recv` returned and no send holds it | closing in `close()` races a reader still inside `recv`, which could then touch a reused handle | closing the handle in `close()` |
| A loopback connect asks for no SYN retransmissions; remote hosts keep the OS default | Windows retries a refused SYN for ~2 s, so a closed 127.0.0.1 port would hang the connect and "localhost" would wait on ::1 before IPv4 | the default retries everywhere |
| 1101 and 1102 (connectivity restored) are notices | IB sends them after a brief gateway-to-IB outage; as fatal they would abort a `connect` that happens to span one | leaving them fatal |
| `placeOrder` returns the id as soon as the frame is queued, not on IB's acknowledgement | the caller needs the id to cancel or correlate; the outcome (ack, rejection) arrives through `orders()` | waiting for IB's openOrder / orderStatus |
| `placeOrder`, `modifyOrder`, `cancelOrder` require the state `.connected` | before `nextValidId` the id counter is 0, and an order sent mid-handshake would take an id IB has not issued | allowing them once the socket is up |
| Public memberwise initialisers for the stage-1 value types move to stage 5 | the TWS adapter's fakes will show which ones are needed | adding them all now |

## Error-code table

| Kind | Codes | Effect |
|---|---|---|
| notice | 2100...2199, 10167, 399, 404, 161, 10147, 10148, 165, 1101, 1102 | informational, never fails a request |
| order cancelled | 202 | the cancel confirmation, not a rejection |
| fatal | everything else | fails the request it belongs to |

A message id that is not a number decodes as malformed with id 0: there is no id to report.
