import Foundation
@testable import IBKR

/// A scripted gateway: answers the hello and the connect-time requests the way IB Gateway does.
// @unchecked Sendable: the mutable state (`sawHello`, `sent`, `closed`, `_onRequest`) sits behind `lock`.
final class FakeGateway: Transport, @unchecked Sendable {
    let incoming: AsyncThrowingStream<[UInt8], any Error>
    private let continuation: AsyncThrowingStream<[UInt8], any Error>.Continuation
    private let serverVersion: String, nextValidID: Int, accounts: String, answersStartAPI: Bool
    private let answersPositions: Bool
    private let lock = NSLock()
    private var sawHello = false
    private var sent: [[String]] = []
    private var closed = false
    private var _onRequest: (@Sendable ([String]) -> [[String]])?

    init(serverVersion: String = "178", nextValidID: Int = 1, accounts: String = "DU1", answersStartAPI: Bool = true,
         answersPositions: Bool = true) {
        (incoming, continuation) = AsyncThrowingStream.makeStream()
        self.serverVersion = serverVersion
        self.nextValidID = nextValidID
        self.accounts = accounts
        self.answersStartAPI = answersStartAPI
        self.answersPositions = answersPositions
    }

    var connector: Connector { { _, _, _ in self } }

    /// Replies to a framed request, fed before the defaults.
    var onRequest: (@Sendable ([String]) -> [[String]])? {
        get { lock.withLock { _onRequest } }
        set { lock.withLock { _onRequest = newValue } }
    }

    func feed(_ fields: [String]) { feedRaw(Frame.encode(body(fields))) }

    func feedRaw(_ bytes: [UInt8]) { continuation.yield(bytes) }

    var isClosed: Bool { lock.withLock { closed } }

    func close() {
        lock.withLock { closed = true }
        continuation.finish()
    }

    func write(_ bytes: [UInt8]) throws(IBClientError) {
        let (wasClosed, isHello) = lock.withLock { () -> (Bool, Bool) in
            defer { sawHello = true }
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
        case "7": feed(["55", "1", fields[2]])
        case "61" where answersPositions: feed(["62", "1"])
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
