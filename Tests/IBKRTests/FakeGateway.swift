import Foundation
@testable import IBKR

/// A scripted gateway: answers the hello and the connect-time requests the way IB Gateway does.
// @unchecked Sendable: the mutable state (`sawHello`, `sent`, `closed`, `_onRequest`) sits behind `lock`.
final class FakeGateway: Transport, @unchecked Sendable {
    let incoming: AsyncThrowingStream<[UInt8], any Error>
    private let continuation: AsyncThrowingStream<[UInt8], any Error>.Continuation
    private let serverVersion: String, nextValidID: Int, accounts: String, answersStartAPI: Bool
    private let answersPositions: Bool, answersAccountUpdates: Bool, answersExecutions: Bool
    private let lock = NSLock()
    private var sawHello = false
    private var sent: [[String]] = []
    private var closed = false
    private var _writesAfterClose = 0
    private var _onRequest: (@Sendable ([String]) -> [[String]])?

    init(serverVersion: String = "178", nextValidID: Int = 1, accounts: String = "DU1", answersStartAPI: Bool = true,
         answersPositions: Bool = true, answersAccountUpdates: Bool = true, answersExecutions: Bool = true) {
        (incoming, continuation) = AsyncThrowingStream.makeStream()
        self.serverVersion = serverVersion
        self.nextValidID = nextValidID
        self.accounts = accounts
        self.answersStartAPI = answersStartAPI
        self.answersPositions = answersPositions
        self.answersAccountUpdates = answersAccountUpdates
        self.answersExecutions = answersExecutions
    }

    /// What `connect` sends with one account: 71, 16, 99, 7, 61, 6.
    static let syncFrames = 6

    var connector: Connector { { _, _, _ in self } }

    /// Replies to a framed request, fed before the defaults.
    var onRequest: (@Sendable ([String]) -> [[String]])? {
        get { lock.withLock { _onRequest } }
        set { lock.withLock { _onRequest = newValue } }
    }

    func feed(_ fields: [String]) { feedRaw(Frame.encode(body(fields))) }

    func feedRaw(_ bytes: [UInt8]) { continuation.yield(bytes) }

    var isClosed: Bool { lock.withLock { closed } }

    /// Writes attempted after `close()`; they throw and never reach the sent frames.
    var writesAfterClose: Int { lock.withLock { _writesAfterClose } }

    /// Returns once the client closed this transport, within 2 s.
    func waitUntilClosed() async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !isClosed {
            guard ContinuousClock.now < deadline else { throw TimedOut() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func close() {
        lock.withLock { closed = true }
        continuation.finish()
    }

    func write(_ bytes: [UInt8]) throws(IBClientError) {
        let (wasClosed, isHello) = lock.withLock { () -> (Bool, Bool) in
            defer { sawHello = true }
            if closed { _writesAfterClose += 1 }
            return (closed, !sawHello)
        }
        if wasClosed { throw .connectionClosed }
        if isHello { return feed([serverVersion, "20261110 10:22:12 GMT"]) }

        let fields = FieldReader(Array(bytes.dropFirst(4))).fields   // one write is one frame
        for reply in onRequest?(fields) ?? [] { feed(reply) }
        // recorded after the replies, so a test that waited for a request can close behind its answer
        defer { lock.withLock { sent.append(fields) } }
        switch fields.first {
        case "71" where answersStartAPI:
            feed(["9", "1", "\(nextValidID)"])
            feed(["15", "1", accounts])
        case "16": feed(["53", "1"])
        case "99": feed(["102"])
        case "7" where answersExecutions: feed(["55", "1", fields[2]])
        case "61" where answersPositions: feed(["62", "1"])
        case "6" where answersAccountUpdates && fields[2] == "1": feed(["54", "1", fields[3]])
        // only the sync's 76s (several accounts): a consumer's accountUpdatesMulti must wait for the test's end marker
        case "76" where answersAccountUpdates && accounts.contains(","): feed(["74", "1", fields[2]])
        default: break
        }
    }

    /// Every framed write so far (hello excluded), once there are at least `count`.
    func waitForSent(_ count: Int, timeout: Duration = .seconds(2)) async throws -> [[String]] {
        let deadline = ContinuousClock.now + timeout
        while true {
            let all = lock.withLock { sent }
            if all.count >= count { return all }
            guard ContinuousClock.now < deadline else { throw TimedOut() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

/// Hands out one gateway per connect, in order; a `nil` in the list, or a list used up, refuses that connect.
actor Gateways {
    private var list: [FakeGateway?]
    private(set) var connects = 0   // every attempt, refused ones included
    init(_ list: [FakeGateway?]) { self.list = list }

    func next() throws(IBClientError) -> FakeGateway {
        connects += 1
        guard !list.isEmpty, let gateway = list.removeFirst() else { throw .transport("refused") }
        return gateway
    }

    nonisolated var connector: Connector { { _, _, _ in try await self.next() } }
}
