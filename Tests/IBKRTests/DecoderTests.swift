import Foundation
import Testing
@testable import IBKR

@Test func orderStatusDecodes() {
    let m = IBDecoder.decode(body("3", "12", "Submitted", "0", "100", "0", "918273001", "0", "0", "1", "", "1.7976931348623157E308"))
    #expect(m == .orderStatus(OrderStatusMessage(
        orderID: 12, status: .submitted, filled: 0, remaining: 100, averageFillPrice: 0, permID: 918273001,
        parentID: 0, lastFillPrice: 0, clientID: 1, whyHeld: "", marketCapPrice: nil)))
}

@Test func errorDecodes() {
    let text = "Order rejected - reason:x"
    #expect(IBDecoder.decode(body("4", "2", "12", "201", text, "")) ==
        .error(IBErrorMessage(requestID: 12, code: 201, text: text, advancedOrderRejectJSON: "")))
}

@Test func errorWithMinusOneIsConnectionLevel() {
    guard case .error(let e) = IBDecoder.decode(body("4", "2", "-1", "2104", "farm ok", "")) else { Issue.record("not error"); return }
    #expect(e.requestID == -1)
}

@Test func nextValidIDDecodes() { #expect(IBDecoder.decode(body("9", "1", "13")) == .nextValidID(13)) }

@Test func managedAccountsSplitsOnComma() {
    #expect(IBDecoder.decode(body("15", "1", "DU123456,DU654321")) == .managedAccounts(["DU123456", "DU654321"]))
    #expect(IBDecoder.decode(body("15", "1", "DU123456,")) == .managedAccounts(["DU123456"]))
}

@Test func execDetailsDecodes() {
    let m = IBDecoder.decode(body("11", "7", "12", "265598", "AAPL", "STK", "", "0", "", "", "SMART", "USD", "AAPL", "NMS",
        "0000e0d5.6556b5f0.01.01", "20251109 10:00:00", "DU123456", "ISLAND", "BOT", "100", "187.25", "918273001", "1", "0",
        "100", "187.25", "", "", "", "", "1", "0"))
    var c = Contract(symbol: "AAPL", exchange: "SMART", currency: "USD")
    c.conID = 265598; c.strike = 0; c.localSymbol = "AAPL"; c.tradingClass = "NMS"
    let e = Execution(execID: "0000e0d5.6556b5f0.01.01", time: "20251109 10:00:00", account: "DU123456", exchange: "ISLAND",
        side: "BOT", shares: 100, price: d("187.25"), permID: 918273001, clientID: 1, orderID: 12, liquidation: 0,
        cumulativeQuantity: 100, averagePrice: d("187.25"), orderRef: "", lastLiquidity: 1, pendingPriceRevision: false,
        date: Date(timeIntervalSince1970: 1_762_682_400))   // 2025-11-09 10:00:00 UTC
    #expect(m == .execDetails(requestID: 7, contract: c, execution: e))
}

@Test func execDetailsDecodesEVAndModel() {
    func execution(_ ev: [String]) -> Execution? {
        guard case .execDetails(_, _, let e) = IBDecoder.decode(body(["11", "7", "12", "265598", "AAPL", "STK", "", "0", "",
            "", "SMART", "USD", "AAPL", "NMS", "0000e0d5.6556b5f0.01.01", "20251109 10:00:00", "DU123456", "ISLAND", "BOT",
            "100", "187.25", "918273001", "1", "0", "100", "187.25", ""] + ev + ["1", "0"])) else { return nil }
        return e
    }
    let e = execution(["EVR", "0.5", "M1"])
    #expect(e?.evRule == "EVR" && e?.evMultiplier == d("0.5") && e?.modelCode == "M1")
    let old = execution(["", "", ""])
    #expect(old != nil && old?.evRule == "" && old?.evMultiplier == nil && old?.modelCode == "")
}

@Test func commissionReportDecodes() {
    #expect(IBDecoder.decode(body("59", "1", "0000e0d5.6556b5f0.01.01", "1.0", "USD", "1.7976931348623157E308", "1.7976931348623157E308", "")) ==
        .commissionReport(CommissionReport(execID: "0000e0d5.6556b5f0.01.01", commission: d("1.0"), currency: "USD",
                                           realizedPNL: nil, yield: nil, yieldRedemptionDate: nil)))
}

@Test func endMarkersDecode() {
    #expect(IBDecoder.decode(body("53", "1")) == .openOrderEnd)
    #expect(IBDecoder.decode(body("55", "1", "7")) == .execDetailsEnd(requestID: 7))
    #expect(IBDecoder.decode(body("102")) == .completedOrdersEnd)
}

@Test func orderBoundDecodes() {
    #expect(IBDecoder.decode(body("100", "918273001", "1", "12")) == .orderBound(permID: 918273001, clientID: 1, orderID: 12))
}

@Test func currentTimeDecodes() { #expect(IBDecoder.decode(body("49", "1", "1762680000")) == .currentTime(1762680000)) }

@Test func unknownIDIsKept() { #expect(IBDecoder.decode(body("999", "x")) == .unknown(id: 999, fields: ["999", "x"])) }

@Test func truncatedKnownMessageIsMalformed() {
    guard case .malformed(let id, _, _) = IBDecoder.decode(body("3", "12")) else { Issue.record("not malformed"); return }
    #expect(id == 3)
}

@Test func nonNumericIDIsMalformedWithIDZero() {
    guard case .malformed(let id, _, _) = IBDecoder.decode(body("abc")) else { Issue.record("not malformed"); return }
    #expect(id == 0)
}

@Test func escapedErrorTextIsDecoded() {
    #expect(IBDecoder.decode(body("4", "2", "-1", "2104", "Connexion r\\u00e9ussie \\ud83d\\ude00", "{\"t\":\"\\u0022\"}"))
        == .error(IBErrorMessage(requestID: -1, code: 2104, text: "Connexion réussie 😀",
                                 advancedOrderRejectJSON: "{\"t\":\"\\u0022\"}")))
}

@Test func malformedEscapesStayLiteral() {
    let text = "a\\u12 b\\uZZZZ c\\ud83d d\\"
    #expect(IBDecoder.decode(body("4", "2", "-1", "2104", text, ""))
        == .error(IBErrorMessage(requestID: -1, code: 2104, text: text, advancedOrderRejectJSON: "")))
}

@Test func userInfoDecodes() {
    #expect(IBDecoder.decode(body("107", "8", "IBKR")) == .userInfo(requestID: 8, whiteBrandingID: "IBKR"))
    guard case .malformed(let id, _, _) = IBDecoder.decode(body("107")) else { Issue.record("not malformed"); return }
    #expect(id == 107)
}
