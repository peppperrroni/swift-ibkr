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
    // Seen live on a paper account without a data subscription and no other session open (2026-11-11).
    #expect(ErrorCode.isNoMarketDataPermission(code: 162, text: "Historical Market Data Service error message:Trading TWS session is connected from a different IP address"))
    #expect(ErrorCode.isNoMarketDataPermission(code: 10189, text: "Failed to request tick-by-tick data.No market data permissions for ISLAND STK"))
    #expect(!ErrorCode.isNoMarketDataPermission(code: 10189, text: "Failed to request tick-by-tick data."))
    #expect(ErrorCode.isNoMarketDataPermission(code: 420, text: "Invalid Real-time Query:No market data permissions for NYSE STK"))
    #expect(!ErrorCode.isNoMarketDataPermission(code: 420, text: "Invalid Real-time Query:Historical data request pacing violation"))
}

@Test func kindTableAdditions() {
    for c in [317, 10090, 10091] { #expect(ErrorCode.kind(c) == .notice) }
}

@Test func warningKinds() {
    for c in [105, 321, 329, 434, 492] { #expect(ErrorCode.kind(c) == .warning) }
    #expect(ErrorCode.kind(110) == .fatal)
}

@Test func grantsNoDepthReadsTheGrantedPart() {
    #expect(ErrorCode.grantsNoDepth("Exchanges - Top: IBEOS; OVERNIGHT; Unknown market data permissions - Depth: NASDAQ; BATS; ARCA; BEX; NYSE; IEX; Top: BYX; AMEX; PEARL; T24X; MEMX; EDGEA; TXSE; CHX; NYSENAT; PSX; LTSE; ISE; DRCTEDGE; "))
    #expect(ErrorCode.grantsNoDepth("Exchanges - Top: IBEOS; "))
    #expect(!ErrorCode.grantsNoDepth("Exchanges - Depth: ISLAND; Top: BYX; Unknown market data permissions - Depth: BATS; "))
    #expect(!ErrorCode.grantsNoDepth("Exchanges - Depth: ISLAND; "))
}
