import Foundation

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
    case position(Position)
    case positionEnd
    case accountSummary(requestID: Int, AccountValue)
    case accountSummaryEnd(requestID: Int)
    case pnlSingle(requestID: Int, PnL)
    case contractData(requestID: Int, ContractDetails)
    case contractDataEnd(requestID: Int)
    case symbolSamples(requestID: Int, [ContractDescription])
    case tick(requestID: Int, Tick)
    case historicalData(requestID: Int, [Bar])
    case historicalDataUpdate(requestID: Int, Bar)
    case depth(requestID: Int, DepthUpdate)
    case tickByTick(requestID: Int, TickByTick)
    case tickRequestParameters(requestID: Int, minTick: Decimal?, bboExchange: String, snapshotPermissions: Int)
    case unknown(id: Int, fields: [String])
    case malformed(id: Int, fields: [String], reason: String)
}
