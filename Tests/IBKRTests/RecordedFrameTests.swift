import Foundation
import Testing
@testable import IBKR

/// Frames the paper gateway sent during the live tests (Tests/IBKRTests/Recorded, written by LiveTests).
func recording(_ name: String, file: String = #filePath) throws -> [[String]] {
    let url = URL(fileURLWithPath: file).deletingLastPathComponent().appendingPathComponent("Recorded/\(name).json")
    return try JSONDecoder().decode([[String]].self, from: Data(contentsOf: url))
}

/// Every Recorded/*.json, found on disk so a new recording is covered without editing this list.
let recordings: [String] = {
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
    o.openClose = ""; o.volatilityType = 0; o.referencePriceType = 0; o.trailStopPrice = 2; o.clearingIntent = "IB"
    o.adjustedOrderType = "None"; o.cashQty = 0; o.dontUseAutoPriceForHedge = true
    o.deltaNeutralOrderType = "None"; o.deltaNeutralOpenClose = "?"
    let statuses: [OrderStatus] = [.preSubmitted, .preSubmitted, .pendingCancel, .pendingCancel]
    #expect(frames.map(\.count) == [135, 135, 135, 135])
    #expect(frames.map { IBDecoder.decode(body($0)) } == statuses.map {
        .openOrder(OpenOrderMessage(orderID: 2, clientID: 77, permID: 610467324, contract: c, order: o, status: $0))
    })
}

/// An order this client did not place takes the decoded order with IB's `?` dropped to `Order`'s defaults, as
/// ib_async does (wrapper.py:695-698); the contract stays as decoded (`Contract.recreate` keeps `right` `?`).
@Test func untrackedOpenOrderDropsQuestionMarks() throws {
    let frame = try #require(try recording("liveLimitOrderPlacesAndCancels").first { $0.first == "5" })
    var tracker = OrderTracker(clientID: 0)
    let s = try #require(tracker.apply(IBDecoder.decode(body(frame))).first)
    #expect(s.order.deltaNeutralOpenClose == "")
    #expect(s.order.deltaNeutralOrderType == "None" && s.order.clearingIntent == "IB" && s.order.account == "DU0000001")
    #expect(s.contract.right == "?")
    // fields whose default is not "": tif (18) and openClose (21)
    var other = OrderTracker(clientID: 0)
    let t = try #require(other.apply(IBDecoder.decode(body(replacing(frame, [18: "?", 21: "?"])))).first)
    #expect(t.order.tif == "DAY" && t.order.openClose == "O")
}

@Test func recordedLimitOrderEndsCancelled() throws {
    var tracker = OrderTracker(clientID: 77)
    for f in try recording("liveLimitOrderPlacesAndCancels") { _ = tracker.apply(IBDecoder.decode(body(f))) }
    let orders = tracker.orders.filter { $0.contract.symbol == "AAPL" }
    #expect(orders.count == 1)
    #expect(orders.first?.order.limitPrice == d("1"))
    #expect(orders.first?.status == .cancelled)
    #expect(orders.first?.rejectReason == nil)
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
    // The closing SELL: its report arrived live in the 2026-11-10 stage-3 run, with realized P&L.
    let sell = tracker.fills.first { $0.execution.execID == "0000dc8f.6c0b3a8d.01.01" }
    #expect(sell?.execution.price == d("347.52"))
    #expect(sell?.commission.commission == d("1.007162"))
    #expect(sell?.commission.realizedPNL == d("-2.027165"))
}

/// The gateway sent each fill's Filled openOrder before its Filled orderStatus: the tracker must hold it.
@Test(.enabled(if: fillRecorded))
func recordedFillNeverPublishesFilledWithoutTheFill() throws {
    var tracker = OrderTracker(clientID: 77)
    var published: [OrderSnapshot] = []
    for f in try recording("liveOrderFillsWithCommission") { published += tracker.apply(IBDecoder.decode(body(f))) }
    #expect(published.contains { $0.status == .filled })
    #expect(!published.contains { $0.status == .filled && $0.filled == 0 })
}

/// The fill run's connect-time sync replayed the morning's cancelled $1 limit order: the first live completedOrder.
@Test(.enabled(if: fillRecorded))
func recordedCompletedOrderDecodes() throws {
    // The sync replays several completed orders: pick the cancelled $1 BUY by permID.
    let found: CompletedOrderMessage? = try recording("liveOrderFillsWithCommission").lazy.compactMap { f -> CompletedOrderMessage? in
        guard f.first == "101", case .completedOrder(let m) = IBDecoder.decode(body(f)), m.permID == 610467324 else { return nil }
        return m
    }.first
    let m = try #require(found)
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

@Test func recordedAccountSummaryDecodes() throws {
    var values: [String: String] = [:]
    var ends = 0
    for f in try recording("liveAccountSummary") {
        switch IBDecoder.decode(body(f)) {
        case .accountSummary(_, let v) where v.account == "DU0000001" && v.currency == "GBP": values[v.tag] = v.value
        case .accountSummaryEnd: ends += 1
        default: break
        }
    }
    #expect(values["NetLiquidation"] == "4642.32")
    #expect(values["TotalCashValue"] == "4642.32")
    #expect(values["BuyingPower"] == "18569.26")
    #expect(ends == 1)
}

/// IB keeps a 0 row for a closed position; it must not show as one.
@Test(.enabled(if: fillRecorded))
func recordedPositionsGoFlatAgain() throws {
    var tracker = PositionTracker()
    tracker.reload()
    var sets: [[Position]] = []
    for f in try recording("liveOrderFillsWithCommission") {
        if let s = tracker.apply(IBDecoder.decode(body(f))) { sets.append(s) }
    }
    let aapl = sets.map { $0.first { $0.contract.conID == 265598 }?.quantity ?? 0 }
    #expect(aapl.contains(1))
    #expect(aapl.last == 0)
    #expect(sets.last?.contains { $0.contract.conID == 265598 } == false)
    #expect(!sets.flatMap { $0 }.contains { $0.quantity == 0 })
}

@Test(.enabled(if: fillRecorded))
func recordedPnLSingleDecodes() throws {
    let pnls = try recording("liveOrderFillsWithCommission").compactMap { f -> PnL? in
        if case .pnlSingle(_, let p) = IBDecoder.decode(body(f)) { return p }
        return nil
    }
    let p = try #require(pnls.first)
    #expect(p.position == 1)
    #expect(p.daily == d("-4.9739869"))
    #expect(p.unrealized == d("-0.9296179000000393"))
    #expect(p.realized == d("-4.0444118499999995"))
    #expect(p.value == d("347.6103821"))
}

/// IB's price cap cancels an over-aggressive limit with a 202; the tracker keeps its reason as `rejectReason`.
@Test func recordedPriceCapCancelEndsCancelled() throws {
    var tracker = OrderTracker(clientID: 77)
    var snapshots: [OrderSnapshot] = []
    var cap: IBErrorMessage?
    for f in try recording("liveOrderRefusedByPriceCap") {
        let m = IBDecoder.decode(body(f))
        if case .error(let e) = m, e.code == 202 { cap = e }
        snapshots += tracker.apply(m)
    }
    let last = try #require(snapshots.last { $0.orderID == 7 })
    #expect(last.status == .cancelled)
    #expect(last.order.action == .buy && last.order.totalQuantity == 1 && last.order.limitPrice == d("358.53"))
    #expect(last.rejectReason?.contains("357.97385") == true)
    let e = try #require(cap)
    #expect(e.requestID == 7 && e.text.contains("357.97385"))
}

/// AAPL's contractData from the paper gateway (2026-11-11): one entry, the stock on SMART.
@Test func recordedContractDetailsDecodes() throws {
    let frames = try recording("liveContractLookups").filter { $0.first == "10" }
    #expect(frames.count == 1)
    guard let f = frames.first, case .contractData(_, let details) = IBDecoder.decode(body(f)) else {
        Issue.record("no contractData"); return
    }
    #expect(details.contract.conID == 265598)
    #expect(details.minTick == d("0.01"))
    #expect(details.timeZoneID == "US/Eastern")
    #expect(!details.tradingHours.isEmpty)
    #expect(details.secIDList == [TagValue(tag: "ISIN", value: "US0378331005")])
    #expect(details.marketRuleIDs.count == 27 && details.marketRuleIDs.first == 4563)
    #expect(details.industry == "Technology" && details.aggGroup == 1 && details.evMultiplier == nil)
}

/// A paper account without a market-data subscription (2026-11-11): quotes 10197, history 162 «different IP»,
/// tick-by-tick 10189 — all typed refusals; depth gets only notice 2152 and then nothing (which
/// `recordedDepth2152EndsTheDepthStream` turns into a typed end).
@Test func recordedMarketDataRefusalsAreTyped() throws {
    var seen: [Int: Bool] = [:]
    for f in try recording("liveMarketData") {
        guard case .error(let e) = IBDecoder.decode(body(f)), e.requestID > 0 else { continue }
        seen[e.code] = ErrorCode.isNoMarketDataPermission(code: e.code, text: e.text)
    }
    #expect(seen[10197] == true)
    #expect(seen[162] == true)
    #expect(seen[10189] == true)
    #expect(seen[2152] == false)
    #expect(ErrorCode.kind(2152) == .notice)
}

private func connected(_ gateway: FakeGateway) async throws -> IBClient {
    let client = IBClient(connector: gateway.connector)
    try await within2s { try await client.connect(clientID: 7) }
    return client
}

/// The recorded 2152 grants `Top:` only, so the book ends with a typed refusal and the cancel goes out.
@Test func recordedDepth2152EndsTheDepthStream() async throws {
    guard let frame = try recording("liveMarketData").first(where: { $0.first == "4" && $0.count > 3 && $0[3] == "2152" }) else {
        Issue.record("no 2152 frame"); return
    }
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.marketDepth(Contract(symbol: "AAPL"), rows: 5)
    let id = try await gateway.waitForSent(FakeGateway.syncFrames + 1)[FakeGateway.syncFrames][2]
    gateway.feed(replacing(frame, [2: id]))
    await #expect(throws: IBClientError.noMarketDataPermission(code: 2152, text: frame[4])) {
        _ = try await within2s { try await stream.first { _ in true } }
    }
    #expect(try await gateway.waitForSent(FakeGateway.syncFrames + 2)[FakeGateway.syncFrames + 1] == ["11", "1", id, "1"])
    try await within2s { while await client.requestStreamCount != 0 { try await Task.sleep(for: .milliseconds(5)) } }
}

/// Both live execDetails time formats are in the recordings, and every one reads as an instant.
@Test(arguments: recordings)
func recordedExecutionsDecodeWithADate(_ name: String) throws {
    for f in try recording(name) where f.first == "11" {
        guard case .execDetails(_, _, let e) = IBDecoder.decode(body(f)) else { continue }
        #expect(e.date != nil, "\(name): \(e.time)")
    }
}

@Test func recordedExecutionTimesCoverBothFormats() throws {
    var times: [String] = []
    for name in recordings {
        for f in try recording(name) where f.first == "11" {
            if case .execDetails(_, _, let e) = IBDecoder.decode(body(f)) { times.append(e.time) }
        }
    }
    #expect(times.contains { $0.contains("-") && !$0.contains(" ") }, "the live format: \(times)")
    #expect(times.contains { $0.contains(" ") }, "the reply format: \(times)")
}
