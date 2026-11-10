# swift-ibkr Stage 2: Connection and `IBClient` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Swift program can connect to IB Gateway, place / modify / cancel orders and receive whole orders and whole fills (with commission) through one `IBClient` actor; checked on a fake transport in tests and once live on the owner's paper account, whose real frames become fixtures.

**Architecture:** `Client/` adds four pieces on top of stage 1's codec and trackers. `TCPSocket` (Winsock / BSD) behind an internal `Transport` protocol; `Throttle` (≤ 45 messages in a sliding second); `Subscribers` (fan-out of `AsyncStream`s); and `IBClient`, an actor that owns the transport, the frame reader, both trackers and one id counter. One reader task feeds incoming chunks to the actor in order; one writer task drains a FIFO outbox through the throttle, so requests leave in call order.

**Tech Stack:** Swift 6.4.2, SwiftPM tools 6.0 (Swift 6 language mode), Foundation, WinSDK / Darwin, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-09-swift-ibkr-design.md` (sections «Устройство», «Публичный API», «Тесты», «Этапы» item 2).

## Global Constraints

- Repository `C:\Users\viohn\swift-ibkr`, branch `stage-2-client` off `main` (87cb94c). Nothing is pushed to GitHub, and `main` is not moved, without the owner's «да». Build with `swift build`, test with `swift test`.
- No dependencies. `platforms: [.macOS(.v13)]`. Sockets: `#if os(Windows) import WinSDK`, `#elseif canImport(Darwin) import Darwin`, `#else import Glibc`.
- Swift 6 strict concurrency, no warnings in `Sources/`. `@unchecked Sendable` only on a final class whose mutable state sits behind one `NSLock`, with a one-line comment saying so (`Mutex` needs macOS 15).
- Never copy code from the official `ibapi`. Field order is `docs/protocol-178.md`; stage 1's `IBRequest.body()`, `IBDecoder.decode`, `Frame`, `FrameReader`, `Handshake`, `OrderTracker`, `ExecutionTracker` are reused as they are.
- Orders and requests share ONE id counter seeded from `nextValidId` (`docs/DECISIONS.md`). A later `nextValidId` never lowers it.
- Money and quantities are `Decimal`; in tests use `d("…")`.
- Tests use `@testable import IBKR` and the existing helpers `body(_ fields: String...)`, `body(_ fields: [String])`, `d(_:)` and `Fixtures.openOrderFields(…)` / `Fixtures.completedOrderFields(…)`.
- A test that waits on an async event waits at most 2 s and fails instead of hanging.
- Commits: one imperative sentence + reasoning; last line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. `README.md`, `docs/DECISIONS.md` and `docs/KNOWN-GAPS.md` change in the commit whose behaviour they describe. At the end verify the series with `git rebase --exec "swift test > /dev/null" main`.
- Live tests run only with `IBKR_LIVE=1`. A subagent never runs them: the controller runs them on the owner's paper account.

## Decisions taken in this plan (owner can veto)

- `states()`, `messages()`, `orders()`, `executions()` return a fresh stream on every call, so any number of consumers can listen. `states()` yields the current state first.
- `messages()` carries every decoded incoming message, including the ones routed to the trackers. The spec asks for "all that did not go to a request"; a superset loses nothing and needs no filter.
- One timeout covers the whole `connect`: TCP, handshake, readiness and the order / fill sync. The default is 10 s.
- `placeOrder` returns the order id as soon as the frame is queued, not on IB's acknowledgement. The outcome arrives through `orders()`.
- `connect` after a disconnect starts fresh trackers (the client id may differ). Existing stream subscribers stay subscribed. Streams end only when their consumer stops.
- During `connect`, a fatal error with reqId −1 (e.g. 326 "client id already in use") fails `connect` with that code and text. After `connect`, it only goes to `messages()`.
- `Transport` is internal. Consumers get `IBClient()` over TCP; tests inject a fake through an internal init.
- Live tests refuse to place anything unless every managed account starts with `DU` (paper). Recorded frames replace the account id with `DU0000001`.
- Public memberwise initialisers for the stage-1 value types move to stage 5: the TWS adapter's fakes decide which it needs.

## Review Focus

1. A place followed at once by a cancel of the same id must leave in that order, even when the throttle delays them → Task 4 `cancelRightAfterPlaceKeepsOrder`.
2. The gateway refuses the client id or closes the socket during or after connect → `connect` throws a typed error or the state turns `disconnected`, never a hang → Task 3 `connectFailsWithIBError`, `peerCloseReportsDisconnected`.
3. A frame split across TCP reads, or several frames in one read, through the whole client → Task 3 `chunkedFramesAreReassembled`.
4. Order messages arriving during sync, before any `orders()` call, are in the first snapshot → Task 3 `syncedOrdersAreInSnapshot`.
5. A burst of more than 45 requests is throttled, not dropped or reordered → Task 1 `throttleWaitsForTheWindow`, Task 4 `burstIsThrottledNotDropped`.

---

### Task 1: Throttle and Subscribers

**Files:**
- Create: `Sources/IBKR/Client/Throttle.swift`, `Sources/IBKR/Client/Subscribers.swift`
- Test: `Tests/IBKRTests/ThrottleTests.swift`, `Tests/IBKRTests/SubscribersTests.swift`

**Interfaces:**
- Produces:
  - `struct Throttle { init(limit: Int = 45, window: Duration = .seconds(1)); mutating func reserve(at now: ContinuousClock.Instant) -> Duration }`. It reserves the earliest send slot at or after `now` such that no window holds more than `limit` slots, and returns how long to wait (`.zero` when the slot is now).
  - `struct Subscribers<Element: Sendable> { init(); mutating func stream(onTermination: @escaping @Sendable (Int) -> Void) -> AsyncStream<Element>; mutating func remove(_ id: Int); func yield(_ element: Element); var count: Int }`. Streams use `.unbounded` buffering. `onTermination` receives the stream's id so the owner can call `remove`.

- [ ] **Step 1: Write the failing tests**
  - `throttleAllowsTheLimitAtOnce`: with `t = ContinuousClock.now`, 45 `reserve(at: t)` calls all return `.zero`.
  - `throttleWaitsForTheWindow`: with `Throttle(limit: 2, window: .seconds(1))`, these calls return in turn:
    - `reserve(at: t) == .zero`;
    - `reserve(at: t) == .zero`;
    - `reserve(at: t) == .seconds(1)`;
    - `reserve(at: t + .seconds(2)) == .zero`.
  - `throttleSlidesTheWindow`: `limit 2`. `reserve(at: t) == .zero`, `reserve(at: t + .milliseconds(600)) == .zero`, `reserve(at: t + .milliseconds(800)) == .milliseconds(200)`.
  - `subscribersFanOut`: two streams; `yield(1)`, `yield(2)` → each stream's first two elements are `[1, 2]`.
  - `removedSubscriberGetsNothing`: two streams; `remove` the first's id; `yield(1)`; `count == 1`; the second gets `1`.
- [ ] **Step 2: Run** `swift test` — Expected: FAIL (types not defined).
- [ ] **Step 3: Implement** `Throttle` (keeps the reserved instants of the last window; slot = max(now, the `limit`-th most recent slot + window)) and `Subscribers` (dictionary id → continuation, increasing `Int` ids).
- [ ] **Step 4: Run** `swift test` — Expected: all PASS.
- [ ] **Step 5: Commit** «Throttle outgoing messages and fan out streams to many consumers».

### Task 2: Transport and TCPSocket

**Files:**
- Create: `Sources/IBKR/Client/Transport.swift`, `Sources/IBKR/Client/TCPSocket.swift`, `Sources/IBKR/Client/IBClientError.swift`
- Test: `Tests/IBKRTests/TCPSocketTests.swift`

**Interfaces:**
- Produces:
  - `public enum IBClientError: Error, Equatable, Sendable { case notConnected, alreadyConnected, timeout, connectionClosed; case transport(String); case protocolError(IBProtocolError); case encoding(IBEncodingError); case ib(code: Int, text: String) }`
  - `protocol Transport: AnyObject, Sendable { var incoming: AsyncThrowingStream<[UInt8], any Error> { get }; func write(_ bytes: [UInt8]) throws(IBClientError); func close() }`. `incoming` yields chunks as read, finishes when the peer closes, and throws `IBClientError.transport` on a read error. `write` writes every byte or throws. `close` is idempotent and ends `incoming`.
  - `typealias Connector = @Sendable (_ host: String, _ port: Int, _ timeout: Duration) async throws -> any Transport`. It throws `IBClientError` only.
  - `final class TCPSocket: Transport, @unchecked Sendable { static func connect(host: String, port: Int, timeout: Duration) async throws -> TCPSocket }`

- [ ] **Step 1: Write the failing tests**
  - `connectToClosedPortFails`: `TCPSocket.connect(host: "127.0.0.1", port: 1, timeout: .seconds(2))` throws an `IBClientError.transport`, within 2 s.
  - `unknownHostFails`: host `"no-such-host.invalid"` throws `IBClientError.transport`.
- [ ] **Step 2: Run** `swift test` — Expected: FAIL.
- [ ] **Step 3: Implement** `TCPSocket`.
  - **Connect:** `getaddrinfo` (`AF_UNSPEC`, `SOCK_STREAM`), trying each address. Use a non-blocking `connect` plus `select` bounded by `timeout`, then switch back to blocking. Run it on a `Thread`, never on the cooperative pool. Timeout → `.timeout`; failure → `.transport("connect: <OS error code>")`. Set `TCP_NODELAY`.
  - **Windows:** `WSAStartup` once per process (a `static let`).
  - **Reading:** a dedicated `Thread` runs a blocking `recv` loop into a 64 KiB buffer and yields to `incoming`. `0` → finish; an error after `close()` → finish; any other error → throw.
  - **Writing:** `write` loops `send` until every byte is out, under the lock.
  - **Closing:** `close` runs `shutdown`, then `closesocket` / `close`, once.
- [ ] **Step 4: Run** `swift test` — Expected: all PASS. Also run `swift build` — no warnings.
- [ ] **Step 5: Commit** «Connect to the gateway over a plain OS socket on Windows and macOS».

### Task 3: IBClient — connect, state, messages

**Files:**
- Create: `Sources/IBKR/Client/IBClient.swift`, `Tests/IBKRTests/FakeGateway.swift`
- Modify: `README.md` (a usage section), `docs/DECISIONS.md` (this plan's decisions as rows)
- Test: `Tests/IBKRTests/IBClientConnectTests.swift`

**Interfaces:**
- Consumes: Task 1 `Throttle`, `Subscribers`; Task 2 `Transport`, `Connector`, `TCPSocket`, `IBClientError`; stage 1 `Handshake.hello()`, `Handshake.parseServerHello`, `Frame.encode`, `FrameReader`, `IBRequest.body()`, `IBDecoder.decode`, `OrderTracker(clientID:)`, `ExecutionTracker()`.
- Produces:
  - `public enum ConnectionState: Sendable, Equatable { case disconnected(IBClientError?); case connecting; case connected(serverVersion: Int, accounts: [String]) }`
  - `public actor IBClient` with `public init()` (TCP), `init(connector: @escaping Connector)`, and these methods:
    - `public func connect(host: String = "127.0.0.1", port: Int = 4002, clientID: Int, timeout: Duration = .seconds(10)) async throws(IBClientError)`
    - `public func disconnect()`
    - `public func states() -> AsyncStream<ConnectionState>`
    - `public func messages() -> AsyncStream<IBMessage>`
    - internal `func send(_ request: IBRequest) throws(IBClientError)`, which encodes, frames and queues
    - internal `func nextRequestID() -> Int`
  - Test helper `final class FakeGateway: Transport, @unchecked Sendable`:
    - `init(serverVersion: String = "178", nextValidID: Int = 1, accounts: String = "DU1", answersStartAPI: Bool = true)`
    - `var connector: Connector`, which returns `self`
    - `var onRequest: (@Sendable ([String]) -> [[String]])?`, whose replies are fed before the defaults
    - `func feed(_ fields: [String])`
    - `func feedRaw(_ bytes: [UInt8])`
    - `func close()`
    - `func waitForSent(_ count: Int, timeout: Duration = .seconds(2)) async throws -> [[String]]`, the fields of every framed write so far, hello excluded; throws when `timeout` passes first
  - **FakeGateway defaults.** The first write must be the hello, answered by `[serverVersion, "20261110 10:22:12 GMT"]`. Then each framed request is answered by its message id:
    - `71` → `["9","1","\(nextValidID)"]` and `["15","1",accounts]` (unless `answersStartAPI` is false);
    - `16` → `["53","1"]`;
    - `99` → `["102"]`;
    - `7` → `["55","1",<its field 2>]`.

- [ ] **Step 1: Write the failing tests** (all on `FakeGateway`, client id 7)
  - `connectReachesConnectedAfterSync`: `connect` returns. The first element of `states()` is `.connected(serverVersion: 178, accounts: ["DU1"])`. The message ids of `waitForSent(4)` are `["71","16","99","7"]`, and the first frame is `["71","2","7",""]`.
  - `connectRejectsOtherServerVersion`: hello answered `"176"` → throws `.protocolError(.unsupportedServerVersion(176))`; the state is `.disconnected(.protocolError(.unsupportedServerVersion(176)))`.
  - `connectTimesOut`: `answersStartAPI: false`, `timeout: .milliseconds(300)` → throws `.timeout`; the state is `.disconnected(.timeout)`.
  - `connectFailsWithIBError`: `onRequest` answers `71` with `["4","2","-1","326","Unable to connect as the client id is already in use.",""]`, then the test calls `close()` → throws `.ib(code: 326, text: "Unable to connect as the client id is already in use.")`.
  - `connectTwiceThrows`: a second `connect` → `.alreadyConnected`.
  - `peerCloseReportsDisconnected`: after connect, `close()` → `states()` reaches `.disconnected(.connectionClosed)`.
  - `disconnectReportsNoError`: after connect, `disconnect()` → `.disconnected(nil)`. A later `connect` on a fresh `FakeGateway` succeeds.
  - `malformedFrameReachesMessages`: after connect, `feed(["5","x"])` → `messages()` gets a `.malformed(id: 5, …)` and the state stays connected.
  - `chunkedFramesAreReassembled`: after connect, `feedRaw` one byte at a time with `Frame.encode(body("49","1","1700000000"))` + `Frame.encode(body("9","1","50"))` → `messages()` gets `.currentTime(1700000000)` then `.nextValidID(50)`.
  - `oversizedFrameDisconnects`: `feedRaw([0x01,0,0,0])` → `.disconnected(.protocolError(.frameTooLong(16_777_216)))`.
- [ ] **Step 2: Run** `swift test` — Expected: FAIL.
- [ ] **Step 3: Implement** `IBClient`.
  - **Setup.** `connect` refuses unless the state is disconnected (`.alreadyConnected`). It sets `.connecting`, gets a transport from the connector, writes `Handshake.hello()` straight to the transport, and starts the reader task and the writer task.
  - **Reader task.** `for try await chunk in transport.incoming { await self.receive(chunk) }`, then `closed(error)`.
  - **Writer task.** It drains an `AsyncStream<[UInt8]>` outbox: `Throttle.reserve` → `Task.sleep` → `transport.write`. A write error closes the connection.
  - **Frames.** The first frame goes through `parseServerHello`, then `startAPI(clientID:, capabilities: "")` is sent. Every later frame is decoded and handled:
    - `nextValidID` → counter = max(counter, n);
    - `managedAccounts` → accounts;
    - every message → `messages()` subscribers and both trackers (Task 4 publishes their output).
  - **Readiness and sync.** Once both `nextValidID` and `managedAccounts` have arrived, `connect` sends `allOpenOrders`, `completedOrders(apiOnly: false)` and `executions(requestID: nextRequestID(), filter: ExecutionFilter())`. It counts only the end markers that arrive after these are sent (`openOrderEnd`, `completedOrdersEnd`, `execDetailsEnd` with that id). When all three are in, it sets `.connected` and returns.
  - **Failure.** A fatal `error` with reqId −1 before that point fails `connect` with `.ib(code:text:)`. Peer close fails it with `.connectionClosed`, and the timeout with `.timeout`. Every failure closes the transport and sets `.disconnected(error)`.
  - **Disconnect.** `disconnect()` closes the transport, finishes the outbox and sets `.disconnected(nil)`. A close that arrives after that changes nothing.
- [ ] **Step 4: Run** `swift test` — Expected: all PASS, no warnings.
- [ ] **Step 5: Docs.**
  - `README.md` gets a «Use» section: connect, `states()`, `messages()`, and a note that the state is not reconnected automatically.
  - `docs/DECISIONS.md` gets a row for each of this plan's decisions.
- [ ] **Step 6: Commit** «Connect, handshake and sync orders and fills through one IBClient actor».

### Task 4: IBClient — orders and fills

**Files:**
- Modify: `Sources/IBKR/Client/IBClient.swift`, `README.md` (the Use section)
- Test: `Tests/IBKRTests/IBClientOrderTests.swift`

**Interfaces:**
- Consumes: Task 3 `IBClient`, `FakeGateway`, `send`, `nextRequestID`; stage 1 `OrderTracker.sent/apply`, `ExecutionTracker.apply`, `OrderSnapshot`, `Fill`.
- Produces, on `IBClient`:
  - `public func placeOrder(_ contract: Contract, _ order: Order) throws(IBClientError) -> Int`
  - `public func modifyOrder(_ orderID: Int, _ contract: Contract, _ order: Order) throws(IBClientError)`
  - `public func cancelOrder(_ orderID: Int) throws(IBClientError)`
  - `public func orders() -> (snapshot: [OrderSnapshot], updates: AsyncStream<OrderSnapshot>)`
  - `public func executions() -> (snapshot: [Fill], updates: AsyncStream<Fill>)`

- [ ] **Step 1: Write the failing tests** (on `FakeGateway(nextValidID: 100)`, client id 7, after `connect`; `aapl = Contract(symbol: "AAPL")`, `buy = Order(action: .buy, quantity: 1, orderType: "LMT", limitPrice: d("1"))`)
  - `requestsAndOrdersShareOneSequence`: the sync's reqExecutions carries id `100`. `placeOrder` returns `101`, then `102`.
  - `laterNextValidIDNeverLowersTheCounter`: `feed(["9","1","5"])` → the next `placeOrder` returns `101`.
  - `requestBeforeConnectThrows`: on a fresh client, `placeOrder` → `.notConnected`.
  - `placeOrderPublishesWholeOrderOnAck`: subscribe `orders()`; `placeOrder` → 101. `feed` an orderStatus for 101 (`["3","101","Submitted","0","1","0","555","0","0","7","","0"]`) → `updates` yields a snapshot with `orderID 101`, `status .submitted`, `contract.symbol "AAPL"`, `order.limitPrice d("1")`.
  - `cancelRightAfterPlaceKeepsOrder`: `placeOrder` then `cancelOrder(101)` → the last two sent frames start `["3","101",…]` and are followed by exactly `["4","1","101",""]`.
  - `modifyResendsPlaceOrderWithSameID`: `modifyOrder(101, aapl, buy with limitPrice d("2"))` → a second `placeOrder` frame with id `101` and limit field `"2"`.
  - `encodingErrorThrowsAndSendsNothing`: an order with `orderRef "Купить"` → throws `.encoding(.nonASCII(field: "Купить"))`; no new frame is sent.
  - `errorRejectsOwnPendingOrder`: `placeOrder` → 101; `feed(["4","2","101","201","Order rejected",""])` → `orders().snapshot` has 101 with `status .inactive` and `rejectReason "Order rejected"`.
  - `syncedOrdersAreInSnapshot`: `onRequest` answers `16` with `Fixtures.openOrderFields(orderID: 3, permID: 900, clientID: 7, …status: "Submitted")`, ahead of `openOrderEnd` → right after `connect`, `orders().snapshot.count == 1`.
  - `fillPublishedWhenBothHalvesArrive`: subscribe `executions()`. `feed` an execDetails, then its commissionReport (fields per `docs/protocol-178.md`, execId `"0001.01"`) → `updates` yields one `Fill`, with `commission.commission` equal to the fed value.
  - `burstIsThrottledNotDropped`: 50 `cancelOrder(i)` calls for `i` in 1...50 → `waitForSent(50, timeout: .seconds(3))` gets all 50 cancel frames, in order.
- [ ] **Step 2: Run** `swift test` — Expected: FAIL.
- [ ] **Step 3: Implement.**
  - `placeOrder` takes `nextRequestID()`, calls `send(.placeOrder…)` (which throws before queuing on an encoding error), calls `orderTracker.sent(…)` and returns the id.
  - `modifyOrder` does the same with the given id.
  - `cancelOrder` sends `.cancelOrder(orderID:, manualCancelTime: "")`.
  - Incoming messages: every snapshot from `orderTracker.apply` is yielded to the order subscribers, and every fill from `executionTracker.apply` to the fill subscribers.
  - `orders()` and `executions()` read the tracker and register the stream in one actor step.
  - Removal: `onTermination` hops to the actor to `remove`.
- [ ] **Step 4: Run** `swift test` — Expected: all PASS.
- [ ] **Step 5: Docs.** `README.md` «Use»: place / modify / cancel, a bracket (parent `transmit = false`, children `parentID`, last child `transmit = true`), and `orders()` / `executions()`.
- [ ] **Step 6: Commit** «Place, modify and cancel orders and publish whole orders and fills».

### Task 5: Live check on the paper account and frame recording

**Files:**
- Modify: `Sources/IBKR/Client/IBClient.swift` (internal frame tap)
- Create: `Tests/IBKRTests/LiveTests.swift`, `Tests/IBKRTests/Recorded/` (written by the live run)

**Interfaces:**
- Produces:
  - internal `func setFrameTap(_ tap: (@Sendable ([String]) -> Void)?)` on `IBClient`, which receives the fields of every incoming frame after the server hello;
  - recordings `Tests/IBKRTests/Recorded/<test name>.json`, each a JSON array of frames, each frame an array of field strings, with every managed-account id replaced by `DU0000001` inside every field.

- [ ] **Step 1: Write the live tests.**
  - The suite is `.serialized` and `.enabled(if: ProcessInfo.processInfo.environment["IBKR_LIVE"] == "1")`. It runs on `127.0.0.1:4002`, client id `77`.
  - Each test records through the tap and writes its recording (path from `#filePath`) when it ends.
  - **Paper guard:** each test first checks that every account in `.connected` starts with `"DU"`. If one does not, it records an issue and returns before placing anything.
  - `liveConnects`: `serverVersion == 178`, at least one account.
  - `liveLimitOrderPlacesAndCancels`: BUY 1 AAPL (SMART, USD) LMT `1.00` DAY.
    - Within 15 s the order reaches `.preSubmitted` or `.submitted`.
    - `cancelOrder` → within 15 s it reaches `.cancelled`.
  - `liveMarketOrderFillsWithCommission`, also gated on `IBKR_LIVE_FILL == "1"`, for US regular trading hours only.
    - BUY 1 AAPL MKT. Within 30 s the order is `.filled` and a `Fill` with that order's id has a commission.
    - Connect a second client (id `78`): its `executions().snapshot` contains that execId (this confirms that `clientID "0"` in reqExecutions returns every client's fills).
    - Then SELL 1 AAPL MKT, and within 30 s it is `.filled`.
- [ ] **Step 2: Run** `swift test` without `IBKR_LIVE` — Expected: the live tests are skipped and everything else passes.
- [ ] **Step 3: Live run (the controller, not a subagent).** In PowerShell, run `$env:IBKR_LIVE="1"; swift test --filter LiveTests`. Add `$env:IBKR_LIVE_FILL="1"` only during US regular hours (14:30–21:00 UTC).
  - Expected: PASS, and recordings appear in `Tests/IBKRTests/Recorded/`.
  - Read the recordings and settle each «To confirm against a live gateway» line of `docs/KNOWN-GAPS.md`.
- [ ] **Step 4: Fix what the live run breaks.** Each fix gets a failing test built from the recorded frame first. If a fix needs more than the decoder or encoder of one message, stop and report to the owner.
- [ ] **Step 5: Commit** «Check the client live on the paper account and record its frames», with the recordings, any fixes and `docs/KNOWN-GAPS.md` updated (settled lines deleted, findings added).

### Task 6: Replay the recorded frames

**Files:**
- Create: `Tests/IBKRTests/RecordedFrameTests.swift`
- Modify: `README.md` (Status: stage 2 done; how to run the live tests), `docs/KNOWN-GAPS.md` (the fixture line)

**Interfaces:**
- Consumes: Task 5 recordings; stage 1 `IBDecoder`, `OrderTracker`, `ExecutionTracker`.

- [ ] **Step 1: Write the tests** over every `Recorded/*.json` (loaded via `#filePath`):
  - `recordedFramesDecodeWithoutMalformed`: no frame decodes to `.malformed`.
  - `recordedLimitOrderEndsCancelled`: replaying `liveLimitOrderPlacesAndCancels.json` through `OrderTracker(clientID: 77)` leaves an AAPL order with `limitPrice d("1")` and `status .cancelled`.
  - `recordedFillHasCommission`: only if `liveMarketOrderFillsWithCommission.json` exists. Replaying it through `ExecutionTracker` yields at least one fill with `commission.commission > 0`.
- [ ] **Step 2: Run** `swift test` — Expected: all PASS.
- [ ] **Step 3: Docs.**
  - `README.md` Status: stage 2 done, the live command, and the note that `main` is local.
  - `docs/KNOWN-GAPS.md`: the line «Replace the hand-built fixtures with recorded frames» now names what is recorded and what is still hand-built.
- [ ] **Step 4: Commit** «Replay the recorded gateway frames through the decoder and trackers».
