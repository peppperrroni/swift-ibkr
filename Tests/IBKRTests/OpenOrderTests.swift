import Foundation
import Testing
@testable import IBKR

private let unset = "1.7976931348623157E308"

private func openFields(orderType: String = "LMT", limitPrice: String = "187.25", auxPrice: String = unset,
                        parentID: String = "0") -> [String] {
    Fixtures.openOrderFields(orderID: 12, permID: 918273001, clientID: 1, symbol: "AAPL", action: "BUY", quantity: "100",
                             orderType: orderType, limitPrice: limitPrice, auxPrice: auxPrice, tif: "DAY",
                             parentID: parentID, outsideRTH: "0", orderRef: "preset-1", status: "Submitted")
}

private func completedFields() -> [String] {
    Fixtures.completedOrderFields(orderID: 12, permID: 918273001, clientID: 1, symbol: "AAPL", action: "BUY",
                                  quantity: "100", orderType: "LMT", limitPrice: "187.25", auxPrice: unset, tif: "DAY",
                                  parentID: "0", outsideRTH: "0", orderRef: "preset-1", status: "Filled",
                                  completedTime: "20261109 15:59:01", completedStatus: "Filled", filledQuantity: "100")
}

private func openOrder(_ fields: [String]) -> OpenOrderMessage? {
    guard case .openOrder(let m) = IBDecoder.decode(body(fields)) else { return nil }
    return m
}

private func isMalformed(_ fields: [String]) -> Bool {
    if case .malformed = IBDecoder.decode(body(fields)) { return true }
    return false
}

@Test func fixturesHaveTheBaseCaseLengthOfTheTable() {
    #expect(openFields().count == 127)
    #expect(completedFields().count == 96)
}

@Test func openOrderDecodesModelledFields() {
    var f = openFields()
    f[2] = "265598"; f[12] = "NMS"; f[19] = "oca-1"; f[26] = "1"; f[53] = "2"  // modelled, left at defaults by the fixture
    var c = Contract(symbol: "AAPL")
    c.conID = 265598; c.strike = 0; c.localSymbol = "AAPL"; c.tradingClass = "NMS"
    var o = Order(action: .buy, quantity: 100, orderType: "LMT", limitPrice: d("187.25"), tif: "DAY")
    o.account = "DU123456"; o.orderRef = "preset-1"; o.ocaGroup = "oca-1"; o.ocaType = 2; o.outsideRTH = true
    o.volatilityType = 0; o.referencePriceType = 0; o.clearingIntent = "IB"
    #expect(IBDecoder.decode(body(f)) == .openOrder(OpenOrderMessage(
        orderID: 12, clientID: 1, permID: 918273001, contract: c, order: o, status: .submitted)))
}

@Test func bracketChildDecodesParent() {
    let m = openOrder(openFields(orderType: "STP", limitPrice: unset, auxPrice: "180", parentID: "12"))
    #expect(m?.order.parentID == 12)
    #expect(m?.order.auxPrice == d("180"))
}

@Test func unsetPricesAreNil() {
    let m = openOrder(openFields(orderType: "MKT", limitPrice: unset, auxPrice: unset))
    #expect(m != nil)
    #expect(m?.order.limitPrice == nil)
    #expect(m?.order.auxPrice == nil)
}

@Test func openOrderConsumesEveryField() {
    #expect(openOrder(openFields() + ["extra"]) != nil)
    #expect(isMalformed(Array(openFields().dropLast())))
}

@Test func completedOrderDecodes() {
    var c = Contract(symbol: "AAPL")
    c.strike = 0; c.localSymbol = "AAPL"
    var o = Order(action: .buy, quantity: 100, orderType: "LMT", limitPrice: d("187.25"), tif: "DAY")
    o.account = "DU123456"; o.orderRef = "preset-1"
    o.volatilityType = 0; o.referencePriceType = 0; o.clearingIntent = "IB"
    #expect(IBDecoder.decode(body(completedFields())) == .completedOrder(CompletedOrderMessage(
        permID: 918273001, contract: c, order: o, status: .filled,
        completedTime: "20261109 15:59:01", completedStatus: "Filled", filledQuantity: 100)))
}

/// The contract both every-field frames carry.
private func plainContract() -> Contract {
    var c = Contract(symbol: "AAPL")
    c.conID = 265598; c.strike = 0; c.localSymbol = "AAPL"; c.tradingClass = "NMS"
    return c
}

/// The fields openOrder and completedOrder share, as the every-field frames set them.
private func plainOrder(orderType: String) -> Order {
    var o = Order(action: .sell, quantity: 100, orderType: orderType, limitPrice: d("187.25"), auxPrice: d("1.5"),
                  tif: "GTC")
    o.ocaGroup = "g1"; o.account = "DU1"; o.openClose = "C"; o.origin = 1; o.orderRef = "r1"
    o.outsideRTH = true; o.hidden = true
    o.discretionaryAmt = d("0.05"); o.goodAfterTime = "20261112 09:30:00"; o.faGroup = "G"; o.faMethod = "EqualQuantity"
    o.faPercentage = "50"; o.modelCode = "M1"; o.goodTillDate = "20261113 16:00:00"; o.rule80A = "I"
    o.percentOffset = d("0.01"); o.settlingFirm = "F"
    o.shortSaleSlot = 2; o.designatedLocation = "L"; o.exemptCode = 0; o.startingPrice = d("1.1")
    o.stockRefPrice = d("1.2"); o.delta = d("0.5"); o.stockRangeLower = 1; o.stockRangeUpper = 2
    o.displaySize = 10; o.sweepToFill = true; o.allOrNone = true; o.minQty = 5; o.ocaType = 1
    o.triggerMethod = 2; o.volatility = d("0.3"); o.volatilityType = 2
    o.continuousUpdate = true; o.referencePriceType = 1; o.trailStopPrice = 180; o.trailingPercent = 2
    o.scaleInitLevelSize = 10; o.scaleSubsLevelSize = 5
    o.clearingAccount = "CA"; o.clearingIntent = "IB"; o.notHeld = true; o.solicited = true
    o.randomizeSize = true; o.randomizePrice = true
    o.limitPriceOffset = d("0.1"); o.cashQty = 1000
    o.dontUseAutoPriceForHedge = true; o.isOmsContainer = true; o.autoCancelParent = true
    return o
}

@Test func openOrderDecodesEveryPlainField() {
    let f = ["5", "12",
             "265598", "AAPL", "STK", "", "0", "", "", "SMART", "USD", "AAPL", "NMS",          // 2–12
             "SELL", "100", "VOL", "187.25", "1.5", "GTC", "g1", "DU1", "C", "1", "r1",       // 13–23
             "7", "918273001", "1",                                                           // 24–26
             "1", "0.05", "20261112 09:30:00", "alloc", "G", "EqualQuantity", "50", "M1",     // 27–34
             "20261113 16:00:00", "I", "0.01", "F", "2", "L", "0", "1",                       // 35–42
             "1.1", "1.2", "0.5", "1", "2", "10", "1", "1", "1", "5",                         // 43–52
             "1", "0", "0", "", "9",                                                          // 53–57
             "2", "0.3", "2", "", "",                                                         // 58–62
             "1", "1", "179", "2", "3", "1",                                                  // 63–68
             "", "0", "0", "0", "10", "5", "", "",                                            // 69–76
             "1", "CA", "IB", "1", "0", "", "1", "0",                                         // 77–84
             "Submitted", "", "", "", "", "", "", "", "", "", "", "", "", "", "",             // 85–99
             "1", "1", "0",                                                                   // 100–102
             "STP", "185", "180", "0.1", "184", "183", "1", "1", "N", "V", "Display", "1000", // 103–114
             "1", "1", "1", "1", "60", "1", "1",                                              // 115–121
             "", "", "", "", ""]                                                              // 122–126
    #expect(f.count == 127)
    var o = plainOrder(orderType: "VOL")
    o.auctionStrategy = 1; o.blockOrder = true; o.parentID = 9; o.basisPoints = 3; o.basisPointsType = 1
    o.optOutSmartRouting = true
    o.adjustedOrderType = "STP"; o.triggerPrice = 185; o.adjustedStopPrice = 184; o.adjustedStopLimitPrice = 183
    o.adjustedTrailingAmount = 1; o.adjustableTrailingUnit = 1
    o.softDollarTier = SoftDollarTier(name: "N", value: "V", displayName: "Display")
    o.discretionaryUpToLimitPrice = true; o.usePriceMgmtAlgo = true; o.duration = 60; o.postToAts = 1
    #expect(IBDecoder.decode(body(f)) == .openOrder(OpenOrderMessage(
        orderID: 12, clientID: 7, permID: 918273001, contract: plainContract(), order: o, status: .submitted)))
}

@Test func completedOrderDecodesEveryPlainField() {
    let f = ["101",
             "265598", "AAPL", "STK", "", "0", "", "", "SMART", "USD", "AAPL", "NMS",          // 1–11
             "SELL", "100", "LMT", "187.25", "1.5", "GTC", "g1", "DU1", "C", "1", "r1",       // 12–22
             "918273001", "1",                                                                // 23–24
             "1", "0.05", "20261112 09:30:00", "G", "EqualQuantity", "50", "M1",              // 25–31
             "20261113 16:00:00", "I", "0.01", "F", "2", "L", "0",                            // 32–38
             "1.1", "1.2", "0.5", "1", "2", "10", "1", "1", "5",                              // 39–47
             "1", "2", "0.3", "2", "", "",                                                    // 48–53
             "1", "1", "179", "2",                                                            // 54–57
             "", "0", "0", "0", "10", "5", "", "",                                            // 58–65
             "CA", "IB", "1", "0", "", "1",                                                   // 66–71
             "Filled", "1", "1", "0",                                                         // 72–75
             "180", "0.1", "1000", "1", "1", "20261231", "100", "495512551",                  // 76–83
             "1", "Not an insider or substantial shareholder", "1", "1", "918273000",         // 84–88
             "20261112 15:59:01", "Filled Size: 100",                                         // 89–90
             "", "", "", "", ""]                                                              // 91–95
    #expect(f.count == 96)
    var o = plainOrder(orderType: "LMT")
    o.autoCancelDate = "20261231"; o.refFuturesConID = 495512551
    o.shareholder = "Not an insider or substantial shareholder"; o.imbalanceOnly = true; o.routeMarketableToBbo = true
    o.parentPermID = 918273000
    #expect(IBDecoder.decode(body(f)) == .completedOrder(CompletedOrderMessage(
        permID: 918273001, contract: plainContract(), order: o, status: .filled,
        completedTime: "20261112 15:59:01", completedStatus: "Filled Size: 100", filledQuantity: 100)))
}

@Test func unknownActionIsMalformed() {
    var f = openFields()
    f[13] = "HOLD"
    guard case .malformed(let id, _, _) = IBDecoder.decode(body(f)) else { Issue.record("not malformed"); return }
    #expect(id == 5)
}

@Test func completedOrderConsumesEveryField() {
    guard case .completedOrder = IBDecoder.decode(body(completedFields() + ["extra"])) else { Issue.record("not decoded"); return }
    #expect(isMalformed(Array(completedFields().dropLast())))
}

/// The groups both conditional-group frames carry, as decoded.
private func expectConditionalGroups(_ c: Contract, _ o: Order) {
    #expect(c.comboLegs == [ComboLeg(conID: 265598, ratio: 1, action: .buy, exchange: "SMART")])
    #expect(o.orderComboLegs == [OrderComboLeg(price: 187)])
    #expect(o.smartComboRoutingParams == [TagValue(tag: "NonGuaranteed", value: "1")])
    #expect(o.scalePriceIncrement == d("0.05") && o.scalePriceAdjustValue == d("0.01"))
    #expect(o.scalePriceAdjustInterval == 60 && o.scaleProfitOffset == d("0.1") && o.scaleInitPosition == 0)
    #expect(o.hedgeType == "D" && o.hedgeParam == "0.5")
    #expect(c.deltaNeutralContract == DeltaNeutralContract(conID: 265598, delta: d("0.5"), price: 187))
}

@Test func openOrderDecodesEveryConditionalGroup() throws {
    var f = openFields(orderType: "PEG BENCH")
    f[61] = "LMT"; f[70] = "1"; f[71] = "1"; f[72] = "1"; f[75] = "0.05"; f[76] = "D"; f[81] = "1"; f[82] = "Adaptive"; f[102] = "2"
    f[122...126] = ["50", "100", "Infinite", "0.01", "0.005"]
    f = inserting([
        (62, ["265598", "", "", "", "O", "0", "0", ""]),                                // delta-neutral, 8
        (70, ["265598", "1", "BUY", "SMART", "0", "0", "", "-1"]),                       // one combo leg
        (71, ["187.0"]),                                                                 // one order combo-leg price
        (72, ["NonGuaranteed", "1"]),                                                    // one smart routing param
        (75, ["0.01", "60", "0.1", "0", "0", "0", "0"]),                                 // scale, 7
        (76, ["0.5"]),                                                                   // hedgeParam
        (81, ["265598", "0.5", "187"]),                                                  // delta-neutral contract
        (82, ["1", "adaptivePriority", "Normal"]),                                       // algo params
        (101, ["265598", "0", "1", "1", "ISLAND"]),                                      // PEG BENCH, 5
        (102, ["1", "a", "1", "180.5", "265598", "SMART", "0", "3", "o", "0", "20261109 15:00:00", "0", "0"]),
    ], into: f)                                                                          // price + time condition, flags
    let m = try #require(openOrder(f))
    #expect(m.status == .submitted)
    #expect(m.order.deltaNeutralOrderType == "LMT" && m.order.deltaNeutralConID == 265598)
    #expect(m.order.deltaNeutralOpenClose == "O")
    expectConditionalGroups(m.contract, m.order)
    #expect(m.order.algoStrategy == "Adaptive" && m.order.algoParams == [TagValue(tag: "adaptivePriority", value: "Normal")])
    #expect(m.order.referenceContractID == 265598 && m.order.isPeggedChangeAmountDecrease == false)
    #expect(m.order.peggedChangeAmount == 1 && m.order.referenceChangeAmount == 1 && m.order.referenceExchangeID == "ISLAND")
    #expect(m.order.conditions == [.price(conID: 265598, exchange: "SMART", isMore: true, price: d("180.5")),
                                   .time(isMore: false, time: "20261109 15:00:00", conjunction: .or)])
    #expect(!m.order.conditionsIgnoreRTH && !m.order.conditionsCancelOrder)
    #expect(m.order.minTradeQty == 50 && m.order.minCompeteSize == 100 && m.order.competeAgainstBestOffset == .upToMid)
    #expect(m.order.midOffsetAtWhole == d("0.01") && m.order.midOffsetAtHalf == d("0.005"))
    #expect(isMalformed(Array(f.dropLast())))
}

/// Review Focus 5: a condition type or conjunction the decoder does not know makes the frame malformed.
@Test func unknownConditionIsMalformed() {
    for condition in [["2", "a", "1", "0", "0"], ["1", "x", "1", "180.5", "265598", "SMART", "0", "0", "0"]] {
        var f = openFields()
        f[102] = "1"
        guard case .malformed(let id, _, _) = IBDecoder.decode(body(inserting([(102, condition)], into: f))) else {
            Issue.record("not malformed: \(condition)"); continue
        }
        #expect(id == 5)
    }
}

@Test func completedOrderDecodesEveryConditionalGroup() throws {
    var f = completedFields()
    f[14] = "PEGBENCH"; f[52] = "LMT"; f[59] = "1"; f[60] = "1"; f[61] = "1"; f[64] = "0.05"; f[65] = "D"
    f[69] = "1"; f[70] = "Adaptive"; f[75] = "2"
    f = inserting([
        (53, ["265598", "0", "0", ""]),                                                  // delta-neutral, 4
        (59, ["265598", "1", "BUY", "SMART", "0", "0", "", "-1"]),
        (60, ["187.0"]),
        (61, ["NonGuaranteed", "1"]),
        (64, ["0.01", "60", "0.1", "0", "0", "0", "0"]),
        (65, ["0.5"]),
        (69, ["265598", "0.5", "187"]),
        (70, ["1", "adaptivePriority", "Normal"]),
        (74, ["265598", "0", "1", "1", "ISLAND"]),
        (75, ["5", "a", "STK", "SMART", "AAPL", "4", "a", "1", "30", "0", "0"]),       // execution + margin condition, flags
    ], into: f)
    guard case .completedOrder(let m) = IBDecoder.decode(body(f)) else { Issue.record("not decoded"); return }
    #expect(m.status == .filled)
    #expect(m.completedTime == "20261109 15:59:01")
    #expect(m.order.deltaNeutralOrderType == "LMT" && m.order.deltaNeutralConID == 265598)
    #expect(m.order.deltaNeutralShortSale == false)
    expectConditionalGroups(m.contract, m.order)
    #expect(m.order.conditions == [.execution(secType: "STK", exchange: "SMART", symbol: "AAPL"),
                                   .margin(isMore: true, percent: 30)])
    #expect(isMalformed(Array(f.dropLast())))
}

@Test func openOrderDecodesTheWhatIfState() {
    var f = openFields()
    f[84] = "1"
    f[86...99] = ["1000", "800", "10000", "250.5", "200.25", "-1.5", "1250.5", "1000.25", "9998.5", "1.25", "1", "1.5",
                  "USD", "margin warning"]
    let m = openOrder(f)
    #expect(m?.order.whatIf == true)
    #expect(m?.state == OrderState(
        initMarginBefore: 1000, maintMarginBefore: 800, equityWithLoanBefore: 10000, initMarginChange: d("250.5"),
        maintMarginChange: d("200.25"), equityWithLoanChange: d("-1.5"), initMarginAfter: d("1250.5"),
        maintMarginAfter: d("1000.25"), equityWithLoanAfter: d("9998.5"), commission: d("1.25"), minCommission: 1,
        maxCommission: d("1.5"), commissionCurrency: "USD", warningText: "margin warning"))
}
