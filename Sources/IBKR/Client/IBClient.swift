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

    /// Returns once the handshake is done and open orders, completed orders and executions are synced.
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
        orderTracker = OrderTracker(clientID: clientID)
        executionTracker = ExecutionTracker()
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

    /// Encodes, frames and queues; throws before queuing when the request does not encode.
    func send(_ request: IBRequest) throws(IBClientError) {
        guard let outbox else { throw .notConnected }
        let body: [UInt8]
        do { body = try request.body() } catch { throw .encoding(error) }
        outbox.yield(Frame.encode(body))
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
        let message = IBDecoder.decode(body)
        messageSubscribers.yield(message)
        _ = orderTracker.apply(message)       // Task 4 publishes what the trackers return
        _ = executionTracker.apply(message)
        switch message {
        case .nextValidID(let n): nextID = max(nextID ?? n, n)
        case .managedAccounts(let a): accounts = a
        case .error(let e) where pendingConnect != nil && e.requestID == -1 && ErrorCode.kind(e.code) == .fatal:
            return end(.ib(code: e.code, text: e.text))
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
        syncEnds = [.openOrderEnd, .completedOrdersEnd, .execDetailsEnd(requestID: executionsID)]
        try? send(.allOpenOrders)   // none of the three can fail to encode
        try? send(.completedOrders(apiOnly: false))
        try? send(.executions(requestID: executionsID, filter: ExecutionFilter()))
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
}
