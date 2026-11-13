import Foundation
import Testing
@testable import IBKR

// Indices are rows of the placeOrder (out 3) table in docs/protocol-178.md.
private let lmtPriceIndex = 19      // row 19 lmtPrice
private let auxPriceIndex = 20      // row 20 auxPrice
private let transmitIndex = 27      // row 27 transmit
private let parentIDIndex = 28      // row 28 parentId
private let outsideRTHIndex = 33    // row 33 outsideRth

private func limit(_ price: String, ref: String = "") -> IBRequest {
    var o = Order(action: .buy, quantity: d("100"), orderType: "LMT", limitPrice: d(price))
    o.orderRef = ref
    return .placeOrder(orderID: 12, contract: Contract(symbol: "AAPL"), order: o)
}

/// The base case of the table: every field at its default.
let base: [String] = [
    "3", "12",                                   // 0-1 msgId, orderId
    "0", "AAPL", "STK", "", "0.0", "", "", "SMART", "", "USD", "", "",  // 2-13 contract
    "", "",                                      // 14-15 secIdType, secId
    "BUY", "100", "LMT", "187.25", "",           // 16-20 action, qty, type, lmt, aux
    "DAY", "", "",                               // 21-23 tif, ocaGroup, account
    "O", "0", "",                                // 24-26 openClose, origin, orderRef
    "1", "0",                                    // 27-28 transmit, parentId
    "0", "0", "0", "0", "0", "0",                // 29-34 block, sweep, dispSize, trigger, outsideRth, hidden
    "", "0.0", "", "", "", "", "", "",           // 35-42 sharesAlloc..modelCode
    "0", "", "-1",                               // 43-45 shortSaleSlot, designatedLocation, exemptCode
    "0", "", "",                                 // 46-48 ocaType, rule80A, settlingFirm
    "0", "", "", "0", "0", "",                   // 49-54 allOrNone, minQty, percentOffset, eTrade, firmQuote, nbboCap
    "0", "", "", "", "", "",                     // 55-60 auctionStrategy, startingPrice, stockRef, delta, rangeLo, rangeHi
    "0", "", "", "", "",                         // 61-65 overridePct, volatility, volType, dnOrderType, dnAuxPrice
    "0", "", "", "", "", "", "", "",             // 66-73 continuousUpdate, refPriceType, trailStop, trailPct, scale x4
    "", "",                                      // 74-75 activeStart, activeStop
    "",                                          // 76 hedgeType
    "0", "", "", "0", "0",                       // 77-81 optOutSmart, clearingAcct, clearingIntent, notHeld, dnContractPresent
    "", "", "0", "", "0", "0", "0",              // 82-88 algoStrategy, algoId, whatIf, miscOptions, solicited, randSize, randPrice
    "0",                                         // 89 conditionsCount
    "", "", "", "", "", "", "0", "",             // 90-97 adjusted*, trigger, lmtOffset, adjustable unit, extOperator
    "", "",                                      // 98-99 softDollarTier
    "", "", "", "", "",                          // 100-104 cashQty, mifid2 x4
    "0", "0", "0", "0",                          // 105-108 dontUseAutoPrice, omsContainer, discretionaryUpTo, usePriceMgmtAlgo
    "", "", "0", "", "",                         // 109-113 duration, postToAts, autoCancelParent, advancedErrorOverride, manualOrderTime
]

@Test func limitOrderMatchesProtocolTable() throws {
    #expect(base.count == 114)
    #expect(try limit("187.25").body() == base.flatMap { Array($0.utf8) + [0] })
}

private func fields(_ r: IBRequest) throws -> [String] { FieldReader(try r.body()).fields }

@Test func bracketChildCarriesParentAndTransmit() throws {
    var o = Order(action: .sell, quantity: d("100"), orderType: "STP", auxPrice: d("180"))
    o.parentID = 12; o.transmit = false; o.outsideRTH = true
    let f = try fields(.placeOrder(orderID: 13, contract: Contract(symbol: "AAPL"), order: o))
    #expect(f[parentIDIndex] == "12")
    #expect(f[transmitIndex] == "0")
    #expect(f[auxPriceIndex] == "180")
    #expect(f[outsideRTHIndex] == "1")
}

@Test func modifyIsTheSameMessageWithTheSameID() throws {
    let a = try fields(limit("187.25")), b = try fields(limit("187.50"))
    #expect(a.count == b.count)
    #expect(a.indices.filter { a[$0] != b[$0] } == [lmtPriceIndex])
}

@Test func placeOrderRefusesNonASCII() {
    #expect(throws: IBEncodingError.nonASCII(field: "Купить 500")) { try limit("187.25", ref: "Купить 500").body() }
}

@Test func strikeEncodesAsADouble() throws {
    var c = Contract(symbol: "AAPL", secType: "OPT")
    c.strike = d("150")
    let f = try fields(.placeOrder(orderID: 1, contract: c, order: Order(action: .buy, quantity: d("1"), orderType: "LMT")))
    #expect(f[6] == "150.0")  // row 6 strike
}

/// An option contract and an order with every plain field off its default.
private func everyPlainField(orderType: String = "VOL") -> IBRequest {
    var c = Contract(symbol: "AAPL", secType: "OPT", primaryExchange: "CBOE")
    c.conID = 12345; c.lastTradeDateOrContractMonth = "20261218"; c.strike = d("150"); c.right = "C"
    c.multiplier = "100"; c.localSymbol = "AAPL  261218C00150000"; c.tradingClass = "AAPL"
    c.secIDType = "ISIN"; c.secID = "US0378331005"
    var o = Order(action: .sell, quantity: d("100"), orderType: orderType, limitPrice: d("187.25"), auxPrice: d("1.5"), tif: "GTC")
    o.ocaGroup = "g1"; o.account = "DU1"; o.openClose = "C"; o.origin = 1; o.orderRef = "r1"; o.transmit = false
    o.parentID = 9; o.blockOrder = true; o.sweepToFill = true; o.displaySize = 10; o.triggerMethod = 2
    o.outsideRTH = true; o.hidden = true; o.discretionaryAmt = d("0.05")
    o.goodAfterTime = "20261112 09:30:00"; o.goodTillDate = "20261113 16:00:00"
    o.faGroup = "G"; o.faMethod = "EqualQuantity"; o.faPercentage = "50"; o.modelCode = "M1"
    o.shortSaleSlot = 2; o.designatedLocation = "L"; o.exemptCode = 0; o.ocaType = 1; o.rule80A = "I"
    o.settlingFirm = "F"; o.allOrNone = true; o.minQty = 5; o.percentOffset = d("0.01"); o.auctionStrategy = 1
    o.startingPrice = d("1.1"); o.stockRefPrice = d("1.2"); o.delta = d("0.5"); o.stockRangeLower = 1
    o.stockRangeUpper = 2; o.overridePercentageConstraints = true; o.volatility = d("0.3"); o.volatilityType = 2
    o.continuousUpdate = true; o.referencePriceType = 1; o.trailStopPrice = 180; o.trailingPercent = 2
    o.scaleInitLevelSize = 10; o.scaleSubsLevelSize = 5; o.scaleTable = "T"
    o.activeStartTime = "20261112 09:30:00"; o.activeStopTime = "20261112 16:00:00"
    o.optOutSmartRouting = true; o.clearingAccount = "CA"; o.clearingIntent = "IB"; o.notHeld = true
    o.algoID = "A1"; o.whatIf = true; o.orderMiscOptions = [TagValue(tag: "a", value: "1"), TagValue(tag: "b", value: "2")]
    o.solicited = true; o.randomizeSize = true; o.randomizePrice = true
    o.adjustedOrderType = "STP"; o.triggerPrice = 185; o.limitPriceOffset = d("0.1"); o.adjustedStopPrice = 184
    o.adjustedStopLimitPrice = 183; o.adjustedTrailingAmount = 1; o.adjustableTrailingUnit = 1; o.extOperator = "X"
    o.softDollarTier = SoftDollarTier(name: "N", value: "V"); o.cashQty = 1000
    o.mifid2DecisionMaker = "DM"; o.mifid2DecisionAlgo = "DA"; o.mifid2ExecutionTrader = "ET"; o.mifid2ExecutionAlgo = "EA"
    o.dontUseAutoPriceForHedge = true; o.isOmsContainer = true; o.discretionaryUpToLimitPrice = true
    o.usePriceMgmtAlgo = true; o.duration = 60; o.postToAts = 1; o.autoCancelParent = true
    o.advancedErrorOverride = "8229"; o.manualOrderTime = "20261112-09:30:00"
    return .placeOrder(orderID: 12, contract: c, order: o)
}

@Test func everyPlainFieldIsSent() throws {
    let expected: [String] = [
        "3", "12",                                                                       // 0-1
        "12345", "AAPL", "OPT", "20261218", "150.0", "C", "100", "SMART", "CBOE", "USD",
        "AAPL  261218C00150000", "AAPL",                                                 // 2-13
        "ISIN", "US0378331005",                                                          // 14-15
        "SELL", "100", "VOL", "187.25", "1.5", "GTC", "g1", "DU1",                       // 16-23
        "C", "1", "r1", "0", "9",                                                        // 24-28
        "1", "1", "10", "2", "1", "1",                                                   // 29-34
        "", "0.05", "20261112 09:30:00", "20261113 16:00:00", "G", "EqualQuantity", "50", "M1",  // 35-42
        "2", "L", "0", "1", "I", "F",                                                    // 43-48
        "1", "5", "0.01", "0", "0", "",                                                  // 49-54
        "1", "1.1", "1.2", "0.5", "1", "2",                                              // 55-60
        "1", "0.3", "2", "", "",                                                         // 61-65
        "1", "1", "180", "2", "10", "5", "", "T",                                        // 66-73
        "20261112 09:30:00", "20261112 16:00:00", "",                                    // 74-76
        "1", "CA", "IB", "1", "0",                                                       // 77-81
        "", "A1", "1", "a=1;b=2;", "1", "1", "1",                                        // 82-88
        "0",                                                                             // 89
        "STP", "185", "0.1", "184", "183", "1", "1", "X",                                // 90-97
        "N", "V",                                                                        // 98-99
        "1000", "DM", "DA", "ET", "EA",                                                  // 100-104
        "1", "1", "1", "1",                                                              // 105-108
        "60", "1", "1", "8229", "20261112-09:30:00",                                     // 109-113
    ]
    #expect(expected.count == 114)
    #expect(try fields(everyPlainField()) == expected)
}

@Test func deprecatedOrderFieldsAreSent() throws {
    var o = Order(action: .buy, quantity: d("100"), orderType: "LMT", limitPrice: d("187.25"))
    #expect(try fields(.placeOrder(orderID: 12, contract: Contract(symbol: "AAPL"), order: o)) == base)  // all nil
    o.eTradeOnly = true; o.firmQuoteOnly = false; o.nbboPriceCap = d("1.5")
    #expect(try fields(.placeOrder(orderID: 12, contract: Contract(symbol: "AAPL"), order: o))
            == replacing(base, [52: "1", 53: "0", 54: "1.5"]))  // client.py:562-564
}

@Test func volatilityIsSentOnlyForVolOrders() throws {
    let vol = try fields(everyPlainField()), lmt = try fields(everyPlainField(orderType: "LMT"))
    #expect(lmt[62] == "")  // row 62 volatility
    #expect(lmt.count == vol.count)
    #expect(vol.indices.filter { vol[$0] != lmt[$0] } == [18, 62])
}

/// The base case's order and contract, changed by `change`, encoded with order id 12.
private func group(_ change: (inout Contract, inout Order) -> Void) throws -> [String] {
    var c = Contract(symbol: "AAPL")
    var o = Order(action: .buy, quantity: d("100"), orderType: "LMT", limitPrice: d("187.25"))
    change(&c, &o)
    return try fields(.placeOrder(orderID: 12, contract: c, order: o))
}

@Test func bagSendsLegsPricesAndRoutingParams() throws {
    let f = try group { c, o in
        c.secType = "BAG"
        c.comboLegs = [ComboLeg(conID: 265598, ratio: 1, action: .buy, exchange: "SMART"),
                       ComboLeg(conID: 272093, ratio: 2, action: .sell, exchange: "SMART", openClose: 1, shortSaleSlot: 2,
                                designatedLocation: "L", exemptCode: 0)]
        o.orderComboLegs = [OrderComboLeg(price: d("1.25")), OrderComboLeg(price: nil)]
        o.smartComboRoutingParams = [TagValue(tag: "NonGuaranteed", value: "1")]
    }
    let expected = inserting([(34, ["2", "265598", "1", "BUY", "SMART", "0", "0", "", "-1",
                                    "272093", "2", "SELL", "SMART", "1", "2", "L", "0",
                                    "2", "1.25", "", "1", "NonGuaranteed", "1"])], into: replacing(base, [4: "BAG"]))
    #expect(expected.count == 137)
    #expect(f == expected)
}

@Test func bagWithoutLegsSendsThreeZeroCounts() throws {
    let f = try group { c, _ in c.secType = "BAG" }
    #expect(f == inserting([(34, ["0", "0", "0"])], into: replacing(base, [4: "BAG"])))
}

@Test func deltaNeutralOrderSendsItsGroup() throws {
    let f = try group { _, o in
        o.deltaNeutralOrderType = "MKT"; o.deltaNeutralAuxPrice = d("0.1"); o.deltaNeutralConID = 265598
        o.deltaNeutralSettlingFirm = "SF"; o.deltaNeutralClearingAccount = "CA"; o.deltaNeutralClearingIntent = "IB"
        o.deltaNeutralOpenClose = "O"; o.deltaNeutralShortSale = true; o.deltaNeutralShortSaleSlot = 1
        o.deltaNeutralDesignatedLocation = "DL"
    }
    #expect(f == inserting([(65, ["265598", "SF", "CA", "IB", "O", "1", "1", "DL"])],
                           into: replacing(base, [64: "MKT", 65: "0.1"])))
}

@Test func scaleIncrementSendsItsGroup() throws {
    let f = try group { _, o in
        o.scalePriceIncrement = d("0.05"); o.scalePriceAdjustValue = d("0.01"); o.scalePriceAdjustInterval = 60
        o.scaleProfitOffset = d("0.1"); o.scaleAutoReset = true; o.scaleInitPosition = 100; o.scaleInitFillQty = 10
        o.scaleRandomPercent = true
    }
    #expect(f == inserting([(72, ["0.01", "60", "0.1", "1", "100", "10", "1"])], into: replacing(base, [72: "0.05"])))
}

@Test func hedgeTypeSendsItsParam() throws {
    let f = try group { _, o in o.hedgeType = "D"; o.hedgeParam = "0.5" }
    #expect(f == inserting([(76, ["0.5"])], into: replacing(base, [76: "D"])))
}

@Test func deltaNeutralContractIsSent() throws {
    let f = try group { c, _ in c.deltaNeutralContract = DeltaNeutralContract(conID: 265598, delta: d("0.5"), price: d("187.25")) }
    #expect(f == inserting([(81, ["265598", "0.5", "187.25"])], into: replacing(base, [81: "1"])))
}

@Test func algoSendsItsParams() throws {
    let f = try group { _, o in o.algoStrategy = "Adaptive"; o.algoParams = [TagValue(tag: "adaptivePriority", value: "Normal")] }
    #expect(f == inserting([(82, ["1", "adaptivePriority", "Normal"])], into: replacing(base, [82: "Adaptive"])))
    let bare = try group { _, o in o.algoStrategy = "Adaptive" }
    #expect(bare == inserting([(82, ["0"])], into: replacing(base, [82: "Adaptive"])))
}

@Test func pegBenchSendsItsFields() throws {
    let f = try group { _, o in
        o.orderType = "PEG BENCH"; o.referenceContractID = 265598; o.isPeggedChangeAmountDecrease = true
        o.peggedChangeAmount = d("0.5"); o.referenceChangeAmount = 1; o.referenceExchangeID = "ISLAND"
    }
    #expect(f == inserting([(88, ["265598", "1", "0.5", "1.0", "ISLAND"])], into: replacing(base, [18: "PEG BENCH"])))
    let bare = try group { _, o in o.orderType = "PEG BENCH" }
    #expect(bare == inserting([(88, ["0", "0", "0.0", "0.0", ""])], into: replacing(base, [18: "PEG BENCH"])))
}

@Test func conditionsAreSentWithTheirFlags() throws {
    let f = try group { _, o in
        o.conditions = [
            .price(conID: 265598, exchange: "SMART", isMore: true, price: d("180.5"), triggerMethod: 2),
            .time(isMore: false, time: "20261112 15:00:00", conjunction: .or),
            .margin(isMore: true, percent: 30),
            .execution(secType: "STK", exchange: "SMART", symbol: "AAPL"),
            .volume(conID: 265598, exchange: "SMART", isMore: true, volume: 100000),
            .percentChange(conID: 265598, exchange: "SMART", isMore: false, changePercent: d("2.5")),
        ]
        o.conditionsIgnoreRTH = true
    }
    #expect(f == inserting([(89, ["1", "a", "1", "180.5", "265598", "SMART", "2",
                                  "3", "o", "0", "20261112 15:00:00",
                                  "4", "a", "1", "30",
                                  "5", "a", "STK", "SMART", "AAPL",
                                  "6", "a", "1", "100000", "265598", "SMART",
                                  "7", "a", "0", "2.5", "265598", "SMART",
                                  "1", "0"])], into: replacing(base, [89: "6"])))
}

@Test func tailFieldsFollowExchangeAndOrderType() throws {
    /// The fields after row 113; rows 0-113 are the base case with the exchange and order type changed.
    func tail(exchange: String = "SMART", _ orderType: String, _ change: (inout Order) -> Void) throws -> [String] {
        let f = try group { c, o in c.exchange = exchange; o.orderType = orderType; change(&o) }
        #expect(Array(f.prefix(114)) == replacing(base, [9: exchange, 18: orderType]))
        return Array(f.dropFirst(114))
    }
    func mids(_ o: inout Order) { o.midOffsetAtWhole = d("0.01"); o.midOffsetAtHalf = d("0.005") }
    #expect(try tail("PEG BEST") { $0.minCompeteSize = 100; $0.competeAgainstBestOffset = .offset(d("0.02")) }
            == ["100", "0.02"])
    #expect(try tail("PEGBEST") { $0.minCompeteSize = 100; $0.competeAgainstBestOffset = .upToMid; mids(&$0) }
            == ["100", "Infinite", "0.01", "0.005"])
    #expect(try tail("PEG MID") { mids(&$0) } == ["0.01", "0.005"])
    #expect(try tail(exchange: "IBKRATS", "LMT") { $0.minTradeQty = 50 } == ["50"])
    #expect(try tail(exchange: "IBKRATS", "PEGMID") { $0.minTradeQty = 50; mids(&$0) } == ["50", "0.01", "0.005"])
}

/// Review Focus 1: a live openOrder (deltaNeutralOrderType `None`) re-encodes for a modify.
@Test func decodedLiveOrderReencodes() throws {
    let frame = try #require(try recording("liveLimitOrderPlacesAndCancels").first { $0.first == "5" })
    guard case .openOrder(let m) = IBDecoder.decode(body(frame)) else { Issue.record("not decoded"); return }
    let f = try fields(.placeOrder(orderID: 2, contract: m.contract, order: m.order))
    #expect(f.count == 122)  // 114 plus the 8-field None group
    #expect(f[64] == "None")
    #expect(f[24] == "")
    #expect(f[62] == "")  // volatility is dropped for LMT
    #expect(f[76] == "2")  // trailStopPrice: row 68 plus the 8-field shift
}
