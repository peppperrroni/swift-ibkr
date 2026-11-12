import Foundation

/// IB's error (in 4): a notice, a warning or a failure for one request, order or the connection.
public struct IBErrorMessage: Sendable, Equatable {
    /// The request or order id the error names; -1 when it names none (a connection-wide notice).
    public var requestID: Int
    /// IB's error code; `ErrorCode.kind(_:)` classifies it.
    public var code: Int
    /// IB's message, with its `\uXXXX` escapes decoded.
    public var text: String
    /// IB's advanced order reject JSON as sent, empty when there is none.
    public var advancedOrderRejectJSON: String

    /// Creates an error message with every field given.
    public init(requestID: Int, code: Int, text: String, advancedOrderRejectJSON: String) {
        self.requestID = requestID
        self.code = code
        self.text = text
        self.advancedOrderRejectJSON = advancedOrderRejectJSON
    }
}

/// Everything IB sends, decoded; the doc of each case names the IB message and its id.
public enum IBMessage: Sendable, Equatable {
    /// orderStatus (in 3).
    case orderStatus(OrderStatusMessage)
    /// error (in 4).
    case error(IBErrorMessage)
    /// nextValidId (in 9).
    case nextValidID(Int)
    /// managedAccounts (in 15), split at the commas.
    case managedAccounts([String])
    /// currentTime (in 49), IB's epoch seconds.
    case currentTime(Int)
    /// userInfo (in 107).
    case userInfo(requestID: Int, whiteBrandingID: String)
    /// openOrder (in 5).
    case openOrder(OpenOrderMessage)
    /// openOrderEnd (in 53).
    case openOrderEnd
    /// completedOrder (in 101).
    case completedOrder(CompletedOrderMessage)
    /// execDetails (in 11).
    case execDetails(requestID: Int, contract: Contract, execution: Execution)
    /// execDetailsEnd (in 55).
    case execDetailsEnd(requestID: Int)
    /// commissionReport (in 59).
    case commissionReport(CommissionReport)
    /// orderBound (in 100).
    case orderBound(permID: Int, clientID: Int, orderID: Int)
    /// completedOrdersEnd (in 102).
    case completedOrdersEnd
    /// position (in 61).
    case position(Position)
    /// positionEnd (in 62).
    case positionEnd
    /// accountSummary (in 63).
    case accountSummary(requestID: Int, AccountValue)
    /// accountSummaryEnd (in 64).
    case accountSummaryEnd(requestID: Int)
    /// updateAccountValue (in 6).
    case accountValue(AccountValue)
    /// updatePortfolio (in 7).
    case portfolioItem(PortfolioItem)
    /// updateAccountTime (in 8).
    case accountTime(String)
    /// accountDownloadEnd (in 54).
    case accountDownloadEnd(account: String)
    /// positionMulti (in 71).
    case positionMulti(requestID: Int, Position)
    /// positionMultiEnd (in 72).
    case positionMultiEnd(requestID: Int)
    /// accountUpdateMulti (in 73).
    case accountUpdateMulti(requestID: Int, AccountValue)
    /// accountUpdateMultiEnd (in 74).
    case accountUpdateMultiEnd(requestID: Int)
    /// pnl (in 94).
    case pnl(requestID: Int, AccountPnL)
    /// pnlSingle (in 95).
    case pnlSingle(requestID: Int, PnL)
    /// contractData (in 10), and bondContractData (in 18).
    case contractData(requestID: Int, ContractDetails)
    /// contractDataEnd (in 52).
    case contractDataEnd(requestID: Int)
    /// symbolSamples (in 79).
    case symbolSamples(requestID: Int, [ContractDescription])
    /// tickPrice (in 1), tickSize (in 2), tickGeneric (in 45), tickString (in 46), marketDataType (in 58) and
    /// tickReqParams (in 81).
    case tick(requestID: Int, Tick)
    /// historicalData (in 17).
    case historicalData(requestID: Int, [Bar])
    /// historicalDataUpdate (in 90).
    case historicalDataUpdate(requestID: Int, Bar)
    /// historicalSchedule (in 106).
    case historicalSchedule(requestID: Int, HistoricalSchedule)
    /// realtimeBar (in 50).
    case realTimeBar(requestID: Int, Bar)
    /// updateMktDepth (in 12) and updateMktDepthL2 (in 13).
    case depth(requestID: Int, DepthUpdate)
    /// tickByTick (in 99).
    case tickByTick(requestID: Int, TickByTick)
    /// historicalTicks, historicalTicksBidAsk and historicalTicksLast (in 96, 97, 98); `done` is IB's last-batch flag.
    case historicalTicks(requestID: Int, [TickByTick], done: Bool)
    /// headTimestamp (in 88).
    case headTimeStamp(requestID: Int, Date)
    /// histogramData (in 89).
    case histogramData(requestID: Int, [HistogramData])
    /// tickSnapshotEnd (in 57).
    case tickSnapshotEnd(requestID: Int)
    /// deltaNeutralValidation (in 56). Reaches `messages()` only.
    case deltaNeutralValidation(requestID: Int, DeltaNeutralContract)
    /// mktDepthExchanges (in 80).
    case depthExchanges([DepthMarketDataDescription])
    /// smartComponents (in 82).
    case smartComponents(requestID: Int, [SmartComponent])
    /// securityDefinitionOptionParameter (in 75).
    case securityDefinitionOptionParameter(requestID: Int, OptionChain)
    /// securityDefinitionOptionParameterEnd (in 76).
    case securityDefinitionOptionParameterEnd(requestID: Int)
    /// marketRule (in 93).
    case marketRule(marketRuleID: Int, [PriceIncrement])
    /// familyCodes (in 78).
    case familyCodes([FamilyCode])
    /// softDollarTiers (in 77).
    case softDollarTiers(requestID: Int, [SoftDollarTier])
    /// scannerParameters (in 19), IB's XML.
    case scannerParameters(String)
    /// scannerData (in 20).
    case scannerData(requestID: Int, [ScanData])
    /// newsProviders (in 85).
    case newsProviders([NewsProvider])
    /// newsArticle (in 83).
    case newsArticle(requestID: Int, NewsArticle)
    /// historicalNews (in 86).
    case historicalNews(requestID: Int, HistoricalNews)
    /// historicalNewsEnd (in 87).
    case historicalNewsEnd(requestID: Int, hasMore: Bool)
    /// updateNewsBulletin (in 14).
    case newsBulletin(NewsBulletin)
    /// IB's fundamentals report XML, Wall Street Horizon's metadata JSON and event JSON: text, never parsed.
    case fundamentalData(requestID: Int, String)
    /// wshMetaData (in 104).
    case wshMetaData(requestID: Int, String)
    /// wshEventData (in 105).
    case wshEventData(requestID: Int, String)
    /// IB's FA XML for one `FADataType`, and `replaceFA`'s confirmation text.
    case receiveFA(type: FADataType, xml: String)
    /// replaceFAEnd (in 103).
    case replaceFAEnd(requestID: Int, String)
    /// IB's display groups as its raw `"1|2|3"`, and a group's new contract as IB's `contractInfo` text.
    case displayGroupList(requestID: Int, String)
    /// displayGroupUpdated (in 68).
    case displayGroupUpdated(requestID: Int, String)
    /// The verify handshake's answers; they reach `messages()` only.
    case verifyMessageAPI(apiData: String)
    /// verifyCompleted (in 66).
    case verifyCompleted(isSuccessful: Bool, errorText: String)
    /// verifyAndAuthMessageAPI (in 69).
    case verifyAndAuthMessageAPI(apiData: String, xyzChallenge: String)
    /// verifyAndAuthCompleted (in 70).
    case verifyAndAuthCompleted(isSuccessful: Bool, errorText: String)
    /// rerouteMktDataReq (in 91). Reaches `messages()` only.
    case rerouteMarketData(requestID: Int, conID: Int, exchange: String)
    /// rerouteMktDepthReq (in 92). Reaches `messages()` only.
    case rerouteMarketDepth(requestID: Int, conID: Int, exchange: String)
    /// A message id the decoder has no layout for, with its raw fields.
    case unknown(id: Int, fields: [String])
    /// A message whose fields did not decode: its id, the raw fields and why.
    case malformed(id: Int, fields: [String], reason: String)
}
