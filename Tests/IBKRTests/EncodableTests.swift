import Foundation
import IBKR
import Testing

private func json<T: Encodable>(_ v: T) throws -> String {
    String(decoding: try JSONEncoder().encode(v), as: UTF8.self)
}

@Test func everyPublicModelEncodes() throws {
    let contract = Contract(symbol: "AAPL")
    let order = Order(action: .buy, quantity: 1, orderType: "MKT")
    let execution = Execution(
        execID: "e1", time: "t", account: "A", exchange: "X", side: "BOT", shares: 1, price: 2, permID: 3,
        clientID: 4, orderID: 5, liquidation: 0, cumulativeQuantity: 1, averagePrice: 2, orderRef: "",
        lastLiquidity: 0, pendingPriceRevision: false)
    let commission = CommissionReport(execID: "e1", commission: 1, currency: "USD")
    let open = OpenOrderMessage(orderID: 5, clientID: 4, permID: 3, contract: contract, order: order, status: .submitted)
    _ = try [
        json(contract), json(order), json(execution), json(commission), json(open),
        json(Position(account: "A", contract: contract, quantity: 1, averageCost: 2)),
        json(AccountValue(account: "A", tag: "t", value: "v", currency: "USD")),
        json(PnL(position: 1, daily: 2)), json(AccountPnL(daily: 1)),
        json(PortfolioItem(account: "A", contract: contract, quantity: 1, marketPrice: 2, marketValue: 2,
                           averageCost: 1, unrealizedPNL: 1)),
        json(ContractDetails(contract: contract, marketName: "m", minTick: 1, priceMagnifier: 1, longName: "l",
                             stockType: "", timeZoneID: "", tradingHours: "", liquidHours: "")),
        json(ContractDescription(contract: contract, description: "d", issuerID: "")),
        json(OptionChain(exchange: "SMART", underlyingConID: 1, tradingClass: "AAPL", multiplier: "100",
                         expirations: ["20261218"], strikes: [190])),
        json(PriceIncrement(lowEdge: 0, increment: 1)), json(FamilyCode(accountID: "DU1", familyCodeStr: "F")),
        json(ScannerSubscription()),
        json(ScanData(rank: 0, contract: contract, marketName: "NMS", distance: "", benchmark: "", projection: "",
                      legsStr: "")),
        json(NewsProvider(code: "BRFG", name: "Briefing")), json(NewsArticle(articleType: 0, articleText: "t")),
        json(HistoricalNews(time: "", providerCode: "BRFG", articleID: "A", headline: "h")),
        json(NewsBulletin(msgID: 1, msgType: 1, message: "m", origExchange: "NYSE")), json(WshEventData()),
        json(FADataType.aliases), json(GenericTick(integerLiteral: 233)),
        json(Bar(time: Date(timeIntervalSince1970: 0), open: 1, high: 2, low: 0, close: 1, volume: 5, count: 1)),
        json(DepthLevel(price: 1, size: 2, marketMaker: "")), json(OptionComputation(tickAttrib: 0)),
        json(EFPData()), json(NewsTick(timeStamp: 1, providerCode: "P", articleID: "A", headline: "H")),
        json(Ticker(contract: contract)),
        json(TickData(time: Date(timeIntervalSince1970: 0), field: .bid, price: 1, size: 2)),
        json(TickPoint(time: Date(timeIntervalSince1970: 0), price: 1, size: 2)),
        json(BarList(bars: [], hasNewBar: true)),
        json(DepthTick(time: Date(timeIntervalSince1970: 0), update: DepthUpdate(
            position: 0, marketMaker: "", operation: .insert, side: .bid, price: 1, size: 2))),
        json(Dividends()), json(FundamentalRatios(values: ["MKTCAP": "1"])),
        json(DepthUpdate(position: 0, marketMaker: "", operation: .insert, side: .bid, price: 1, size: 2)),
        json(OrderStatusMessage(orderID: 5, status: .filled, filled: 1, remaining: 0, permID: 3, parentID: 0,
                                clientID: 4, whyHeld: "")),
        json(IBErrorMessage(requestID: 1, code: 2104, text: "t", advancedOrderRejectJSON: "")),
        json(OrderState()),
        json(CompletedOrderMessage(permID: 3, contract: contract, order: order, status: .filled, completedTime: "",
                                   completedStatus: "", filledQuantity: 1)),
        json(Fill(contract: contract, execution: execution, commission: commission)),
        json(OrderSnapshot(orderID: 5, clientID: 4, permID: 3, contract: contract, order: order, status: .submitted,
                           filled: 0, remaining: 1, whyHeld: "")),
        json(ServerLogLevel.detail), json(ExerciseAction.lapse), json(TagValue(tag: "a", value: "1")),
        json(SoftDollarTier()), json(ComboLeg(conID: 1, ratio: 2, action: .sell, exchange: "SMART")),
        json(OrderComboLeg(price: 1)), json(DeltaNeutralContract(conID: 1, delta: 0.5, price: 2)),
        json(DepthMarketDataDescription(exchange: "ISLAND", secType: "STK", listingExchange: "NASDAQ",
                                        serviceDataType: "Deep2", aggGroup: 1)),
        json(SmartComponent(bitNumber: 0, exchange: "NYSE", exchangeLetter: "N")),
        json(HistoricalSchedule(startDateTime: "a", endDateTime: "b", timeZone: "UTC",
                                sessions: [HistoricalSession(startDateTime: "a", endDateTime: "b", refDate: "c")])),
        json(HistogramData(price: 1, count: 2)),
        json(OrderCondition.margin(isMore: true, percent: 30)), json(CompeteOffset.upToMid),
        json(ContractQualification.notFound),
        json(BracketOrder(parent: order, takeProfit: order, stopLoss: order)),
        json(IBMessage.tick(requestID: 1, .price(.bid, price: 1, size: 2))), json(IBMessage.openOrder(open)),
    ]
}

@Test func tickerDictionariesEncodeAsObjects() throws {
    let t = Ticker(contract: Contract(symbol: "AAPL"), prices: [TickField(rawValue: 15): 1])
    #expect(try json(t).contains("\"prices\":{\"15\":1}"))
}

@Test func decimalsEncodeAsNumbers() throws {
    let bar = Bar(time: Date(timeIntervalSince1970: 0), open: d("351.5"), high: 2, low: 0, close: 1, volume: 5, count: 1)
    #expect(try json(bar).contains("\"open\":351.5"))
}

@Test func rawRepresentableTypesEncodeAsTheirRawValue() throws {
    #expect(try json([OrderStatus.filled]) == "[\"Filled\"]")
    #expect(try json([GenericTick(integerLiteral: 233)]) == "[\"233\"]")
}
