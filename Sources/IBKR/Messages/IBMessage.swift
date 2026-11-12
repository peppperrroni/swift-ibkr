import Foundation

public struct IBErrorMessage: Sendable, Equatable {
    public var requestID: Int
    public var code: Int
    public var text: String
    public var advancedOrderRejectJSON: String

    public init(requestID: Int, code: Int, text: String, advancedOrderRejectJSON: String) {
        self.requestID = requestID
        self.code = code
        self.text = text
        self.advancedOrderRejectJSON = advancedOrderRejectJSON
    }
}

public enum IBMessage: Sendable, Equatable {
    case orderStatus(OrderStatusMessage)
    case error(IBErrorMessage)
    case nextValidID(Int)
    case managedAccounts([String])
    case currentTime(Int)
    case userInfo(requestID: Int, whiteBrandingID: String)
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
    case accountValue(AccountValue)
    case portfolioItem(PortfolioItem)
    case accountTime(String)
    case accountDownloadEnd(account: String)
    case positionMulti(requestID: Int, Position)
    case positionMultiEnd(requestID: Int)
    case accountUpdateMulti(requestID: Int, AccountValue)
    case accountUpdateMultiEnd(requestID: Int)
    case pnl(requestID: Int, AccountPnL)
    case pnlSingle(requestID: Int, PnL)
    case contractData(requestID: Int, ContractDetails)
    case contractDataEnd(requestID: Int)
    case symbolSamples(requestID: Int, [ContractDescription])
    case tick(requestID: Int, Tick)
    case historicalData(requestID: Int, [Bar])
    case historicalDataUpdate(requestID: Int, Bar)
    case historicalSchedule(requestID: Int, HistoricalSchedule)
    case realTimeBar(requestID: Int, Bar)
    case depth(requestID: Int, DepthUpdate)
    case tickByTick(requestID: Int, TickByTick)
    case historicalTicks(requestID: Int, [TickByTick], done: Bool)
    case headTimeStamp(requestID: Int, Date)
    case histogramData(requestID: Int, [HistogramData])
    case tickSnapshotEnd(requestID: Int)
    case deltaNeutralValidation(requestID: Int, DeltaNeutralContract)
    case depthExchanges([DepthMarketDataDescription])
    case smartComponents(requestID: Int, [SmartComponent])
    case rerouteMarketData(requestID: Int, conID: Int, exchange: String)
    case rerouteMarketDepth(requestID: Int, conID: Int, exchange: String)
    case unknown(id: Int, fields: [String])
    case malformed(id: Int, fields: [String], reason: String)
}
