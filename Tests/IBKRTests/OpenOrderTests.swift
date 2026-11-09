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
                                  completedTime: "20261109 15:59:01", completedStatus: "Filled")
}

private func openOrder(_ fields: [String]) -> OpenOrderMessage? {
    guard case .openOrder(let m) = Decoder.decode(body(fields)) else { return nil }
    return m
}

private func isMalformed(_ fields: [String]) -> Bool {
    if case .malformed = Decoder.decode(body(fields)) { return true }
    return false
}

/// Inserts each group after the base-case index given, so the indices stay those of the table.
private func inserting(_ groups: [(after: Int, fields: [String])], into f: [String]) -> [String] {
    var f = f
    for g in groups.sorted(by: { $0.after > $1.after }) { f.insert(contentsOf: g.fields, at: g.after + 1) }
    return f
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
    #expect(Decoder.decode(body(f)) == .openOrder(OpenOrderMessage(
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
    #expect(Decoder.decode(body(completedFields())) == .completedOrder(CompletedOrderMessage(
        permID: 918273001, clientID: 0, orderID: 0, contract: c, order: o, status: .filled,
        completedTime: "20261109 15:59:01", completedStatus: "Filled")))
}

@Test func completedOrderConsumesEveryField() {
    guard case .completedOrder = Decoder.decode(body(completedFields() + ["extra"])) else { Issue.record("not decoded"); return }
    #expect(isMalformed(Array(completedFields().dropLast())))
}

@Test func openOrderSkipsEveryConditionalGroup() {
    var f = openFields(orderType: "PEG BENCH")
    f[61] = "LMT"; f[70] = "1"; f[71] = "1"; f[72] = "1"; f[75] = "0.05"; f[76] = "D"; f[81] = "1"; f[82] = "Adaptive"; f[102] = "2"
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
    #expect(openOrder(f)?.status == .submitted)
    #expect(isMalformed(Array(f.dropLast())))
}

@Test func completedOrderSkipsEveryConditionalGroup() {
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
    guard case .completedOrder(let m) = Decoder.decode(body(f)) else { Issue.record("not decoded"); return }
    #expect(m.status == .filled)
    #expect(m.completedTime == "20261109 15:59:01")
    #expect(isMalformed(Array(f.dropLast())))
}
