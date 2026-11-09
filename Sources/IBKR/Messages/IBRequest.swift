public enum IBRequest: Sendable, Equatable {
    case startAPI(clientID: Int, capabilities: String)
    case requestIDs
    case cancelOrder(orderID: Int, manualCancelTime: String)
    case openOrders
    case allOpenOrders
    case autoOpenOrders(Bool)
    case completedOrders(apiOnly: Bool)
    case executions(requestID: Int, filter: ExecutionFilter)
    case placeOrder(orderID: Int, contract: Contract, order: Order)

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
        case .placeOrder(let id, let c, let o):
            try Self.placeOrder(&w, id, c, o)
        }
        return w.body
    }

    /// The base case of the table: plain order, no BAG / delta-neutral / scale / hedge / algo / PEG / conditions.
    /// Every unmodelled field carries the table's default; row numbers are the table's.
    private static func placeOrder(_ w: inout FieldWriter, _ id: Int, _ c: Contract, _ o: Order) throws(IBEncodingError) {
        func raw(_ values: String...) throws(IBEncodingError) { for v in values { try w.add(v) } }
        w.add(3); w.add(id)
        w.add(c.conID); try w.add(c.symbol); try w.add(c.secType); try w.add(c.lastTradeDateOrContractMonth)
        if let k = c.strike { w.add(k) } else { try raw("0.0") }
        try w.add(c.right); try w.add(c.multiplier); try w.add(c.exchange); try w.add(c.primaryExchange)
        try w.add(c.currency); try w.add(c.localSymbol); try w.add(c.tradingClass)
        try raw("", "")                                           // 14-15 secIdType, secId
        try w.add(o.action.rawValue); w.add(o.totalQuantity); try w.add(o.orderType)
        w.add(o.limitPrice); w.add(o.auxPrice)
        try w.add(o.tif); try w.add(o.ocaGroup); try w.add(o.account)
        try raw("O", "0"); try w.add(o.orderRef)                  // 24-26 openClose, origin, orderRef
        w.add(o.transmit); w.add(o.parentID)
        try raw("0", "0", "0", "0"); w.add(o.outsideRTH); try raw("0")  // 29-34
        try raw("", "0.0", "", "", "", "", "", "")                // 35-42
        try raw("0", "", "-1"); w.add(o.ocaType)                  // 43-46
        try raw("", "", "0", "", "", "0", "0", "")                // 47-54
        try raw("0", "", "", "", "", "")                          // 55-60
        try raw("0", "", "", "", "")                              // 61-65
        try raw("0", "", "", "", "", "", "", "")                  // 66-73
        try raw("", "", "")                                       // 74-76
        try raw("0", "", "", "0", "0")                            // 77-81
        try raw("", "", "0", "", "0", "0", "0")                   // 82-88
        try raw("0")                                              // 89 conditionsCount
        try raw("", "", "", "", "", "", "0", "", "", "")          // 90-99
        try raw("", "", "", "", "")                               // 100-104
        try raw("0", "0", "0", "0")                               // 105-108
        try raw("", "", "0", "", "")                              // 109-113
    }
}
