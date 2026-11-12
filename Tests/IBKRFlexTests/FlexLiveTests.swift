import Foundation
import Testing
import IBKRFlex

// Opt-in: downloads the owner's Flex query from IB. Skipped unless both variables are set.
private let env = ProcessInfo.processInfo.environment

@Suite(.enabled(if: env["IBKR_FLEX_TOKEN"] != nil && env["IBKR_FLEX_QUERY"] != nil))
struct FlexLiveTests {
    @Test func downloadsTheConfiguredQuery() async throws {
        let report = try await FlexReport.download(token: env["IBKR_FLEX_TOKEN"]!, queryID: env["IBKR_FLEX_QUERY"]!)
        #expect(!report.topics.isEmpty)
    }
}
