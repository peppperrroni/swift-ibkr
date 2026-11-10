import Foundation
import Testing
@testable import IBKR

private func pos(_ account: String, _ conID: Int, _ qty: String) -> IBMessage {
    var contract = Contract(symbol: "AAPL")
    contract.conID = conID
    return .position(Position(account: account, contract: contract, quantity: d(qty), averageCost: d("10")))
}

private func keys(_ set: [Position]?) -> [String]? { set?.map { "\($0.account)/\($0.contract.conID)" } }

@Suite struct PositionTrackerTests {
    @Test func positionUpdateReplacesByAccountAndConID() {
        var t = PositionTracker()
        _ = t.apply(pos("DU1", 1, "5"))
        let set = t.apply(pos("DU1", 1, "3"))
        #expect(set?.count == 1)
        #expect(set?.first?.quantity == d("3"))
    }

    @Test func zeroPositionIsRemoved() {
        var t = PositionTracker()
        _ = t.apply(pos("DU1", 1, "5"))
        #expect(t.apply(pos("DU1", 1, "0")) == [])
    }

    @Test func sameConIDInTwoAccountsIsTwoPositions() {
        var t = PositionTracker()
        _ = t.apply(pos("DU1", 1, "5"))
        #expect(t.apply(pos("DU2", 1, "5"))?.count == 2)
    }

    @Test func positionsAreSortedByAccountThenConID() {
        var t = PositionTracker()
        _ = t.apply(pos("DU2", 1, "1"))
        _ = t.apply(pos("DU1", 2, "1"))
        _ = t.apply(pos("DU1", 1, "1"))
        #expect(keys(t.positions) == ["DU1/1", "DU1/2", "DU2/1"])
    }

    @Test func reloadPublishesOnlyAtItsEnd() {
        var t = PositionTracker()
        _ = t.apply(pos("DU1", 1, "1"))
        t.reload()
        #expect(t.apply(pos("DU1", 2, "1")) == nil)
        #expect(keys(t.positions) == ["DU1/1"])
        #expect(keys(t.apply(.positionEnd)) == ["DU1/2"])
        #expect(keys(t.positions) == ["DU1/2"])
    }

    @Test func zeroDuringReloadRemovesThePendingPosition() {
        var t = PositionTracker()
        t.reload()
        _ = t.apply(pos("DU1", 1, "5"))
        _ = t.apply(pos("DU1", 1, "0"))
        #expect(t.apply(.positionEnd) == [])
        #expect(t.positions.isEmpty)
    }

    @Test func unrelatedMessagesPublishNothing() {
        var t = PositionTracker()
        #expect(t.apply(.openOrderEnd) == nil)
        #expect(t.apply(.positionEnd) == nil)
    }

    @Test func unchangedPositionPublishesNothing() {
        var t = PositionTracker()
        _ = t.apply(pos("DU1", 1, "5"))
        #expect(t.apply(pos("DU1", 1, "5")) == nil)
        #expect(t.apply(pos("DU1", 2, "0")) == nil)
    }
}
