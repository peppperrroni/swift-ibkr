import Foundation

public struct OrderSnapshot: Sendable, Equatable {
    public var orderID: Int
    public var clientID: Int
    public var permID: Int
    public var contract: Contract
    public var order: Order
    public var status: OrderStatus
    public var filled: Decimal
    public var remaining: Decimal
    public var averageFillPrice: Decimal?
    public var lastFillPrice: Decimal?
    public var whyHeld: String
    public var rejectReason: String?
    public var completedTime: String?

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
        completedTime: String? = nil
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
    }
}

/// `.api` when the order has an id on this API, else IB's permanent id (manual and completed orders).
enum OrderKey: Hashable, Sendable {
    case api(clientID: Int, orderID: Int)
    case permanent(Int)
}

/// Merges IB's separate order messages into whole snapshots. Pure value, no I/O: the owner publishes
/// whatever `apply` returns.
public struct OrderTracker: Sendable {
    private var snaps: [OrderSnapshot] = []
    private var keyIndex: [OrderKey: Int] = [:]
    private var permIndex: [Int: Int] = [:]
    private var held: [OrderKey: OrderStatusMessage] = [:]
    private var sentOrders: [OrderKey: (contract: Contract, order: Order)] = [:]
    private let ownClientID: Int

    /// `clientID` is this connection's: IB sends order errors only to the owning client, so errors match its orders only.
    public init(clientID: Int) { ownClientID = clientID }

    /// First-seen order.
    public var orders: [OrderSnapshot] { snaps }

    public mutating func sent(orderID: Int, clientID: Int, contract: Contract, order: Order) {
        sentOrders[.api(clientID: clientID, orderID: orderID)] = (contract, order)
    }

    public mutating func apply(_ message: IBMessage) -> [OrderSnapshot] {
        switch message {
        case .openOrder(let m):
            let key = Self.key(m.orderID, m.clientID, m.permID)
            let heldStatus = held.removeValue(forKey: key)
            return upsert(key, m.permID, new: Self.blank(m.contract, m.order)) { s in
                let prior = s.status
                s.orderID = m.orderID; s.clientID = m.clientID; s.permID = m.permID
                s.contract = m.contract; s.order = m.order; s.status = m.status
                if prior.isFinal && !m.status.isFinal { s.status = prior }
                if let h = heldStatus { Self.merge(h, into: &s) }
            }
        case .orderStatus(let m):
            let key = Self.key(m.orderID, m.clientID, m.permID)
            let known = keyIndex[key] != nil || (m.permID > 0 && permIndex[m.permID] != nil)
            guard known || sentOrders[key] != nil else { held[key] = m; return [] }
            return upsert(key, m.permID, new: sentSnapshot(key)) { Self.merge(m, into: &$0) }
        case .completedOrder(let m):
            var fresh = Self.blank(m.contract, m.order)
            fresh.permID = m.permID
            fresh.filled = m.filledQuantity; fresh.remaining = max(0, m.order.totalQuantity - m.filledQuantity)  // a filled one arrives with totalQuantity 0
            return upsert(.permanent(m.permID), m.permID, new: fresh) { s in
                s.status = m.status; s.completedTime = m.completedTime  // a joined order keeps its own order/contract: v178 completedOrder lacks parentID etc.
            }
        case .orderBound(let permID, let clientID, let orderID):
            return upsert(.api(clientID: clientID, orderID: orderID), permID, new: nil) { s in
                s.orderID = orderID; s.clientID = clientID
            }
        case .error(let e):
            return apply(e)
        default:
            return []
        }
    }

    // MARK: -

    private mutating func apply(_ e: IBErrorMessage) -> [OrderSnapshot] {
        let kind = ErrorCode.kind(e.code)
        guard kind != .notice, let key = errorKey(e.requestID) else { return [] }
        return upsert(key, 0, new: sentSnapshot(key)) { s in
            if kind == .orderCancelled { s.status = .cancelled; return }
            s.rejectReason = e.text
            if kind == .fatal, s.status == .apiPending { s.status = .inactive }  // once IB acknowledged the order, its own status wins
        }
    }

    /// IB reports order errors with the orderId as reqId and sends them only to the owning client.
    private func errorKey(_ id: Int) -> OrderKey? {
        id > 0 ? .api(clientID: ownClientID, orderID: id) : nil
    }

    private func sentSnapshot(_ key: OrderKey) -> OrderSnapshot? {
        guard case .api(let c, let o) = key, let s = sentOrders[key] else { return nil }
        var snap = Self.blank(s.contract, s.order)
        snap.orderID = o; snap.clientID = c
        return snap
    }

    private static func key(_ orderID: Int, _ clientID: Int, _ permID: Int) -> OrderKey {
        orderID > 0 ? .api(clientID: clientID, orderID: orderID) : .permanent(permID)
    }

    private static func blank(_ contract: Contract, _ order: Order) -> OrderSnapshot {
        OrderSnapshot(orderID: 0, clientID: 0, permID: 0, contract: contract, order: order, status: .apiPending,
                      filled: 0, remaining: order.totalQuantity, whyHeld: "")
    }

    private static func merge(_ m: OrderStatusMessage, into s: inout OrderSnapshot) {
        if m.orderID > 0 { s.orderID = m.orderID; s.clientID = m.clientID }
        if m.permID > 0 { s.permID = m.permID }
        s.status = m.status; s.filled = m.filled; s.remaining = m.remaining
        s.averageFillPrice = m.averageFillPrice; s.lastFillPrice = m.lastFillPrice; s.whyHeld = m.whyHeld
    }

    /// Finds the order by key, then by permID; edits it (or `new`, when there is none) and indexes both
    /// ids. Returns the snapshot only if the edit changed it.
    private mutating func upsert(_ key: OrderKey, _ permID: Int, new: OrderSnapshot?,
                                 _ edit: (inout OrderSnapshot) -> Void) -> [OrderSnapshot] {
        let found = keyIndex[key] ?? (permID > 0 ? permIndex[permID] : nil)
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
