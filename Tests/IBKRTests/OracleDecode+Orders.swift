import Foundation
@testable import IBKR

/// ib_async's `Execution` fields under `prefix`; `time` is `Execution.date` (a zone-less text is UTC on both sides:
/// the generator sets `TimezoneTWS = "UTC"`, ours has no `gatewayTimeZone`).
func executionArgs(_ e: Execution, prefix: String) -> [String: String] {
    let a: [String: String] = [
        "execId": e.execID, "time": canon(e.date), "acctNumber": e.account, "exchange": e.exchange, "side": e.side,
        "shares": canon(e.shares), "price": canon(e.price), "permId": canon(e.permID), "clientId": canon(e.clientID),
        "orderId": canon(e.orderID), "liquidation": canon(e.liquidation), "cumQty": canon(e.cumulativeQuantity),
        "avgPrice": canon(e.averagePrice), "orderRef": e.orderRef, "evRule": e.evRule,
        "evMultiplier": canon(e.evMultiplier), "modelCode": e.modelCode, "lastLiquidity": canon(e.lastLiquidity),
        "pendingPriceRevision": canon(e.pendingPriceRevision),
    ]
    return Dictionary(uniqueKeysWithValues: a.map { (prefix + $0.key, $0.value) })
}

/// Every ib_async `Order` dataclass field swift-ibkr's `Order` models, under ib_async's name (DECISIONS: Swift names
/// are ib_async's with `Id` → `ID`, `Rth` → `RTH`, `lmt` → `limit`; `val` and `exch`). `orderId`, `clientId`, `permId`
/// and `filledQuantity` live on the message, so the callers add them. `faProfile` is absent at 178 (DECISIONS:
/// «`faProfile` is absent at 178»), so it is the `""` ib_async's decoder leaves in it. Task 10 reuses these names.
func orderArgs(_ o: Order, prefix: String) -> [String: String] {
    var a: [String: String] = [
        "action": o.action.rawValue, "totalQuantity": canon(o.totalQuantity), "orderType": o.orderType,
        "lmtPrice": canon(o.limitPrice), "auxPrice": canon(o.auxPrice), "tif": o.tif,
        "activeStartTime": o.activeStartTime, "activeStopTime": o.activeStopTime, "ocaGroup": o.ocaGroup,
        "ocaType": canon(o.ocaType), "orderRef": o.orderRef, "transmit": canon(o.transmit),
        "parentId": canon(o.parentID), "blockOrder": canon(o.blockOrder), "sweepToFill": canon(o.sweepToFill),
        "displaySize": canon(o.displaySize), "triggerMethod": canon(o.triggerMethod),
        "outsideRth": canon(o.outsideRTH), "hidden": canon(o.hidden), "goodAfterTime": o.goodAfterTime,
        "goodTillDate": o.goodTillDate, "rule80A": o.rule80A, "allOrNone": canon(o.allOrNone),
        "minQty": canon(o.minQty), "percentOffset": canon(o.percentOffset),
        "overridePercentageConstraints": canon(o.overridePercentageConstraints),
        "trailStopPrice": canon(o.trailStopPrice), "trailingPercent": canon(o.trailingPercent),
        // faProfile: read only below server version 177 (decoder.py:924-925, 1188-1189), so order.py:57's ""
        "faGroup": o.faGroup, "faProfile": "", "faMethod": o.faMethod, "faPercentage": o.faPercentage,
        "designatedLocation": o.designatedLocation, "openClose": o.openClose, "origin": canon(o.origin),
        "shortSaleSlot": canon(o.shortSaleSlot), "exemptCode": canon(o.exemptCode),
        "discretionaryAmt": canon(o.discretionaryAmt),
        // nil is the wire default 0 (DECISIONS: «`eTradeOnly`, `firmQuoteOnly` and `nbboPriceCap` are optional»)
        "eTradeOnly": canon(o.eTradeOnly ?? false), "firmQuoteOnly": canon(o.firmQuoteOnly ?? false),
        "nbboPriceCap": canon(o.nbboPriceCap), "optOutSmartRouting": canon(o.optOutSmartRouting),
        "auctionStrategy": canon(o.auctionStrategy), "startingPrice": canon(o.startingPrice),
        "stockRefPrice": canon(o.stockRefPrice), "delta": canon(o.delta), "stockRangeLower": canon(o.stockRangeLower),
        "stockRangeUpper": canon(o.stockRangeUpper), "randomizePrice": canon(o.randomizePrice),
        "randomizeSize": canon(o.randomizeSize), "volatility": canon(o.volatility),
        "volatilityType": canon(o.volatilityType), "deltaNeutralOrderType": o.deltaNeutralOrderType,
        "deltaNeutralAuxPrice": canon(o.deltaNeutralAuxPrice), "deltaNeutralConId": canon(o.deltaNeutralConID),
        "deltaNeutralSettlingFirm": o.deltaNeutralSettlingFirm,
        "deltaNeutralClearingAccount": o.deltaNeutralClearingAccount,
        "deltaNeutralClearingIntent": o.deltaNeutralClearingIntent, "deltaNeutralOpenClose": o.deltaNeutralOpenClose,
        "deltaNeutralShortSale": canon(o.deltaNeutralShortSale),
        "deltaNeutralShortSaleSlot": canon(o.deltaNeutralShortSaleSlot),
        "deltaNeutralDesignatedLocation": o.deltaNeutralDesignatedLocation,
        "continuousUpdate": canon(o.continuousUpdate), "referencePriceType": canon(o.referencePriceType),
        "basisPoints": canon(o.basisPoints), "basisPointsType": canon(o.basisPointsType),
        "scaleInitLevelSize": canon(o.scaleInitLevelSize), "scaleSubsLevelSize": canon(o.scaleSubsLevelSize),
        "scalePriceIncrement": canon(o.scalePriceIncrement), "scalePriceAdjustValue": canon(o.scalePriceAdjustValue),
        "scalePriceAdjustInterval": canon(o.scalePriceAdjustInterval),
        "scaleProfitOffset": canon(o.scaleProfitOffset), "scaleAutoReset": canon(o.scaleAutoReset),
        "scaleInitPosition": canon(o.scaleInitPosition), "scaleInitFillQty": canon(o.scaleInitFillQty),
        "scaleRandomPercent": canon(o.scaleRandomPercent), "scaleTable": o.scaleTable, "hedgeType": o.hedgeType,
        "hedgeParam": o.hedgeParam, "account": o.account, "settlingFirm": o.settlingFirm,
        "clearingAccount": o.clearingAccount, "clearingIntent": o.clearingIntent, "algoStrategy": o.algoStrategy,
        "algoId": o.algoID, "whatIf": canon(o.whatIf), "notHeld": canon(o.notHeld), "solicited": canon(o.solicited),
        "modelCode": o.modelCode, "referenceContractId": canon(o.referenceContractID),
        "peggedChangeAmount": canon(o.peggedChangeAmount),
        "isPeggedChangeAmountDecrease": canon(o.isPeggedChangeAmountDecrease),
        "referenceChangeAmount": canon(o.referenceChangeAmount), "referenceExchangeId": o.referenceExchangeID,
        "adjustedOrderType": o.adjustedOrderType, "triggerPrice": canon(o.triggerPrice),
        "adjustedStopPrice": canon(o.adjustedStopPrice), "adjustedStopLimitPrice": canon(o.adjustedStopLimitPrice),
        "adjustedTrailingAmount": canon(o.adjustedTrailingAmount),
        "adjustableTrailingUnit": canon(o.adjustableTrailingUnit), "lmtPriceOffset": canon(o.limitPriceOffset),
        "conditionsCancelOrder": canon(o.conditionsCancelOrder), "conditionsIgnoreRth": canon(o.conditionsIgnoreRTH),
        "extOperator": o.extOperator, "softDollarTier.name": o.softDollarTier.name,
        "softDollarTier.val": o.softDollarTier.value, "softDollarTier.displayName": o.softDollarTier.displayName,
        "cashQty": canon(o.cashQty), "mifid2DecisionMaker": o.mifid2DecisionMaker,
        "mifid2DecisionAlgo": o.mifid2DecisionAlgo, "mifid2ExecutionTrader": o.mifid2ExecutionTrader,
        "mifid2ExecutionAlgo": o.mifid2ExecutionAlgo, "dontUseAutoPriceForHedge": canon(o.dontUseAutoPriceForHedge),
        "isOmsContainer": canon(o.isOmsContainer), "discretionaryUpToLimitPrice": canon(o.discretionaryUpToLimitPrice),
        "autoCancelDate": o.autoCancelDate, "refFuturesConId": canon(o.refFuturesConID),
        "autoCancelParent": canon(o.autoCancelParent), "shareholder": o.shareholder,
        "imbalanceOnly": canon(o.imbalanceOnly), "routeMarketableToBbo": canon(o.routeMarketableToBbo),
        "parentPermId": canon(o.parentPermID), "usePriceMgmtAlgo": canon(o.usePriceMgmtAlgo),
        "duration": canon(o.duration), "postToAts": canon(o.postToAts),
        "advancedErrorOverride": o.advancedErrorOverride, "manualOrderTime": o.manualOrderTime,
        "minTradeQty": canon(o.minTradeQty), "minCompeteSize": canon(o.minCompeteSize),
        "midOffsetAtWhole": canon(o.midOffsetAtWhole), "midOffsetAtHalf": canon(o.midOffsetAtHalf),
    ]
    switch o.competeAgainstBestOffset {
    case nil: a["competeAgainstBestOffset"] = ""
    case .offset(let d): a["competeAgainstBestOffset"] = canon(d)
    case .upToMid: a["competeAgainstBestOffset"] = "Infinite"  // the canonical form of ib_async's +∞
    }
    for (name, list) in [("algoParams", o.algoParams), ("smartComboRoutingParams", o.smartComboRoutingParams),
                         ("orderMiscOptions", o.orderMiscOptions)] {
        a["\(name).#"] = canon(list.count)
        for (i, t) in list.enumerated() {  // ib_async's TagValue is a NamedTuple: the canonical form flattens a tuple
            a["\(name)[\(i)].#"] = "2"; a["\(name)[\(i)][0]"] = t.tag; a["\(name)[\(i)][1]"] = t.value
        }
    }
    a["orderComboLegs.#"] = canon(o.orderComboLegs.count)
    for (i, l) in o.orderComboLegs.enumerated() { a["orderComboLegs[\(i)].price"] = canon(l.price) }
    a["conditions.#"] = canon(o.conditions.count)
    for (i, c) in o.conditions.enumerated() {
        let p = "conditions[\(i)]."
        func set(_ type: Int, _ j: OrderCondition.Conjunction, _ fields: [String: String]) {
            a[p + "condType"] = canon(type); a[p + "conjunction"] = j.rawValue
            for (k, v) in fields { a[p + k] = v }
        }
        switch c {
        case let .price(conID, exchange, isMore, price, triggerMethod, j):
            set(1, j, ["isMore": canon(isMore), "price": canon(price), "conId": canon(conID), "exch": exchange,
                       "triggerMethod": canon(triggerMethod)])
        case let .time(isMore, time, j): set(3, j, ["isMore": canon(isMore), "time": time])
        case let .margin(isMore, percent, j): set(4, j, ["isMore": canon(isMore), "percent": canon(percent)])
        case let .execution(secType, exchange, symbol, j):
            set(5, j, ["secType": secType, "exch": exchange, "symbol": symbol])
        case let .volume(conID, exchange, isMore, volume, j):
            set(6, j, ["isMore": canon(isMore), "volume": canon(volume), "conId": canon(conID), "exch": exchange])
        case let .percentChange(conID, exchange, isMore, changePercent, j):
            set(7, j, ["isMore": canon(isMore), "changePercent": canon(changePercent), "conId": canon(conID),
                       "exch": exchange])
        }
    }
    return Dictionary(uniqueKeysWithValues: a.map { (prefix + $0.key, $0.value) })
}

/// ib_async's `OrderState` fields swift-ibkr's `OrderState` models; `status`, `completedTime` and `completedStatus`
/// live on the message, so the callers add them.
func orderStateArgs(_ s: OrderState, prefix: String) -> [String: String] {
    let a: [String: String] = [
        "initMarginBefore": canon(s.initMarginBefore), "maintMarginBefore": canon(s.maintMarginBefore),
        "equityWithLoanBefore": canon(s.equityWithLoanBefore), "initMarginChange": canon(s.initMarginChange),
        "maintMarginChange": canon(s.maintMarginChange), "equityWithLoanChange": canon(s.equityWithLoanChange),
        "initMarginAfter": canon(s.initMarginAfter), "maintMarginAfter": canon(s.maintMarginAfter),
        "equityWithLoanAfter": canon(s.equityWithLoanAfter), "commission": canon(s.commission),
        "minCommission": canon(s.minCommission), "maxCommission": canon(s.maxCommission),
        "commissionCurrency": s.commissionCurrency, "warningText": s.warningText,
    ]
    return Dictionary(uniqueKeysWithValues: a.map { (prefix + $0.key, $0.value) })
}

/// in 3, 5, 11, 53, 55, 59, 100, 101, 102 under ib_async's wrapper names.
func orderCalls(id: Int, _ m: IBMessage) -> [OracleCall]? {
    func call(_ method: String, _ args: [String: String] = [:]) -> [OracleCall] {
        [OracleCall(method: method, args: args)]
    }
    switch m {
    case .orderStatus(let s):
        return call("orderStatus", [
            "orderId": canon(s.orderID), "status": s.status.rawValue, "filled": canon(s.filled),
            "remaining": canon(s.remaining), "avgFillPrice": canon(s.averageFillPrice), "permId": canon(s.permID),
            "parentId": canon(s.parentID), "lastFillPrice": canon(s.lastFillPrice), "clientId": canon(s.clientID),
            "whyHeld": s.whyHeld, "mktCapPrice": canon(s.marketCapPrice),
        ])
    case .execDetails(let reqId, let contract, let execution):
        return call("execDetails", contractArgs(contract, prefix: "contract.")
            .merging(executionArgs(execution, prefix: "execution.")) { a, _ in a }
            .merging(["reqId": canon(reqId)]) { a, _ in a })
    case .execDetailsEnd(let reqId): return call("execDetailsEnd", ["reqId": canon(reqId)])
    case .commissionReport(let c):
        return call("commissionReport", [
            "commissionReport.execId": c.execID, "commissionReport.commission": canon(c.commission),
            "commissionReport.currency": c.currency, "commissionReport.realizedPNL": canon(c.realizedPNL),
            "commissionReport.yield_": canon(c.yield), "commissionReport.yieldRedemptionDate": canon(c.yieldRedemptionDate),
        ])
    case .orderBound(let permID, let clientID, let orderID):
        return call("orderBound", ["reqId": canon(permID), "apiClientId": canon(clientID), "apiOrderId": canon(orderID)])
    case .openOrder(let m):
        // filledQuantity, refFuturesConId, parentPermId, completedTime and completedStatus are not read by openOrder's
        // decoder at 178 (decoder.py:882-1147), so they are ib_async's dataclass defaults (order.py:147, 148, 153,
        // 324-325); these constants replace orderArgs' values for them.
        return call("openOrder", contractArgs(m.contract, prefix: "contract.")
            .merging(orderArgs(m.order, prefix: "order.")) { a, _ in a }
            .merging(orderStateArgs(m.state, prefix: "orderState.")) { a, _ in a }
            .merging([
                "orderId": canon(m.orderID), "order.orderId": canon(m.orderID), "order.clientId": canon(m.clientID),
                "order.permId": canon(m.permID), "order.filledQuantity": "", "order.refFuturesConId": "0",
                "order.parentPermId": "0", "orderState.status": m.status.rawValue,
                "orderState.completedTime": "", "orderState.completedStatus": "",
            ]) { _, constant in constant })
    case .completedOrder(let m):
        // orderId and clientId are not on completedOrder's wire at 178 (its decoder, decoder.py:1149-1359, never sets
        // them, so order.py:25-26's default 0); nor are the margins and commissions (it reads only status,
        // completedTime and completedStatus into OrderState(), so order.py:308-325's defaults).
        return call("completedOrder", contractArgs(m.contract, prefix: "contract.")
            .merging(orderArgs(m.order, prefix: "order.")) { a, _ in a }
            .merging(orderStateArgs(OrderState(), prefix: "orderState.")) { a, _ in a }
            .merging([
                "order.orderId": "0", "order.clientId": "0", "order.permId": canon(m.permID),
                "order.filledQuantity": canon(m.filledQuantity), "orderState.status": m.status.rawValue,
                "orderState.completedTime": m.completedTime, "orderState.completedStatus": m.completedStatus,
            ]) { a, _ in a })
    case .openOrderEnd: return call("openOrderEnd")
    case .completedOrdersEnd: return call("completedOrdersEnd")
    default: return nil
    }
}
