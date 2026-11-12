import Testing
@testable import IBKR

struct ContractFactoryTests {
    @Test func everyFactorySetsItsSecType() {
        let all = [Contract.stock("X"), .option("X"), .futuresOption("X"), .future("X"), .contFuture("X"),
                   .forex("EURUSD"), .index("X"), .cfd("X"), .commodity("X"), .crypto("X"), .mutualFund("X"),
                   .warrant("X"), .bond(), .bag("X", legs: [])]
        #expect(all.map(\.secType) == ["STK", "OPT", "FOP", "FUT", "CONTFUT", "CASH", "IND", "CFD", "CMDTY",
                                       "CRYPTO", "FUND", "WAR", "BOND", "BAG"])
    }

    @Test func factoriesKeepIbAsyncDefaults() {
        let stock = Contract.stock("AAPL")
        #expect(stock.exchange == "" && stock.currency == "")
        let fx = Contract.forex("EURUSD")
        #expect(fx.symbol == "EUR" && fx.currency == "USD" && fx.exchange == "IDEALPRO")
        #expect(Contract.option("AAPL").strike == nil)
    }

    @Test func optionFactoryFillsItsFields() throws {
        #expect(aaplCall.lastTradeDateOrContractMonth == "20261218" && aaplCall.strike == 200
                && aaplCall.right == "C" && aaplCall.exchange == "SMART" && aaplCall.currency == "USD")
        #expect(try IBRequest.contractDetails(requestID: 5, contract: aaplCall).body()
                == body(["9", "8", "5"] + aaplCallBlock + ["0", "", "", ""]))
    }

    @Test func shortForexPairDoesNotTrap() {
        let fx = Contract.forex("EUR")
        #expect(fx.symbol == "EUR" && fx.currency == "")
    }

    @Test func futureFactoriesPlaceLocalSymbolAndMultiplier() throws {
        let fut = Contract.future("ES", lastTradeDateOrContractMonth: "202612", exchange: "CME", localSymbol: "ESZ6",
                                  multiplier: "50", currency: "USD")
        #expect(try IBRequest.contractDetails(requestID: 5, contract: fut).body()
                == body(["9", "8", "5", "0", "ES", "FUT", "202612", "0.0", "", "50", "CME", "", "USD", "ESZ6", "",
                         "0", "", "", ""]))
        let cont = Contract.contFuture("ES", exchange: "CME", localSymbol: "ESZ6", multiplier: "50", currency: "USD")
        #expect(try IBRequest.contractDetails(requestID: 5, contract: cont).body()
                == body(["9", "8", "5", "0", "ES", "CONTFUT", "", "0.0", "", "50", "CME", "", "USD", "ESZ6", "",
                         "0", "", "", ""]))
    }

    @Test func bondAndBagFactories() {
        let bond = Contract.bond(secIDType: "ISIN", secID: "US459200HU86")
        #expect(bond.secIDType == "ISIN" && bond.secID == "US459200HU86" && bond.symbol == "")
        #expect(Contract.bag("AAPL", legs: bagContract.comboLegs, exchange: "SMART", currency: "USD").comboLegs
                == bagContract.comboLegs)
    }
}
