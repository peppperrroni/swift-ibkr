import Testing
@testable import IBKR

@Test func errorKinds() {
    for c in [2104, 2100, 2199, 10167, 399, 404, 161, 10147, 10148, 165, 1101, 1102] { #expect(ErrorCode.kind(c) == .notice) }
    #expect(ErrorCode.kind(202) == .orderCancelled)
    for c in [201, 200, 354, 2200, 2099] { #expect(ErrorCode.kind(c) == .fatal) }
}

@Test func noMarketDataPermissionCodes() {
    for c in [354, 10089, 10168, 10186, 10197] { #expect(ErrorCode.isNoMarketDataPermission(code: c, text: "")) }
    #expect(ErrorCode.isNoMarketDataPermission(code: 162, text: "Historical Market Data Service error message:No market data permissions for NASDAQ STK"))
    #expect(!ErrorCode.isNoMarketDataPermission(code: 162, text: "Historical Market Data Service error message:API historical data query cancelled: 1"))
    #expect(!ErrorCode.isNoMarketDataPermission(code: 200, text: "permission"))
}

@Test func kindTableAdditions() {
    for c in [317, 10090, 10091] { #expect(ErrorCode.kind(c) == .notice) }
}
