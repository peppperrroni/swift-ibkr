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

@Test func placeOrderRefusesLayoutsItCannotEncode() {
    func req(secType: String = "STK", exchange: String = "SMART", orderType: String = "LMT") -> IBRequest {
        var c = Contract(symbol: "AAPL", secType: secType, exchange: exchange)
        c.strike = nil
        return .placeOrder(orderID: 1, contract: c, order: Order(action: .buy, quantity: d("1"), orderType: orderType))
    }
    #expect(throws: IBEncodingError.unsupported("secType BAG")) { try req(secType: "BAG").body() }
    #expect(throws: IBEncodingError.unsupported("exchange IBKRATS")) { try req(exchange: "IBKRATS").body() }
    for t in ["PEG BENCH", "PEGBENCH", "PEG BEST", "PEGBEST", "PEG MID", "PEGMID"] {
        #expect(throws: IBEncodingError.unsupported("orderType \(t)")) { try req(orderType: t).body() }
    }
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

@Test func volatilityIsSentOnlyForVolOrders() throws {
    let vol = try fields(everyPlainField()), lmt = try fields(everyPlainField(orderType: "LMT"))
    #expect(lmt[62] == "")  // row 62 volatility
    #expect(lmt.count == vol.count)
    #expect(vol.indices.filter { vol[$0] != lmt[$0] } == [18, 62])
}
