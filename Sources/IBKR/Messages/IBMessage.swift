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
    case securityDefinitionOptionParameter(requestID: Int, OptionChain)
    case securityDefinitionOptionParameterEnd(requestID: Int)
    case marketRule(marketRuleID: Int, [PriceIncrement])
    case familyCodes([FamilyCode])
    case softDollarTiers(requestID: Int, [SoftDollarTier])
    case scannerParameters(String)
    case scannerData(requestID: Int, [ScanData])
    case newsProviders([NewsProvider])
    case newsArticle(requestID: Int, NewsArticle)
    case historicalNews(requestID: Int, HistoricalNews)
    case historicalNewsEnd(requestID: Int, hasMore: Bool)
    case newsBulletin(NewsBulletin)
    /// IB's fundamentals report XML, Wall Street Horizon's metadata JSON and event JSON: text, never parsed.
    case fundamentalData(requestID: Int, String)
    case wshMetaData(requestID: Int, String)
    case wshEventData(requestID: Int, String)
    /// IB's FA XML for one `FADataType`, and `replaceFA`'s confirmation text.
    case receiveFA(type: FADataType, xml: String)
    case replaceFAEnd(requestID: Int, String)
    /// IB's display groups as its raw `"1|2|3"`, and a group's new contract as IB's `contractInfo` text.
    case displayGroupList(requestID: Int, String)
    case displayGroupUpdated(requestID: Int, String)
    /// The verify handshake's answers; they reach `messages()` only.
    case verifyMessageAPI(apiData: String)
    case verifyCompleted(isSuccessful: Bool, errorText: String)
    case verifyAndAuthMessageAPI(apiData: String, xyzChallenge: String)
    case verifyAndAuthCompleted(isSuccessful: Bool, errorText: String)
    case rerouteMarketData(requestID: Int, conID: Int, exchange: String)
    case rerouteMarketDepth(requestID: Int, conID: Int, exchange: String)
    case unknown(id: Int, fields: [String])
    case malformed(id: Int, fields: [String], reason: String)
}
