import Foundation
import Testing
@testable import IBKR

private let unset = "1.7976931348623157E308"

private func open(_ orderID: Int = 12, permID: Int = 918273001, clientID: Int = 1, status: String = "Submitted") -> IBMessage {
    Decoder.decode(body(Fixtures.openOrderFields(
        orderID: orderID, permID: permID, clientID: clientID, symbol: "AAPL", action: "BUY", quantity: "100",
        orderType: "LMT", limitPrice: "187.25", auxPrice: unset, tif: "DAY", parentID: "0", outsideRTH: "0",
        orderRef: "r", status: status)))
}

private func completed(permID: Int, status: String = "Filled") -> IBMessage {
    Decoder.decode(body(Fixtures.completedOrderFields(
        orderID: 0, permID: permID, clientID: 0, symbol: "AAPL", action: "BUY", quantity: "100", orderType: "LMT",
        limitPrice: "187.25", auxPrice: unset, tif: "DAY", parentID: "0", outsideRTH: "0", orderRef: "r", status: status,
        completedTime: "20261109 15:59:01")))
}

private func status(_ s: OrderStatus, id orderID: Int = 12, filled: String = "0", remaining: String = "100",
                    avg: String? = nil, permID: Int = 918273001, clientID: Int = 1) -> IBMessage {
    .orderStatus(OrderStatusMessage(orderID: orderID, status: s, filled: d(filled), remaining: d(remaining),
                                    averageFillPrice: avg.map(d), permID: permID, parentID: 0, lastFillPrice: nil,
                                    clientID: clientID, whyHeld: "", marketCapPrice: nil))
}

private func error(_ id: Int, _ code: Int, _ text: String = "boom") -> IBMessage {
    .error(IBErrorMessage(requestID: id, code: code, text: text, advancedOrderRejectJSON: ""))
}

private let aapl = Contract(symbol: "AAPL")
private let sentOrder = Order(action: .buy, quantity: d("100"), orderType: "LMT", limitPrice: d("187.25"))

@Test func openOrderThenStatusMerges() {
    var t = OrderTracker()
    let a = t.apply(open())
    #expect(a.count == 1 && a[0].status == .submitted && a[0].remaining == d("100"))
    let b = t.apply(status(.filled, filled: "100", remaining: "0", avg: "187.20"))
    #expect(b.count == 1)
    #expect(b[0].order.limitPrice == d("187.25") && b[0].contract.symbol == "AAPL")
    #expect(b[0].status == .filled && b[0].filled == d("100") && b[0].remaining == 0 && b[0].averageFillPrice == d("187.20"))
    #expect(t.orders.count == 1)
}

@Test func statusBeforeOpenOrderIsHeld() {
    var t = OrderTracker()
    #expect(t.apply(status(.preSubmitted, filled: "40", remaining: "60")).isEmpty)
    #expect(t.orders.isEmpty)
    let r = t.apply(open())
    #expect(r.count == 1 && r[0].status == .preSubmitted && r[0].filled == d("40") && r[0].remaining == d("60"))
}

@Test func statusAfterSendPublishesFromTheSentOrder() {
    var t = OrderTracker()
    t.sent(orderID: 12, clientID: 1, contract: aapl, order: sentOrder)
    let r = t.apply(status(.preSubmitted))
    #expect(r.count == 1 && r[0].contract == aapl && r[0].order == sentOrder && r[0].status == .preSubmitted)
}

@Test func identicalRepeatPublishesNothing() {
    var t = OrderTracker()
    _ = t.apply(open())
    #expect(t.apply(open()).isEmpty)
    #expect(t.apply(status(.submitted, filled: "10", remaining: "90")).count == 1)
    #expect(t.apply(status(.submitted, filled: "10", remaining: "90")).isEmpty)
}

@Test func rejectionBeforeOpenOrder() {
    var t = OrderTracker()
    t.sent(orderID: 12, clientID: 1, contract: aapl, order: sentOrder)
    let r = t.apply(error(12, 201, "Order rejected"))
    #expect(r.count == 1 && r[0].status == .inactive && r[0].rejectReason == "Order rejected")
}

@Test func cancelConfirmation() {
    var t = OrderTracker()
    _ = t.apply(open())
    let r = t.apply(error(12, 202, "Order Canceled"))
    #expect(r.count == 1 && r[0].status == .cancelled && r[0].rejectReason == nil)
}

@Test func cancelRejectionKeepsTheOrder() {
    var t = OrderTracker()
    _ = t.apply(open(status: "Filled"))
    #expect(t.apply(error(12, 10148)).isEmpty)
    #expect(t.orders[0].status == .filled && t.orders[0].rejectReason == nil)
}

@Test func fatalErrorKeepsAFinalStatus() {
    var t = OrderTracker()
    _ = t.apply(open(status: "Filled"))
    let r = t.apply(error(12, 201, "late"))
    #expect(r[0].status == .filled && r[0].rejectReason == "late")
}

@Test func errorForUnknownOrderChangesNothing() {
    var t = OrderTracker()
    #expect(t.apply(error(99, 201)).isEmpty)
    #expect(t.orders.isEmpty)
}

@Test func errorMatchesOwnClientsOrder() {
    var t = OrderTracker()
    t.sent(orderID: 5, clientID: 1, contract: aapl, order: sentOrder)
    _ = t.apply(open(12, permID: 1, clientID: 2))
    _ = t.apply(open(12, permID: 2, clientID: 1))
    let r = t.apply(error(12, 202))
    #expect(r.count == 1 && r[0].clientID == 1)
}

@Test func ambiguousErrorWithoutSentMatchesNone() {
    var t = OrderTracker()
    _ = t.apply(open(12, permID: 1, clientID: 2))
    _ = t.apply(open(12, permID: 2, clientID: 1))
    #expect(t.apply(error(12, 202)).isEmpty)
}

@Test func manualOrderKeyedByPermID() {
    var t = OrderTracker()
    let a = t.apply(open(0, permID: 5555, clientID: 0))
    #expect(a.count == 1 && a[0].orderID == 0)
    let b = t.apply(status(.filled, id: 0, filled: "100", remaining: "0", permID: 5555, clientID: 0))
    #expect(b.count == 1 && b[0].permID == 5555 && b[0].status == .filled)
    #expect(t.orders.count == 1)
}

@Test func completedOrderJoinsByPermID() {
    var t = OrderTracker()
    _ = t.apply(open())
    let r = t.apply(completed(permID: 918273001))
    #expect(r.count == 1 && r[0].orderID == 12 && r[0].status == .filled && r[0].completedTime == "20261109 15:59:01")
    #expect(t.orders.count == 1)
    let n = t.apply(completed(permID: 777))
    #expect(n.count == 1 && n[0].permID == 777)
    #expect(t.orders.count == 2 && t.orders[1].permID == 777)
}

@Test func orderBoundLinks() {
    var t = OrderTracker()
    _ = t.apply(open(0, permID: 5555, clientID: 0))
    _ = t.apply(.orderBound(permID: 5555, clientID: 0, orderID: 41))
    let r = t.apply(status(.filled, id: 41, filled: "100", remaining: "0", permID: 5555, clientID: 0))
    #expect(r.count == 1 && r[0].status == .filled && r[0].orderID == 41)
    #expect(t.orders.count == 1)
}
