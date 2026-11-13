import Foundation
import Testing
@testable import IBKR

private let id1 = "0000e0d5.6556b5f0.01.01"
private let id2 = "0000e0d5.6556b5f0.01.02"

private func exec(_ id: String = id1, price: String = "187.25") -> IBMessage {
    .execDetails(requestID: 7, contract: Contract(symbol: "AAPL"), execution: Execution(
        execID: id, time: "20261109 15:59:01", account: "DU1", exchange: "ISLAND", side: "BOT", shares: d("100"),
        price: d(price), permID: 918273001, clientID: 1, orderID: 12, liquidation: 0, cumulativeQuantity: d("100"),
        averagePrice: d(price), orderRef: "", lastLiquidity: 1, pendingPriceRevision: false))
}

private func commission(_ id: String = id1) -> IBMessage {
    .commissionReport(CommissionReport(execID: id, commission: d("1.0"), currency: "USD",
                                       realizedPNL: nil, yield: nil, yieldRedemptionDate: nil))
}

@Test func execThenCommissionPublishesOnce() {
    var t = ExecutionTracker()
    #expect(t.apply(exec()) == [])
    let f = t.apply(commission())
    #expect(f.count == 1 && f[0].execution.execID == id1 && f[0].commission.commission == d("1.0"))
    #expect(f[0].contract.symbol == "AAPL")
}

@Test func unmatchedHalvesAreCapped() {
    var t = ExecutionTracker(maxPending: 3)
    let ids = ["a.01", "b.01", "c.01", "d.01"]
    for id in ids { #expect(t.apply(commission(id)) == []) }
    #expect(t.apply(exec(ids[0])) == [])   // the oldest of four lone halves went over the cap of three
    #expect(t.apply(exec(ids[3])).count == 1)
}

@Test func commissionBeforeExecWaits() {
    var t = ExecutionTracker()
    #expect(t.apply(commission()) == [])
    #expect(t.apply(exec()).count == 1)
}

@Test func repeatedExecPublishesNothing() {
    var t = ExecutionTracker()
    _ = t.apply(exec()); _ = t.apply(commission())
    #expect(t.apply(exec()) == [])
    #expect(t.apply(commission()) == [])
    #expect(t.fills.count == 1)
}

@Test func correctionReplaces() {
    var t = ExecutionTracker()
    _ = t.apply(exec()); _ = t.apply(commission())
    #expect(t.apply(exec(id2, price: "187.30")) == [])
    #expect(t.apply(commission(id2)).count == 1)
    #expect(t.fills.count == 1)
    #expect(t.fills[0].execution.price == d("187.30"))
    // IB resending the old execution's halves must not bring the superseded fill back.
    #expect(t.apply(exec()) == [])
    #expect(t.apply(commission()) == [])
    #expect(t.fills.count == 1 && t.fills[0].execution.execID == id2)
}

@Test func unsetRealizedPNLIsNil() {
    var t = ExecutionTracker()
    _ = t.apply(exec())
    _ = t.apply(IBDecoder.decode(body("59", "1", id1, "1.0", "USD", "1.7976931348623157E308", "1.7976931348623157E308", "")))
    #expect(t.fills[0].commission.realizedPNL == nil)
}

@Test func otherMessagesIgnored() {
    var t = ExecutionTracker()
    #expect(t.apply(.orderStatus(OrderStatusMessage(orderID: 1, status: .filled, filled: 1, remaining: 0,
        averageFillPrice: nil, permID: 1, parentID: 0, lastFillPrice: nil, clientID: 1, whyHeld: "", marketCapPrice: nil))) == [])
}

@Test func lateOriginalDoesNotOverwriteCorrection() {
    var t = ExecutionTracker()
    _ = t.apply(exec()); _ = t.apply(exec(id2, price: "187.30"))
    #expect(t.apply(commission(id2)).count == 1)
    #expect(t.apply(commission()) == [])
    #expect(t.fills.count == 1 && t.fills[0].execution.execID == id2)
}

@Test func correctionCommissionBeforeExec() {
    var t = ExecutionTracker()
    _ = t.apply(exec()); _ = t.apply(commission())
    #expect(t.apply(commission(id2)) == [])
    #expect(t.apply(exec(id2, price: "187.30")).count == 1)
    #expect(t.fills.count == 1 && t.fills[0].execution.execID == id2)
}
