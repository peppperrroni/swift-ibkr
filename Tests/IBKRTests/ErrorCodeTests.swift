import Testing
@testable import IBKR

@Test func errorKinds() {
    for c in [2104, 2100, 2199, 10167, 399, 404, 161, 10147, 10148, 165] { #expect(ErrorCode.kind(c) == .notice) }
    #expect(ErrorCode.kind(202) == .orderCancelled)
    for c in [201, 200, 354, 2200, 2099] { #expect(ErrorCode.kind(c) == .fatal) }
}
