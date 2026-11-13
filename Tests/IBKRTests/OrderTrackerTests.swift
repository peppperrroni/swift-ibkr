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
    _ = t.placed(orderID: 12, clientID: 1, contract: aapl, order: sentOrder)
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
    _ = t.placed(orderID: 12, clientID: 1, contract: aapl, order: sentOrder)
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
    _ = t.placed(orderID: 12, clientID: 1, contract: aapl, order: sentOrder)
    let r = t.apply(error(12, 321, "Error validating request"))
    #expect(r.count == 1 && r[0].status == .validationError && r[0].rejectReason == "Error validating request")
    #expect(r.first?.isActive == true && r.first?.isWorking == true)
}

@Test func fatalAfterWarningBeforeAckMakesTheOrderInactive() {
    var t = OrderTracker(clientID: 1)
    _ = t.placed(orderID: 12, clientID: 1, contract: aapl, order: sentOrder)
    _ = t.apply(error(12, 321, "Error validating request"))
    let r = t.apply(error(12, 201, "Order rejected"))
    #expect(r.count == 1 && r[0].status == .inactive && r[0].rejectReason == "Order rejected")
    #expect(r.first?.isActive == false)
}

@Test func errorsOnAFinalOrderKeepItsStatus() throws {
    var t = OrderTracker(clientID: 1)
    _ = t.apply(open(status: "Filled"))
    _ = t.apply(status(.filled, filled: "100", remaining: "0"))
    let w = t.apply(error(12, 321, "late warning"))
    try #require(w.count == 1)
    #expect(w[0].status == .filled && w[0].log.last?.errorCode == 321)   // logged, status kept
    var held = sentOrder
    held.transmit = false
    var u = OrderTracker(clientID: 1)
    _ = u.placed(orderID: 12, clientID: 1, contract: aapl, order: held)
    _ = u.cancelRequested(orderID: 12)   // cancelled locally before IB acknowledged it: final with no permID
    let f = u.apply(error(12, 201, "late reject"))
    try #require(f.count == 1)
    #expect(f[0].status == .cancelled && f[0].log.last?.errorCode == 201)
}

@Test func completedOrderLogsAStatusChange() throws {
    var t = OrderTracker(clientID: 1)
    _ = t.apply(open())
    let before = t.orders[0].log.count
    let r = t.apply(completed(permID: 918273001, status: "Cancelled"))
    try #require(r.count == 1)
    #expect(r[0].log.count == before + 1 && r[0].log.last?.status == .cancelled)
    #expect(t.apply(completed(permID: 918273001, status: "Cancelled")).isEmpty)   // no change, no entry
}

@available(*, deprecated)
@Test func deprecatedSentForwardsToPlaced() {
    var t = OrderTracker(clientID: 1)
    t.sent(orderID: 12, clientID: 1, contract: aapl, order: sentOrder)
    #expect(t.orders.count == 1 && t.orders.first?.status == .pendingSubmit && t.orders.first?.order == sentOrder)
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
    _ = t.placed(orderID: 12, clientID: 1, contract: aapl, order: sentOrder)
    let r = t.apply(error(12, 201, "Order rejected", json: "{\"r\":1}"))
    #expect(r.count == 1 && r[0].advancedOrderRejectJSON == "{\"r\":1}")
    var u = OrderTracker(clientID: 1)
    _ = u.placed(orderID: 12, clientID: 1, contract: aapl, order: sentOrder)
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

@Test func filledOpenOrderOfAPartFilledOrderWaits() {
    var t = OrderTracker(clientID: 1)
    _ = t.apply(open())
    _ = t.apply(status(.submitted, filled: "50", remaining: "50"))
    #expect(t.apply(open(status: "Filled")).isEmpty)
    let r = t.apply(status(.filled, filled: "100", remaining: "0"))
    #expect(r.count == 1 && r[0].status == .filled && r[0].filled == d("100") && r[0].remaining == 0)
}

@Test func openOrderKeepsTheParentPermID() {
    var t = OrderTracker(clientID: 1)
    _ = t.apply(completed(permID: 918273001, parentPermID: "918273000"))
    let r = t.apply(open())
    #expect(r.count == 1 && r[0].orderID == 12 && r[0].order.parentPermID == 918273000)
}

@Test func statusSetsMatchIbAsync() {
    let all: [OrderStatus] = [.pendingSubmit, .pendingCancel, .preSubmitted, .submitted, .apiPending, .apiCancelled,
                              .apiUpdate, .cancelled, .filled, .inactive, .validationError]
    #expect(OrderStatus.apiUpdate.rawValue == "ApiUpdate" && OrderStatus.validationError.rawValue == "ValidationError")
    // order.py:274-300
    #expect(all.filter { $0.isActive } == [.pendingSubmit, .preSubmitted, .submitted, .apiPending, .apiUpdate, .validationError])
    #expect(all.filter { $0.isWaiting } == [.pendingSubmit, .preSubmitted, .apiPending])
    #expect(all.filter { $0.isWorking } == [.submitted, .apiUpdate, .validationError])
    #expect(all.filter { $0.isFinal } == [.apiCancelled, .cancelled, .filled, .inactive])
}

@Test func snapshotTotalAndSets() {
    let s = OrderSnapshot(orderID: 1, clientID: 1, permID: 1, contract: aapl, order: sentOrder, status: .preSubmitted,
                          filled: d("40"), remaining: d("60"), whyHeld: "")
    #expect(s.total == d("100"))
    #expect(s.isActive && s.isWaiting && !s.isWorking)
}

@Test func marketCapPriceIsMerged() throws {
    var t = OrderTracker(clientID: 1)
    _ = t.apply(open())
    let r = t.apply(IBDecoder.decode(body(["3", "12", "Submitted", "0", "100", "0", "918273001", "0", "0", "1", "",
                                           "187.5"])))
    try #require(r.count == 1)
    #expect(r[0].marketCapPrice == d("187.5"))
}

@Test func orderStateMapAndFormatted() {
    let s = OrderState(initMarginChange: d("300000.211"), maintMarginAfter: d("-1234.5"), commission: d("0"))
    let f = s.formatted()
    #expect(f["initMarginChange"] == "300,000.21")
    #expect(f["maintMarginAfter"] == "-1,234.50")
    #expect(f["commission"] == "0.00")
    #expect(f["minCommission"] == "")
    #expect(f.count == 12)
    #expect(OrderState(initMarginChange: d("999.5")).formatted(digits: 0)["initMarginChange"] == "1,000")
    let doubled = s.map { $0 * 2 }
    #expect(doubled == OrderState(initMarginChange: d("600000.422"), maintMarginAfter: d("-2469"), commission: d("0")))
}

private let t0 = Date(timeIntervalSince1970: 1_000), t1 = Date(timeIntervalSince1970: 1_001)
private let t2 = Date(timeIntervalSince1970: 1_002), t3 = Date(timeIntervalSince1970: 1_003)

@Test func placedPublishesPendingSubmitWithALogEntry() {
    var t = OrderTracker(clientID: 1)
    let r = t.placed(orderID: 12, clientID: 1, contract: aapl, order: sentOrder, at: t0)
    #expect(r == [OrderSnapshot(orderID: 12, clientID: 1, permID: 0, contract: aapl, order: sentOrder,
                                status: .pendingSubmit, filled: 0, remaining: d("100"), whyHeld: "",
                                log: [TradeLogEntry(time: t0, status: .pendingSubmit)])])
    #expect(t.orders == r)
    let s = t.apply(status(.preSubmitted), at: t1)
    #expect(s.first?.log == [TradeLogEntry(time: t0, status: .pendingSubmit), TradeLogEntry(time: t1, status: .preSubmitted)])
    #expect(t.apply(status(.preSubmitted), at: t2).isEmpty, "a repeat appends nothing")
}

@Test func modifyLogsAndAnUnchangedSubmittedLogsModified() throws {
    var t = OrderTracker(clientID: 1)
    _ = t.placed(orderID: 12, clientID: 1, contract: aapl, order: sentOrder, at: t0)
    _ = t.apply(status(.submitted), at: t0)
    _ = t.apply(error(12, 110, "The price does not conform"), at: t1)
    #expect(t.orders[0].status == .submitted && t.orders[0].rejectReason == "The price does not conform")
    var changed = sentOrder
    changed.limitPrice = d("187.30")
    let m = try #require(t.placed(orderID: 12, clientID: 1, contract: aapl, order: changed, at: t2).first)
    #expect(m.order.limitPrice == d("187.30") && m.rejectReason == nil && m.status == .submitted)
    #expect(m.log.last == TradeLogEntry(time: t2, status: .submitted, message: "Modify"))
    #expect(m.log.map(\.errorCode).contains(110), "the rejection stays in the log")
    let a = try #require(t.apply(status(.submitted), at: t3).first)
    #expect(a.log.last == TradeLogEntry(time: t3, status: .submitted, message: "Modified"))
    #expect(t.apply(status(.submitted), at: t3).isEmpty)
}

@Test func modifyOfAFinalOrderChangesNothing() {
    var t = OrderTracker(clientID: 1)
    _ = t.placed(orderID: 12, clientID: 1, contract: aapl, order: sentOrder, at: t0)
    _ = t.apply(error(12, 202, "Order Canceled - reason:"), at: t1)
    #expect(t.placed(orderID: 12, clientID: 1, contract: aapl, order: sentOrder, at: t2).isEmpty)
    #expect(t.orders[0].status == .cancelled)
}

@Test func cancelRequestedFollowsIbAsync() {
    var t = OrderTracker(clientID: 1)
    _ = t.placed(orderID: 12, clientID: 1, contract: aapl, order: sentOrder, at: t0)
    #expect(t.cancelRequested(orderID: 12, at: t1).first?.status == .pendingCancel)
    var held = sentOrder
    held.transmit = false
    _ = t.placed(orderID: 13, clientID: 1, contract: aapl, order: held, at: t0)
    let c = t.cancelRequested(orderID: 13, at: t1)
    #expect(c.first?.status == .cancelled && c.first?.log.last == TradeLogEntry(time: t1, status: .cancelled))
    #expect(t.cancelRequested(orderID: 13, at: t2).isEmpty, "final")
    #expect(t.cancelRequested(orderID: 99, at: t2).isEmpty, "unknown")
    let e = t.apply(error(12, 202, "Order Canceled - reason:"), at: t2)
    #expect(e.first?.log.map(\.status) == [.pendingSubmit, .pendingCancel, .cancelled])
    #expect(e.first?.log.last == TradeLogEntry(time: t2, status: .cancelled, message: "Order Canceled - reason:", errorCode: 202))
}

@Test func fatalErrorBeforeAcknowledgementIsLoggedWithItsCode() {
    var t = OrderTracker(clientID: 1)
    _ = t.placed(orderID: 12, clientID: 1, contract: aapl, order: sentOrder, at: t0)
    let r = t.apply(error(12, 201, "Order rejected"), at: t1)
    #expect(r.first?.status == .inactive)
    #expect(r.first?.log.last == TradeLogEntry(time: t1, status: .inactive, message: "Order rejected", errorCode: 201))
}

@Test func openOrderLogsTheStatusItChanges() {
    var t = OrderTracker(clientID: 1)
    #expect(t.apply(open(), at: t0).first?.log == [], "a new order from openOrder starts with no log, as ib_async")
    _ = t.placed(orderID: 14, clientID: 1, contract: aapl, order: sentOrder, at: t0)
    let r = t.apply(open(14, permID: 918273002), at: t1)
    #expect(r.first?.log == [TradeLogEntry(time: t0, status: .pendingSubmit), TradeLogEntry(time: t1, status: .submitted)])
}

private func fill(_ execID: String, orderID: Int = 12, permID: Int = 918273001, shares: String = "100") -> Fill {
    let e = Execution(execID: execID, time: "20261109 10:00:00", account: "DU1", exchange: "ISLAND", side: "BOT",
                      shares: d(shares), price: d("187.25"), permID: permID, clientID: 1, orderID: orderID,
                      liquidation: 0, cumulativeQuantity: d(shares), averagePrice: d("187.25"), orderRef: "",
                      lastLiquidity: 1, pendingPriceRevision: false)
    return Fill(contract: aapl, execution: e, commission: CommissionReport(execID: execID, commission: d("1"), currency: "USD"))
}

@Test func fillsJoinByPermIDAndCorrectionsReplace() throws {
    var t = OrderTracker(clientID: 1)
    _ = t.placed(orderID: 12, clientID: 1, contract: aapl, order: sentOrder, at: t0)
    let a = t.add(fill("e.01.01", permID: 0), at: t1)
    #expect(a.first?.log.last == TradeLogEntry(time: t1, status: .pendingSubmit, message: "Fill 100@187.25"))
    #expect(t.add(fill("e.01.01", permID: 0), at: t2).isEmpty, "the same fill again")
    let c = try #require(t.add(fill("e.01.02", permID: 0, shares: "90"), at: t2).first)
    #expect(c.fills.map(\.execution.execID) == ["e.01.02"] && c.log.last?.message == "Fill 90@187.25")
    _ = t.apply(open(), at: t3)   // indexes permID 918273001
    #expect(t.add(fill("f.01.01", orderID: 0), at: t3).first?.fills.count == 2, "found by permID")
    #expect(t.add(fill("g.01.01", orderID: 77, permID: 5), at: t3).isEmpty, "unknown order")
}

/// `droppingUnknown` must reach every `String` field of `Order`: a new one is a new place IB's `?` can land.
@Test func droppingUnknownCoversEveryStringField() {
    var order = Order(action: .buy, quantity: 1, orderType: "LMT")
    let keys = OrderTracker.stringFields
    for (i, k) in keys.enumerated() { order[keyPath: k] = "k\(i)" }
    let children = Mirror(reflecting: order).children
    let strings = children.compactMap { type(of: $0.value) == String.self ? $0.value as? String : nil }
    #expect(strings.sorted() == keys.indices.map { "k\($0)" }.sorted())
    #expect(!children.contains { type(of: $0.value) == Optional<String>.self }, "a String? field droppingUnknown misses")
}

/// The caller's own order with a field openOrder does not copy (tif) apart from the fixture's.
private func placedOwn(_ tracker: inout OrderTracker) -> Order {
    var mine = Order(action: .buy, quantity: 100, orderType: "LMT", limitPrice: d("187.25"), tif: "GTC")
    mine.orderRef = "r"
    _ = tracker.placed(orderID: 12, clientID: 1, contract: Contract(symbol: "AAPL"), order: mine)
    return mine
}

/// A held Filled openOrder of an own order, applied by its orderStatus, keeps the caller's order.
@Test func ownFilledOrderKeepsItsOrderThroughOrderStatus() throws {
    var tracker = OrderTracker(clientID: 1)
    let mine = placedOwn(&tracker)
    #expect(tracker.apply(open(status: "Filled")).isEmpty)
    let s = try #require(tracker.apply(status(.filled, filled: "100", remaining: "0", avg: "187.25")).first)
    #expect(s.status == .filled && s.permID == 918273001)
    #expect(s.order == mine && s.order.tif == "GTC")
    #expect(s.contract == Contract(symbol: "AAPL"))
}

/// A held Filled openOrder of an own order, consumed by its completedOrder, keeps the caller's order.
@Test func ownFilledOrderKeepsItsOrderThroughCompletedOrder() throws {
    var tracker = OrderTracker(clientID: 1)
    let mine = placedOwn(&tracker)
    #expect(tracker.apply(open(status: "Filled")).isEmpty)
    let s = try #require(tracker.apply(completed(permID: 918273001, filledQuantity: "100")).first)
    #expect(s.status == .filled && s.orderID == 12)
    #expect(s.order == mine && s.order.tif == "GTC")
    #expect(s.contract == Contract(symbol: "AAPL"))
}
