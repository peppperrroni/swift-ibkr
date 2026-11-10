/// A byte pipe to the gateway; `TCPSocket` in production, a fake in tests.
protocol Transport: AnyObject, Sendable {
    /// Chunks as read; finishes when the peer closes or after `close()`, throws `IBClientError.transport` on a read error.
    var incoming: AsyncThrowingStream<[UInt8], any Error> { get }
    /// Writes every byte or throws.
    func write(_ bytes: [UInt8]) throws(IBClientError)
    /// Idempotent; ends `incoming`.
    func close()
}

/// Opens a transport; throws `IBClientError` only.
typealias Connector = @Sendable (_ host: String, _ port: Int, _ timeout: Duration) async throws -> any Transport
