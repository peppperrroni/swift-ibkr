import Foundation

public struct Contract: Sendable, Equatable, Hashable {
    public var conID: Int
    public var symbol: String
    public var secType: String
    public var lastTradeDateOrContractMonth: String
    public var strike: Decimal?
    public var right: String
    public var multiplier: String
    public var exchange: String
    public var primaryExchange: String
    public var currency: String
    public var localSymbol: String
    public var tradingClass: String

    public init(symbol: String, secType: String = "STK", exchange: String = "SMART",
                currency: String = "USD", primaryExchange: String = "") {
        conID = 0; self.symbol = symbol; self.secType = secType
        lastTradeDateOrContractMonth = ""; strike = nil; right = ""; multiplier = ""
        self.exchange = exchange; self.primaryExchange = primaryExchange; self.currency = currency
        localSymbol = ""; tradingClass = ""
    }
}
