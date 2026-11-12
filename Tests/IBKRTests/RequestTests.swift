import Testing
@testable import IBKR

private let opt: Contract = {
    var c = Contract(symbol: "AAPL", secType: "OPT")
    c.conID = 12345; c.lastTradeDateOrContractMonth = "20261218"; c.strike = d("150"); c.right = "C"
    c.multiplier = "100"; c.localSymbol = "AAPL  261218C00150000"; c.tradingClass = "AAPL"
    return c
}()

@Suite struct RequestTests {
    @Test func bodyMatchesProtocolTable_startAPI() throws {
        #expect(try IBRequest.startAPI(clientID: 1, capabilities: "").body() == body("71", "2", "1", ""))
    }
    @Test func bodyMatchesProtocolTable_requestIDs() throws {
        #expect(try IBRequest.requestIDs.body() == body("8", "1", "1"))
    }
    @Test func bodyMatchesProtocolTable_cancelOrder() throws {
        #expect(try IBRequest.cancelOrder(orderID: 42, manualCancelTime: "").body() == body("4", "1", "42", ""))
    }
    @Test func exerciseOptionsEncodes() throws {
        #expect(try IBRequest.exerciseOptions(requestID: 5, contract: opt, action: .exercise, quantity: 2, account: "DU1", override: false).body()
            == body("21", "2", "5", "12345", "AAPL", "OPT", "20261218", "150.0", "C", "100", "SMART", "USD", "AAPL  261218C00150000", "AAPL", "1", "2", "DU1", "0"))
    }
    @Test func exerciseOptionsRefusesABag() {
        var bag = opt; bag.secType = "BAG"
        #expect(throws: IBEncodingError.unsupported("secType BAG")) {
            try IBRequest.exerciseOptions(requestID: 5, contract: bag, action: .lapse, quantity: 1, account: "DU1", override: true).body()
        }
    }
    @Test func bodyMatchesProtocolTable_openOrders() throws {
        #expect(try IBRequest.openOrders.body() == body("5", "1"))
    }
    @Test func bodyMatchesProtocolTable_allOpenOrders() throws {
        #expect(try IBRequest.allOpenOrders.body() == body("16", "1"))
    }
    @Test func bodyMatchesProtocolTable_autoOpenOrders() throws {
        #expect(try IBRequest.autoOpenOrders(true).body() == body("15", "1", "1"))
        #expect(try IBRequest.autoOpenOrders(false).body() == body("15", "1", "0"))
    }
    @Test func bodyMatchesProtocolTable_completedOrders() throws {
        #expect(try IBRequest.completedOrders(apiOnly: true).body() == body("99", "1"))
    }
    @Test func bodyMatchesProtocolTable_executions() throws {
        #expect(try IBRequest.executions(requestID: 7, filter: ExecutionFilter()).body()
            == body("7", "3", "7", "0", "", "", "", "", "", ""))
        let f = ExecutionFilter(clientID: 5, account: "DU1", time: "20261109 09:30:00", symbol: "AAPL",
                                secType: "STK", exchange: "SMART", side: "BUY")
        #expect(try IBRequest.executions(requestID: 8, filter: f).body()
            == body("7", "3", "8", "5", "DU1", "20261109 09:30:00", "AAPL", "STK", "SMART", "BUY"))
    }
    @Test func bodyMatchesProtocolTable_session() throws {
        #expect(try IBRequest.currentTime.body() == body("49", "1"))
        #expect(try IBRequest.managedAccounts.body() == body("17", "1"))
        #expect(try IBRequest.userInfo(requestID: 8).body() == body("104", "8"))
        #expect(try IBRequest.serverLogLevel(.detail).body() == body("14", "1", "5"))
        #expect(try IBRequest.globalCancel.body() == body("58", "1"))
    }
    @Test func nonASCIIFieldThrows() {
        #expect(throws: IBEncodingError.nonASCII(field: "é")) {
            try IBRequest.startAPI(clientID: 1, capabilities: "é").body()
        }
    }
    @Test func bagIsRefusedWhereIBSendsNoLegs() {
        #expect(throws: IBEncodingError.unsupported("secType BAG")) {
            try IBRequest.marketDepth(requestID: 1, contract: bagContract, rows: 5, smart: true).body()
        }
        #expect(throws: IBEncodingError.unsupported("secType BAG")) {
            try IBRequest.tickByTick(requestID: 1, contract: bagContract, type: .last).body()
        }
    }
    @Test func contractDetailsSendsSecID() throws {
        var c = Contract(symbol: "AAPL")
        c.secIDType = "ISIN"; c.secID = "US0378331005"
        let f = FieldReader(try IBRequest.contractDetails(requestID: 1, contract: c).body()).fields
        #expect(f.suffix(4) == ["0", "ISIN", "US0378331005", ""])  // includeExpired, secIdType, secId, issuerId
    }
}
