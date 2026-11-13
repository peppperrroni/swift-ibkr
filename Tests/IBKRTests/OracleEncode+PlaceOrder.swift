import Foundation
import Testing
@testable import IBKR

/// placeOrder (out 3) from ib_async's `Client.placeOrder(orderId, contract, order)` arguments; `nil` for another
/// family's method. `placeOrder/modify/recorded-openOrder` is built from the recorded frame its case decoded:
/// swift-ibkr's `IBDecoder` reads it, and the decoded order is sent back, as a `modifyOrder` would.
func placeOrderRequest(for c: EncodeCase) throws -> IBRequest? {
    guard c.method == "placeOrder" else { return nil }
    var a = CaseArgs(c.args, c.name)
    let id = try a.int("orderId")
    let r: IBRequest
    if c.name == "placeOrder/modify/recorded-openOrder" {
        _ = try a.value("contract")  // ib_async's own decode of the frame; the decode oracle compares it with ours
        _ = try a.value("order")
        let frame = try recording("liveLimitOrderPlacesAndCancels").first { $0.first == "5" }
        guard let frame, case .openOrder(let m) = IBDecoder.decode(body(frame)) else {
            throw CaseError("\(c.name): no openOrder in the recording")
        }
        guard m.orderID == id else { throw CaseError("\(c.name): order id \(m.orderID), ib_async sent \(id)") }
        r = .placeOrder(orderID: m.orderID, contract: m.contract, order: m.order)
    } else {
        r = .placeOrder(orderID: id, contract: try contract(from: a.value("contract")),
                        order: try order(from: a.value("order"), orderID: id))
    }
    try a.done()
    return r
}

/// An ib_async `Order` (any subclass): every attribute is read. `orderId` must be 0 or the id the call sends
/// (ib.py:790); `clientId`, `permId`, `filledQuantity` and `faProfile`, which swift-ibkr's `Order` does not model,
/// must hold ib_async's defaults. An ib_async default maps to swift-ibkr's default (`False` deprecated flags and a `0`
/// refFuturesConId / parentPermId to `nil`, IB's unset numbers to `nil`).
func order(from v: CaseValue, orderID: Int) throws -> Order {
    var a = try CaseArgs(v, type: nil, "order")
    let ownID = try a.int("orderId")
    guard ownID == 0 || ownID == orderID else { throw CaseError("order.orderId \(ownID), sent as \(orderID)") }
    try a.unmodelled("clientId", default: "0")
    try a.unmodelled("permId", default: "0")
    try a.unmodelled("filledQuantity", default: unsetDouble)
    try a.unmodelled("faProfile", default: "")
    let actionText = try a.text("action")
    guard let action = OrderAction(rawValue: actionText) else { throw CaseError("order.action: \(actionText)") }
    var o = Order(action: action, quantity: try a.decimal("totalQuantity"), orderType: try a.text("orderType"))
    o.limitPrice = try a.optionalDecimal("lmtPrice")
    o.auxPrice = try a.optionalDecimal("auxPrice")
    o.tif = try a.text("tif")
    o.activeStartTime = try a.text("activeStartTime")
    o.activeStopTime = try a.text("activeStopTime")
    o.ocaGroup = try a.text("ocaGroup")
    o.ocaType = try a.int("ocaType")
    o.orderRef = try a.text("orderRef")
    o.transmit = try a.bool("transmit")
    o.parentID = try a.int("parentId")
    o.blockOrder = try a.bool("blockOrder")
    o.sweepToFill = try a.bool("sweepToFill")
    o.displaySize = try a.int("displaySize")
    o.triggerMethod = try a.int("triggerMethod")
    o.outsideRTH = try a.bool("outsideRth")
    o.hidden = try a.bool("hidden")
    o.goodAfterTime = try a.text("goodAfterTime")
    o.goodTillDate = try a.text("goodTillDate")
    o.rule80A = try a.text("rule80A")
    o.allOrNone = try a.bool("allOrNone")
    o.minQty = try a.optionalInt("minQty")
    o.percentOffset = try a.optionalDecimal("percentOffset")
    o.overridePercentageConstraints = try a.bool("overridePercentageConstraints")
    o.trailStopPrice = try a.optionalDecimal("trailStopPrice")
    o.trailingPercent = try a.optionalDecimal("trailingPercent")
    o.faGroup = try a.text("faGroup")
    o.faMethod = try a.text("faMethod")
    o.faPercentage = try a.text("faPercentage")
    o.designatedLocation = try a.text("designatedLocation")
    o.openClose = try a.text("openClose")
    o.origin = try a.int("origin")
    o.shortSaleSlot = try a.int("shortSaleSlot")
    o.exemptCode = try a.int("exemptCode")
    o.discretionaryAmt = try a.decimal("discretionaryAmt")
    o.eTradeOnly = try a.bool("eTradeOnly") ? true : nil  // False is the wire's 0, swift-ibkr's nil
    o.firmQuoteOnly = try a.bool("firmQuoteOnly") ? true : nil
    o.nbboPriceCap = try a.optionalDecimal("nbboPriceCap")
    o.optOutSmartRouting = try a.bool("optOutSmartRouting")
    o.auctionStrategy = try a.int("auctionStrategy")
    o.startingPrice = try a.optionalDecimal("startingPrice")
    o.stockRefPrice = try a.optionalDecimal("stockRefPrice")
    o.delta = try a.optionalDecimal("delta")
    o.stockRangeLower = try a.optionalDecimal("stockRangeLower")
    o.stockRangeUpper = try a.optionalDecimal("stockRangeUpper")
    o.randomizePrice = try a.bool("randomizePrice")
    o.randomizeSize = try a.bool("randomizeSize")
    o.volatility = try a.optionalDecimal("volatility")
    o.volatilityType = try a.optionalInt("volatilityType")
    o.deltaNeutralOrderType = try a.text("deltaNeutralOrderType")
    o.deltaNeutralAuxPrice = try a.optionalDecimal("deltaNeutralAuxPrice")
    o.deltaNeutralConID = try a.int("deltaNeutralConId")
    o.deltaNeutralSettlingFirm = try a.text("deltaNeutralSettlingFirm")
    o.deltaNeutralClearingAccount = try a.text("deltaNeutralClearingAccount")
    o.deltaNeutralClearingIntent = try a.text("deltaNeutralClearingIntent")
    o.deltaNeutralOpenClose = try a.text("deltaNeutralOpenClose")
    o.deltaNeutralShortSale = try a.bool("deltaNeutralShortSale")
    o.deltaNeutralShortSaleSlot = try a.int("deltaNeutralShortSaleSlot")
    o.deltaNeutralDesignatedLocation = try a.text("deltaNeutralDesignatedLocation")
    o.continuousUpdate = try a.bool("continuousUpdate")
    o.referencePriceType = try a.optionalInt("referencePriceType")
    o.basisPoints = try a.optionalDecimal("basisPoints")
    o.basisPointsType = try a.optionalInt("basisPointsType")
    o.scaleInitLevelSize = try a.optionalInt("scaleInitLevelSize")
    o.scaleSubsLevelSize = try a.optionalInt("scaleSubsLevelSize")
    o.scalePriceIncrement = try a.optionalDecimal("scalePriceIncrement")
    o.scalePriceAdjustValue = try a.optionalDecimal("scalePriceAdjustValue")
    o.scalePriceAdjustInterval = try a.optionalInt("scalePriceAdjustInterval")
    o.scaleProfitOffset = try a.optionalDecimal("scaleProfitOffset")
    o.scaleAutoReset = try a.bool("scaleAutoReset")
    o.scaleInitPosition = try a.optionalInt("scaleInitPosition")
    o.scaleInitFillQty = try a.optionalInt("scaleInitFillQty")
    o.scaleRandomPercent = try a.bool("scaleRandomPercent")
    o.scaleTable = try a.text("scaleTable")
    o.hedgeType = try a.text("hedgeType")
    o.hedgeParam = try a.text("hedgeParam")
    o.account = try a.text("account")
    o.settlingFirm = try a.text("settlingFirm")
    o.clearingAccount = try a.text("clearingAccount")
    o.clearingIntent = try a.text("clearingIntent")
    o.algoStrategy = try a.text("algoStrategy")
    o.algoParams = try a.tagValues("algoParams")
    o.smartComboRoutingParams = try a.tagValues("smartComboRoutingParams")
    o.algoID = try a.text("algoId")
    o.whatIf = try a.bool("whatIf")
    o.notHeld = try a.bool("notHeld")
    o.solicited = try a.bool("solicited")
    o.modelCode = try a.text("modelCode")
    o.orderComboLegs = try a.list("orderComboLegs").map { leg in
        var l = try CaseArgs(leg, type: "OrderComboLeg", "order.orderComboLegs[]")
        let price = try l.optionalDecimal("price")
        try l.done()
        return OrderComboLeg(price: price)
    }
    o.orderMiscOptions = try a.tagValues("orderMiscOptions")
    o.referenceContractID = try a.int("referenceContractId")
    o.peggedChangeAmount = try a.decimal("peggedChangeAmount")
    o.isPeggedChangeAmountDecrease = try a.bool("isPeggedChangeAmountDecrease")
    o.referenceChangeAmount = try a.decimal("referenceChangeAmount")
    o.referenceExchangeID = try a.text("referenceExchangeId")
    o.adjustedOrderType = try a.text("adjustedOrderType")
    o.triggerPrice = try a.optionalDecimal("triggerPrice")
    o.adjustedStopPrice = try a.optionalDecimal("adjustedStopPrice")
    o.adjustedStopLimitPrice = try a.optionalDecimal("adjustedStopLimitPrice")
    o.adjustedTrailingAmount = try a.optionalDecimal("adjustedTrailingAmount")
    o.adjustableTrailingUnit = try a.int("adjustableTrailingUnit")
    o.limitPriceOffset = try a.optionalDecimal("lmtPriceOffset")
    o.conditions = try a.list("conditions").map(condition(from:))
    o.conditionsCancelOrder = try a.bool("conditionsCancelOrder")
    o.conditionsIgnoreRTH = try a.bool("conditionsIgnoreRth")
    o.extOperator = try a.text("extOperator")
    var tier = try CaseArgs(a.value("softDollarTier"), type: "SoftDollarTier", "order.softDollarTier")
    o.softDollarTier = SoftDollarTier(name: try tier.text("name"), value: try tier.text("val"),
                                      displayName: try tier.text("displayName"))
    try tier.done()
    o.cashQty = try a.optionalDecimal("cashQty")
    o.mifid2DecisionMaker = try a.text("mifid2DecisionMaker")
    o.mifid2DecisionAlgo = try a.text("mifid2DecisionAlgo")
    o.mifid2ExecutionTrader = try a.text("mifid2ExecutionTrader")
    o.mifid2ExecutionAlgo = try a.text("mifid2ExecutionAlgo")
    o.dontUseAutoPriceForHedge = try a.bool("dontUseAutoPriceForHedge")
    o.isOmsContainer = try a.bool("isOmsContainer")
    o.discretionaryUpToLimitPrice = try a.bool("discretionaryUpToLimitPrice")
    o.autoCancelDate = try a.text("autoCancelDate")
    let refFutures = try a.int("refFuturesConId"), parentPerm = try a.int("parentPermId")
    o.refFuturesConID = refFutures == 0 ? nil : refFutures  // ib_async's default 0 is swift-ibkr's nil
    o.parentPermID = parentPerm == 0 ? nil : parentPerm
    o.autoCancelParent = try a.bool("autoCancelParent")
    o.shareholder = try a.text("shareholder")
    o.imbalanceOnly = try a.bool("imbalanceOnly")
    o.routeMarketableToBbo = try a.bool("routeMarketableToBbo")
    o.usePriceMgmtAlgo = try a.bool("usePriceMgmtAlgo")
    o.duration = try a.optionalInt("duration")
    o.postToAts = try a.optionalInt("postToAts")
    o.advancedErrorOverride = try a.text("advancedErrorOverride")
    o.manualOrderTime = try a.text("manualOrderTime")
    o.minTradeQty = try a.optionalInt("minTradeQty")
    o.minCompeteSize = try a.optionalInt("minCompeteSize")
    if case .text("inf") = try a.value("competeAgainstBestOffset") {  // float('inf'), sent as Infinite
        o.competeAgainstBestOffset = .upToMid
    } else {
        o.competeAgainstBestOffset = try a.optionalDecimal("competeAgainstBestOffset").map(CompeteOffset.offset)
    }
    o.midOffsetAtWhole = try a.optionalDecimal("midOffsetAtWhole")
    o.midOffsetAtHalf = try a.optionalDecimal("midOffsetAtHalf")
    try a.done()
    return o
}

/// One of ib_async's condition dataclasses, by `_type`; `condType` must be that class's.
func condition(from v: CaseValue) throws -> OrderCondition {
    guard case .object(let o) = v, case .text(let type)? = o["_type"] else { throw CaseError("condition: \(v)") }
    var a = try CaseArgs(v, type: type, "order.conditions[]")
    let joinText = try a.text("conjunction")
    guard let j = OrderCondition.Conjunction(rawValue: joinText) else { throw CaseError("conjunction \(joinText)") }
    let condType = try a.int("condType")
    let c: OrderCondition, expected: Int
    switch type {
    case "PriceCondition":
        expected = 1
        c = .price(conID: try a.int("conId"), exchange: try a.text("exch"), isMore: try a.bool("isMore"),
                   price: try a.decimal("price"), triggerMethod: try a.int("triggerMethod"), conjunction: j)
    case "TimeCondition":
        expected = 3
        c = .time(isMore: try a.bool("isMore"), time: try a.text("time"), conjunction: j)
    case "MarginCondition":
        expected = 4
        c = .margin(isMore: try a.bool("isMore"), percent: try a.int("percent"), conjunction: j)
    case "ExecutionCondition":
        expected = 5
        c = .execution(secType: try a.text("secType"), exchange: try a.text("exch"), symbol: try a.text("symbol"),
                       conjunction: j)
    case "VolumeCondition":
        expected = 6
        c = .volume(conID: try a.int("conId"), exchange: try a.text("exch"), isMore: try a.bool("isMore"),
                    volume: try a.int("volume"), conjunction: j)
    case "PercentChangeCondition":
        expected = 7
        c = .percentChange(conID: try a.int("conId"), exchange: try a.text("exch"), isMore: try a.bool("isMore"),
                           changePercent: try a.decimal("changePercent"), conjunction: j)
    default: throw CaseError("condition type \(type)")
    }
    guard condType == expected else { throw CaseError("\(type).condType \(condType)") }
    try a.done()
    return c
}

/// `repr(UNSET_DOUBLE)`, ib_async's unset float.
let unsetDouble = "1.7976931348623157e+308"

extension CaseArgs {
    /// `None` or ib_async's unset float is `nil`.
    mutating func optionalDecimal(_ key: String) throws -> Decimal? {
        switch try value(key) {
        case .null, .text(unsetDouble): return nil
        default: return try decimal(key)
        }
    }

    /// `None` or ib_async's unset int (2147483647) is `nil`.
    mutating func optionalInt(_ key: String) throws -> Int? {
        switch try value(key) {
        case .null, .text("2147483647"): return nil
        default: return try int(key)
        }
    }
}

extension CaseArgs {
    /// A list of ib_async `TagValue`s (a NamedTuple, so each is a two-element list).
    mutating func tagValues(_ key: String) throws -> [TagValue] {
        try list(key).map { item in
            guard case .list(let pair) = item, pair.count == 2, case .text(let tag) = pair[0],
                  case .text(let value) = pair[1] else { throw CaseError("\(key)[]: not a TagValue: \(item)") }
            return TagValue(tag: tag, value: value)
        }
    }
}

/// The protocol-178 name of each field placeOrder sends for `contract` and `order` (docs/protocol-178.md, the
/// placeOrder table and «Order condition element»), so an `out 3` mismatch and its allowlist entry name the field,
/// not an index that shifts with every conditional group (ruling P7). Written from the table, not from the encoder;
/// `ibAsyncEncodesLikeSwiftIBKR` checks that it has one name per field the encoder wrote.
func placeOrderFieldNames(_ c: Contract, _ o: Order) -> [String] {
    var n = ["msgId", "orderId", "conId", "symbol", "secType", "lastTradeDateOrContractMonth", "strike", "right",
             "multiplier", "exchange", "primaryExchange", "currency", "localSymbol", "tradingClass", "secIdType",
             "secId", "action", "totalQuantity", "orderType", "lmtPrice", "auxPrice", "tif", "ocaGroup", "account",
             "openClose", "origin", "orderRef", "transmit", "parentId", "blockOrder", "sweepToFill", "displaySize",
             "triggerMethod", "outsideRth", "hidden"]
    if c.secType == "BAG" {
        n.append("comboLegsCount")
        for i in c.comboLegs.indices {
            n += ["conId", "ratio", "action", "exchange", "openClose", "shortSaleSlot", "designatedLocation",
                  "exemptCode"].map { "comboLegs[\(i)].\($0)" }
        }
        n.append("orderComboLegsCount")
        n += o.orderComboLegs.indices.map { "orderComboLegs[\($0)].price" }
        n.append("smartComboRoutingParamsCount")
        for i in o.smartComboRoutingParams.indices {
            n += ["tag", "value"].map { "smartComboRoutingParams[\(i)].\($0)" }
        }
    }
    n += ["sharesAllocation", "discretionaryAmt", "goodAfterTime", "goodTillDate", "faGroup", "faMethod",
          "faPercentage", "modelCode", "shortSaleSlot", "designatedLocation", "exemptCode", "ocaType", "rule80A",
          "settlingFirm", "allOrNone", "minQty", "percentOffset", "eTradeOnly", "firmQuoteOnly", "nbboPriceCap",
          "auctionStrategy", "startingPrice", "stockRefPrice", "delta", "stockRangeLower", "stockRangeUpper",
          "overridePercentageConstraints", "volatility", "volatilityType", "deltaNeutralOrderType",
          "deltaNeutralAuxPrice"]
    if !o.deltaNeutralOrderType.isEmpty {
        n += ["deltaNeutralConId", "deltaNeutralSettlingFirm", "deltaNeutralClearingAccount",
              "deltaNeutralClearingIntent", "deltaNeutralOpenClose", "deltaNeutralShortSale",
              "deltaNeutralShortSaleSlot", "deltaNeutralDesignatedLocation"]
    }
    n += ["continuousUpdate", "referencePriceType", "trailStopPrice", "trailingPercent", "scaleInitLevelSize",
          "scaleSubsLevelSize", "scalePriceIncrement"]
    if let increment = o.scalePriceIncrement, increment > 0 {
        n += ["scalePriceAdjustValue", "scalePriceAdjustInterval", "scaleProfitOffset", "scaleAutoReset",
              "scaleInitPosition", "scaleInitFillQty", "scaleRandomPercent"]
    }
    n += ["scaleTable", "activeStartTime", "activeStopTime", "hedgeType"]
    if !o.hedgeType.isEmpty { n.append("hedgeParam") }
    n += ["optOutSmartRouting", "clearingAccount", "clearingIntent", "notHeld", "deltaNeutralContractPresent"]
    if c.deltaNeutralContract != nil {
        n += ["deltaNeutralContract.conId", "deltaNeutralContract.delta", "deltaNeutralContract.price"]
    }
    n.append("algoStrategy")
    if !o.algoStrategy.isEmpty {
        n.append("algoParamsCount")
        for i in o.algoParams.indices { n += ["tag", "value"].map { "algoParams[\(i)].\($0)" } }
    }
    n += ["algoId", "whatIf", "orderMiscOptions", "solicited", "randomizeSize", "randomizePrice"]
    if ["PEG BENCH", "PEGBENCH"].contains(o.orderType) {
        n += ["referenceContractId", "isPeggedChangeAmountDecrease", "peggedChangeAmount", "referenceChangeAmount",
              "referenceExchangeId"]
    }
    n.append("conditionsCount")
    for (i, condition) in o.conditions.enumerated() {
        let fields: [String]
        switch condition {
        case .price: fields = ["isMore", "price", "conId", "exch", "triggerMethod"]
        case .time: fields = ["isMore", "time"]
        case .margin: fields = ["isMore", "percent"]
        case .execution: fields = ["secType", "exch", "symbol"]
        case .volume: fields = ["isMore", "volume", "conId", "exch"]
        case .percentChange: fields = ["isMore", "changePercent", "conId", "exch"]
        }
        n += (["condType", "conjunction"] + fields).map { "conditions[\(i)].\($0)" }
    }
    if !o.conditions.isEmpty { n += ["conditionsIgnoreRth", "conditionsCancelOrder"] }
    n += ["adjustedOrderType", "triggerPrice", "lmtPriceOffset", "adjustedStopPrice", "adjustedStopLimitPrice",
          "adjustedTrailingAmount", "adjustableTrailingUnit", "extOperator", "softDollarTier.name",
          "softDollarTier.value", "cashQty", "mifid2DecisionMaker", "mifid2DecisionAlgo", "mifid2ExecutionTrader",
          "mifid2ExecutionAlgo", "dontUseAutoPriceForHedge", "isOmsContainer", "discretionaryUpToLimitPrice",
          "usePriceMgmtAlgo", "duration", "postToAts", "autoCancelParent", "advancedErrorOverride",
          "manualOrderTime"]
    if c.exchange == "IBKRATS" { n.append("minTradeQty") }
    let pegBest = ["PEG BEST", "PEGBEST"].contains(o.orderType)
    if pegBest { n += ["minCompeteSize", "competeAgainstBestOffset"] }
    if ["PEG MID", "PEGMID"].contains(o.orderType) || (pegBest && o.competeAgainstBestOffset == .upToMid) {
        n += ["midOffsetAtWhole", "midOffsetAtHalf"]
    }
    return n
}
