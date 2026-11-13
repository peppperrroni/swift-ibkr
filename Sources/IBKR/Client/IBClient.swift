import Foundation
/// Where an `IBClient` stands, as `states()` reports it.
public enum ConnectionState: Sendable, Equatable {
    /// Not connected: `nil` after `disconnect()` or before any connect, else the error that ended the connection.
    case disconnected(IBClientError?)
    /// `connect` or a reconnect attempt is under way.
    case connecting
    /// The handshake and the sync are done; the server's version and the managed account ids.
    case connected(serverVersion: Int, accounts: [String])
}

/// One connection to IB Gateway. Incoming chunks reach the actor in order through one reader task; requests
/// leave in call order through one throttled writer task. A lost connection is reconnected only under the
/// `ReconnectPolicy` given to `connect`.
public actor IBClient {
    private let connector: Connector
    var state: ConnectionState = .disconnected(nil)
    private var stateSubscribers = Subscribers<ConnectionState>()
    private var messageSubscribers = Subscribers<IBMessage>()
    private var orderSubscribers = Subscribers<OrderSnapshot>()
    private var orderEventSubscribers = Subscribers<OrderEvent>()
    private var fillSubscribers = Subscribers<Fill>()
    private var positionSubscribers = Subscribers<[Position]>()
    private var portfolioSubscribers = Subscribers<[PortfolioItem]>()
    private var accountValueSubscribers = Subscribers<AccountValue>()

    /// A per-request stream, by reqId: `route` gets what IB sends for it, `finish` ends it, `cancel` is sent
    /// when the consumer stops it (`nil`: nothing to send). `route` returns true when it finished the stream
    /// itself, and the entry is then removed. On IB error `resend.onCode` for its reqId the client sends `cancel`
    /// and then `resend.request` again, and the stream stays open; an error with reqId -1 does that for every stream
    /// whose `resend.onCode` it carries. A `oneShot` (an id-less one-shot, R16) ends on a fatal or warning error with
    /// reqId -1 and after `ConnectOptions.idlessRequestTimeout`. Every entry belongs to the current connection;
    /// `end()` clears them all.
    private struct RequestStream {
        let route: (IBMessage) -> Bool
        let finish: (IBClientError) -> Void
        let cancel: IBRequest?
        let resend: (onCode: Int, request: IBRequest)?
        let oneShot: Bool
    }
    private var requestStreams: [Int: RequestStream] = [:]
    /// The open `realTimeBars` and `liveHistoricalBars` subscriptions, by reqId; an entry goes with its stream.
    var liveBars: [Int: LiveBars] = [:]
    var barUpdateSubscribers = Subscribers<LiveBars>()
    /// The open `tickers` streams' latest `Ticker`, by a key of their own (`tickerKey`); an entry goes when its fold
    /// ends or the connection does.
    var tickerRegistry: [Int: Ticker] = [:]
    var tickerKey = 0
    var pendingTickerSubscribers = Subscribers<[Ticker]>()
    /// The latest value of each open `pnl` and `pnlSingle` stream, by reqId; an entry goes with its stream.
    var accountPnLs: [Int: AccountPnL] = [:]
    var positionPnLs: [Int: PnL] = [:]
    /// Every news tick and bulletin since the last manual `connect` (a reconnect keeps them).
    var newsTickLog: [NewsTick] = []
    var newsTickSubscribers = Subscribers<NewsTick>()
    var bulletins: [NewsBulletin] = []
    private var localID = -1
    /// The open `newsBulletins` stream's key; IB holds one bulletin subscription per connection.
    var newsBulletinKey: Int?
    /// The `wshMetaData` request left open after its answer (R7, as `ib_async`); the next call cancels it.
    var wshMetaRequestID: Int?

    // The current connection. `generation` changes whenever one starts or ends, so a late event from an old
    // connection's reader, writer or timer is dropped.
    private var generation = 0
    private var transport: (any Transport)?
    private var outbox: AsyncStream<[UInt8]>.Continuation?
    private var frames = FrameReader()
    var clientID = 0
    private var serverVersion: Int?
    private var accounts: [String]?
    private var nextID: Int?
    var orderTracker = OrderTracker(clientID: 0)
    var executionTracker = ExecutionTracker()
    private var positionTracker = PositionTracker()
    private var accountTracker = AccountTracker()
    private var accountSyncIDs: Set<Int> = []   // the sync's reqAccountUpdatesMulti ids; only these feed accountTracker
    private var frameTap: (@Sendable ([String]) -> Void)?

    // While `connect` waits: its continuation, its deadline timer, and the sync's end markers still due
    // (nil until the sync requests are sent).
    private var pendingConnect: CheckedContinuation<Result<Void, IBClientError>, Never>?
    private var connectTimer: Task<Void, Never>?
    private var syncEnds: [IBMessage]?

    // Opt-in reconnect: what `connect` was given, the running attempt loop (nil when none: an attempt's `end()`
    // then publishes), the silence probe, and when the last chunk came in.
    private var reconnect: (policy: ReconnectPolicy, host: String, port: Int, clientID: Int, timeout: Duration)?
    private var reconnectTask: Task<Void, Never>?
    private var probeTask: Task<Void, Never>?
    var lastFrame = ContinuousClock.now

    // What the last manual `connect` was given (reconnect attempts reuse it), where the connection goes, its
    // counters, and the writer's throttle state: frames queued and not yet written, and whether it is waiting.
    private var options = ConnectOptions()
    var address = (host: "", port: 0)
    var stats = ConnectionStats(startTime: Date(), duration: .zero, bytesReceived: 0, bytesSent: 0,
                                messagesReceived: 0, messagesSent: 0)
    var startedAt = ContinuousClock.now
    private var queuedFrames = 0
    var isThrottling = false
    var throttleSubscribers = Subscribers<Bool>()
    let logBox = LogBox()
    var activeIdleTimers = 0   // running `idleTimeouts` timers

    /// Creates a client that is not connected; `connect` opens the socket.
    public init() {
        self.init(connector: { host, port, timeout in
            try await TCPSocket.connect(host: host, port: port, timeout: timeout)
        })
    }

    init(connector: @escaping Connector) { self.connector = connector }

    /// Returns once the handshake is done and open orders, completed orders, executions, positions, the portfolio
    /// and the account values are synced, as far as `options` asks for them (`ib_async`'s sync: client 0 first
    /// binds TWS's manual orders with `setAutoOpenOrders(true)`).
    /// `timeout` covers all of it. Cancelling the calling task stops it with `.cancelled`.
    /// With `reconnect`, a connection that reached `.connected` and then ends with an error publishes
    /// `.disconnected(error)`, then `.connecting`, and is retried under the policy until `disconnect()`; request
    /// streams still end at the drop, and nothing outside the sync is resent (`setMarketDataType` included).
    /// While it retries, `connect` throws `.alreadyConnected`. A first connect that fails is not retried.
    /// Every reconnect attempt uses the same `options`.
    public func connect(host: String = "127.0.0.1", port: Int = 4002, clientID: Int,
                        timeout: Duration = .seconds(10), reconnect policy: ReconnectPolicy? = nil,
                        options: ConnectOptions = .init())
        async throws(IBClientError) {
        guard case .disconnected = state else { throw .alreadyConnected }
        (newsTickLog, bulletins) = ([], [])   // ib_async's wrapper.reset at connect
        self.options = options
        reconnect = policy.map { ($0, host, port, clientID, timeout) }   // acts only once this connect succeeds
        try await open(host: host, port: port, clientID: clientID, timeout: timeout).get()
    }

    /// The connect path, shared by `connect` and the reconnect attempts.
    private func open(host: String, port: Int, clientID: Int, timeout: Duration) async -> Result<Void, IBClientError> {
        let deadline = ContinuousClock.now + timeout
        generation += 1
        let gen = generation
        self.clientID = clientID
        address = (host, port)
        frames = FrameReader()
        (serverVersion, accounts, nextID, syncEnds, accountSyncIDs) = (nil, nil, nil, nil, [])
        // A reconnect attempt keeps the orders (same client id) so they stay visible while it retries. Fills are
        // always kept: the sync's replay of them publishes nothing.
        if reconnectTask == nil { orderTracker = OrderTracker(clientID: clientID) }
        positionTracker.reload()   // the set is kept too, and replaced whole at the sync's positionEnd
        setState(.connecting)

        return await withTaskCancellationHandler { () async -> Result<Void, IBClientError> in
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
        }
    }

    /// Pauses and reruns the connect path until it succeeds, `maxAttempts` run out (then publishes
    /// `.disconnected` with the last error), or `disconnect()` cancels it (which has published already).
    private func reconnectLoop(after drop: IBClientError) async {
        guard let r = reconnect else { return }
        var lastError = drop, attempt = 0
        while r.policy.maxAttempts.map({ attempt < $0 }) ?? true {
            attempt += 1
            if !r.policy.delays.isEmpty {
                try? await Task.sleep(for: r.policy.delays[min(attempt, r.policy.delays.count) - 1])
            }
            guard !Task.isCancelled else { return }
            switch await open(host: r.host, port: r.port, clientID: r.clientID, timeout: r.timeout) {
            case .success: return
            case .failure(let e): lastError = e
            }
        }
        guard !Task.isCancelled else { return }
        reconnectTask = nil
        setState(.disconnected(lastError))
    }

    /// While connected: after `every` with no incoming chunk, asks IB the time; as long again with nothing ends
    /// the connection with `.timeout`.
    private func probe(every: Duration, _ gen: Int) async {
        var probedAt: ContinuousClock.Instant?
        while true {
            guard (try? await Task.sleep(until: (probedAt ?? lastFrame) + every)) != nil,
                  gen == generation else { return }
            if let p = probedAt {
                if lastFrame >= p { probedAt = nil } else { return end(.timeout) }
            } else if ContinuousClock.now - lastFrame >= every {
                try? send(.currentTime)   // no fields to encode
                probedAt = .now
            }
        }
    }

    private func cancelConnect(_ gen: Int) {
        // `.connecting`: a late cancel keeps a done connect
        if gen == generation, state == .connecting { end(.cancelled) }
    }

    /// Reports `.disconnected(nil)` and ends the request streams at once. From `.connected` it first queues
    /// cancelPositions and lets the queue drain: the writer closes after the last frame, or 2 s later at the
    /// latest. From `.connecting` it closes at once. Does nothing when already disconnected. Stops reconnecting.
    public func disconnect() {
        reconnect = nil
        reconnectTask?.cancel()
        reconnectTask = nil   // first: the end() below then publishes
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

    /// Queues the order and returns its id at once, publishing a local `.pendingSubmit` snapshot on `orders()`
    /// (`ib_async`'s new `Trade`); IB's answer arrives through `orders()` too. Throws
    /// `.notConnected` unless the state is `.connected`, and `.encoding` when the order does not encode or has
    /// `whatIf` set (use `whatIfOrder`).
    public func placeOrder(_ contract: Contract, _ order: Order) throws(IBClientError) -> Int {
        try requireConnected()
        let id = nextRequestID()
        try submit(id, contract, order, verb: "placeOrder")
        return id
    }

    /// Queues a parent and its two children, linked and transmitted last, and returns their ids. All three encode
    /// before any is queued, so a `whatIf` leg or an encoding error sends nothing.
    public func placeBracket(_ contract: Contract, _ bracket: BracketOrder)
        throws(IBClientError) -> (parent: Int, takeProfit: Int, stopLoss: Int) {
        try requireConnected()
        let ids = (parent: nextRequestID(), takeProfit: nextRequestID(), stopLoss: nextRequestID())
        var legs = [(ids.parent, bracket.parent), (ids.takeProfit, bracket.takeProfit),
                    (ids.stopLoss, bracket.stopLoss)]
        for i in legs.indices {
            if i > 0 { legs[i].1.parentID = ids.parent }
            legs[i].1.transmit = i == 2
        }
        let frames = try legs.map { (id, order) throws(IBClientError) -> [UInt8] in
            if order.whatIf { throw .encoding(.unsupported("whatIf")) }
            return try encode(.placeOrder(orderID: id, contract: contract, order: order))
        }
        for (i, leg) in legs.enumerated() {
            try enqueue(frames[i])
            log(.info, "placeOrder \(leg.0): \(Self.describe(contract, leg.1))")
            for s in orderTracker.placed(orderID: leg.0, clientID: clientID, contract: contract, order: leg.1) {
                orderSubscribers.yield(s)
            }
        }
        return ids
    }

    /// Re-sends the order under its id; IB treats that as a modification. A known order that is not final gets the
    /// new order, loses its `rejectReason`, logs `"Modify"` and goes to `orders()` and, as `.modified`, to
    /// `orderEvents()`; an unknown id is recorded as a new `.pendingSubmit` order.
    public func modifyOrder(_ orderID: Int, _ contract: Contract, _ order: Order) throws(IBClientError) {
        try requireConnected()
        try submit(orderID, contract, order, verb: "modifyOrder")
    }

    /// IB's margin and commission for `order`, worked out without placing it; nothing reaches `orders()`. Throws
    /// like `contractDetails`: IB's error for it (201 when IB refuses the order), or the connection ending.
    public func whatIfOrder(_ contract: Contract, _ order: Order) async throws(IBClientError) -> OrderState {
        try requireConnected()
        let id = nextRequestID()
        var o = order
        o.whatIf = true
        return try await answer(.placeOrder(orderID: id, contract: contract, order: o), id: id) {
            // IB may first echo the order with no margins: only the one carrying them answers
            if case .openOrder(let m) = $0, m.order.whatIf, m.state.initMarginChange != nil { m.state } else { nil }
        }
    }

    /// `manualCancelOrderTime` (yyyyMMdd-HH:mm:ss) is the time IB records for a cancel made by hand; "" for none.
    /// A known order that is not final goes to `orders()` and, as `.cancelRequested`, to `orderEvents()` at once:
    /// `.pendingCancel`, or `.cancelled` for a `.pendingSubmit` order sent with `transmit` off.
    public func cancelOrder(_ orderID: Int, manualCancelOrderTime: String = "") throws(IBClientError) {
        try requireConnected()
        try send(.cancelOrder(orderID: orderID, manualCancelTime: manualCancelOrderTime))
        log(.info, "cancelOrder \(orderID)")
        for s in orderTracker.cancelRequested(orderID: orderID) {
            orderSubscribers.yield(s)
            orderEventSubscribers.yield(.cancelRequested(s))
        }
    }

    /// Exercises or lets lapse `quantity` contracts of an option; returns the request id. Refuses a `BAG`.
    @discardableResult
    public func exerciseOptions(_ contract: Contract, action: ExerciseAction, quantity: Int, account: String,
                                override: Bool = false) throws(IBClientError) -> Int {
        try requireConnected()
        let id = nextRequestID()
        try send(.exerciseOptions(requestID: id, contract: contract, action: action, quantity: quantity,
                                  account: account, override: override))
        return id
    }

    /// The orders known now, then every change from now on, as whole snapshots.
    public func orders() -> (snapshot: [OrderSnapshot], updates: AsyncStream<OrderSnapshot>) {
        (orderTracker.orders, orderSubscribers.stream { [weak self] id in Task { await self?.unsubscribe(order: id) } })
    }

    /// A fresh stream on every call, of this client's modifications and cancel requests from now on
    /// (`ib_async`'s `orderModifyEvent` and `cancelOrderEvent`).
    public func orderEvents() -> AsyncStream<OrderEvent> {
        orderEventSubscribers.stream { [weak self] id in Task { await self?.unsubscribe(orderEvent: id) } }
    }

    /// The fills known now, then every new or corrected fill from now on.
    public func executions() -> (snapshot: [Fill], updates: AsyncStream<Fill>) {
        (executionTracker.fills,
         fillSubscribers.stream { [weak self] id in Task { await self?.unsubscribe(fill: id) } })
    }

    /// The positions known now, then every whole new set from now on. On unless `ConnectOptions.fetch` leaves out
    /// `.positions`: `connect` requests them and they stream for the whole connection.
    public func positions() -> (snapshot: [Position], updates: AsyncStream<[Position]>) {
        (positionTracker.positions,
         positionSubscribers.stream { [weak self] id in Task { await self?.unsubscribe(position: id) } })
    }

    /// The portfolio known now, then every whole new set from now on. On like `positions()` (`fetch` flag
    /// `.accountUpdates`): `connect` subscribes with reqAccountUpdates for `ConnectOptions.account`, by default the
    /// login's only account (with several and none named, IB sends no portfolio).
    public func portfolio() -> (snapshot: [PortfolioItem], updates: AsyncStream<[PortfolioItem]>) {
        (accountTracker.portfolio,
         portfolioSubscribers.stream { [weak self] id in Task { await self?.unsubscribe(portfolio: id) } })
    }

    /// The account values known now, then every changed value from now on. On like `portfolio()`: `connect`
    /// subscribes with reqAccountUpdates for one account, and with several (or without that request) also with
    /// reqAccountUpdatesMulti per account while there are at most `maxSyncedSubAccounts` (`.subAccountUpdates`).
    public func accountValues() -> (snapshot: [AccountValue], updates: AsyncStream<AccountValue>) {
        (accountTracker.values,
         accountValueSubscribers.stream { [weak self] id in Task { await self?.unsubscribe(accountValue: id) } })
    }

    /// `ib_async`'s account summary tags (ib.py:2247-2258): 33 tags and `"$LEDGER:ALL"`.
    public static let defaultAccountSummaryTags = [
        "AccountType", "NetLiquidation", "TotalCashValue", "SettledCash", "AccruedCash", "BuyingPower",
        "EquityWithLoanValue", "PreviousDayEquityWithLoanValue", "GrossPositionValue", "RegTEquity", "RegTMargin", "SMA",
        "InitMarginReq", "MaintMarginReq", "AvailableFunds", "ExcessLiquidity", "Cushion", "FullInitMarginReq",
        "FullMaintMarginReq", "FullAvailableFunds", "FullExcessLiquidity", "LookAheadNextChange",
        "LookAheadInitMarginReq", "LookAheadMaintMarginReq", "LookAheadAvailableFunds", "LookAheadExcessLiquidity",
        "HighestSeverity", "DayTradesRemaining", "DayTradesRemainingT+1", "DayTradesRemainingT+2",
        "DayTradesRemainingT+3", "DayTradesRemainingT+4", "Leverage", "$LEDGER:ALL",
    ]

    /// The account summary for `tags` (by default `ib_async`'s set) in `group`: the whole set, keyed and sorted by
    /// account, tag and currency, at IB's first end marker, then again on every change. On IB's notice 1102
    /// (connectivity restored) it sends its cancel and then the same request under the same reqId, as `ib_async`
    /// re-requests it (ib.py:414), and goes on. Ends, throwing, on a fatal IB error for it or when the connection
    /// ends; stopping it cancels the subscription. IB allows two at a time.
    public func accountSummary(tags: [String] = IBClient.defaultAccountSummaryTags, group: String = "All")
        throws(IBClientError) -> AsyncThrowingStream<[AccountValue], any Error> {
        try requireConnected()
        let id = nextRequestID()
        var values: [AccountValue] = [], ended = false, last: [AccountValue]?
        return try openStream(.accountSummary(requestID: id, group: group, tags: tags), id: id,
                              cancel: .cancelAccountSummary(requestID: id), resendOn: 1102) { message, out in
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
                positions.removeAll {
                    ($0.account, $0.modelCode, $0.contract.conID) == (p.account, p.modelCode, p.contract.conID)
                }
                if p.quantity != 0 { positions.append(p) }
                positions.sort {
                    ($0.account, $0.modelCode, $0.contract.conID) < ($1.account, $1.modelCode, $1.contract.conID)
                }
            case .positionMultiEnd: ended = true
            default: return false
            }
            Self.yieldSet(positions, ended: ended, last: &last, out)
            return false
        }
    }

    /// Every account-level P&L update IB sends, as it comes, with `account` and `modelCode` set from the request.
    /// Ends like `accountSummary`. While open, its latest value is listed by `pnlValues(account:modelCode:)`.
    public func pnl(account: String, modelCode: String = "") throws(IBClientError)
        -> AsyncThrowingStream<AccountPnL, any Error> {
        try requireConnected()
        let id = nextRequestID()
        return try openStream(.pnl(requestID: id, account: account, modelCode: modelCode), id: id,
                              cancel: .cancelPnL(requestID: id)) { message, out in
            if case .pnl(_, var pnl) = message {
                (pnl.account, pnl.modelCode) = (account, modelCode)
                self.accountPnLs[id] = pnl
                out.yield(pnl)
            }
            return false
        }
    }

    /// The «set at the end marker, then on change» rule of the set-valued streams.
    private static func yieldSet<T: Equatable & Sendable>(
        _ set: T, ended: Bool, last: inout T?, _ out: AsyncThrowingStream<T, any Error>.Continuation
    ) {
        if ended, set != last { last = set; out.yield(set) }
    }

    /// Every P&L update IB sends for one position, as it comes, with `account`, `modelCode` and `conID` set from the
    /// request. Ends like `accountSummary`. While open, its latest value is listed by `pnlSingleValues(…)`.
    public func pnlSingle(account: String, conID: Int, modelCode: String = "") throws(IBClientError)
        -> AsyncThrowingStream<PnL, any Error> {
        try requireConnected()
        let id = nextRequestID()
        return try openStream(.pnlSingle(requestID: id, account: account, modelCode: modelCode, conID: conID), id: id,
                              cancel: .cancelPnLSingle(requestID: id)) { message, out in
            if case .pnlSingle(_, var pnl) = message {
                (pnl.account, pnl.modelCode, pnl.conID) = (account, modelCode, conID)
                self.positionPnLs[id] = pnl
                out.yield(pnl)
            }
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
    /// `.noMarketDataPermission` when IB refuses for want of a subscription; stopping it cancels. `genericTicks` are
    /// IB's generic tick numbers or tagged entries (`"mdoff"`, `"292:BRFG"` for news ticks). A `snapshot` stream
    /// ends by itself at IB's snapshot end, with no cancel. `options` are IB's market data options.
    public func marketData(
        _ contract: Contract, genericTicks: [GenericTick] = [], snapshot: Bool = false,
        regulatorySnapshot: Bool = false, options: [TagValue] = []
    ) throws(IBClientError) -> AsyncThrowingStream<Tick, any Error> {
        try requireConnected()
        let id = nextRequestID()
        return try openStream(.marketData(requestID: id, contract: contract, genericTicks: genericTicks,
                                          snapshot: snapshot,
                                          regulatorySnapshot: regulatorySnapshot, options: options), id: id,
                              cancel: .cancelMarketData(requestID: id)) { message, out in
            switch message {
            case .tick(_, let tick): out.yield(tick)
            case .tickSnapshotEnd: out.finish(); return true
            default: break
            }
            return false
        }
    }

    /// Historical bars as one `.history` batch. Without `keepUpToDate` the stream then ends, with no cancel; with it,
    /// every IB update follows raw as `.update` (a same-time update replaces the forming bar; the consumer merges, or
    /// uses `liveHistoricalBars`). With `keepUpToDate`, IB's 10225 (bust event) cancels and resends the same request
    /// under the same reqId and the stream goes on; IB's new batch then comes as another `.history`.
    /// `end` nil is now; `duration`, `barSize` and `whatToShow` are IB's strings ("1 D", "5 mins", "TRADES").
    /// A BAG sends its legs. `whatToShow` "SCHEDULE" is refused: use `historicalSchedule`. `options` are IB's chart
    /// options.
    public func historicalBars(
        _ contract: Contract, end: Date? = nil, duration: String, barSize: String, whatToShow: String = "TRADES",
        rth: Bool = true, keepUpToDate: Bool = false, options: [TagValue] = []
    ) throws(IBClientError) -> AsyncThrowingStream<BarEvent, any Error> {
        try requireConnected()
        if whatToShow == "SCHEDULE" { throw .encoding(.unsupported("whatToShow SCHEDULE")) }
        let id = nextRequestID()
        return try openStream(.historicalData(requestID: id, contract: contract, end: end, barSize: barSize,
                                              duration: duration, rth: rth, whatToShow: whatToShow,
                                              keepUpToDate: keepUpToDate, options: options),
                              id: id, cancel: .cancelHistoricalData(requestID: id),
                              resendOn: keepUpToDate ? 10225 : nil) { message, out in
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

    /// The trading sessions of `contract` over the last `days` days up to `end` (nil is now), as IB's history request
    /// with `whatToShow` SCHEDULE. Throws like `contractDetails` when IB refuses it; a missing permission sends
    /// the cancel.
    public func historicalSchedule(_ contract: Contract, days: Int, end: Date? = nil, rth: Bool = true)
        async throws(IBClientError) -> HistoricalSchedule {
        try requireConnected()
        let id = nextRequestID()
        let stream = try openStream(.historicalData(requestID: id, contract: contract, end: end, barSize: "1 day",
                                                    duration: "\(days) D", rth: rth, whatToShow: "SCHEDULE",
                                                    keepUpToDate: false),
                                    id: id, cancel: .cancelHistoricalData(requestID: id)) {
            (message, out: AsyncThrowingStream<HistoricalSchedule, any Error>.Continuation) in
            guard case .historicalSchedule(_, let schedule) = message else { return false }
            out.yield(schedule); out.finish(); return true
        }
        guard let schedule = try await collect(stream).first else { throw .cancelled }
        return schedule
    }

    /// Historical midpoint (`whatToShow` "MIDPOINT"), bid/ask ("BID_ASK") or trade ("TRADES") ticks, up to `count`,
    /// from `start` or up to `end` (nil is unset). IB has no cancel for it, so none is sent. Throws like
    /// `contractDetails`. `options` are IB's misc options.
    public func historicalTicks(
        _ contract: Contract, start: Date? = nil, end: Date? = nil, count: Int, whatToShow: String = "TRADES",
        rth: Bool = true, ignoreSize: Bool = false, options: [TagValue] = []
    ) async throws(IBClientError) -> [TickByTick] {
        try requireConnected()
        let id = nextRequestID()
        let stream = try openStream(.historicalTicks(requestID: id, contract: contract, start: start, end: end,
                                                     count: count, whatToShow: whatToShow, rth: rth,
                                                     ignoreSize: ignoreSize, options: options),
                                    id: id, cancel: nil) {
            (message, out: AsyncThrowingStream<TickByTick, any Error>.Continuation) in
            guard case .historicalTicks(_, let ticks, let done) = message else { return false }
            ticks.forEach { out.yield($0) }
            if done { out.finish() }
            return done
        }
        return try await collect(stream)
    }

    /// The date of the earliest data IB has for `contract` and `whatToShow`. Throws like `contractDetails` when IB
    /// refuses it.
    /// IB's cancel goes out after the answer, as `ib_async` does.
    public func headTimeStamp(_ contract: Contract, whatToShow: String = "TRADES", rth: Bool = true)
        async throws(IBClientError) -> Date {
        try requireConnected()
        let id = nextRequestID()
        let stream = try openStream(.headTimeStamp(requestID: id, contract: contract, whatToShow: whatToShow, rth: rth),
                                    id: id, cancel: .cancelHeadTimeStamp(requestID: id)) {
            (message, out: AsyncThrowingStream<Date, any Error>.Continuation) in
            guard case .headTimeStamp(_, let date) = message else { return false }
            out.yield(date); out.finish(); return false   // false: the termination hop sends the cancel
        }
        guard let date = try await collect(stream).first else { throw .cancelled }
        return date
    }

    /// The histogram of trade counts by price over `period` ("3 days"). Throws like `contractDetails` when IB refuses
    /// it; the cancel goes out only when the calling task is cancelled before the answer.
    public func histogramData(_ contract: Contract, period: String, rth: Bool = true)
        async throws(IBClientError) -> [HistogramData] {
        try requireConnected()
        let id = nextRequestID()
        return try await collect(try openStream(.histogramData(requestID: id, contract: contract, rth: rth,
                                                                period: period),
                                                id: id, cancel: .cancelHistogramData(requestID: id)) {
            (message, out: AsyncThrowingStream<[HistogramData], any Error>.Continuation) in
            guard case .histogramData(_, let list) = message else { return false }
            out.yield(list); out.finish(); return true
        }).flatMap { $0 }
    }

    /// IB's five-second bars for `contract`, one per bar, never ending itself; ends like `marketData` on a refusal.
    /// `whatToShow` is "TRADES", "MIDPOINT", "BID" or "ASK". MIDPOINT/BID/ASK bars carry -1 volume, average and
    /// count, as historical bars do. IB's 10225 (bust event) cancels and resends the same request under the same
    /// reqId, as `ib_async` does, and the stream goes on. While open it is listed by `liveBarSubscriptions()`, where
    /// its bars accumulate, and each bar goes to `barUpdates()`. `options` are IB's real-time bar options.
    public func realTimeBars(_ contract: Contract, whatToShow: String = "TRADES", rth: Bool = true,
                             options: [TagValue] = [])
        throws(IBClientError) -> AsyncThrowingStream<Bar, any Error> {
        try requireConnected()
        let id = nextRequestID()
        let stream = try openStream(.realTimeBars(requestID: id, contract: contract, whatToShow: whatToShow, rth: rth,
                                                  options: options),
                                    id: id, cancel: .cancelRealTimeBars(requestID: id), resendOn: 10225) { message, out in
            if case .realTimeBar(_, let bar) = message {
                out.yield(bar)
                _ = self.foldLiveBar(id, bar, append: true)
            }
            return false
        }
        liveBars[id] = LiveBars(requestID: id, contract: contract, barSize: "5 secs", whatToShow: whatToShow, bars: [],
                                hasNewBar: false)
        return stream
    }

    /// The whole depth book after every update (12 and 13 both feed it). IB's depth reset (317) empties the book,
    /// yields it and goes on. `smart` is resent on cancel, as IB requires. Ends like `marketData` on a refusal. IB
    /// refuses depth with notice 2152 and nothing else, so a 2152 that carries «Unknown market data permissions» and
    /// whose part before it names no `Depth:` exchange ends the stream with `.noMarketDataPermission(code: 2152, …)`;
    /// any other 2152 leaves the book open.
    /// Every element is a whole book, so a slow consumer keeps only the newest. `options` are IB's depth options.
    public func marketDepth(_ contract: Contract, rows: Int, smart: Bool = true, options: [TagValue] = [])
        throws(IBClientError) -> AsyncThrowingStream<DepthBook, any Error> {
        var book = DepthBook()
        return try depthRequest(contract, rows: rows, smart: smart, options: options, buffering: .bufferingNewest(1)) {
            if let u = $0 { book.apply(u) } else { book.reset() }
            return book
        }
    }

    /// IB's depth request, shared by `marketDepth` and `tickers`: each update, or `nil` for IB's reset (317), goes
    /// out through `element`; a 2152 that grants no depth ends it, and stopping it sends the cancel.
    private func depthRequest<E: Sendable>(
        _ contract: Contract, rows: Int, smart: Bool, options: [TagValue],
        buffering: AsyncThrowingStream<E, any Error>.Continuation.BufferingPolicy,
        _ element: @escaping (DepthUpdate?) -> E
    ) throws(IBClientError) -> AsyncThrowingStream<E, any Error> {
        try requireConnected()
        let id = nextRequestID()
        return try openStream(.marketDepth(requestID: id, contract: contract, rows: rows, smart: smart,
                                           options: options), id: id,
                              cancel: .cancelMarketDepth(requestID: id, smart: smart),
                              buffering: buffering) { message, out in
            switch message {
            case .depth(_, let u): out.yield(element(u))
            case .error(let e) where e.code == 317: out.yield(element(nil))
            case .error(let e) where e.code == 2152 && ErrorCode.grantsNoDepth(e.text):
                out.finish(throwing: IBClientError.noMarketDataPermission(code: 2152, text: e.text))
            default: break
            }
            return false
        }
    }

    /// `contract`'s market data folded into one `Ticker`, yielded whole after every tick, depth update or
    /// tick-by-tick event, with no deduplication. Each update stamps `time` and replaces `ticks`, `tickByTicks` and
    /// `domTicks` with its own; a slow consumer gets the newest ticker carrying the lists of every update it skipped,
    /// so no tick is lost or seen twice. `depthRows` adds the depth book, opened first, since it refuses everything
    /// `marketData` refuses and BAG too; `tickByTick` adds IB's tick-by-tick events of that type, opened last. An
    /// open error stops what was already opened. The first inner error ends the stream with that error, and however
    /// it ends, every request still open is cancelled. `options` go with the market data request only. While open,
    /// its latest ticker is listed by `ticker(for:)` and `activeTickers()`, and each update goes to `pendingTickers()`.
    public func tickers(_ contract: Contract, genericTicks: [GenericTick] = [], depthRows: Int? = nil,
                        smartDepth: Bool = true, tickByTick: TickByTickType? = nil, options: [TagValue] = [])
        throws(IBClientError) -> AsyncThrowingStream<Ticker, any Error> {
        var depth: AsyncThrowingStream<TickerPart, any Error>?
        if let depthRows {
            depth = try depthRequest(contract, rows: depthRows, smart: smartDepth, options: [], buffering: .unbounded) {
                $0.map(TickerPart.depth) ?? .depthReset
            }
        }
        let quotes: AsyncThrowingStream<Tick, any Error>
        do throws(IBClientError) {
            quotes = try marketData(contract, genericTicks: genericTicks, options: options)
        } catch {
            if let depth { Self.stop(depth) }
            throw error
        }
        var events: AsyncThrowingStream<TickByTick, any Error>?
        do throws(IBClientError) {
            if let tickByTick { events = try self.tickByTick(contract, tickByTick) }
        } catch {
            if let depth { Self.stop(depth) }
            Self.stop(quotes)
            throw error
        }
        tickerKey += 1
        let key = tickerKey
        tickerRegistry[key] = Ticker(contract: contract)   // listed from the request on, as ib_async's reqMktData
        return Self.fold(contract, quotes, depth, events) { [weak self] in await self?.recordTicker(key, $0) }
    }

    /// One snapshot `Ticker` per contract, in the order of `contracts`, each read to IB's snapshot end. Every request
    /// is sent before any is read, as `ib_async`'s `reqTickers`. The first error is thrown and every request still open
    /// is cancelled, where `ib_async` returns partial tickers; a cancelled calling task throws `.cancelled`.
    /// There is no timeout: a request IB never ends keeps the call waiting until the calling task is cancelled, as
    /// with `ib_async`'s default `RequestTimeout` 0. An already-cancelled caller sends nothing.
    public func tickers(for contracts: [Contract], regulatorySnapshot: Bool = false)
        async throws(IBClientError) -> [Ticker] {
        try requireConnected()
        if Task.isCancelled { throw .cancelled }
        var streams: [AsyncThrowingStream<Tick, any Error>] = []
        do throws(IBClientError) {
            for c in contracts {
                streams.append(try marketData(c, snapshot: true, regulatorySnapshot: regulatorySnapshot))
            }
        } catch {
            streams.forEach(Self.stop)
            throw error
        }
        let tickers: [Ticker]
        do {
            // a child that throws makes the group cancel the others, which stops their streams and sends their cancels
            tickers = try await withThrowingTaskGroup(of: (Int, Ticker).self) { group in
                for (i, (contract, ticks)) in zip(contracts, streams).enumerated() {
                    group.addTask {
                        var t = Ticker(contract: contract)
                        for try await tick in ticks { t.apply(tick) }
                        return (i, t)
                    }
                }
                var got = contracts.map { Ticker(contract: $0) }
                for try await (i, t) in group { got[i] = t }
                return got
            }
        } catch { throw error as? IBClientError ?? .cancelled }
        if Task.isCancelled { throw .cancelled }   // a cancelled stream ends without error, its ticker partial
        return tickers
    }

    /// What `tickers` folds: a tick, a depth update, IB's depth reset (317), or a tick-by-tick event.
    private enum TickerPart: Sendable { case tick(Tick), depth(DepthUpdate), depthReset, tickByTick(TickByTick) }

    /// One task per inner stream forwards it into an unbounded channel (a dropped tick is lost state); the fold
    /// applies each part with one `now`, clears and refills the per-update lists, and puts the whole ticker in a
    /// `TickerMailbox`. The first inner end or error ends the fold; the mailbox's end, or the consumer leaving,
    /// cancels the readers, which stops each inner stream and so sends its cancel.
    /// Each step is `record`ed (awaited, so one ticker's updates keep their order) before the consumer gets it; the
    /// fold's end records `nil`.
    private nonisolated static func fold(_ contract: Contract, _ quotes: AsyncThrowingStream<Tick, any Error>,
                                         _ depth: AsyncThrowingStream<TickerPart, any Error>?,
                                         _ events: AsyncThrowingStream<TickByTick, any Error>?,
                                         record: @escaping @Sendable (Ticker?) async -> Void)
        -> AsyncThrowingStream<Ticker, any Error> {
        let (parts, feed) = AsyncThrowingStream.makeStream(of: TickerPart.self, throwing: (any Error).self)
        func forward<E: Sendable>(_ s: AsyncThrowingStream<E, any Error>, _ wrap: @escaping @Sendable (E) -> TickerPart)
            -> Task<Void, Never> {
            Task {
                do { for try await e in s { feed.yield(wrap(e)) }; feed.finish() }
                catch { feed.finish(throwing: error) }
            }
        }
        var readers = [forward(quotes, TickerPart.tick)]
        if let depth { readers.append(forward(depth) { $0 }) }
        if let events { readers.append(forward(events, TickerPart.tickByTick)) }
        let box = TickerMailbox(readers: readers)
        Task {
            var ticker = Ticker(contract: contract)
            do {
                for try await part in parts {
                    let now = Date()
                    ticker.ticks = []; ticker.tickByTicks = []; ticker.domTicks = []
                    switch part {
                    case .tick(let t): ticker.apply(t, at: now)
                    case .depth(let u): ticker.apply(u, at: now)
                    case .depthReset: ticker.resetDepth(at: now)
                    case .tickByTick(let t): ticker.apply(t, at: now)
                    }
                    ticker.time = now
                    await record(ticker)
                    box.put(ticker)
                }
                box.finish(throwing: nil)
            } catch { box.finish(throwing: error) }
            await record(nil)
        }
        return box.stream()
    }

    /// Stops a stream nobody reads: a cancelled reader terminates it, which sends its cancel. Freeing an unread
    /// stream would too, but nothing promises when.
    private nonisolated static func stop<E: Sendable>(_ stream: AsyncThrowingStream<E, any Error>) {
        Task { for try await _ in stream {} }.cancel()
    }

    /// Every trade, quote or midpoint IB reports for `contract`. `count` above 0 asks IB for that many past ticks
    /// first; `ignoreSize` drops quote changes that move only the size. Never ends itself; ends like `marketData` on
    /// a refusal.
    public func tickByTick(_ contract: Contract, _ type: TickByTickType, count: Int = 0, ignoreSize: Bool = false)
        throws(IBClientError) -> AsyncThrowingStream<TickByTick, any Error> {
        try requireConnected()
        let id = nextRequestID()
        return try openStream(.tickByTick(requestID: id, contract: contract, type: type, count: count,
                                          ignoreSize: ignoreSize), id: id,
                              cancel: .cancelTickByTick(requestID: id)) { message, out in
            if case .tickByTick(_, let t) = message { out.yield(t) }
            return false
        }
    }

    /// IB's clock. Throws like `contractDetails` when the connection ends, or `.cancelled`. Its reply carries no
    /// reqId, so, as for every id-less one-shot, a fatal or warning IB error with reqId -1 that arrives while it
    /// waits ends it with `.ib(code:text:)`, related or not, and `ConnectOptions.idlessRequestTimeout` ends it with
    /// `.timeout`.
    public func currentTime() async throws(IBClientError) -> Date {
        try requireConnected()
        let seconds = try await answer(.currentTime) { if case .currentTime(let t) = $0 { t } else { nil } }
        return Date(timeIntervalSince1970: Double(seconds))
    }

    /// The exchanges that offer market depth. An id-less one-shot: it ends like `currentTime()`.
    public func depthExchanges() async throws(IBClientError) -> [DepthMarketDataDescription] {
        try requireConnected()
        return try await answer(.depthExchanges) { if case .depthExchanges(let d) = $0 { d } else { nil } }
    }

    /// The exchanges behind a SMART route, for the `bboExchange` that `Tick.requestParameters` reported. Throws
    /// like `contractDetails` when IB refuses the request.
    public func smartComponents(_ bboExchange: String) async throws(IBClientError) -> [SmartComponent] {
        try requireConnected()
        let id = nextRequestID()
        return try await answer(.smartComponents(requestID: id, bboExchange: bboExchange), id: id) {
            if case .smartComponents(_, let c) = $0 { c } else { nil }
        }
    }

    /// The accounts IB lists for this login now. Only the returned list is fresh: `states()` keeps the accounts seen
    /// at connect. An id-less one-shot: it ends like `currentTime()`.
    public func managedAccounts() async throws(IBClientError) -> [String] {
        try requireConnected()
        return try await answer(.managedAccounts) { if case .managedAccounts(let a) = $0 { a } else { nil } }
    }

    /// The id the next `placeOrder` takes, with IB's answer merged by `max` as at connect. Does not consume it. An
    /// id-less one-shot: it ends like `currentTime()`.
    public func nextOrderID() async throws(IBClientError) -> Int {
        try requireConnected()
        let told = try await answer(.requestIDs) { if case .nextValidID(let n) = $0 { n } else { nil } }
        return max(nextID ?? told, told)   // the message already merged into nextID; a lower answer never lowers it
    }

    /// The white-branding id of the account; `""` for most.
    public func userInfo() async throws(IBClientError) -> String {
        try requireConnected()
        let id = nextRequestID()
        return try await answer(.userInfo(requestID: id), id: id) {
            if case .userInfo(_, let w) = $0 { w } else { nil }
        }
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

    /// Sends `request` and waits for the first message `pick` takes. Without `id` the waiter is an id-less one-shot
    /// keyed by a local negative id: `routeToStream` offers it the id-less messages, oldest waiter first. `cancel` is
    /// sent for a cancelled caller; with `thenCancel` it is also sent after the answer (the termination hop sends it).
    func answer<T: Sendable>(_ request: IBRequest, id: Int? = nil, cancel: IBRequest? = nil, thenCancel: Bool = false,
                             pick: @escaping @Sendable (IBMessage) -> T?) async throws(IBClientError) -> T {
        let key = id ?? nextLocalID()
        let stream = try openStream(request, id: key, cancel: cancel, oneShot: id == nil) {
            (message, out: AsyncThrowingStream<T, any Error>.Continuation) in
            guard let value = pick(message) else { return false }
            out.yield(value); out.finish(); return !thenCancel
        }
        guard let value = try await collect(stream).first else { throw .cancelled }
        return value
    }

    /// Reads a self-ending stream to its end. It ends without error only when its end marker came, or when the
    /// calling task was cancelled.
    func collect<E: Sendable>(_ stream: AsyncThrowingStream<E, any Error>) async throws(IBClientError) -> [E] {
        var got: [E] = []
        do { for try await x in stream { got.append(x) } } catch { throw error as? IBClientError ?? .cancelled }
        if Task.isCancelled { throw .cancelled }
        return got
    }

    /// Receives the fields of every incoming frame after the server hello, in arrival order, on the actor.
    /// Used to record live frames; `nil` removes it.
    func setFrameTap(_ tap: (@Sendable ([String]) -> Void)?) { frameTap = tap }

    var orderSubscriberCount: Int { orderSubscribers.count }
    var stateSubscriberCount: Int { stateSubscribers.count }
    var messageSubscriberCount: Int { messageSubscribers.count }
    var requestStreamCount: Int { requestStreams.count }
    func hasStream(_ key: Int) -> Bool { requestStreams[key] != nil }

    func requireConnected() throws(IBClientError) {
        guard case .connected = state else { throw .notConnected }
    }

    /// A what-if order is never placed: it goes through `whatIfOrder`.
    private func submit(_ id: Int, _ contract: Contract, _ order: Order, verb: String) throws(IBClientError) {
        if order.whatIf { throw .encoding(.unsupported("whatIf")) }
        try send(.placeOrder(orderID: id, contract: contract, order: order))
        log(.info, "\(verb) \(id): \(Self.describe(contract, order))")
        for s in orderTracker.placed(orderID: id, clientID: clientID, contract: contract, order: order) {
            orderSubscribers.yield(s)
            if s.log.last?.message == "Modify" { orderEventSubscribers.yield(.modified(s)) }   // a new id logs ""
        }
    }

    /// An order as the log names it: `BUY 1 AAPL LMT 180`, then the aux price when set.
    private static func describe(_ contract: Contract, _ order: Order) -> String {
        ([order.action.rawValue, "\(order.totalQuantity)", contract.symbol, order.orderType]
            + [order.limitPrice, order.auxPrice].compactMap { $0.map { "\($0)" } }).joined(separator: " ")
    }

    /// Sends any request as is, through the same throttled queue as every call (`ib_async`'s `client.send`). IB's
    /// answers arrive on `messages()` only, and no stream or tracker state is kept for the request: a `placeOrder`
    /// sent this way skips `orders()`'s local `.pendingSubmit`, modify and cancel states. Throws `.notConnected`
    /// without a connection and `.encoding` when the request does not encode, before queuing it.
    public func send(_ request: IBRequest) throws(IBClientError) {
        try enqueue(encode(request))
    }

    private func encode(_ request: IBRequest) throws(IBClientError) -> [UInt8] {
        do { return Frame.encode(try request.body()) } catch { throw .encoding(error) }
    }

    private func enqueue(_ frame: [UInt8]) throws(IBClientError) {
        guard let outbox else { throw .notConnected }
        outbox.yield(frame)
        queuedFrames += 1
        log(.debug, ">>> " + FieldReader(Array(frame.dropFirst(4))).fields.joined(separator: "|"))
    }

    /// The writer wrote one frame of `count` bytes; its queue is empty again when none is left.
    private func wrote(_ count: Int, _ gen: Int) {
        guard gen == generation else { return }
        stats.messagesSent += 1
        stats.bytesSent += count
        queuedFrames -= 1
        if queuedFrames == 0 { setThrottling(false) }
    }

    /// The writer starts waiting on the throttle.
    private func throttleWaits(_ gen: Int) {
        if gen == generation { setThrottling(true) }
    }

    private func setThrottling(_ on: Bool) {
        guard on != isThrottling else { return }
        isThrottling = on
        throttleSubscribers.yield(on)
    }

    /// Sends `request`, then registers its stream; nothing is registered when it does not encode. `resendOn` is the IB
    /// error code on which the same request is cancelled and sent again (`RequestStream.resend`). A `oneShot` gets
    /// a timer of `ConnectOptions.idlessRequestTimeout`, cancelled whenever the stream ends.
    func openStream<Element: Sendable>(
        _ request: IBRequest, id: Int, cancel: IBRequest?, resendOn: Int? = nil, oneShot: Bool = false,
        buffering: AsyncThrowingStream<Element, any Error>.Continuation.BufferingPolicy = .unbounded,
        route: @escaping (IBMessage, AsyncThrowingStream<Element, any Error>.Continuation) -> Bool
    ) throws(IBClientError) -> AsyncThrowingStream<Element, any Error> {
        try send(request)
        let (stream, out) = AsyncThrowingStream.makeStream(of: Element.self, throwing: (any Error).self,
                                                           bufferingPolicy: buffering)
        requestStreams[id] = RequestStream(route: { route($0, out) }, finish: { out.finish(throwing: $0) },
                                           cancel: cancel, resend: resendOn.map { ($0, request) }, oneShot: oneShot)
        let gen = generation
        let timer = oneShot ? options.idlessRequestTimeout.map { bound in
            Task { [weak self] in
                guard (try? await Task.sleep(for: bound)) != nil else { return }
                await self?.oneShotTimedOut(id, gen)
            }
        } : nil
        out.onTermination = { [weak self] _ in
            timer?.cancel()
            Task { await self?.stopped(id, gen) }
        }
        return stream
    }

    /// An id-less one-shot heard nothing within `ConnectOptions.idlessRequestTimeout`.
    private func oneShotTimedOut(_ id: Int, _ gen: Int) {
        guard gen == generation, let s = requestStreams.removeValue(forKey: id) else { return }
        s.finish(.timeout)
    }

    /// The consumer stopped the stream. An entry already gone was finished by the client, which sends no cancel;
    /// `gen` keeps a late stop from touching a stream that reuses the reqId on a later connection.
    private func stopped(_ id: Int, _ gen: Int) {
        guard gen == generation, let s = requestStreams.removeValue(forKey: id) else { return }
        dropSubscription(id)
        if let cancel = s.cancel { try? send(cancel) }   // the cancel encodes: it is all integers
    }

    private func routeToStream(_ message: IBMessage) {
        switch message {
        case .accountSummary(let id, _), .accountSummaryEnd(let id), .pnlSingle(let id, _),
             .contractData(let id, _), .contractDataEnd(let id), .symbolSamples(let id, _), .tick(let id, _),
             .historicalData(let id, _), .historicalDataUpdate(let id, _), .historicalSchedule(let id, _),
             .realTimeBar(let id, _), .depth(let id, _), .tickByTick(let id, _), .historicalTicks(let id, _, _),
             .headTimeStamp(let id, _), .histogramData(let id, _), .tickSnapshotEnd(let id), .userInfo(let id, _),
             .positionMulti(let id, _), .positionMultiEnd(let id), .accountUpdateMulti(let id, _),
             .accountUpdateMultiEnd(let id), .pnl(let id, _), .smartComponents(let id, _),
             .securityDefinitionOptionParameter(let id, _), .securityDefinitionOptionParameterEnd(let id),
             .softDollarTiers(let id, _), .scannerData(let id, _), .newsArticle(let id, _), .historicalNews(let id, _),
             .historicalNewsEnd(let id, _), .fundamentalData(let id, _), .wshMetaData(let id, _),
             .wshEventData(let id, _), .replaceFAEnd(let id, _), .displayGroupList(let id, _),
             .displayGroupUpdated(let id, _), .execDetails(let id, _, _), .execDetailsEnd(let id):
            if requestStreams[id]?.route(message) == true { requestStreams[id] = nil }   // before any termination hop
        case .openOrder(let m) where m.order.whatIf:   // whatIfOrder's answer, keyed by the order id it took
            if requestStreams[m.orderID]?.route(message) == true { requestStreams[m.orderID] = nil }
        case .currentTime, .managedAccounts, .nextValidID, .depthExchanges, .marketRule, .familyCodes,
             // no reqId: the oldest waiter that takes it gets it
             .scannerParameters, .newsProviders, .newsBulletin, .receiveFA, .openOrder, .openOrderEnd,
             .completedOrder, .completedOrdersEnd:
            for key in requestStreams.keys.filter({ $0 < -1 }).sorted(by: >)
                where requestStreams[key]?.route(message) == true {
                requestStreams[key] = nil
                break
            }
        case .error(let e) where requestStreams[e.requestID]?.resend?.onCode == e.code:
            resend(e.requestID)
        case .error(let e) where e.requestID == -1 && ErrorCode.kind(e.code).failsRequest:
            // R16: IB cannot name an id-less one-shot, so any such error may be its refusal and fails each one waiting
            for (key, s) in requestStreams where s.oneShot {
                requestStreams[key] = nil
                s.finish(.ib(code: e.code, text: e.text))
            }
        case .error(let e) where e.requestID == -1:
            // ib.py:414's 1102 re-request: only the streams that resend on this code (bars resend on 10225)
            for key in requestStreams.keys.sorted() where requestStreams[key]?.resend?.onCode == e.code { resend(key) }
        case .error(let e) where ErrorCode.kind(e.code) == .notice:
            if requestStreams[e.requestID]?.route(message) == true { requestStreams[e.requestID] = nil }
        case .error(let e) where ErrorCode.kind(e.code).failsRequest:
            guard let s = requestStreams.removeValue(forKey: e.requestID) else { break }
            dropSubscription(e.requestID)
            if ErrorCode.isNoMarketDataPermission(code: e.code, text: e.text) {
                if let cancel = s.cancel { try? send(cancel) }   // IB keeps a refused subscription open
                s.finish(.noMarketDataPermission(code: e.code, text: e.text))
            } else {
                s.finish(.ib(code: e.code, text: e.text))
            }
        default: break
        }
    }

    /// `ib_async`'s resubscribe (wrapper.py:1694-1721): the stream's cancel, then the same request under the same
    /// reqId; the stream stays open.
    private func resend(_ id: Int) {
        guard let s = requestStreams[id], let resend = s.resend else { return }
        if let cancel = s.cancel { try? send(cancel) }
        try? send(resend.request)   // it encoded when the stream opened
    }

    /// The whole fill an execDetails or commissionReport names when the execution tracker already had it: the sync
    /// replays the day's fills on every connect, and a fresh order tracker still joins them to its orders.
    private func knownFill(_ message: IBMessage) -> [Fill] {
        switch message {
        case .execDetails(_, _, let e): executionTracker.fill(execID: e.execID).map { [$0] } ?? []
        case .commissionReport(let r): executionTracker.fill(execID: r.execID).map { [$0] } ?? []
        default: []
        }
    }

    /// Orders and requests share this one sequence (docs/DECISIONS.md).
    func nextRequestID() -> Int {
        let id = nextID ?? 0
        nextID = id + 1
        return id
    }

    /// Takes the next id from the sequence that orders and requests share, after raising the sequence to at least
    /// `minimum` (`ib_async`'s `getReqId` and `updateReqId`), e.g. for orders linked by `parentID` before placing.
    /// The id is used up: no later call or order takes it. Throws `.notConnected` unless the state is `.connected`.
    public func reserveOrderID(atLeast minimum: Int = 0) throws(IBClientError) -> Int {
        try requireConnected()
        nextID = max(nextID ?? 0, minimum)
        return nextRequestID()
    }

    /// Keys for waiters with no reqId: -2, -3, ... (-1 is IB's "no request" in errors).
    func nextLocalID() -> Int {
        localID -= 1
        return localID
    }

    private func start(_ t: any Transport, _ gen: Int, _ deadline: ContinuousClock.Instant) {
        transport = t
        let (queued, outbox) = AsyncStream.makeStream(of: [UInt8].self)
        self.outbox = outbox
        (stats, startedAt) = (ConnectionStats(startTime: Date(), duration: .zero, bytesReceived: 0, bytesSent: 0,
                                              messagesReceived: 0, messagesSent: 0), .now)
        let (limit, window) = (options.maxRequests, options.requestsInterval)
        Task.detached {   // detached: a blocking write must never hold the actor
            var throttle = Throttle(limit: limit, window: window)
            for await frame in queued {
                let wait = throttle.reserve(at: .now)
                if wait > .zero {
                    await self.throttleWaits(gen)
                    try? await Task.sleep(for: wait)
                }
                do { try t.write(frame) } catch { return await self.closed(error, gen) }
                await self.wrote(frame.count, gen)
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
        let hello = Handshake.hello(connectOptions: options.connectOptions)
        do { try t.write(hello) } catch { return end(error) }
        stats.messagesSent += 1   // as ib_async's connection.sendMsg counts it
        stats.bytesSent += hello.count
    }

    private func receive(_ chunk: [UInt8], _ gen: Int) {
        guard gen == generation else { return }
        lastFrame = .now
        stats.bytesReceived += chunk.count
        do { try frames.append(chunk) } catch { return end(.protocolError(error)) }
        while gen == generation, let body = frames.next() { handle(body) }
    }

    private func handle(_ body: [UInt8]) {
        stats.messagesReceived += 1
        log(.debug, "<<< " + FieldReader(body).fields.joined(separator: "|"))
        guard serverVersion != nil else {   // the first frame answers the hello
            do { serverVersion = try Handshake.parseServerHello(body).serverVersion } catch {
                return end(.protocolError(error))
            }
            do { try send(.startAPI(clientID: clientID, capabilities: options.optionalCapabilities)) } catch {
                return end(error)   // capabilities that are not ASCII
            }
            return
        }
        frameTap?(FieldReader(body).fields)
        let message = IBDecoder.decode(body, gatewayTimeZone: options.gatewayTimeZone)
        messageSubscribers.yield(message)
        for snapshot in orderTracker.apply(message) { orderSubscribers.yield(snapshot) }
        let live = if case .execDetails(-1, _, _) = message { Date() } else { nil as Date? }
        let fills = executionTracker.apply(message, receivedAt: live)
        for fill in fills {
            fillSubscribers.yield(fill)
            let e = fill.execution
            log(.info, "fill \(e.execID): order \(e.orderID) \(e.side) \(e.shares) \(fill.contract.symbol) "
                + "at \(e.price)")
        }
        for fill in fills.isEmpty ? knownFill(message) : fills {
            for s in orderTracker.add(fill) { orderSubscribers.yield(s) }
        }
        if let set = positionTracker.apply(message) { positionSubscribers.yield(set) }
        let foreign = if case .accountUpdateMulti(let id, _) = message { !accountSyncIDs.contains(id) } else { false }
        switch foreign ? nil : accountTracker.apply(message) {
        case .portfolio(let set)?: portfolioSubscribers.yield(set)
        case .value(let v)?: accountValueSubscribers.yield(v)
        case nil: break
        }
        logError(message)
        routeToStream(message)
        recordNews(message)
        switch message {
        case .nextValidID(let n): nextID = max(nextID ?? n, n)
        case .managedAccounts(let a): accounts = a
        case .error(let e) where pendingConnect != nil && e.requestID == -1 && ErrorCode.kind(e.code) == .fatal:
            return end(.ib(code: e.code, text: e.text))   // the connection itself
        case .error(let e) where pendingConnect != nil && ErrorCode.kind(e.code).failsRequest
                && (syncEnds?.contains(.execDetailsEnd(requestID: e.requestID)) == true
                    || accountSyncIDs.contains(e.requestID)):
            // a sync request: fails connect, or is given up so the sync stops waiting for it
            if options.throwsOnSyncError { return end(.ib(code: e.code, text: e.text)) }
            log(.error, "connect: sync request \(e.requestID) given up after IB \(e.code): \(e.text)")
            syncEnds?.removeAll {
                $0 == .execDetailsEnd(requestID: e.requestID) || $0 == .accountUpdateMultiEnd(requestID: e.requestID)
            }
        default: break
        }
        guard pendingConnect != nil else { return }
        if syncEnds == nil {
            guard nextID != nil, accounts != nil else { return }
            sync()
        } else {
            syncEnds?.removeAll { $0 == message }
        }
        if syncEnds == [] { connected() }   // `fetch: []` sends nothing to wait for
    }

    /// IB's warnings and fatal errors as log lines; notices and 202 stay on `messages()`.
    private func logError(_ message: IBMessage) {
        guard case .error(let e) = message else { return }
        switch ErrorCode.kind(e.code) {
        case .warning: log(.warning, "IB warning \(e.code), reqId \(e.requestID): \(e.text)")
        case .fatal: log(.error, "IB error \(e.code), reqId \(e.requestID): \(e.text)")
        case .notice, .orderCancelled: break
        }
    }

    /// `ib_async`'s sync (ib.py:2040-2100), each request under its `options.fetch` flag. Only end markers that
    /// arrive after these requests are counted.
    private func sync() {
        let o = options
        syncEnds = []
        // none of these can fail to encode but reqAccountUpdates: IB's account ids are ASCII, a caller's may not be
        if clientID == 0 { try? send(.autoOpenOrders(true)) }   // binds TWS's manual orders, as ib.py:2046
        if !o.readOnly, o.fetch.contains(.ordersOpen) {
            syncEnds?.append(.openOrderEnd)
            try? send(.allOpenOrders)
        }
        if !o.readOnly, o.fetch.contains(.ordersComplete) {
            syncEnds?.append(.completedOrdersEnd)
            try? send(.completedOrders(apiOnly: false))
        }
        if o.fetch.contains(.executions) {
            let id = nextRequestID()
            syncEnds?.append(.execDetailsEnd(requestID: id))
            try? send(.executions(requestID: id, filter: ExecutionFilter()))
        }
        if o.fetch.contains(.positions) {
            syncEnds?.append(.positionEnd)
            try? send(.positions)
        }
        guard let accounts else { return }
        // reqAccountUpdates: the portfolio too, but for one account at a time
        let named = o.account.flatMap { $0.isEmpty ? nil : $0 } ?? (accounts.count == 1 ? accounts[0] : nil)
        let subscribed = o.fetch.contains(.accountUpdates) ? named : nil
        // another login's state is stale; the subscribed account's set stays until its accountDownloadEnd replaces it
        if accountTracker.prune(to: accounts, keeping: subscribed) {
            portfolioSubscribers.yield(accountTracker.portfolio)
        }
        if let subscribed {
            do { try send(.accountUpdates(subscribe: true, account: subscribed)) } catch { return end(error) }
            accountTracker.reload()
            syncEnds?.append(.accountDownloadEnd(account: subscribed))
        }
        // reqAccountUpdatesMulti per account, as ib.py:2069 (a single account already subscribed needs none)
        let covered = accounts.count == 1 && subscribed == accounts[0]
        guard !covered, accounts.count <= o.maxSyncedSubAccounts, o.fetch.contains(.subAccountUpdates)
        else { return }
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
        (connectTimer, syncEnds, reconnectTask) = (nil, nil, nil)   // a reconnect loop ends with this attempt
        if let every = reconnect?.policy.probeAfter {
            let gen = generation
            probeTask = Task { await probe(every: every, gen) }
        }
        setState(.connected(serverVersion: serverVersion, accounts: accounts))
        pendingConnect?.resume(returning: .success(()))
        pendingConnect = nil
    }

    /// The connect deadline: fails `connect`, or, with `throwsOnSyncError` off and only sync end markers due, logs
    /// them and lets it succeed.
    private func timedOut(_ gen: Int) {
        guard gen == generation, pendingConnect != nil else { return }
        guard let due = syncEnds, !options.throwsOnSyncError else { return end(.timeout) }
        log(.error, "connect: the sync timed out waiting for \(due)")
        connected()
    }

    private func closed(_ error: (any Error)?, _ gen: Int) {
        guard gen == generation else { return }
        end(error.map { $0 as? IBClientError ?? .transport("\($0)") } ?? .connectionClosed)
    }

    /// Every exit path ends here: the transport is closed (its reader thread holds it), the outbox finished,
    /// and anything still in flight from this connection is ignored from now on. `draining` (a clean disconnect)
    /// queues cancelPositions and leaves the close to the writer, with a 2 s bound. A reconnect attempt's end
    /// publishes nothing; a stored policy turns an error on a `.connected` connection into a reconnect.
    private func end(_ error: IBClientError?, draining: Bool = false) {
        var drop: IBClientError?
        if case .connected = state, reconnect != nil { drop = error }
        generation += 1
        probeTask?.cancel()
        probeTask = nil
        if draining, let t = transport {
            try? send(.cancelPositions)   // all integers: encodes
            Task.detached { try? await Task.sleep(for: .seconds(2)); t.close() }   // close() needs no actor
        } else {
            transport?.close()
        }
        outbox?.finish()
        connectTimer?.cancel()
        (transport, outbox, connectTimer, syncEnds, queuedFrames) = (nil, nil, nil, nil, 0)
        setThrottling(false)
        let streams = requestStreams.values
        requestStreams = [:]   // emptied first: their termination then sends no cancel
        (liveBars, accountPnLs, positionPnLs, tickerRegistry) = ([:], [:], [:], [:])
        wshMetaRequestID = nil   // a reqId belongs to one connection
        for s in streams { s.finish(error ?? .connectionClosed) }
        if reconnectTask == nil { setState(.disconnected(error)) }
        pendingConnect?.resume(returning: .failure(error ?? .connectionClosed))
        pendingConnect = nil
        if let drop {
            setState(.connecting)
            reconnectTask = Task { await reconnectLoop(after: drop) }
        }
    }

    private func setState(_ new: ConnectionState) {
        guard new != state else { return }
        state = new
        log(.info, "\(new)")
        stateSubscribers.yield(new)
    }

    private func unsubscribe(state id: Int) { stateSubscribers.remove(id) }
    private func unsubscribe(message id: Int) { messageSubscribers.remove(id) }
    private func unsubscribe(order id: Int) { orderSubscribers.remove(id) }
    private func unsubscribe(orderEvent id: Int) { orderEventSubscribers.remove(id) }
    private func unsubscribe(fill id: Int) { fillSubscribers.remove(id) }
    private func unsubscribe(position id: Int) { positionSubscribers.remove(id) }
    private func unsubscribe(portfolio id: Int) { portfolioSubscribers.remove(id) }
    private func unsubscribe(accountValue id: Int) { accountValueSubscribers.remove(id) }
    func unsubscribe(throttling id: Int) { throttleSubscribers.remove(id) }
}
