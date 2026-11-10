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
    .deletingLastPathComponent().appendingPathComponent("Recorded/liveMarketOrderFillsWithCommission.json").path)

/// Absent until the fill test has run during US regular hours.
@Test(.enabled(if: fillRecorded))
func recordedFillHasCommission() throws {
    var tracker = ExecutionTracker()
    for f in try recording("liveMarketOrderFillsWithCommission") { _ = tracker.apply(IBDecoder.decode(body(f))) }
    #expect(tracker.fills.contains { $0.commission.commission > 0 })
}
