import Foundation
import Testing
@testable import IBKR

// Opt-in tests against the owner's real IB Gateway paper account (see README). Skipped unless IBKR_LIVE=1.

private let env = ProcessInfo.processInfo.environment
private let aapl = Contract(symbol: "AAPL")

/// Every managed account id becomes `DU0000001`, inside every field.
func redact(_ frames: [[String]], accounts: [String]) -> [[String]] {
    frames.map { $0.map { field in accounts.reduce(field) { $0.replacingOccurrences(of: $1, with: "DU0000001") } } }
}

// @unchecked Sendable: `frames` sits behind `lock`.
final class FrameRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [[String]] = []
    var tap: @Sendable ([String]) -> Void { { [self] f in lock.withLock { frames.append(f) } } }
    var recorded: [[String]] { lock.withLock { frames } }
}

struct LiveFailure: Error, CustomStringConvertible { var description: String }

/// Waits for the first element of `stream` that satisfies `match`, failing clearly after `limit`.
private func wait<S: AsyncSequence & Sendable>(_ what: String, _ limit: Duration, _ stream: S,
                                               _ match: @escaping @Sendable (S.Element) -> Bool) async throws -> S.Element
where S.Element: Sendable {
    try await withThrowingTaskGroup(of: S.Element.self) { group in
        group.addTask {
            for try await x in stream where match(x) { return x }
            throw LiveFailure(description: "stream ended while waiting for \(what)")
        }
        group.addTask { try await Task.sleep(for: limit); throw LiveFailure(description: "timed out waiting for \(what)") }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}

/// What `account` holds of `conID` in a whole position set; 0 when it holds none.
private func held(_ set: [Position], _ account: String, _ conID: Int) -> Decimal {
    set.filter { $0.account == account && $0.contract.conID == conID }.reduce(0) { $0 + $1.quantity }
}

/// Connects as `clientID`, runs the paper guard, hands the client and the managed accounts to `work`, then always disconnects and writes
/// the recording (named `name`) — also when `work` fails.
private func live(_ name: String, clientID: Int = 77, file: String = #filePath,
                  _ work: (IBClient, [String]) async throws -> Void) async throws {
    let client = IBClient()
    let recorder = FrameRecorder()
    await client.setFrameTap(recorder.tap)
    try await client.connect(clientID: clientID, timeout: .seconds(15))
    var failure: (any Error)?
    var accounts: [String] = []
    for await s in await client.states() {
        if case .connected(_, let a) = s { accounts = a }
        break
    }
    if accounts.isEmpty || !accounts.allSatisfy({ $0.hasPrefix("DU") }) {
        Issue.record("not a paper gateway (accounts: \(accounts.count)); nothing placed")
        await client.disconnect()
        return
    }
    do { try await work(client, accounts) } catch { failure = error }
    await client.disconnect()

    let dir = URL(fileURLWithPath: file).deletingLastPathComponent().appendingPathComponent("Recorded")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try encoder.encode(redact(recorder.recorded, accounts: accounts))
        .write(to: dir.appendingPathComponent("\(name).json"))
    if let failure { throw failure }
}

@Suite(.serialized, .enabled(if: env["IBKR_LIVE"] == "1"))
struct LiveTests {
    @Test func liveConnects() async throws {
        try await live("liveConnects") { client, _ in
            for await s in await client.states() {
                guard case .connected(let version, let accounts) = s else { continue }
                #expect(version == 178)
                #expect(!accounts.isEmpty)
                break
            }
        }
    }

    @Test func liveLimitOrderPlacesAndCancels() async throws {
        try await live("liveLimitOrderPlacesAndCancels") { client, _ in
            let placed = await client.orders().updates
            let cancelled = await client.orders().updates
            let id = try await client.placeOrder(
                aapl, Order(action: .buy, quantity: 1, orderType: "LMT", limitPrice: d("1.00")))
            do {
                _ = try await wait("order \(id) to be PreSubmitted or Submitted", .seconds(15), placed) {
                    $0.orderID == id && ($0.status == .preSubmitted || $0.status == .submitted)
                }
                try await client.cancelOrder(id)
                _ = try await wait("order \(id) to be Cancelled", .seconds(15), cancelled) {
                    $0.orderID == id && $0.status == .cancelled
                }
            } catch {
                try? await client.cancelOrder(id)   // the $1 DAY BUY must not stay working
                throw error
            }
        }
    }

    @Test func liveAccountSummary() async throws {
        try await live("liveAccountSummary") { client, managed in
            do {   // the stream lives only in this scope: leaving it must cancel the subscription
                let summary = try await client.accountSummary(tags: ["NetLiquidation", "TotalCashValue", "BuyingPower"])
                _ = try await wait("a NetLiquidation for every managed account", .seconds(15), summary) { values in
                    managed.allSatisfy { a in values.contains { $0.account == a && $0.tag == "NetLiquidation" } }
                }
            }
            // Counts, never ids: a failed #expect prints its operands.
            let outside = await client.positions().snapshot.filter { !managed.contains($0.account) }.count
            #expect(outside == 0, "positions outside the managed accounts")
            var open = await client.requestStreamCount
            for _ in 0..<20 where open != 0 {
                try await Task.sleep(for: .milliseconds(100))
                open = await client.requestStreamCount
            }
            #expect(open == 0, "the account summary subscription was not cancelled")
        }
    }

    /// Marketable limit orders with `outsideRTH`, so the test also runs pre-market and after hours, where IB does not
    /// fill MKT orders. `IBKR_LIVE_FILL_PRICE` is the current AAPL price; BUY at +1% of it; the SELL is priced 1% under the BUY's fill
    /// (the reference goes stale when the market moves), or under the snapshot's average fill price if there is no fill.
    @Test(.enabled(if: env["IBKR_LIVE_FILL"] == "1"))
    func liveOrderFillsWithCommission() async throws {
        guard let reference = env["IBKR_LIVE_FILL_PRICE"].flatMap({ Decimal(string: $0) }), reference > 0 else {
            Issue.record("set IBKR_LIVE_FILL_PRICE to the current AAPL price; nothing placed")
            return
        }
        func limit(_ action: OrderAction, _ quantity: Decimal, from base: Decimal? = nil) -> Order {
            var price = (base ?? reference) * (action == .buy ? d("1.01") : d("0.99")), rounded = Decimal()
            NSDecimalRound(&rounded, &price, 2, .plain)
            var order = Order(action: action, quantity: quantity, orderType: "LMT", limitPrice: rounded)
            order.outsideRTH = true
            return order
        }
        try await live("liveOrderFillsWithCommission") { client, managed in
            guard let account = managed.first else { throw LiveFailure(description: "no managed account") }
            let q0 = held(await client.positions().snapshot, account, 265598)
            let buyHeld = await client.positions().updates
            let buyFilled = await client.orders().updates
            let fills = await client.executions().updates
            let buyID = try await client.placeOrder(aapl, limit(.buy, 1))
            // From here the paper account may hold AAPL: whatever fails, flatten before rethrowing the first failure.
            var failure: (any Error)?
            var filled = false
            var sellBase = reference
            do {
                let filledSnapshot = try await wait("order \(buyID) to be Filled", .seconds(30), buyFilled) {
                    $0.orderID == buyID && $0.status == .filled
                }
                filled = true
                if let avg = filledSnapshot.averageFillPrice, avg != 0 { sellBase = avg }
                let fill = try await wait("a fill with commission for order \(buyID)", .seconds(30), fills) {
                    $0.execution.orderID == buyID
                }
                sellBase = fill.execution.price
                #expect(fill.commission.execID == fill.execution.execID)
                _ = try await wait("AAPL at \(q0 + 1) in the positions", .seconds(30), buyHeld) { held($0, account, 265598) == q0 + 1 }
                let pnl = try await client.pnlSingle(account: account, conID: 265598)
                _ = try await wait("a P&L for AAPL at position \(q0 + 1)", .seconds(30), pnl) { $0.position == q0 + 1 }

                // clientID "0" in reqExecutions should return every client's fills
                let other = IBClient()
                do {
                    try await other.connect(clientID: 78, timeout: .seconds(15))
                    let seen = await other.executions().snapshot.contains { $0.execution.execID == fill.execution.execID }
                    #expect(seen, "client 78 does not see client 77's execution")
                } catch { await other.disconnect(); throw error }
                await other.disconnect()
            } catch { failure = error }

            // A cancelled test still gets here; only the waits below end early, and the SELL is queued before them.
            var quantity: Decimal = filled ? 1 : 0
            if !filled {
                let settled = await client.orders().updates  // subscribed before the cancel so the final status is not missed
                try? await client.cancelOrder(buyID)
                let final = try? await wait("order \(buyID) to reach a final status", .seconds(15), settled) {
                    $0.orderID == buyID && $0.status.isFinal
                }
                if var final {
                    final = await withFillNumbers(final, client)
                    quantity = final.filled
                    if let avg = final.averageFillPrice, avg != 0 { sellBase = avg }
                    if final.status == .filled && quantity == 0 {
                        Issue.record("BUY \(buyID) is Filled but no fill quantity arrived; check the paper account in TWS and flatten AAPL by hand")
                    }
                } else {
                    // No final status yet: cancel again, then poll the snapshot until it is final.
                    do { try await client.cancelOrder(buyID) } catch { Issue.record("second cancel of BUY \(buyID) failed: \(error)") }
                    var last: OrderSnapshot?
                    for _ in 0..<60 {
                        last = await client.orders().snapshot.first { $0.orderID == buyID }
                        if last?.status.isFinal == true { break }
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                    if let l = last, l.status.isFinal { last = await withFillNumbers(l, client) }
                    quantity = last?.filled ?? 0
                    if let avg = last?.averageFillPrice, avg != 0 { sellBase = avg }
                    if last?.status.isFinal != true || (last?.status == .filled && quantity == 0) {
                        Issue.record("BUY \(buyID) is not final after cancel (status \(String(describing: last?.status)), filled \(quantity)); check the paper account in TWS and flatten AAPL by hand")
                    }
                }
            }
            if quantity > 0 {
                do {
                    let sellFilled = await client.orders().updates
                    let sellHeld = await client.positions().updates
                    let sellFills = await client.executions().updates
                    let sellID = try await client.placeOrder(aapl, limit(.sell, quantity, from: sellBase))
                    _ = try await wait("order \(sellID) to be Filled", .seconds(30), sellFilled) {
                        $0.orderID == sellID && $0.status == .filled
                    }
                    let sellFill = try await wait("a fill with commission for order \(sellID)", .seconds(30), sellFills) {
                        $0.execution.orderID == sellID
                    }
                    do {
                        #expect(sellFill.commission.realizedPNL != nil, "the SELL's commission report carries no realized P&L")
                        if filled {
                            _ = try await wait("AAPL back at \(q0) in the positions", .seconds(30), sellHeld) { held($0, account, 265598) == q0 }
                        }
                    } catch {
                        Issue.record("post-fill checks after the SELL failed: \(error)")
                    }
                } catch {
                    Issue.record("SELL after the BUY failed: \(error); check the paper account in TWS and flatten AAPL by hand")
                }
            }
            if let failure { throw failure }
        }
    }
}

/// openOrder Filled can arrive before the orderStatus with the quantity: re-read the snapshot for up to 5 s until `filled > 0`.
private func withFillNumbers(_ s: OrderSnapshot, _ client: IBClient) async -> OrderSnapshot {
    guard s.status == .filled, s.filled == 0 else { return s }
    for _ in 0..<10 {
        try? await Task.sleep(for: .milliseconds(500))
        if let n = await client.orders().snapshot.first(where: { $0.orderID == s.orderID }), n.filled > 0 { return n }
    }
    return s
}

@Test func frameTapSeesFramesAndRecordingsHideTheAccount() async throws {
    let gateway = FakeGateway(accounts: "DU1")
    let client = IBClient(connector: gateway.connector)
    let recorder = FrameRecorder()
    await client.setFrameTap(recorder.tap)
    try await within2s { try await client.connect(clientID: 7) }
    let frames = recorder.recorded
    #expect(frames.contains(["15", "1", "DU1"]))
    #expect(!frames.contains { $0.first == "178" }, "the server hello is not tapped")
    #expect(redact(frames, accounts: ["DU1"]).contains(["15", "1", "DU0000001"]))
    #expect(redact([["x DU1 y"]], accounts: ["DU1"]) == [["x DU0000001 y"]])

    await client.setFrameTap(nil)
    let count = recorder.recorded.count
    gateway.feed(["9", "1", "5"])
    try await Task.sleep(for: .milliseconds(100))
    #expect(recorder.recorded.count == count)
}
