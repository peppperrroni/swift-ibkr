import Foundation
import Testing
@testable import IBKR

private let unset = "1.7976931348623157E308"

private func open(_ orderID: Int = 12, permID: Int = 918273001, clientID: Int = 1, status: String = "Submitted",
                  parentID: Int = 0) -> IBMessage {
    IBDecoder.decode(body(Fixtures.openOrderFields(
        orderID: orderID, permID: permID, clientID: clientID, symbol: "AAPL", action: "BUY", quantity: "100",
        orderType: "LMT", limitPrice: "187.25", auxPrice: unset, tif: "DAY", parentID: "\(parentID)", outsideRTH: "0",
        orderRef: "r", status: status)))
}

private func completed(permID: Int, status: String = "Filled", filledQuantity: String = "0",
                       parentPermID: String = "") -> IBMessage {
    IBDecoder.decode(body(Fixtures.completedOrderFields(
        orderID: 0, permID: permID, clientID: 0, symbol: "AAPL", action: "BUY", quantity: "100", orderType: "LMT",
        limitPrice: "187.25", auxPrice: unset, tif: "DAY", parentID: "0", outsideRTH: "0", orderRef: "r", status: status,
        completedTime: "20261109 15:59:01", filledQuantity: filledQuantity, parentPermID: parentPermID)))
}

private func status(_ s: OrderStatus, id orderID: Int = 12, filled: String = "0", remaining: String = "100",
                    avg: String? = nil, permID: Int = 918273001, clientID: Int = 1) -> IBMessage {
    .orderStatus(OrderStatusMessage(orderID: orderID, status: s, filled: d(filled), remaining: d(remaining),
                                    averageFillPrice: avg.map(d), permID: permID, parentID: 0, lastFillPrice: nil,
                                    clientID: clientID, whyHeld: "", marketCapPrice: nil))
}

private func error(_ id: Int, _ code: Int, _ text: String = "boom", json: String = "") -> IBMessage {
    .error(IBErrorMessage(requestID: id, code: code, text: text, advancedOrderRejectJSON: json))
}

private let aapl = Contract(symbol: "AAPL")
private let sentOrder = Order(action: .buy, quantity: d("100"), orderType: "LMT", limitPrice: d("187.25"))

@Test func openOrderThenStatusMerges() {
    var t = OrderTracker(clientID: 1)
    let a = t.apply(open())
    #expect(a.count == 1 && a[0].status == .submitted && a[0].remaining == d("100"))
    let b = t.apply(status(.filled, filled: "100", remaining: "0", avg: "187.20"))
    #expect(b.count == 1)
    #expect(b[0].order.limitPrice == d("187.25") && b[0].contract.symbol == "AAPL")
    #expect(b[0].status == .filled && b[0].filled == d("100") && b[0].remaining == 0 && b[0].averageFillPrice == d("187.20"))
    #expect(t.orders.count == 1)
}

@Test func statusBeforeOpenOrderIsHeld() {
    var t = OrderTracker(clientID: 1)
    #expect(t.apply(status(.preSubmitted, filled: "40", remaining: "60")).isEmpty)
    #expect(t.orders.isEmpty)
    let r = t.apply(open())
    #expect(r.count == 1 && r[0].status == .preSubmitted && r[0].filled == d("40") && r[0].remaining == d("60"))
}

@Test func statusAfterSendPublishesFromTheSentOrder() {
    var t = OrderTracker(clientID: 1)
    t.sent(orderID: 12, clientID: 1, contract: aapl, order: sentOrder)
    let r = t.apply(status(.preSubmitted))
    #expect(r.count == 1 && r[0].contract == aapl && r[0].order == sentOrder && r[0].status == .preSubmitted)
}

@Test func identicalRepeatPublishesNothing() {
    var t = OrderTracker(clientID: 1)
    _ = t.apply(open())
    #expect(t.apply(open()).isEmpty)
    #expect(t.apply(status(.submitted, filled: "10", remaining: "90")).count == 1)
    #expect(t.apply(status(.submitted, filled: "10", remaining: "90")).isEmpty)
}

@Test func rejectionBeforeOpenOrder() {
    var t = OrderTracker(clientID: 1)
    t.sent(orderID: 12, clientID: 1, contract: aapl, order: sentOrder)
    let r = t.apply(error(12, 201, "Order rejected"))
    #expect(r.count == 1 && r[0].status == .inactive && r[0].rejectReason == "Order rejected")
}

@Test func rejectedModifyKeepsTheOrderWorking() {
    var t = OrderTracker(clientID: 1)
    _ = t.apply(open())
    let r = t.apply(error(12, 201, "Order rejected"))
    #expect(r.count == 1 && r[0].status == .submitted && r[0].rejectReason == "Order rejected")
}

@Test func completedOrderCancelledAfterPartialFill() {
    var t = OrderTracker(clientID: 1)
    let r = t.apply(completed(permID: 555, status: "Cancelled", filledQuantity: "40"))
    #expect(r.count == 1 && r[0].filled == d("40") && r[0].remaining == d("60") && r[0].status == .cancelled)
}

@Test func cancelConfirmation() {
    var t = OrderTracker(clientID: 1)
    _ = t.apply(open())
    let r = t.apply(error(12, 202, "Order Canceled"))
    #expect(r.count == 1 && r[0].status == .cancelled && r[0].rejectReason == nil)
}

@Test func cancelRejectionKeepsTheOrder() {
    var t = OrderTracker(clientID: 1)
    _ = t.apply(open(status: "Filled"))
    _ = t.apply(status(.filled, filled: "100", remaining: "0"))
    #expect(t.apply(error(12, 10148)).isEmpty)
    #expect(t.orders[0].status == .filled && t.orders[0].rejectReason == nil)
}

@Test func fatalErrorKeepsAFinalStatus() throws {
    var t = OrderTracker(clientID: 1)
    _ = t.apply(open(status: "Filled"))
    _ = t.apply(status(.filled, filled: "100", remaining: "0"))
    let r = t.apply(error(12, 201, "late"))
    try #require(r.count == 1)
    #expect(r[0].status == .filled && r[0].rejectReason == "late")
}

@Test func errorForUnknownOrderChangesNothing() {
    var t = OrderTracker(clientID: 1)
    #expect(t.apply(error(99, 201)).isEmpty)
    #expect(t.orders.isEmpty)
}

@Test func errorForAnotherClientsOrderChangesNothing() {
    var t = OrderTracker(clientID: 1)
    _ = t.apply(open(5, permID: 1, clientID: 2))
    let before = t.orders
    #expect(t.apply(error(5, 201)).isEmpty)
    #expect(t.orders == before)
}

@Test func openOrderDoesNotReviveAFinalStatus() {
    var t = OrderTracker(clientID: 1)
    _ = t.apply(open(status: "Filled"))
    _ = t.apply(status(.filled, filled: "100", remaining: "0"))
    #expect(t.apply(open(status: "Submitted")).isEmpty)
    #expect(t.orders[0].status == .filled)
}

@Test func completedOrderKeepsTheBracketLink() throws {
    var t = OrderTracker(clientID: 1)
    _ = t.apply(open(13, permID: 918273001, parentID: 12))
    _ = t.apply(status(.filled, id: 13, filled: "100", remaining: "0"))
    let before = t.orders[0]
    let r = t.apply(completed(permID: 918273001))
    try #require(r.count == 1)
    #expect(r[0].order == before.order && r[0].order.parentID == 12 && r[0].contract == before.contract)
    #expect(r[0].completedTime != nil)
}

@Test func manualOrderKeyedByPermID() {
    var t = OrderTracker(clientID: 1)
    let a = t.apply(open(0, permID: 5555, clientID: 0))
    #expect(a.count == 1 && a[0].orderID == 0)
    let b = t.apply(status(.filled, id: 0, filled: "100", remaining: "0", permID: 5555, clientID: 0))
    #expect(b.count == 1 && b[0].permID == 5555 && b[0].status == .filled)
    #expect(t.orders.count == 1)
}

@Test func completedOrderJoinsByPermID() {
    var t = OrderTracker(clientID: 1)
    _ = t.apply(open())
    let r = t.apply(completed(permID: 918273001))
    #expect(r.count == 1 && r[0].orderID == 12 && r[0].status == .filled && r[0].completedTime == "20261109 15:59:01")
    #expect(t.orders.count == 1)
    let n = t.apply(completed(permID: 777))
    #expect(n.count == 1 && n[0].permID == 777)
    #expect(t.orders.count == 2 && t.orders[1].permID == 777)
}

@Test func orderBoundLinks() {
    var t = OrderTracker(clientID: 1)
    _ = t.apply(open(0, permID: 5555, clientID: 0))
    _ = t.apply(.orderBound(permID: 5555, clientID: 0, orderID: 41))
    let r = t.apply(status(.filled, id: 41, filled: "100", remaining: "0", permID: 5555, clientID: 0))
    #expect(r.count == 1 && r[0].status == .filled && r[0].orderID == 41)
    #expect(t.orders.count == 1)
}

@Test func warningKeepsAPendingOrderLive() {
    var t = OrderTracker(clientID: 1)
    t.sent(orderID: 12, clientID: 1, contract: aapl, order: sentOrder)
    let r = t.apply(error(12, 321, "Error validating request"))
    #expect(r.count == 1 && r[0].status == .apiPending && r[0].rejectReason == "Error validating request")
}

@Test func whatIfOpenOrderLeavesTheTrackerAlone() {
    var f = Fixtures.openOrderFields(
        orderID: 12, permID: 918273001, clientID: 1, symbol: "AAPL", action: "BUY", quantity: "100", orderType: "LMT",
        limitPrice: "187.25", auxPrice: unset, tif: "DAY", parentID: "0", outsideRTH: "0", orderRef: "r",
        status: "PreSubmitted")
    f[84] = "1"
    var t = OrderTracker(clientID: 1)
    #expect(t.apply(IBDecoder.decode(body(f))).isEmpty)
    #expect(t.orders.isEmpty)
}

@Test func cancelReasonOf202IsKept() {
    var t = OrderTracker(clientID: 1)
    _ = t.apply(open())
    let text = "Order Canceled - reason:We cannot accept an order at a limit price at or more aggressive than 357.97385."
    let r = t.apply(error(12, 202, text))
    #expect(r.count == 1 && r[0].status == .cancelled && r[0].rejectReason == text)
}

@Test func bareCancelHasNoReason() {
    var t = OrderTracker(clientID: 1)
    _ = t.apply(open())
    let r = t.apply(error(12, 202, "Order Canceled - reason:"))
    #expect(r.count == 1 && r[0].status == .cancelled && r[0].rejectReason == nil)
}

@Test func filledOpenOrderWaitsForOrderStatus() throws {
    var t = OrderTracker(clientID: 1)
    #expect(t.apply(open(status: "Filled")).isEmpty)
    #expect(t.orders.isEmpty)
    let r = t.apply(status(.filled, filled: "100", remaining: "0", avg: "187.20"))
    try #require(r.count == 1)
    #expect(r[0].status == .filled && r[0].filled == d("100") && r[0].averageFillPrice == d("187.20"))
    #expect(r[0].order.limitPrice == d("187.25") && r[0].contract.symbol == "AAPL")
}

@Test func filledOpenOrderOfAKnownOrderWaits() {
    var t = OrderTracker(clientID: 1)
    _ = t.apply(open())
    #expect(t.apply(open(status: "Filled")).isEmpty)
    #expect(t.orders[0].status == .submitted)
    let r = t.apply(status(.filled, filled: "100", remaining: "0"))
    #expect(r.count == 1 && r[0].status == .filled && r[0].filled == d("100"))
}

@Test func filledOpenOrderAfterTheFillPublishes() {
    var t = OrderTracker(clientID: 1)
    _ = t.apply(open())
    _ = t.apply(status(.filled, filled: "100", remaining: "0"))
    let r = t.apply(open(status: "Filled", parentID: 5))
    #expect(r.count == 1 && r[0].filled == d("100") && r[0].order.parentID == 5)
}

@Test func heldFilledOpenOrderShowsThroughCompletedOrder() {
    var t = OrderTracker(clientID: 1)
    #expect(t.apply(open(status: "Filled", parentID: 5)).isEmpty)
    let r = t.apply(completed(permID: 918273001, filledQuantity: "100"))
    #expect(r.count == 1 && r[0].status == .filled && r[0].filled == d("100") && r[0].remaining == 0)
    #expect(r.first?.orderID == 12 && r.first?.clientID == 1)
    #expect(r.first?.order.limitPrice == d("187.25") && r.first?.order.parentID == 5, "the held open's order")
    _ = t.apply(status(.filled, filled: "100", remaining: "0"))
    #expect(t.orders.count == 1)
}

@Test func completedOrderCarriesTheFillOfAKnownOrder() {
    var t = OrderTracker(clientID: 1)
    _ = t.apply(open())
    #expect(t.apply(open(status: "Filled")).isEmpty)
    let r = t.apply(completed(permID: 918273001, filledQuantity: "100"))
    #expect(r.count == 1 && r[0].status == .filled && r[0].filled == d("100") && r[0].remaining == 0)
    #expect(t.orders.count == 1)
}

@Test func advancedRejectIsKept() {
    var t = OrderTracker(clientID: 1)
    t.sent(orderID: 12, clientID: 1, contract: aapl, order: sentOrder)
    let r = t.apply(error(12, 201, "Order rejected", json: "{\"r\":1}"))
    #expect(r.count == 1 && r[0].advancedOrderRejectJSON == "{\"r\":1}")
    var u = OrderTracker(clientID: 1)
    u.sent(orderID: 12, clientID: 1, contract: aapl, order: sentOrder)
    let n = u.apply(error(12, 201, "Order rejected"))
    #expect(n.count == 1 && n[0].advancedOrderRejectJSON == nil)
}

@Test func completedOrderCarriesParentPermID() {
    var t = OrderTracker(clientID: 1)
    let a = t.apply(completed(permID: 918273001, parentPermID: "918273000"))
    #expect(a.count == 1 && a[0].order.parentPermID == 918273000)
    var u = OrderTracker(clientID: 1)
    _ = u.apply(open(13, parentID: 12))
    let b = u.apply(completed(permID: 918273001, parentPermID: "918273000"))
    #expect(b.count == 1 && b[0].order.parentPermID == 918273000 && b[0].order.parentID == 12)
}
