import Foundation
import Testing
@testable import IBKR

private func item(_ account: String, _ conID: Int, _ qty: String) -> IBMessage {
    var contract = Contract(symbol: "AAPL")
    contract.conID = conID
    return .portfolioItem(PortfolioItem(
        account: account, contract: contract, quantity: d(qty), marketPrice: d("10"), marketValue: d("10"),
        averageCost: d("9")))
}

private func value(_ tag: String, _ v: String, model: String = "") -> IBMessage {
    .accountValue(AccountValue(account: "DU1", tag: tag, value: v, currency: "USD", modelCode: model))
}

private func keys(_ set: [PortfolioItem]) -> [String] { set.map { "\($0.account)/\($0.contract.conID)" } }

@Suite struct AccountTrackerTests {
    @Test func portfolioItemReplacesByAccountAndConID() {
        var t = AccountTracker()
        _ = t.apply(item("DU1", 1, "5"))
        guard case .portfolio(let set)? = t.apply(item("DU1", 1, "3")) else { Issue.record("no change"); return }
        #expect(set.count == 1)
        #expect(set.first?.quantity == d("3"))
    }

    @Test func zeroPortfolioItemIsRemoved() {
        var t = AccountTracker()
        _ = t.apply(item("DU1", 1, "5"))
        #expect(t.apply(item("DU1", 1, "0")) == .portfolio([]))
    }

    @Test func portfolioIsSortedByAccountThenConID() {
        var t = AccountTracker()
        _ = t.apply(item("DU2", 1, "1"))
        _ = t.apply(item("DU1", 2, "1"))
        _ = t.apply(item("DU1", 1, "1"))
        #expect(keys(t.portfolio) == ["DU1/1", "DU1/2", "DU2/1"])
    }

    @Test func reloadPublishesThePortfolioOnlyAtDownloadEnd() {
        var t = AccountTracker()
        _ = t.apply(item("DU1", 1, "1"))
        t.reload()
        #expect(t.apply(item("DU1", 2, "1")) == nil)
        #expect(keys(t.portfolio) == ["DU1/1"])
        guard case .portfolio(let set)? = t.apply(.accountDownloadEnd(account: "DU1")) else {
            Issue.record("no set"); return
        }
        #expect(keys(set) == ["DU1/2"])
    }

    @Test func accountValuePublishesOnlyChanges() {
        var t = AccountTracker()
        #expect(t.apply(value("NetLiquidation", "100")) != nil)
        #expect(t.apply(value("NetLiquidation", "100")) == nil)
        #expect(t.apply(value("NetLiquidation", "101")) != nil)
        #expect(t.values.count == 1)
    }

    @Test func modelCodeKeepsValuesApart() {
        var t = AccountTracker()
        _ = t.apply(value("NetLiquidation", "100", model: "M1"))
        _ = t.apply(value("NetLiquidation", "100"))
        #expect(t.values.map(\.modelCode) == ["", "M1"])
    }

    @Test func multiUpdatesUpsertLikeValues() {
        var t = AccountTracker()
        let v = AccountValue(account: "DU1", tag: "NetLiquidation", value: "5", currency: "USD", modelCode: "M1")
        #expect(t.apply(.accountUpdateMulti(requestID: 1, v)) == .value(v))
    }

    @Test func unrelatedMessagesChangeNothing() {
        var t = AccountTracker()
        #expect(t.apply(.positionEnd) == nil)
        #expect(t.apply(.accountDownloadEnd(account: "DU1")) == nil)
    }
}
