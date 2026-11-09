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

@Test func limitOrderMatchesProtocolTable() throws {
    let expected: [String] = [
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
    #expect(expected.count == 114)
    #expect(try limit("187.25").body() == expected.flatMap { Array($0.utf8) + [0] })
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
