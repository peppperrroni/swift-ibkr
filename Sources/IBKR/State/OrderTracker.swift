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
}

/// `.api` when the order has an id on this API, else IB's permanent id (manual and completed orders).
public enum OrderKey: Hashable, Sendable {
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
    private var ownClientID: Int?

    public init() {}

    /// First-seen order.
    public var orders: [OrderSnapshot] { snaps }

    public mutating func sent(orderID: Int, clientID: Int, contract: Contract, order: Order) {
        sentOrders[.api(clientID: clientID, orderID: orderID)] = (contract, order)
        ownClientID = clientID
    }

    public mutating func apply(_ message: IBMessage) -> [OrderSnapshot] {
        switch message {
        case .openOrder(let m):
            let key = Self.key(m.orderID, m.clientID, m.permID)
            let heldStatus = held.removeValue(forKey: key)
            return upsert(key, m.permID, new: Self.blank(m.contract, m.order)) { s in
                s.orderID = m.orderID; s.clientID = m.clientID; s.permID = m.permID
                s.contract = m.contract; s.order = m.order; s.status = m.status
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
            if m.status == .filled { fresh.filled = m.order.totalQuantity; fresh.remaining = 0 }
            return upsert(.permanent(m.permID), m.permID, new: fresh) { s in
                s.contract = m.contract; s.order = m.order; s.status = m.status; s.completedTime = m.completedTime
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
            if !s.status.isFinal { s.status = .inactive }
        }
    }

    /// IB reports order errors with the orderId as reqId, with no client id. This connection's order wins
    /// (`sent` fixes its client id); with no `sent` a lone candidate is taken and an ambiguous id matches none.
    private func errorKey(_ id: Int) -> OrderKey? {
        guard id > 0 else { return nil }
        var candidates = Set(keyIndex.keys).union(sentOrders.keys).filter {
            if case .api(_, let o) = $0 { return o == id } else { return false }
        }
        if let own = ownClientID { candidates = candidates.filter { $0 == .api(clientID: own, orderID: id) } }
        return candidates.count == 1 ? candidates.first : nil
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
