import Foundation
public enum ConnectionState: Sendable, Equatable {
    case disconnected(IBClientError?)
    case connecting
    case connected(serverVersion: Int, accounts: [String])
}

/// One connection to IB Gateway. Incoming chunks reach the actor in order through one reader task; requests
/// leave in call order through one throttled writer task. A lost connection is not reconnected automatically.
public actor IBClient {
    private let connector: Connector
    private var state: ConnectionState = .disconnected(nil)
    private var stateSubscribers = Subscribers<ConnectionState>()
    private var messageSubscribers = Subscribers<IBMessage>()
    private var orderSubscribers = Subscribers<OrderSnapshot>()
    private var fillSubscribers = Subscribers<Fill>()
    private var positionSubscribers = Subscribers<[Position]>()
    private var portfolioSubscribers = Subscribers<[PortfolioItem]>()
    private var accountValueSubscribers = Subscribers<AccountValue>()

    /// A per-request stream, by reqId: `route` gets what IB sends for it, `finish` ends it, `cancel` is sent
    /// when the consumer stops it (`nil`: nothing to send). `route` returns true when it finished the stream
    /// itself, and the entry is then removed. Every entry belongs to the current connection; `end()` clears them all.
    private struct RequestStream {
        let route: (IBMessage) -> Bool
        let finish: (IBClientError) -> Void
        let cancel: IBRequest?
    }
    private var requestStreams: [Int: RequestStream] = [:]
    private var localID = -1

    // The current connection. `generation` changes whenever one starts or ends, so a late event from an old
    // connection's reader, writer or timer is dropped.
    private var generation = 0
    private var transport: (any Transport)?
    private var outbox: AsyncStream<[UInt8]>.Continuation?
    private var frames = FrameReader()
    private var clientID = 0
    private var serverVersion: Int?
    private var accounts: [String]?
    private var nextID: Int?
    private var orderTracker = OrderTracker(clientID: 0)
    private var executionTracker = ExecutionTracker()
    private var positionTracker = PositionTracker()
    private var accountTracker = AccountTracker()
    private var accountSyncIDs: Set<Int> = []   // the sync's reqAccountUpdatesMulti ids; only these feed accountTracker
    private var frameTap: (@Sendable ([String]) -> Void)?

    // While `connect` waits: its continuation, its deadline timer, and the sync's end markers still due
    // (nil until the sync requests are sent).
    private var pendingConnect: CheckedContinuation<Result<Void, IBClientError>, Never>?
    private var connectTimer: Task<Void, Never>?
    private var syncEnds: [IBMessage]?

    public init() {
        self.init(connector: { host, port, timeout in
            try await TCPSocket.connect(host: host, port: port, timeout: timeout)
        })
    }

    init(connector: @escaping Connector) { self.connector = connector }

    /// Returns once the handshake is done and open orders, completed orders, executions, positions, the portfolio
    /// and the account values are synced.
    /// `timeout` covers all of it. Cancelling the calling task stops it with `.cancelled`.
    public func connect(host: String = "127.0.0.1", port: Int = 4002, clientID: Int,
                        timeout: Duration = .seconds(10)) async throws(IBClientError) {
        guard case .disconnected = state else { throw .alreadyConnected }
        let deadline = ContinuousClock.now + timeout
        generation += 1
        let gen = generation
        self.clientID = clientID
        frames = FrameReader()
        (serverVersion, accounts, nextID, syncEnds, accountSyncIDs) = (nil, nil, nil, nil, [])
        orderTracker = OrderTracker(clientID: clientID)   // fills are kept: the sync's replay of them publishes nothing
        positionTracker.reload()   // the set is kept too, and replaced whole at the sync's positionEnd
        setState(.connecting)

        try await withTaskCancellationHandler { () async -> Result<Void, IBClientError> in
            let t: any Transport
            do {
                t = try await connector(host, port, timeout)
            } catch {
                let e = Task.isCancelled || error is CancellationError
                    ? .cancelled : error as? IBClientError ?? .transport("\(error)")
                if gen == generation { end(e) }
                return .failure(e)
            }
            guard gen == generation else {   // disconnect() or a cancel came first
                t.close()
                return .failure(Task.isCancelled ? .cancelled : .connectionClosed)
            }
            return await withCheckedContinuation { continuation in
                pendingConnect = continuation
                start(t, gen, deadline)
            }
        } onCancel: {
            Task { await self.cancelConnect(gen) }
        }.get()
    }

    private func cancelConnect(_ gen: Int) {
        if gen == generation, state == .connecting { end(.cancelled) }   // `.connecting`: a late cancel keeps a done connect
    }

    /// Reports `.disconnected(nil)` and ends the request streams at once. From `.connected` it first queues
    /// cancelPositions and lets the queue drain: the writer closes after the last frame, or 2 s later at the
    /// latest. From `.connecting` it closes at once. Does nothing when already disconnected.
    public func disconnect() {
        switch state {
        case .disconnected: return
        case .connecting: end(nil)
        case .connected: end(nil, draining: true)
        }
    }

    /// A fresh stream on every call; the current state comes first.
    public func states() -> AsyncStream<ConnectionState> {
        stateSubscribers.stream(first: state) { [weak self] id in Task { await self?.unsubscribe(state: id) } }
    }

    /// A fresh stream on every call, of every decoded incoming message from now on.
    public func messages() -> AsyncStream<IBMessage> {
        messageSubscribers.stream { [weak self] id in Task { await self?.unsubscribe(message: id) } }
    }

    /// Queues the order and returns its id at once; IB's answer arrives through `orders()`. Throws
    /// `.notConnected` unless the state is `.connected`, and `.encoding` when the order does not encode.
    public func placeOrder(_ contract: Contract, _ order: Order) throws(IBClientError) -> Int {
        try requireConnected()
        let id = nextRequestID()
        try submit(id, contract, order)
        return id
    }

    /// Re-sends the order under its id; IB treats that as a modification.
    public func modifyOrder(_ orderID: Int, _ contract: Contract, _ order: Order) throws(IBClientError) {
        try requireConnected()
        try submit(orderID, contract, order)
    }

    public func cancelOrder(_ orderID: Int) throws(IBClientError) {
        try requireConnected()
        try send(.cancelOrder(orderID: orderID, manualCancelTime: ""))
    }

    /// The orders known now, then every change from now on, as whole snapshots.
    public func orders() -> (snapshot: [OrderSnapshot], updates: AsyncStream<OrderSnapshot>) {
        (orderTracker.orders, orderSubscribers.stream { [weak self] id in Task { await self?.unsubscribe(order: id) } })
    }

    /// The fills known now, then every new or corrected fill from now on.
    public func executions() -> (snapshot: [Fill], updates: AsyncStream<Fill>) {
        (executionTracker.fills, fillSubscribers.stream { [weak self] id in Task { await self?.unsubscribe(fill: id) } })
    }

    /// The positions known now, then every whole new set from now on. Always on: `connect` requests them and
    /// they stream for the whole connection.
    public func positions() -> (snapshot: [Position], updates: AsyncStream<[Position]>) {
        (positionTracker.positions, positionSubscribers.stream { [weak self] id in Task { await self?.unsubscribe(position: id) } })
    }

    /// The portfolio known now, then every whole new set from now on. Always on, like `positions()`: `connect`
    /// subscribes with reqAccountUpdates when the login has one account (with several, IB sends no portfolio).
    public func portfolio() -> (snapshot: [PortfolioItem], updates: AsyncStream<[PortfolioItem]>) {
        (accountTracker.portfolio,
         portfolioSubscribers.stream { [weak self] id in Task { await self?.unsubscribe(portfolio: id) } })
    }

    /// The account values known now, then every changed value from now on. Always on: `connect` subscribes with
    /// reqAccountUpdates for one account, or reqAccountUpdatesMulti per account when there are several.
    public func accountValues() -> (snapshot: [AccountValue], updates: AsyncStream<AccountValue>) {
        (accountTracker.values,
         accountValueSubscribers.stream { [weak self] id in Task { await self?.unsubscribe(accountValue: id) } })
    }

    /// The account summary for `tags`: the whole set, keyed and sorted by account, tag and currency, at
    /// IB's first end marker, then again on every change. Ends, throwing, on a fatal IB error for it or
    /// when the connection ends; stopping it cancels the subscription. IB allows two at a time.
    public func accountSummary(tags: [String], group: String = "All") throws(IBClientError)
        -> AsyncThrowingStream<[AccountValue], any Error> {
        try requireConnected()
        let id = nextRequestID()
        var values: [AccountValue] = [], ended = false, last: [AccountValue]?
        return try openStream(.accountSummary(requestID: id, group: group, tags: tags), id: id,
                              cancel: .cancelAccountSummary(requestID: id)) { message, out in
            switch message {
            case .accountSummary(_, let v):
                values.removeAll { ($0.account, $0.tag, $0.currency) == (v.account, v.tag, v.currency) }
                values.append(v)
                values.sort { ($0.account, $0.tag, $0.currency) < ($1.account, $1.tag, $1.currency) }
            case .accountSummaryEnd: ended = true
            default: return false
            }
            Self.yieldSet(values, ended: ended, last: &last, out)
            return false
        }
    }

    /// The account values of `account` and `modelCode` ("" for all models) through reqAccountUpdatesMulti: the
    /// whole set, keyed and sorted by account, model, tag and currency, at IB's first end marker, then again on
    /// every change. Ends like `accountSummary`. It has its own reqId, so it does not feed `accountValues()`.
    public func accountUpdatesMulti(account: String, modelCode: String = "", ledgerAndNLV: Bool = false)
        throws(IBClientError) -> AsyncThrowingStream<[AccountValue], any Error> {
        try requireConnected()
        let id = nextRequestID()
        var tracker = AccountTracker(), ended = false, last: [AccountValue]?   // the tracker keys and sorts the set
        return try openStream(.accountUpdatesMulti(requestID: id, account: account, modelCode: modelCode,
                                                   ledgerAndNLV: ledgerAndNLV), id: id,
                              cancel: .cancelAccountUpdatesMulti(requestID: id)) { message, out in
            switch message {
            case .accountUpdateMulti: _ = tracker.apply(message)
            case .accountUpdateMultiEnd: ended = true
            default: return false
            }
            Self.yieldSet(tracker.values, ended: ended, last: &last, out)
            return false
        }
    }

    /// The positions of `account` and `modelCode` through reqPositionsMulti: the whole set, keyed by account,
    /// model and conID (quantity 0 removes) and sorted the same way, at IB's first end marker, then on every
    /// change. Ends like `accountSummary`.
    public func positionsMulti(account: String, modelCode: String = "") throws(IBClientError)
        -> AsyncThrowingStream<[Position], any Error> {
        try requireConnected()
        let id = nextRequestID()
        var positions: [Position] = [], ended = false, last: [Position]?
        return try openStream(.positionsMulti(requestID: id, account: account, modelCode: modelCode), id: id,
                              cancel: .cancelPositionsMulti(requestID: id)) { message, out in
            switch message {
            case .positionMulti(_, let p):
                positions.removeAll { ($0.account, $0.modelCode, $0.contract.conID) == (p.account, p.modelCode, p.contract.conID) }
                if p.quantity != 0 { positions.append(p) }
                positions.sort { ($0.account, $0.modelCode, $0.contract.conID) < ($1.account, $1.modelCode, $1.contract.conID) }
            case .positionMultiEnd: ended = true
            default: return false
            }
            Self.yieldSet(positions, ended: ended, last: &last, out)
            return false
        }
    }

    /// Every account-level P&L update IB sends, as it comes. Ends like `accountSummary`.
    public func pnl(account: String, modelCode: String = "") throws(IBClientError)
        -> AsyncThrowingStream<AccountPnL, any Error> {
        try requireConnected()
        let id = nextRequestID()
        return try openStream(.pnl(requestID: id, account: account, modelCode: modelCode), id: id,
                              cancel: .cancelPnL(requestID: id)) { message, out in
            if case .pnl(_, let pnl) = message { out.yield(pnl) }
            return false
        }
    }

    /// The «set at the end marker, then on change» rule of the set-valued streams.
    private static func yieldSet<T: Equatable & Sendable>(
        _ set: T, ended: Bool, last: inout T?, _ out: AsyncThrowingStream<T, any Error>.Continuation
    ) {
        if ended, set != last { last = set; out.yield(set) }
    }

    /// Every P&L update IB sends for one position, as it comes. Ends like `accountSummary`.
    public func pnlSingle(account: String, conID: Int, modelCode: String = "") throws(IBClientError)
        -> AsyncThrowingStream<PnL, any Error> {
        try requireConnected()
        let id = nextRequestID()
        return try openStream(.pnlSingle(requestID: id, account: account, modelCode: modelCode, conID: conID), id: id,
                              cancel: .cancelPnLSingle(requestID: id)) { message, out in
            if case .pnlSingle(_, let pnl) = message { out.yield(pnl) }
            return false
        }
    }

    /// Every contract IB lists for `contract`, in its order, once IB's end marker arrives. Throws like a stream
    /// ends: a fatal IB error for it (200 when nothing matches), or the connection ending.
    public func contractDetails(_ contract: Contract) async throws(IBClientError) -> [ContractDetails] {
        try requireConnected()
        let id = nextRequestID()
        return try await collect(try openStream(.contractDetails(requestID: id, contract: contract), id: id,
                                                cancel: nil) { message, out in
            switch message {
            case .contractData(_, let d): out.yield(d); return false
            case .contractDataEnd: out.finish(); return true
            default: return false
            }
        })
    }

    /// The instruments whose symbol or name matches `pattern`, as IB samples them. Ends like `contractDetails`.
    public func matchingSymbols(_ pattern: String) async throws(IBClientError) -> [ContractDescription] {
        try requireConnected()
        let id = nextRequestID()
        return try await collect(try openStream(.matchingSymbols(requestID: id, pattern: pattern), id: id,
                                                cancel: nil) { message, out in
            guard case .symbolSamples(_, let list) = message else { return false }
            out.yield(list); out.finish(); return true
        }).flatMap { $0 }
    }

    /// Sets which kind of data market-data requests get without a subscription. Not remembered: a new connection
    /// starts at IB's default (real-time), so set it again after `connect`.
    public func setMarketDataType(_ type: MarketDataType) throws(IBClientError) {
        try requireConnected()
        try send(.marketDataType(type))
    }

    /// Every top-of-book tick IB sends for `contract`. Ends like `accountSummary`, with
    /// `.noMarketDataPermission` when IB refuses for want of a subscription; stopping it cancels.
    public func marketData(_ contract: Contract) throws(IBClientError) -> AsyncThrowingStream<Tick, any Error> {
        try requireConnected()
        let id = nextRequestID()
        return try openStream(.marketData(requestID: id, contract: contract), id: id,
                              cancel: .cancelMarketData(requestID: id)) { message, out in
            if case .tick(_, let tick) = message { out.yield(tick) }
            return false
        }
    }

    /// Historical bars as one `.history` batch. Without `keepUpToDate` the stream then ends, with no cancel; with it,
    /// every IB update follows raw as `.update` (a same-time update replaces the forming bar; the consumer merges).
    /// `end` nil is now; `duration`, `barSize` and `whatToShow` are IB's strings ("1 D", "5 mins", "TRADES").
    public func historicalBars(
        _ contract: Contract, end: Date? = nil, duration: String, barSize: String, whatToShow: String = "TRADES",
        rth: Bool = true, keepUpToDate: Bool = false
    ) throws(IBClientError) -> AsyncThrowingStream<BarEvent, any Error> {
        try requireConnected()
        let id = nextRequestID()
        return try openStream(.historicalData(requestID: id, contract: contract, end: end, barSize: barSize,
                                              duration: duration, rth: rth, whatToShow: whatToShow,
                                              keepUpToDate: keepUpToDate),
                              id: id, cancel: .cancelHistoricalData(requestID: id)) { message, out in
            switch message {
            case .historicalData(_, let bars):
                out.yield(.history(bars))
                if !keepUpToDate { out.finish() }
                return !keepUpToDate
            case .historicalDataUpdate(_, let bar): out.yield(.update(bar)); return false
            default: return false
            }
        }
    }

    /// The whole depth book after every update (12 and 13 both feed it). IB's depth reset (317) empties the book,
    /// yields it and goes on. `smart` is resent on cancel, as IB requires. Ends like `marketData` on a refusal, except
    /// that without depth permissions IB sends notice 2152 and nothing more, so the stream stays quiet. Every element
    /// is a whole book, so a slow consumer keeps only the newest.
    public func marketDepth(_ contract: Contract, rows: Int, smart: Bool = true)
        throws(IBClientError) -> AsyncThrowingStream<DepthBook, any Error> {
        try requireConnected()
        let id = nextRequestID()
        var book = DepthBook()
        return try openStream(.marketDepth(requestID: id, contract: contract, rows: rows, smart: smart), id: id,
                              cancel: .cancelMarketDepth(requestID: id, smart: smart),
                              buffering: .bufferingNewest(1)) { message, out in
            switch message {
            case .depth(_, let u): book.apply(u); out.yield(book)
            case .error(let e) where e.code == 317: book.reset(); out.yield(book)
            default: break
            }
            return false
        }
    }

    /// Every trade, quote or midpoint IB reports for `contract`, unlimited and with size-only quote changes kept.
    /// Never ends itself; ends like `marketData` on a refusal.
    public func tickByTick(_ contract: Contract, _ type: TickByTickType)
        throws(IBClientError) -> AsyncThrowingStream<TickByTick, any Error> {
        try requireConnected()
        let id = nextRequestID()
        return try openStream(.tickByTick(requestID: id, contract: contract, type: type), id: id,
                              cancel: .cancelTickByTick(requestID: id)) { message, out in
            if case .tickByTick(_, let t) = message { out.yield(t) }
            return false
        }
    }

    /// IB's clock. Throws like `contractDetails` when the connection ends, or `.cancelled`.
    public func currentTime() async throws(IBClientError) -> Date {
        try requireConnected()
        let seconds = try await answer(.currentTime) { if case .currentTime(let t) = $0 { t } else { nil } }
        return Date(timeIntervalSince1970: Double(seconds))
    }

    /// The accounts IB lists for this login; the stored list is refreshed too.
    public func managedAccounts() async throws(IBClientError) -> [String] {
        try requireConnected()
        return try await answer(.managedAccounts) { if case .managedAccounts(let a) = $0 { a } else { nil } }
    }

    /// The id the next `placeOrder` takes, with IB's answer merged by `max` as at connect. Does not consume it.
    public func nextOrderID() async throws(IBClientError) -> Int {
        try requireConnected()
        let told = try await answer(.requestIDs) { if case .nextValidID(let n) = $0 { n } else { nil } }
        return max(nextID ?? told, told)   // the message already merged into nextID; a lower answer never lowers it
    }

    /// The white-branding id of the account; `""` for most.
    public func userInfo() async throws(IBClientError) -> String {
        try requireConnected()
        let id = nextRequestID()
        return try await answer(.userInfo(requestID: id), id: id) { if case .userInfo(_, let w) = $0 { w } else { nil } }
    }

    /// How much IB Gateway writes to its own log.
    public func setServerLogLevel(_ level: ServerLogLevel) throws(IBClientError) {
        try requireConnected()
        try send(.serverLogLevel(level))
    }

    /// Whether orders placed by other clients or TWS itself bind to this one. Only client 0 can use it.
    public func setAutoOpenOrders(_ autoBind: Bool) throws(IBClientError) {
        try requireConnected()
        try send(.autoOpenOrders(autoBind))
    }

    /// Asks IB to cancel every open order, this client's or not; the outcome arrives through `orders()`.
    public func cancelAllOrders() throws(IBClientError) {
        try requireConnected()
        try send(.globalCancel)
    }

    /// Sends `request` and waits for the first message `pick` takes. Without `id` the waiter is keyed by a local
    /// negative id and `routeToStream` offers it the id-less messages, oldest waiter first.
    private func answer<T: Sendable>(_ request: IBRequest, id: Int? = nil, pick: @escaping @Sendable (IBMessage) -> T?)
        async throws(IBClientError) -> T {
        let key = id ?? nextLocalID()
        let stream = try openStream(request, id: key, cancel: nil) { (message, out: AsyncThrowingStream<T, any Error>.Continuation) in
            guard let value = pick(message) else { return false }
            out.yield(value); out.finish(); return true
        }
        guard let value = try await collect(stream).first else { throw .cancelled }
        return value
    }

    /// Reads a self-ending stream to its end. It ends without error only when its end marker came, or when the
    /// calling task was cancelled.
    private func collect<E: Sendable>(_ stream: AsyncThrowingStream<E, any Error>) async throws(IBClientError) -> [E] {
        var got: [E] = []
        do { for try await x in stream { got.append(x) } } catch { throw error as? IBClientError ?? .cancelled }
        if Task.isCancelled { throw .cancelled }
        return got
    }

    /// Receives the fields of every incoming frame after the server hello, in arrival order, on the actor.
    /// Used to record live frames; `nil` removes it.
    func setFrameTap(_ tap: (@Sendable ([String]) -> Void)?) { frameTap = tap }

    var orderSubscriberCount: Int { orderSubscribers.count }
    var requestStreamCount: Int { requestStreams.count }

    private func requireConnected() throws(IBClientError) {
        guard case .connected = state else { throw .notConnected }
    }

    private func submit(_ id: Int, _ contract: Contract, _ order: Order) throws(IBClientError) {
        try send(.placeOrder(orderID: id, contract: contract, order: order))
        orderTracker.sent(orderID: id, clientID: clientID, contract: contract, order: order)
    }

    /// Encodes, frames and queues; throws before queuing when the request does not encode.
    func send(_ request: IBRequest) throws(IBClientError) {
        guard let outbox else { throw .notConnected }
        let body: [UInt8]
        do { body = try request.body() } catch { throw .encoding(error) }
        outbox.yield(Frame.encode(body))
    }

    /// Sends `request`, then registers its stream; nothing is registered when it does not encode.
    private func openStream<Element: Sendable>(
        _ request: IBRequest, id: Int, cancel: IBRequest?,
        buffering: AsyncThrowingStream<Element, any Error>.Continuation.BufferingPolicy = .unbounded,
        route: @escaping (IBMessage, AsyncThrowingStream<Element, any Error>.Continuation) -> Bool
    ) throws(IBClientError) -> AsyncThrowingStream<Element, any Error> {
        try send(request)
        let (stream, out) = AsyncThrowingStream.makeStream(of: Element.self, throwing: (any Error).self,
                                                           bufferingPolicy: buffering)
        requestStreams[id] = RequestStream(route: { route($0, out) }, finish: { out.finish(throwing: $0) },
                                           cancel: cancel)
        let gen = generation
        out.onTermination = { [weak self] _ in Task { await self?.stopped(id, gen) } }
        return stream
    }

    /// The consumer stopped the stream. An entry already gone was finished by the client, which sends no cancel;
    /// `gen` keeps a late stop from touching a stream that reuses the reqId on a later connection.
    private func stopped(_ id: Int, _ gen: Int) {
        guard gen == generation, let s = requestStreams.removeValue(forKey: id) else { return }
        if let cancel = s.cancel { try? send(cancel) }   // the cancel encodes: it is all integers
    }

    private func routeToStream(_ message: IBMessage) {
        switch message {
        case .accountSummary(let id, _), .accountSummaryEnd(let id), .pnlSingle(let id, _),
             .contractData(let id, _), .contractDataEnd(let id), .symbolSamples(let id, _), .tick(let id, _),
             .historicalData(let id, _), .historicalDataUpdate(let id, _), .depth(let id, _),
             .tickByTick(let id, _), .userInfo(let id, _), .positionMulti(let id, _), .positionMultiEnd(let id),
             .accountUpdateMulti(let id, _), .accountUpdateMultiEnd(let id), .pnl(let id, _):
            if requestStreams[id]?.route(message) == true { requestStreams[id] = nil }   // before any termination hop
        case .currentTime, .managedAccounts, .nextValidID:   // no reqId: the oldest waiter that takes it gets it
            for key in requestStreams.keys.filter({ $0 < -1 }).sorted(by: >) where requestStreams[key]?.route(message) == true {
                requestStreams[key] = nil
                break
            }
        case .error(let e) where ErrorCode.kind(e.code) == .notice:
            if requestStreams[e.requestID]?.route(message) == true { requestStreams[e.requestID] = nil }
        case .error(let e) where ErrorCode.kind(e.code).failsRequest:
            guard let s = requestStreams.removeValue(forKey: e.requestID) else { break }
            if ErrorCode.isNoMarketDataPermission(code: e.code, text: e.text) {
                if let cancel = s.cancel { try? send(cancel) }   // IB keeps a refused subscription open
                s.finish(.noMarketDataPermission(code: e.code, text: e.text))
            } else {
                s.finish(.ib(code: e.code, text: e.text))
            }
        default: break
        }
    }

    /// Orders and requests share this one sequence (docs/DECISIONS.md).
    func nextRequestID() -> Int {
        let id = nextID ?? 0
        nextID = id + 1
        return id
    }

    /// Keys for waiters with no reqId: -2, -3, ... (-1 is IB's "no request" in errors).
    private func nextLocalID() -> Int {
        localID -= 1
        return localID
    }

    private func start(_ t: any Transport, _ gen: Int, _ deadline: ContinuousClock.Instant) {
        transport = t
        let (queued, outbox) = AsyncStream.makeStream(of: [UInt8].self)
        self.outbox = outbox
        Task.detached {   // detached: a blocking write must never hold the actor
            var throttle = Throttle()
            for await frame in queued {
                let wait = throttle.reserve(at: .now)
                if wait > .zero { try? await Task.sleep(for: wait) }
                do { try t.write(frame) } catch { return await self.closed(error, gen) }
            }
            t.close()   // the outbox finished: after a draining disconnect, this is the close
        }
        Task.detached {
            do {
                for try await chunk in t.incoming { await self.receive(chunk, gen) }
                await self.closed(nil, gen)
            } catch {
                await self.closed(error, gen)
            }
        }
        connectTimer = Task {
            guard (try? await Task.sleep(until: deadline)) != nil else { return }   // cancelled: connect is over
            timedOut(gen)
        }
        do { try t.write(Handshake.hello()) } catch { end(error) }
    }

    private func receive(_ chunk: [UInt8], _ gen: Int) {
        guard gen == generation else { return }
        do { try frames.append(chunk) } catch { return end(.protocolError(error)) }
        while gen == generation, let body = frames.next() { handle(body) }
    }

    private func handle(_ body: [UInt8]) {
        guard serverVersion != nil else {   // the first frame answers the hello
            do { serverVersion = try Handshake.parseServerHello(body).serverVersion } catch {
                return end(.protocolError(error))
            }
            try? send(.startAPI(clientID: clientID, capabilities: ""))   // all-ASCII, cannot throw
            return
        }
        frameTap?(FieldReader(body).fields)
        let message = IBDecoder.decode(body)
        messageSubscribers.yield(message)
        for snapshot in orderTracker.apply(message) { orderSubscribers.yield(snapshot) }
        for fill in executionTracker.apply(message) { fillSubscribers.yield(fill) }
        if let set = positionTracker.apply(message) { positionSubscribers.yield(set) }
        let foreign = if case .accountUpdateMulti(let id, _) = message { !accountSyncIDs.contains(id) } else { false }
        switch foreign ? nil : accountTracker.apply(message) {
        case .portfolio(let set)?: portfolioSubscribers.yield(set)
        case .value(let v)?: accountValueSubscribers.yield(v)
        case nil: break
        }
        routeToStream(message)
        switch message {
        case .nextValidID(let n): nextID = max(nextID ?? n, n)
        case .managedAccounts(let a): accounts = a
        case .error(let e) where pendingConnect != nil
                && ((e.requestID == -1 && ErrorCode.kind(e.code) == .fatal)
                    || (ErrorCode.kind(e.code).failsRequest
                        && (syncEnds?.contains(.execDetailsEnd(requestID: e.requestID)) == true
                            || accountSyncIDs.contains(e.requestID)))):
            return end(.ib(code: e.code, text: e.text))   // -1: the connection itself; else a sync request
        default: break
        }
        guard pendingConnect != nil else { return }
        if syncEnds == nil {
            if nextID != nil, accounts != nil { sync() }
        } else {
            syncEnds?.removeAll { $0 == message }
            if syncEnds == [] { connected() }
        }
    }

    /// Only end markers that arrive after these requests are counted.
    private func sync() {
        let executionsID = nextRequestID()
        syncEnds = [.openOrderEnd, .completedOrdersEnd, .execDetailsEnd(requestID: executionsID), .positionEnd]
        try? send(.allOpenOrders)   // none of these can fail to encode: IB account ids are ASCII
        try? send(.completedOrders(apiOnly: false))
        try? send(.executions(requestID: executionsID, filter: ExecutionFilter()))
        try? send(.positions)
        guard let accounts else { return }
        if accounts.count == 1 {   // reqAccountUpdates: the portfolio too, but for one account at a time
            accountTracker.reload()
            syncEnds?.append(.accountDownloadEnd(account: accounts[0]))
            try? send(.accountUpdates(subscribe: true, account: accounts[0]))
            return
        }
        for account in accounts {   // values only; IB has no Multi portfolio
            let id = nextRequestID()
            accountSyncIDs.insert(id)
            syncEnds?.append(.accountUpdateMultiEnd(requestID: id))
            try? send(.accountUpdatesMulti(requestID: id, account: account, modelCode: "", ledgerAndNLV: false))
        }
    }

    private func connected() {
        guard let serverVersion, let accounts else { return }
        connectTimer?.cancel()
        (connectTimer, syncEnds) = (nil, nil)
        setState(.connected(serverVersion: serverVersion, accounts: accounts))
        pendingConnect?.resume(returning: .success(()))
        pendingConnect = nil
    }

    private func timedOut(_ gen: Int) {
        if gen == generation, pendingConnect != nil { end(.timeout) }
    }

    private func closed(_ error: (any Error)?, _ gen: Int) {
        guard gen == generation else { return }
        end(error.map { $0 as? IBClientError ?? .transport("\($0)") } ?? .connectionClosed)
    }

    /// Every exit path ends here: the transport is closed (its reader thread holds it), the outbox finished,
    /// and anything still in flight from this connection is ignored from now on. `draining` (a clean disconnect)
    /// queues cancelPositions and leaves the close to the writer, with a 2 s bound.
    private func end(_ error: IBClientError?, draining: Bool = false) {
        generation += 1
        if draining, let t = transport {
            try? send(.cancelPositions)   // all integers: encodes
            Task { try? await Task.sleep(for: .seconds(2)); t.close() }
        } else {
            transport?.close()
        }
        outbox?.finish()
        connectTimer?.cancel()
        (transport, outbox, connectTimer, syncEnds) = (nil, nil, nil, nil)
        let streams = requestStreams.values
        requestStreams = [:]   // emptied first: their termination then sends no cancel
        for s in streams { s.finish(error ?? .connectionClosed) }
        setState(.disconnected(error))
        pendingConnect?.resume(returning: .failure(error ?? .connectionClosed))
        pendingConnect = nil
    }

    private func setState(_ new: ConnectionState) {
        state = new
        stateSubscribers.yield(new)
    }

    private func unsubscribe(state id: Int) { stateSubscribers.remove(id) }
    private func unsubscribe(message id: Int) { messageSubscribers.remove(id) }
    private func unsubscribe(order id: Int) { orderSubscribers.remove(id) }
    private func unsubscribe(fill id: Int) { fillSubscribers.remove(id) }
    private func unsubscribe(position id: Int) { positionSubscribers.remove(id) }
    private func unsubscribe(portfolio id: Int) { portfolioSubscribers.remove(id) }
    private func unsubscribe(accountValue id: Int) { accountValueSubscribers.remove(id) }
}
