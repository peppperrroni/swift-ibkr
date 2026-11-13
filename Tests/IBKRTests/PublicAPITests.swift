import Foundation
import IBKR
import Testing

@Test func everyPublicModelIsConstructible() {
    let contract = Contract(symbol: "AAPL")
    #expect(Contract.stock("AAPL").secType == "STK")
    let order = Order(action: .buy, quantity: 1, orderType: "MKT")
    let execution = Execution(
        execID: "e1", time: "t", account: "A", exchange: "X", side: "BOT", shares: 1, price: 2, permID: 3,
        clientID: 4, orderID: 5, liquidation: 0, cumulativeQuantity: 1, averagePrice: 2, orderRef: "",
        lastLiquidity: 0, pendingPriceRevision: false)
    let commission = CommissionReport(execID: "e1", commission: 1, currency: "USD")
    let status = OrderStatusMessage(
        orderID: 5, status: .filled, filled: 1, remaining: 0, permID: 3, parentID: 0, clientID: 4, whyHeld: "")
    let update = DepthUpdate(
        position: 0, marketMaker: "", operation: .insert, side: .bid, price: 1, size: 2)

    #expect(Position(account: "A", contract: contract, quantity: 1, averageCost: 2).quantity == 1)
    #expect(AccountValue(account: "A", tag: "t", value: "v", currency: "USD").tag == "t")
    #expect(PnL(position: 1, daily: 2).daily == 2)
    #expect(Position(account: "A", contract: contract, quantity: 1, averageCost: 2, modelCode: "M").modelCode == "M")
    #expect(AccountValue(account: "A", tag: "t", value: "v", currency: "USD", modelCode: "M").modelCode == "M")
    #expect(PortfolioItem(account: "A", contract: contract, quantity: 1, marketPrice: 2, marketValue: 2, averageCost: 1,
                          unrealizedPNL: 1).realizedPNL == nil)
    #expect(AccountPnL(daily: 1).unrealized == nil)
    #expect(AccountPnL(daily: 1, account: "A", modelCode: "M").modelCode == "M")
    #expect(PnL(position: 1, account: "A", modelCode: "M", conID: 7).conID == 7)
    #expect(execution.execID == "e1")
    #expect(commission.realizedPNL == nil)
    #expect(ContractDetails(
        contract: contract, marketName: "m", minTick: 1, priceMagnifier: 1, longName: "l", stockType: "", timeZoneID: "", tradingHours: "", liquidHours: "").orderTypes.isEmpty)
    #expect(ContractDescription(
        contract: contract, description: "d", issuerID: "").derivativeSecTypes.isEmpty)
    #expect(OptionChain(exchange: "SMART", underlyingConID: 1, tradingClass: "AAPL", multiplier: "100",
                        expirations: ["20261218"], strikes: [190]).strikes == [190])
    #expect(PriceIncrement(lowEdge: 0, increment: 1).increment == 1)
    #expect(FamilyCode(accountID: "DU1", familyCodeStr: "F").familyCodeStr == "F")
    #expect(ScannerSubscription().numberOfRows == nil)
    #expect(ScanData(rank: 0, contract: contract, marketName: "NMS", distance: "", benchmark: "", projection: "",
                     legsStr: "").rank == 0)
    #expect(NewsProvider(code: "BRFG", name: "Briefing").code == "BRFG")
    #expect(NewsArticle(articleType: 0, articleText: "t").articleText == "t")
    #expect(HistoricalNews(time: "", providerCode: "BRFG", articleID: "A", headline: "h").headline == "h")
    #expect(NewsBulletin(msgID: 1, msgType: 1, message: "m", origExchange: "NYSE").message == "m")
    #expect(WshEventData().conID == nil)
    #expect(FADataType(rawValue: 3) == .aliases)
    #expect(GenericTick(integerLiteral: 233).rawValue == "233")
    #expect(Bar(time: Date(timeIntervalSince1970: 0), open: 1, high: 2, low: 0, close: 1, volume: 5, count: 1).high == 2)
    #expect(DepthLevel(price: 1, size: 2, marketMaker: "").marketMaker == "")
    #expect(OptionComputation(tickAttrib: 0).delta == nil)
    #expect(EFPData().holdDays == nil)
    #expect(TickAttrib(canAutoExecute: true, pastLimit: true, preOpen: true) == TickAttrib(mask: 7))
    #expect(Contract(symbol: "AAPL").includeExpired == false && contract.issuerID == "")
    #expect(execution.evRule == "" && execution.evMultiplier == nil && execution.modelCode == "")
    #expect(Execution(
        execID: "e1", time: "t", account: "A", exchange: "X", side: "BOT", shares: 1, price: 2, permID: 3,
        clientID: 4, orderID: 5, liquidation: 0, cumulativeQuantity: 1, averagePrice: 2, orderRef: "",
        lastLiquidity: 0, pendingPriceRevision: false, evRule: "R", evMultiplier: 1, modelCode: "M").modelCode == "M")
    #expect(NewsTick(timeStamp: 1, providerCode: "P", articleID: "A", headline: "H").extraData == "")
    #expect(Ticker(contract: contract).bid == nil)
    #expect(TickData(time: Date(timeIntervalSince1970: 0), field: .bid, price: 1, size: 2).size == 2)
    #expect(TickPoint(time: Date(timeIntervalSince1970: 0), price: 1, size: 2).size == 2)
    #expect(BarList(bars: [], hasNewBar: true).hasNewBar)
    #expect(LiveBars(requestID: 1, contract: contract, barSize: "5 secs", whatToShow: "TRADES", bars: [],
                     hasNewBar: false).barSize == "5 secs")
    #expect(DepthTick(time: Date(timeIntervalSince1970: 0), update: update).update == update)
    #expect(Dividends(past12Months: 1).nextDate == nil)
    #expect(FundamentalRatios(values: ["MKTCAP": "1"]).decimal("MKTCAP") == 1)
    #expect(DepthBook().bidsByPosition.isEmpty && DepthBook().asksByPosition.isEmpty)
    #expect(update.size == 2)
    #expect(status.filled == 1)
    #expect(IBErrorMessage(requestID: 1, code: 2104, text: "t", advancedOrderRejectJSON: "").advancedOrderRejectJSON == "")
    #expect(OpenOrderMessage(
        orderID: 5, clientID: 4, permID: 3, contract: contract, order: order, status: .submitted).permID == 3)
    #expect(OrderState().commission == nil)
    #expect(OpenOrderMessage(
        orderID: 5, clientID: 4, permID: 3, contract: contract, order: order, status: .submitted,
        state: OrderState(commission: 1)).state.commission == 1)
    #expect(CompletedOrderMessage(
        permID: 3, contract: contract, order: order, status: .filled, completedTime: "", completedStatus: "",
        filledQuantity: 1).permID == 3)
    #expect(Fill(contract: contract, execution: execution, commission: commission).execution.orderID == 5)
    #expect(OrderSnapshot(
        orderID: 5, clientID: 4, permID: 3, contract: contract, order: order, status: .submitted,
        filled: 0, remaining: 1, whyHeld: "").rejectReason == nil)
    let entry = TradeLogEntry(time: Date(timeIntervalSince1970: 0), status: .pendingSubmit)
    #expect(entry.message == "" && entry.errorCode == nil)
    let snapshot = OrderSnapshot(orderID: 5, clientID: 4, permID: 3, contract: contract, order: order, status: .submitted,
                                 filled: 0, remaining: 1, whyHeld: "", log: [entry])
    #expect(snapshot.fills.isEmpty && OrderEvent.modified(snapshot) != .cancelRequested(snapshot))
    #expect(ServerLogLevel(rawValue: 5) == .detail)
    #expect(ExerciseAction(rawValue: 2) == .lapse)
    #expect(ReconnectPolicy().maxAttempts == nil)
    #expect(ReconnectPolicy(probeAfter: nil).probeAfter == nil)
    #expect(TagValue(tag: "a", value: "1").tag == "a")
    #expect(SoftDollarTier().displayName == "")
    #expect(ComboLeg(conID: 1, ratio: 2, action: .sell, exchange: "SMART").exemptCode == -1)
    #expect(OrderComboLeg(price: 1).price == 1)
    #expect(DeltaNeutralContract(conID: 1, delta: 0.5, price: 2).conID == 1)
    #expect(DepthMarketDataDescription(exchange: "ISLAND", secType: "STK", listingExchange: "NASDAQ", serviceDataType: "Deep2", aggGroup: 1).aggGroup == 1)
    #expect(SmartComponent(bitNumber: 0, exchange: "NYSE", exchangeLetter: "N").bitNumber == 0)
    #expect(HistoricalSchedule(startDateTime: "a", endDateTime: "b", timeZone: "UTC",
                               sessions: [HistoricalSession(startDateTime: "a", endDateTime: "b", refDate: "c")]).sessions.count == 1)
    #expect(HistogramData(price: 1, count: 2).count == 2)
    #expect(OrderCondition.margin(isMore: true, percent: 30) != .margin(isMore: false, percent: 30))
    #expect(CompeteOffset.upToMid != .offset(0))
    #expect(ContractQualification.notFound != .ambiguous([]))
    #expect(BracketOrder(parent: order, takeProfit: order, stopLoss: order).parent == order)
}
