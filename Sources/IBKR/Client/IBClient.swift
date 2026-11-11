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

    /// A per-request stream, by reqId: `route` gets what IB sends for it, `finish` ends it, `cancel` is sent
    /// when the consumer stops it (`nil`: nothing to send). `route` returns true when it finished the stream
    /// itself, and the entry is then removed. Every entry belongs to the current connection; `end()` clears them all.
    private struct RequestStream {
        let route: (IBMessage) -> Bool
        let finish: (IBClientError) -> Void
        let cancel: IBRequest?
    }
    private var requestStreams: [Int: RequestStream] = [:]

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

    /// Returns once the handshake is done and open orders, completed orders, executions and positions are synced.
    /// `timeout` covers all of it.
    public func connect(host: String = "127.0.0.1", port: Int = 4002, clientID: Int,
                        timeout: Duration = .seconds(10)) async throws(IBClientError) {
        guard case .disconnected = state else { throw .alreadyConnected }
        let deadline = ContinuousClock.now + timeout
        generation += 1
        let gen = generation
        self.clientID = clientID
        frames = FrameReader()
        (serverVersion, accounts, nextID, syncEnds) = (nil, nil, nil, nil)
        orderTracker = OrderTracker(clientID: clientID)   // fills are kept: the sync's replay of them publishes nothing
        positionTracker.reload()   // the set is kept too, and replaced whole at the sync's positionEnd
        setState(.connecting)

        let t: any Transport
        do {
            t = try await connector(host, port, timeout)
        } catch {
            let e = error as? IBClientError ?? .transport("\(error)")
            if gen == generation { end(e) }
            throw e
        }
        guard gen == generation else { t.close(); throw .connectionClosed }   // disconnect() came first

        try await withCheckedContinuation { continuation in
            pendingConnect = continuation
            start(t, gen, deadline)
        }.get()
    }

    /// Closes the connection and reports `.disconnected(nil)`. Does nothing when already disconnected.
    public func disconnect() {
        if case .disconnected = state { return }
        end(nil)
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
            if ended, values != last { last = values; out.yield(values) }
            return false
        }
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
    /// yields it and goes on. `smart` is resent on cancel, as IB requires. Ends like `marketData` on a refusal.
    /// Every element is a whole book,
    /// so a slow consumer keeps only the newest.
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
             .tickByTick(let id, _):
            if requestStreams[id]?.route(message) == true { requestStreams[id] = nil }   // before any termination hop
        case .error(let e) where ErrorCode.kind(e.code) == .notice:
            if requestStreams[e.requestID]?.route(message) == true { requestStreams[e.requestID] = nil }
        case .error(let e) where ErrorCode.kind(e.code) == .fatal:
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
        routeToStream(message)
        switch message {
        case .nextValidID(let n): nextID = max(nextID ?? n, n)
        case .managedAccounts(let a): accounts = a
        case .error(let e) where pendingConnect != nil && ErrorCode.kind(e.code) == .fatal
                && (e.requestID == -1 || syncEnds?.contains(.execDetailsEnd(requestID: e.requestID)) == true):
            return end(.ib(code: e.code, text: e.text))   // -1: the connection itself; else the sync's reqExecutions
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
        try? send(.allOpenOrders)   // none of the four can fail to encode
        try? send(.completedOrders(apiOnly: false))
        try? send(.executions(requestID: executionsID, filter: ExecutionFilter()))
        try? send(.positions)
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
    /// and anything still in flight from this connection is ignored from now on.
    private func end(_ error: IBClientError?) {
        generation += 1
        transport?.close()
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
}
