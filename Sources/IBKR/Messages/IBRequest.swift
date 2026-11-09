public enum IBRequest: Sendable, Equatable {
    case startAPI(clientID: Int, capabilities: String)
    case requestIDs
    case cancelOrder(orderID: Int, manualCancelTime: String)
    case openOrders
    case allOpenOrders
    case autoOpenOrders(Bool)
    case completedOrders(apiOnly: Bool)
    case executions(requestID: Int, filter: ExecutionFilter)

    /// Fields only; the caller frames them. Field order is docs/protocol-178.md.
    func body() throws(IBEncodingError) -> [UInt8] {
        var w = FieldWriter()
        switch self {
        case .startAPI(let id, let caps):
            w.add(71); w.add(2); w.add(id); try w.add(caps)
        case .requestIDs:
            w.add(8); w.add(1); w.add(1)
        case .cancelOrder(let id, let t):
            w.add(4); w.add(1); w.add(id); try w.add(t)
        case .openOrders:
            w.add(5); w.add(1)
        case .allOpenOrders:
            w.add(16); w.add(1)
        case .autoOpenOrders(let bind):
            w.add(15); w.add(1); w.add(bind)
        case .completedOrders(let apiOnly):
            w.add(99); w.add(apiOnly)
        case .executions(let reqID, let f):
            w.add(7); w.add(3); w.add(reqID)
            w.add(f.clientID ?? 0)  // the table's default; an empty field is not what IB's client sends
            try w.add(f.account); try w.add(f.time); try w.add(f.symbol)
            try w.add(f.secType); try w.add(f.exchange); try w.add(f.side)
        }
        return w.body
    }
}
