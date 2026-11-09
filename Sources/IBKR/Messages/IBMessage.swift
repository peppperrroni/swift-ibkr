public struct IBErrorMessage: Sendable, Equatable {
    public var requestID: Int
    public var code: Int
    public var text: String
    public var advancedOrderRejectJSON: String
}

public enum IBMessage: Sendable, Equatable {
    case orderStatus(OrderStatusMessage)
    case error(IBErrorMessage)
    case nextValidID(Int)
    case managedAccounts([String])
    case currentTime(Int)
    case openOrder(OpenOrderMessage)
    case openOrderEnd
    case completedOrder(CompletedOrderMessage)
    case execDetails(requestID: Int, contract: Contract, execution: Execution)
    case execDetailsEnd(requestID: Int)
    case commissionReport(CommissionReport)
    case orderBound(permID: Int, clientID: Int, orderID: Int)
    case completedOrdersEnd
    case unknown(id: Int, fields: [String])
    case malformed(id: Int, fields: [String], reason: String)
}
