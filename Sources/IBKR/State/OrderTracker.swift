import Foundation

/// One order as the tracker has merged it from this client's own calls, openOrder, orderStatus, completedOrder,
/// order errors and fills (`ib_async`'s `Trade`).
public struct OrderSnapshot: Sendable, Equatable, Encodable {
    /// The order's id on this API; `0` for a manual or completed order that has none.
    public var orderID: Int
    /// The client id the order belongs to.
    public var clientID: Int
    /// IB's permanent id for the order.
    public var permID: Int
    /// The order's contract.
    public var contract: Contract
    /// The order as IB last reported it, or as this client last sent it.
    public var order: Order
    /// The order's status: IB's, or the local `.pendingSubmit`, `.pendingCancel`, `.cancelled` or
    /// `.validationError` this client set.
    public var status: OrderStatus
    /// Shares or contracts filled so far.
    public var filled: Decimal
    /// Shares or contracts still open.
    public var remaining: Decimal
    /// The average price of the fills so far; `nil` before the first.
    public var averageFillPrice: Decimal?
    /// The price of the latest fill; `nil` before the first.
    public var lastFillPrice: Decimal?
    /// Why IB holds the order, from orderStatus; empty when it does not.
    public var whyHeld: String
    /// IB's text from a warning or error on the order, or from a 202 cancellation that names a reason; `nil`
    /// otherwise, and cleared when `modifyOrder` re-sends the order (the text stays in `log`).
    public var rejectReason: String?
    /// IB's text for when a completed order finished, from completedOrder; `nil` for a live order.
    public var completedTime: String?
    /// The advanced-reject JSON IB attaches to an order error; `nil` when it sent none.
    public var advancedOrderRejectJSON: String?
    /// IB's price cap from orderStatus (`ib_async`'s `mktCapPrice`); `nil` when IB sends none.
    public var marketCapPrice: Decimal?
    /// The order's history, oldest first: local states, status changes, modifications, fills and errors. Empty for an
    /// order first seen through openOrder or completedOrder, as in `ib_async`.
    public var log: [TradeLogEntry]
    /// The order's fills in arrival order, a correction replacing the fill it corrects.
    public var fills: [Fill]

    /// Filled plus remaining: the order's whole size as IB reports it (`ib_async`'s `OrderStatus.total`).
    public var total: Decimal { filled + remaining }
    /// Whether the order can still execute (`OrderStatus.isActive`).
    public var isActive: Bool { status.isActive }
    /// Whether the order is sent but not yet working (`OrderStatus.isWaiting`).
    public var isWaiting: Bool { status.isWaiting }
    /// Whether the order works at the exchanges (`OrderStatus.isWorking`).
    public var isWorking: Bool { status.isWorking }

    /// A snapshot of these values; the prices, reject reason, completed time, reject JSON and price cap default to
    /// `nil`, the log and the fills to empty.
    public init(
        orderID: Int,
        clientID: Int,
        permID: Int,
        contract: Contract,
        order: Order,
        status: OrderStatus,
        filled: Decimal,
        remaining: Decimal,
        averageFillPrice: Decimal? = nil,
        lastFillPrice: Decimal? = nil,
        whyHeld: String,
        rejectReason: String? = nil,
        completedTime: String? = nil,
        advancedOrderRejectJSON: String? = nil,
        marketCapPrice: Decimal? = nil,
        log: [TradeLogEntry] = [],
        fills: [Fill] = []
    ) {
        self.orderID = orderID
        self.clientID = clientID
        self.permID = permID
        self.contract = contract
        self.order = order
        self.status = status
        self.filled = filled
        self.remaining = remaining
        self.averageFillPrice = averageFillPrice
        self.lastFillPrice = lastFillPrice
        self.whyHeld = whyHeld
        self.rejectReason = rejectReason
        self.completedTime = completedTime
        self.advancedOrderRejectJSON = advancedOrderRejectJSON
        self.marketCapPrice = marketCapPrice
        self.log = log
        self.fills = fills
    }
}

/// `.api` when the order has an id on this API, else IB's permanent id (manual and completed orders).
enum OrderKey: Hashable, Sendable {
    case api(clientID: Int, orderID: Int)
    case permanent(Int)
}

/// Merges this client's order calls and IB's separate order messages into whole snapshots, after `ib_async`'s
/// `Trade` bookkeeping. Pure value, no I/O: the owner publishes whatever each call returns.
public struct OrderTracker: Sendable {
    private var snaps: [OrderSnapshot] = []
    private var keyIndex: [OrderKey: Int] = [:]
    private var permIndex: [Int: Int] = [:]
    private var held: [OrderKey: OrderStatusMessage] = [:]
    // Filled openOrders that came before their fill's orderStatus
    private var heldOpen: [OrderKey: OpenOrderMessage] = [:]
    private let ownClientID: Int

    /// `clientID` is this connection's: IB sends order errors only to the owning client, so errors match its
    /// orders only.
    public init(clientID: Int) { ownClientID = clientID }

    /// Every order seen so far, in the order each was first seen.
    public var orders: [OrderSnapshot] { snaps }

    /// Records an order this client sent. A new id gives a `.pendingSubmit` snapshot logged at `time`. A known
    /// order that is not final is a modification: its order and contract are replaced, `rejectReason` is cleared
    /// and the log gains `"Modify"`. A final one is left alone (IB answers the re-sent order itself). Returns the
    /// snapshot it changed, or nothing.
    public mutating func placed(orderID: Int, clientID: Int, contract: Contract, order: Order,
                                at time: Date = Date()) -> [OrderSnapshot] {
        let key = OrderKey.api(clientID: clientID, orderID: orderID)
        if let i = keyIndex[key] {
            guard !snaps[i].status.isFinal else { return [] }
            return upsert(key, 0, new: nil) { s in
                let parentPermID = s.order.parentPermID
                s.contract = contract; s.order = order; s.rejectReason = nil
                s.order.parentPermID = order.parentPermID ?? parentPermID
                s.log.append(TradeLogEntry(time: time, status: s.status, message: "Modify"))
            }
        }
        var s = Self.blank(contract, order)
        s.orderID = orderID; s.clientID = clientID; s.status = .pendingSubmit
        s.log = [TradeLogEntry(time: time, status: .pendingSubmit)]
        return upsert(key, 0, new: s) { _ in }
    }

    /// Records an order this client sent; it now publishes the `.pendingSubmit` snapshot at once, as `placed` does.
    @available(*, deprecated, renamed: "placed(orderID:clientID:contract:order:at:)")
    public mutating func sent(orderID: Int, clientID: Int, contract: Contract, order: Order) {
        _ = placed(orderID: orderID, clientID: clientID, contract: contract, order: order)
    }

    /// Records this client's cancel of its order `orderID`: a known order that is not final becomes `.cancelled`
    /// when it is `.pendingSubmit` with `transmit` off (or `.inactive`), else `.pendingCancel`, logged at `time`.
    /// An unknown or final order changes nothing.
    public mutating func cancelRequested(orderID: Int, at time: Date = Date()) -> [OrderSnapshot] {
        let key = OrderKey.api(clientID: ownClientID, orderID: orderID)
        guard let i = keyIndex[key], !snaps[i].status.isFinal else { return [] }
        return upsert(key, 0, new: nil) { s in
            // ib.py:836; `.inactive` is final here, as in ib_async's DoneStates, so only the first half applies
            s.status = s.status == .pendingSubmit && !s.order.transmit || s.status == .inactive ? .cancelled : .pendingCancel
            s.log.append(TradeLogEntry(time: time, status: s.status))
        }
    }

    /// Joins a whole fill to its order, found by the execution's permID, else its client and order id. A fill
    /// already there changes nothing; a correction replaces the fill it corrects. Logs `"Fill <shares>@<price>"`.
    /// A fill of an order the tracker does not know changes nothing.
    public mutating func add(_ fill: Fill, at time: Date = Date()) -> [OrderSnapshot] {
        let e = fill.execution
        let key = Self.key(e.orderID, e.clientID, e.permID)
        let found = (e.permID > 0 ? permIndex[e.permID] : nil) ?? keyIndex[key]
        guard let i = found else { return [] }
        let correctionKey = ExecutionTracker.correctionKey(e.execID)
        return upsert(Self.key(snaps[i].orderID, snaps[i].clientID, snaps[i].permID), snaps[i].permID, new: nil) { s in
            if let j = s.fills.firstIndex(where: { ExecutionTracker.correctionKey($0.execution.execID) == correctionKey }) {
                guard s.fills[j] != fill else { return }
                s.fills[j] = fill
            } else {
                s.fills.append(fill)
            }
            s.log.append(TradeLogEntry(time: time, status: s.status, message: "Fill \(e.shares)@\(e.price)"))
        }
    }

    /// Folds in openOrder, orderStatus, completedOrder, the order-bound notice or an order error, logging at
    /// `time`; returns the snapshot it changed, or nothing. Other messages, and what-if openOrders, change nothing.
    public mutating func apply(_ message: IBMessage, at time: Date = Date()) -> [OrderSnapshot] {
        switch message {
        case .openOrder(let m) where m.order.whatIf:
            return []   // a what-if answer, not a live order: whatIfOrder takes it
        case .openOrder(let m):
            let key = Self.key(m.orderID, m.clientID, m.permID)
            let known = index(key, m.permID) != nil
            let heldStatus = held.removeValue(forKey: key)
            let edit = { (s: inout OrderSnapshot) in
                let prior = s.status
                Self.applyOpen(m, into: &s)
                if let h = heldStatus { Self.merge(h, into: &s) }
                // ib_async's openOrder never sets the status; here it does, so its change is logged as orderStatus's
                if known && s.status != prior { s.log.append(TradeLogEntry(time: time, status: s.status)) }
            }
            if m.status == .filled {
                // IB sends a fill's openOrder before its orderStatus: don't publish Filled with filled 0
                var s = index(key, m.permID).map { snaps[$0] } ?? Self.blank(m.contract, m.order)
                edit(&s)
                if s.filled == 0 || s.remaining > 0 {
                    heldOpen[key] = m   // a part-filled order waits for its last fill too
                    return []
                }
            }
            heldOpen[key] = nil
            return upsert(key, m.permID, new: Self.blank(m.contract, m.order), edit)
        case .orderStatus(let m):
            let key = Self.key(m.orderID, m.clientID, m.permID)
            let open = takeHeldOpen(key, m.permID)
            guard index(key, m.permID) != nil || open != nil else { held[key] = m; return [] }
            return upsert(key, m.permID, new: open.map { Self.blank($0.contract, $0.order) }) { s in
                let before = s
                if let o = open { Self.applyOpen(o, into: &s) }
                Self.merge(m, into: &s)
                if s != before {
                    s.log.append(TradeLogEntry(time: time, status: s.status))
                } else if m.status == .submitted, s.log.last?.message == "Modify" {
                    s.log.append(TradeLogEntry(time: time, status: s.status, message: "Modified"))   // IB acknowledged it
                }
            }
        case .completedOrder(let m):
            // the held Filled openOrder has the ids and the full order
            let open = takeHeldOpen(.permanent(m.permID), m.permID)
            var fresh = open.map { Self.blank($0.contract, $0.order) } ?? Self.blank(m.contract, m.order)
            fresh.permID = m.permID
            let key = open.map { Self.key($0.orderID, $0.clientID, $0.permID) } ?? .permanent(m.permID)
            let known = index(key, m.permID) != nil
            return upsert(key, m.permID, new: fresh) { s in
                let prior = s.status
                if let o = open { Self.applyOpen(o, into: &s) }
                if m.filledQuantity > s.filled {
                    // a filled one arrives with totalQuantity 0: the remaining uses the snapshot's
                    s.filled = m.filledQuantity; s.remaining = max(0, s.order.totalQuantity - s.filled)
                }
                // a joined order keeps its own order/contract: v178 completedOrder lacks parentID etc.
                s.status = m.status; s.completedTime = m.completedTime
                s.order.parentPermID = m.order.parentPermID
                if known && s.status != prior { s.log.append(TradeLogEntry(time: time, status: s.status)) }
            }
        case .orderBound(let permID, let clientID, let orderID):
            return upsert(.api(clientID: clientID, orderID: orderID), permID, new: nil) { s in
                s.orderID = orderID; s.clientID = clientID
            }
        case .error(let e):
            return apply(e, at: time)
        default:
            return []
        }
    }

    // MARK: -

    /// Every error but a notice is logged with its code. A warning makes an unfinished order `.validationError`
    /// (`ib_async`'s rule); a fatal one makes it `.inactive` only before IB acknowledged it (no permID yet), so a
    /// reject after a warning still ends the order; 202 cancels.
    private mutating func apply(_ e: IBErrorMessage, at time: Date) -> [OrderSnapshot] {
        let kind = ErrorCode.kind(e.code)
        guard kind != .notice, let key = errorKey(e.requestID) else { return [] }
        return upsert(key, 0, new: nil) { s in
            if !e.advancedOrderRejectJSON.isEmpty { s.advancedOrderRejectJSON = e.advancedOrderRejectJSON }
            switch kind {
            case .orderCancelled:
                s.status = .cancelled
                if let r = e.text.range(of: "reason:"),
                   !e.text[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    s.rejectReason = e.text
                }
            case .warning:
                s.rejectReason = e.text
                if !s.status.isFinal { s.status = .validationError }   // the order still lives at IB
            default:
                s.rejectReason = e.text
                // once IB acknowledged the order (openOrder/orderStatus give it a permID), its own status wins
                if s.permID == 0 && !s.status.isFinal { s.status = .inactive }
            }
            s.log.append(TradeLogEntry(time: time, status: s.status, message: e.text, errorCode: e.code))
        }
    }

    /// IB reports order errors with the orderId as reqId and sends them only to the owning client.
    private func errorKey(_ id: Int) -> OrderKey? {
        id > 0 ? .api(clientID: ownClientID, orderID: id) : nil
    }

    private static func key(_ orderID: Int, _ clientID: Int, _ permID: Int) -> OrderKey {
        orderID > 0 ? .api(clientID: clientID, orderID: orderID) : .permanent(permID)
    }

    private static func blank(_ contract: Contract, _ order: Order) -> OrderSnapshot {
        OrderSnapshot(orderID: 0, clientID: 0, permID: 0, contract: contract, order: order, status: .apiPending,
                      filled: 0, remaining: order.totalQuantity, whyHeld: "")
    }

    private static func applyOpen(_ m: OpenOrderMessage, into s: inout OrderSnapshot) {
        let prior = s.status
        s.orderID = m.orderID; s.clientID = m.clientID; s.permID = m.permID
        let parentPermID = s.order.parentPermID   // openOrder never carries it: keep what a completedOrder gave
        s.contract = m.contract; s.order = m.order; s.status = m.status
        s.order.parentPermID = m.order.parentPermID ?? parentPermID
        if prior.isFinal && !m.status.isFinal { s.status = prior }
    }

    /// The held Filled openOrder for this key, else for this permID.
    private mutating func takeHeldOpen(_ key: OrderKey, _ permID: Int) -> OpenOrderMessage? {
        let k = heldOpen[key] != nil ? key : heldOpen.first { permID > 0 && $0.value.permID == permID }?.key
        return k.flatMap { heldOpen.removeValue(forKey: $0) }
    }

    private func index(_ key: OrderKey, _ permID: Int) -> Int? {
        keyIndex[key] ?? (permID > 0 ? permIndex[permID] : nil)
    }

    private static func merge(_ m: OrderStatusMessage, into s: inout OrderSnapshot) {
        if m.orderID > 0 { s.orderID = m.orderID; s.clientID = m.clientID }
        if m.permID > 0 { s.permID = m.permID }
        s.status = m.status; s.filled = m.filled; s.remaining = m.remaining
        s.averageFillPrice = m.averageFillPrice; s.lastFillPrice = m.lastFillPrice; s.whyHeld = m.whyHeld
        s.marketCapPrice = m.marketCapPrice
    }

    /// Finds the order by key, then by permID; edits it (or `new`, when there is none) and indexes both
    /// ids. Returns the snapshot only if the edit changed it.
    private mutating func upsert(_ key: OrderKey, _ permID: Int, new: OrderSnapshot?,
                                 _ edit: (inout OrderSnapshot) -> Void) -> [OrderSnapshot] {
        let found = index(key, permID)
        let before = found.map { snaps[$0] }
        guard var s = before ?? new else { return [] }
        edit(&s)
        guard s != before else { return [] }
        let i = found ?? snaps.count
        if found == nil { snaps.append(s) } else { snaps[i] = s }
        keyIndex[key] = i
        if s.permID > 0 { permIndex[s.permID] = i }
        return [s]
    }
}
