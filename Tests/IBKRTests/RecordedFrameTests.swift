import Foundation
import Testing
@testable import IBKR

/// Frames the paper gateway sent during the live tests (Tests/IBKRTests/Recorded, written by LiveTests).
private func recording(_ name: String, file: String = #filePath) throws -> [[String]] {
    let url = URL(fileURLWithPath: file).deletingLastPathComponent().appendingPathComponent("Recorded/\(name).json")
    return try JSONDecoder().decode([[String]].self, from: Data(contentsOf: url))
}

/// Every Recorded/*.json, found on disk so a new recording is covered without editing this list.
private let recordings: [String] = {
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Recorded")
    let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    return files.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
}()

@Test(arguments: recordings)
func everyRecordedFrameDecodes(_ name: String) throws {
    for f in try recording(name) {
        switch IBDecoder.decode(body(f)) {
        case .malformed(let id, _, let reason): Issue.record("\(name): message \(id) malformed: \(reason)")
        case .unknown(let id, _): Issue.record("\(name): message \(id) unknown")
        default: break
        }
    }
}

/// The gateway sends deltaNeutralOrderType "None" (not "") and so the 8 conditional fields: 135 fields, not 127.
@Test func recordedOpenOrderDecodes() throws {
    let frames = try recording("liveLimitOrderPlacesAndCancels").filter { $0.first == "5" }
    var c = Contract(symbol: "AAPL")
    c.conID = 265598; c.strike = 0; c.right = "?"; c.localSymbol = "AAPL"; c.tradingClass = "NMS"
    var o = Order(action: .buy, quantity: 1, orderType: "LMT", limitPrice: d("1"), auxPrice: 0, tif: "DAY")
    o.account = "DU0000001"; o.ocaType = 3
    let statuses: [OrderStatus] = [.preSubmitted, .preSubmitted, .pendingCancel, .pendingCancel]
    #expect(frames.map(\.count) == [135, 135, 135, 135])
    #expect(frames.map { IBDecoder.decode(body($0)) } == statuses.map {
        .openOrder(OpenOrderMessage(orderID: 2, clientID: 77, permID: 610467324, contract: c, order: o, status: $0))
    })
}

@Test func recordedLimitOrderEndsCancelled() throws {
    var tracker = OrderTracker(clientID: 77)
    for f in try recording("liveLimitOrderPlacesAndCancels") { _ = tracker.apply(IBDecoder.decode(body(f))) }
    let orders = tracker.orders.filter { $0.contract.symbol == "AAPL" }
    #expect(orders.count == 1)
    #expect(orders.first?.order.limitPrice == d("1"))
    #expect(orders.first?.status == .cancelled)
}

private let fillRecorded = FileManager.default.fileExists(atPath: URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().appendingPathComponent("Recorded/liveOrderFillsWithCommission.json").path)

/// Absent until the fill test has run (needs `IBKR_LIVE_FILL` and `IBKR_LIVE_FILL_PRICE`).
@Test(.enabled(if: fillRecorded))
func recordedFillHasCommission() throws {
    var tracker = ExecutionTracker()
    for f in try recording("liveOrderFillsWithCommission") { _ = tracker.apply(IBDecoder.decode(body(f))) }
    #expect(tracker.fills.contains { $0.commission.commission > 0 })
    // The 2026-11-10 pre-market BUY: an opening fill, so IB sends realizedPNL unset.
    let buy = tracker.fills.first { $0.execution.side == "BOT" }
    #expect(buy?.execution.price == d("351.66"))
    #expect(buy?.commission.commission == d("1.000003"))
    #expect(buy?.commission.realizedPNL == nil)
}

/// The fill run's connect-time sync replayed the morning's cancelled $1 limit order: the first live completedOrder.
@Test(.enabled(if: fillRecorded))
func recordedCompletedOrderDecodes() throws {
    let frame = try #require(try recording("liveOrderFillsWithCommission").first { $0.first == "101" })
    guard case .completedOrder(let m) = IBDecoder.decode(body(frame)) else { Issue.record("not a completedOrder"); return }
    #expect(m.permID == 610467324)
    #expect(m.contract.symbol == "AAPL" && m.contract.conID == 265598)
    #expect(m.order.action == .buy && m.order.totalQuantity == 1 && m.order.orderType == "LMT")
    #expect(m.order.limitPrice == d("1"))
    #expect(m.status == .cancelled)
    #expect(m.completedTime == "20261110 06:20:29 US/Eastern")
    #expect(m.completedStatus == "Cancelled by Trader")
    #expect(m.filledQuantity == 0)
}

/// From the gateway's API log of 2026-11-10 (client 78's sync, account redacted):
/// a filled order's completedOrder carries totalQuantity 0 and the size only in filledQuantity.
private let filledCompletedOrder = "101;265598;AAPL;STK;;0;?;;SMART;USD;AAPL;NMS;BUY;0;LMT;357.0;0.0;DAY;;DU0000001;;0;;610467325;1;0;0;;;;;;;;;;0;;-1;;;;;;2147483647;0;0;;3;0;;0;None;;0;0;0;;0;0;;;;0;0;0;2147483647;2147483647;;;;IB;0;0;;0;Filled;0;0;0;358.0;1.7976931348623157E308;0;1;0;;1;2147483647;0;Not an insider or substantial shareholder;0;0;9223372036854775807;20261110 06:56:31 US/Eastern;Filled Size: 1;;;;;".split(separator: ";", omittingEmptySubsequences: false).map(String.init)

@Test func filledCompletedOrderNeverHasNegativeRemaining() throws {
    #expect(filledCompletedOrder.count == 100)
    var tracker = OrderTracker(clientID: 78)
    let r = tracker.apply(IBDecoder.decode(body(filledCompletedOrder)))
    try #require(r.count == 1)
    #expect(r[0].status == .filled && r[0].permID == 610467325)
    #expect(r[0].order.totalQuantity == 0, "kept as IB sent it")
    #expect(r[0].filled == 1 && r[0].remaining == 0)
}
