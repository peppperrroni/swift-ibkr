import Foundation

extension IBClient {
    /// This client's open orders as IB lists them now (reqOpenOrders, `ib_async`'s `reqOpenOrders`): the `orders()`
    /// snapshot of each order IB sent before its end marker, in arrival order, with IB's answer already folded in.
    /// An id-less one-shot: it ends like `currentTime()`.
    public func fetchOpenOrders() async throws(IBClientError) -> [OrderSnapshot] {
        try await listedOrders(.openOrders, until: .openOrderEnd)
    }

    /// Every API client's open orders and TWS's own (reqAllOpenOrders, `ib_async`'s `reqAllOpenOrders`), as
    /// `fetchOpenOrders()` returns them.
    public func fetchAllOpenOrders() async throws(IBClientError) -> [OrderSnapshot] {
        try await listedOrders(.allOpenOrders, until: .openOrderEnd)
    }

    /// The orders IB lists as completed (reqCompletedOrders; `apiOnly` leaves out orders placed in TWS), as
    /// `fetchOpenOrders()` returns them.
    public func completedOrders(apiOnly: Bool = false) async throws(IBClientError) -> [OrderSnapshot] {
        try await listedOrders(.completedOrders(apiOnly: apiOnly), until: .completedOrdersEnd)
    }

    /// The fills of the executions IB lists for `filter` (reqExecutions, `ib_async`'s `reqExecutions`), in arrival
    /// order, read at IB's end marker from the fills `executions()` keeps. IB sends each commission report before
    /// that marker (recorded live); an execution still without one is left out and logged at `.warning`. Throws
    /// like `contractDetails` on IB's error for its reqId or the connection ending.
    public func executions(filter: ExecutionFilter) async throws(IBClientError) -> [Fill] {
        try requireConnected()
        let id = nextRequestID()
        var listed: [String] = []
        return try await collect(try openStream(.executions(requestID: id, filter: filter), id: id, cancel: nil) {
            (message, out: AsyncThrowingStream<Fill, any Error>.Continuation) in
            switch message {
            case .execDetails(_, _, let e): listed.append(e.execID); return false
            case .execDetailsEnd:
                for execID in listed {
                    if let fill = self.executionTracker.fill(execID: execID) { out.yield(fill) }
                    else { self.log(.warning, "executions: \(execID) has no commission report yet, left out") }
                }
                out.finish(); return true
            default: return false
            }
        })
    }

    /// Sends `request` and lists the tracker's snapshot of every order IB names in its answer, at `end`.
    private func listedOrders(_ request: IBRequest, until end: IBMessage) async throws(IBClientError) -> [OrderSnapshot] {
        try requireConnected()
        var listed: [(orderID: Int, clientID: Int, permID: Int)] = []
        return try await collect(try openStream(request, id: nextLocalID(), cancel: nil, oneShot: true) {
            (message, out: AsyncThrowingStream<OrderSnapshot, any Error>.Continuation) in
            switch message {
            case .openOrder(let m) where end == .openOrderEnd: listed.append((m.orderID, m.clientID, m.permID))
            case .completedOrder(let m) where end == .completedOrdersEnd: listed.append((0, 0, m.permID))
            case end:
                // `handle` applied each message to the tracker before routing it here
                let orders = self.orderTracker.orders
                for o in listed {
                    let match = orders.last {
                        o.permID > 0 ? $0.permID == o.permID : ($0.orderID, $0.clientID) == (o.orderID, o.clientID)
                    }
                    if let match { out.yield(match) }
                }
                out.finish(); return true
            default: break
            }
            return false
        })
    }
}
