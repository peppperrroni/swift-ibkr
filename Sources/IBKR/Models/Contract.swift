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
    public var secIDType = ""
    public var secID = ""
    /// Sent only when `secType` is `BAG`.
    public var comboLegs: [ComboLeg] = []
    /// Decoded only, never sent.
    public var comboLegsDescrip = ""
    public var deltaNeutralContract: DeltaNeutralContract?

    public init(symbol: String, secType: String = "STK", exchange: String = "SMART",
                currency: String = "USD", primaryExchange: String = "") {
        conID = 0; self.symbol = symbol; self.secType = secType
        lastTradeDateOrContractMonth = ""; strike = nil; right = ""; multiplier = ""
        self.exchange = exchange; self.primaryExchange = primaryExchange; self.currency = currency
        localSymbol = ""; tradingClass = ""
    }
}

/// ib_async's contract factories. Their defaults are ib_async's (`""`, `IDEALPRO` for forex), so a value
/// equals the ib_async one field for field; `Contract(symbol:)` keeps its SMART/USD.
extension Contract {
    public static func stock(_ symbol: String, exchange: String = "", currency: String = "",
                             primaryExchange: String = "") -> Contract {
        Contract(symbol: symbol, secType: "STK", exchange: exchange, currency: currency, primaryExchange: primaryExchange)
    }

    public static func option(_ symbol: String, lastTradeDateOrContractMonth: String = "", strike: Decimal? = nil,
                              right: String = "", exchange: String = "", multiplier: String = "",
                              currency: String = "") -> Contract {
        derivative(symbol, "OPT", lastTradeDateOrContractMonth, strike, right, exchange, multiplier, currency)
    }

    public static func futuresOption(_ symbol: String, lastTradeDateOrContractMonth: String = "",
                                     strike: Decimal? = nil, right: String = "", exchange: String = "",
                                     multiplier: String = "", currency: String = "") -> Contract {
        derivative(symbol, "FOP", lastTradeDateOrContractMonth, strike, right, exchange, multiplier, currency)
    }

    public static func future(_ symbol: String, lastTradeDateOrContractMonth: String = "", exchange: String = "",
                              localSymbol: String = "", multiplier: String = "", currency: String = "") -> Contract {
        var c = Contract(symbol: symbol, secType: "FUT", exchange: exchange, currency: currency)
        c.lastTradeDateOrContractMonth = lastTradeDateOrContractMonth
        c.localSymbol = localSymbol; c.multiplier = multiplier
        return c
    }

    public static func contFuture(_ symbol: String, exchange: String = "", localSymbol: String = "",
                                  multiplier: String = "", currency: String = "") -> Contract {
        var c = Contract(symbol: symbol, secType: "CONTFUT", exchange: exchange, currency: currency)
        c.localSymbol = localSymbol; c.multiplier = multiplier
        return c
    }

    /// The symbol is the pair's first three characters and the currency the rest; a bad pair is IB's to refuse.
    public static func forex(_ pair: String, exchange: String = "IDEALPRO") -> Contract {
        Contract(symbol: String(pair.prefix(3)), secType: "CASH", exchange: exchange, currency: String(pair.dropFirst(3)))
    }

    public static func index(_ symbol: String, exchange: String = "", currency: String = "") -> Contract {
        Contract(symbol: symbol, secType: "IND", exchange: exchange, currency: currency)
    }

    public static func cfd(_ symbol: String, exchange: String = "", currency: String = "") -> Contract {
        Contract(symbol: symbol, secType: "CFD", exchange: exchange, currency: currency)
    }

    public static func commodity(_ symbol: String, exchange: String = "", currency: String = "") -> Contract {
        Contract(symbol: symbol, secType: "CMDTY", exchange: exchange, currency: currency)
    }

    public static func crypto(_ symbol: String, exchange: String = "", currency: String = "") -> Contract {
        Contract(symbol: symbol, secType: "CRYPTO", exchange: exchange, currency: currency)
    }

    public static func mutualFund(_ symbol: String, exchange: String = "", currency: String = "") -> Contract {
        Contract(symbol: symbol, secType: "FUND", exchange: exchange, currency: currency)
    }

    public static func warrant(_ symbol: String, exchange: String = "", currency: String = "") -> Contract {
        Contract(symbol: symbol, secType: "WAR", exchange: exchange, currency: currency)
    }

    public static func bond(secIDType: String = "", secID: String = "", exchange: String = "",
                            currency: String = "") -> Contract {
        var c = Contract(symbol: "", secType: "BOND", exchange: exchange, currency: currency)
        c.secIDType = secIDType; c.secID = secID
        return c
    }

    public static func bag(_ symbol: String, legs: [ComboLeg], exchange: String = "", currency: String = "") -> Contract {
        var c = Contract(symbol: symbol, secType: "BAG", exchange: exchange, currency: currency)
        c.comboLegs = legs
        return c
    }

    private static func derivative(_ symbol: String, _ secType: String, _ expiry: String, _ strike: Decimal?,
                                   _ right: String, _ exchange: String, _ multiplier: String,
                                   _ currency: String) -> Contract {
        var c = Contract(symbol: symbol, secType: secType, exchange: exchange, currency: currency)
        c.lastTradeDateOrContractMonth = expiry; c.strike = strike; c.right = right; c.multiplier = multiplier
        return c
    }
}
