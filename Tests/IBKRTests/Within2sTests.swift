import Testing
@testable import IBKR

@Test func within2sTimesOutOnStuckTaskValue() async throws {
    // Never finishes and ignores cancellation, like the unstructured reader that hung Task 6's suite.
    let stuck = Task<Void, Never> { await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in } }
    await #expect(throws: TimedOut.self) { try await within2s { await stuck.value } }
}
