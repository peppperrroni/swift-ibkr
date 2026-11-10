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
private func wait<T: Sendable>(_ what: String, _ limit: Duration, _ stream: AsyncStream<T>,
                               _ match: @escaping @Sendable (T) -> Bool) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            for await x in stream where match(x) { return x }
            throw LiveFailure(description: "stream ended while waiting for \(what)")
        }
        group.addTask { try await Task.sleep(for: limit); throw LiveFailure(description: "timed out waiting for \(what)") }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}

/// Connects as `clientID`, runs the paper guard, hands the client to `work`, then always disconnects and writes
/// the recording (named `name`) — also when `work` fails.
private func live(_ name: String, clientID: Int = 77, file: String = #filePath,
                  _ work: (IBClient, String) async throws -> Void) async throws {
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
    do { try await work(client, name) } catch { failure = error }
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
            _ = try await wait("order \(id) to be PreSubmitted or Submitted", .seconds(15), placed) {
                $0.orderID == id && ($0.status == .preSubmitted || $0.status == .submitted)
            }
            try await client.cancelOrder(id)
            _ = try await wait("order \(id) to be Cancelled", .seconds(15), cancelled) {
                $0.orderID == id && $0.status == .cancelled
            }
        }
    }

    @Test(.enabled(if: env["IBKR_LIVE_FILL"] == "1"))
    func liveMarketOrderFillsWithCommission() async throws {
        try await live("liveMarketOrderFillsWithCommission") { client, _ in
            let buyFilled = await client.orders().updates
            let fills = await client.executions().updates
            let buyID = try await client.placeOrder(aapl, Order(action: .buy, quantity: 1, orderType: "MKT"))
            _ = try await wait("order \(buyID) to be Filled", .seconds(30), buyFilled) {
                $0.orderID == buyID && $0.status == .filled
            }
            // The BUY filled: the SELL must run whatever the checks below do, so no AAPL position is left behind.
            var failure: (any Error)?
            do {
                let fill = try await wait("a fill with commission for order \(buyID)", .seconds(30), fills) {
                    $0.execution.orderID == buyID
                }
                #expect(fill.commission.execID == fill.execution.execID)

                // clientID "0" in reqExecutions should return every client's fills
                let other = IBClient()
                try await other.connect(clientID: 78, timeout: .seconds(15))
                let seen = await other.executions().snapshot.contains { $0.execution.execID == fill.execution.execID }
                await other.disconnect()
                #expect(seen, "client 78 does not see client 77's execution")
            } catch { failure = error }

            let sellFilled = await client.orders().updates
            let sellID = try await client.placeOrder(aapl, Order(action: .sell, quantity: 1, orderType: "MKT"))
            _ = try await wait("order \(sellID) to be Filled", .seconds(30), sellFilled) {
                $0.orderID == sellID && $0.status == .filled
            }
            if let failure { throw failure }
        }
    }
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
