import Foundation

/// An instrument as IB describes it: `ib_async`'s `Contract`. Start from `init(symbol:)` or a factory below.
public struct Contract: Sendable, Equatable, Hashable, Encodable {
    /// IB's contract id (`conId`); 0 until known; `qualifyContracts` returns the matched contract that carries it.
    public var conID: Int
    /// The symbol IB lists the instrument under.
    public var symbol: String
    /// IB's security-type code: `STK`, `OPT`, `FUT`, `CASH`, `BAG` and so on.
    public var secType: String
    /// Expiry as IB writes it (`yyyyMMdd` or `yyyyMM`); empty for none.
    public var lastTradeDateOrContractMonth: String
    /// `nil` for none, or when IB's reply leaves it unset; requests that carry it send `nil` as `0.0`, as `ib_async`
    /// does.
    public var strike: Decimal?
    /// The option right as IB writes it (`C` or `P`); empty for a non-option.
    public var right: String
    /// IB's contract multiplier as text; empty for none.
    public var multiplier: String
    /// The exchange to route to; `init(symbol:)` defaults it to `SMART`.
    public var exchange: String
    /// The listing exchange, which tells apart a symbol listed on several; empty for none.
    public var primaryExchange: String
    /// The currency code; `init(symbol:)` defaults it to `USD`.
    public var currency: String
    /// The symbol on the exchange itself, as IB gives it.
    public var localSymbol: String
    /// IB's trading class, such as the option class sharing a symbol.
    public var tradingClass: String
    /// The kind of identifier in `secID` (IB's `secIdType`); empty for none.
    public var secIDType = ""
    /// A security identifier of kind `secIDType`; empty for none.
    public var secID = ""
    /// Sent only when `secType` is `BAG`.
    public var comboLegs: [ComboLeg] = []
    /// Decoded only, never sent.
    public var comboLegsDescrip = ""
    /// The delta-neutral hedge, decoded from openOrder and sent in placeOrder (out 3); `nil` for none.
    public var deltaNeutralContract: DeltaNeutralContract?
    /// Whether contract details, history, head time stamp, histogram and historical tick requests also cover expired
    /// contracts. Sent, never decoded.
    public var includeExpired = false
    /// IB's issuer id, sent with a contract details request; empty for none. Sent, never decoded.
    public var issuerID = ""

    /// Creates a contract for `symbol`; `SMART` and `USD` unless given, every other field unset.
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
    /// A stock (`STK`); the defaults are `ib_async`'s empty strings.
    public static func stock(_ symbol: String, exchange: String = "", currency: String = "",
                             primaryExchange: String = "") -> Contract {
        Contract(symbol: symbol, secType: "STK", exchange: exchange, currency: currency,
                 primaryExchange: primaryExchange)
    }

    /// An option (`OPT`) on `symbol`.
    public static func option(_ symbol: String, lastTradeDateOrContractMonth: String = "", strike: Decimal? = nil,
                              right: String = "", exchange: String = "", multiplier: String = "",
                              currency: String = "") -> Contract {
        derivative(symbol, "OPT", lastTradeDateOrContractMonth, strike, right, exchange, multiplier, currency)
    }

    /// A futures option (`FOP`) on `symbol`.
    public static func futuresOption(_ symbol: String, lastTradeDateOrContractMonth: String = "",
                                     strike: Decimal? = nil, right: String = "", exchange: String = "",
                                     multiplier: String = "", currency: String = "") -> Contract {
        derivative(symbol, "FOP", lastTradeDateOrContractMonth, strike, right, exchange, multiplier, currency)
    }

    /// A future (`FUT`); `lastTradeDateOrContractMonth` or `localSymbol` picks the month.
    public static func future(_ symbol: String, lastTradeDateOrContractMonth: String = "", exchange: String = "",
                              localSymbol: String = "", multiplier: String = "", currency: String = "") -> Contract {
        var c = Contract(symbol: symbol, secType: "FUT", exchange: exchange, currency: currency)
        c.lastTradeDateOrContractMonth = lastTradeDateOrContractMonth
        c.localSymbol = localSymbol; c.multiplier = multiplier
        return c
    }

    /// A continuous future (`CONTFUT`).
    public static func contFuture(_ symbol: String, exchange: String = "", localSymbol: String = "",
                                  multiplier: String = "", currency: String = "") -> Contract {
        var c = Contract(symbol: symbol, secType: "CONTFUT", exchange: exchange, currency: currency)
        c.localSymbol = localSymbol; c.multiplier = multiplier
        return c
    }

    /// The symbol is the pair's first three characters and the currency the rest; a bad pair is IB's to refuse.
    public static func forex(_ pair: String, exchange: String = "IDEALPRO") -> Contract {
        Contract(symbol: String(pair.prefix(3)), secType: "CASH", exchange: exchange,
                 currency: String(pair.dropFirst(3)))
    }

    /// An index (`IND`).
    public static func index(_ symbol: String, exchange: String = "", currency: String = "") -> Contract {
        Contract(symbol: symbol, secType: "IND", exchange: exchange, currency: currency)
    }

    /// A contract for difference (`CFD`).
    public static func cfd(_ symbol: String, exchange: String = "", currency: String = "") -> Contract {
        Contract(symbol: symbol, secType: "CFD", exchange: exchange, currency: currency)
    }

    /// A commodity (`CMDTY`).
    public static func commodity(_ symbol: String, exchange: String = "", currency: String = "") -> Contract {
        Contract(symbol: symbol, secType: "CMDTY", exchange: exchange, currency: currency)
    }

    /// A cryptocurrency (`CRYPTO`).
    public static func crypto(_ symbol: String, exchange: String = "", currency: String = "") -> Contract {
        Contract(symbol: symbol, secType: "CRYPTO", exchange: exchange, currency: currency)
    }

    /// A mutual fund (`FUND`).
    public static func mutualFund(_ symbol: String, exchange: String = "", currency: String = "") -> Contract {
        Contract(symbol: symbol, secType: "FUND", exchange: exchange, currency: currency)
    }

    /// A warrant (`WAR`).
    public static func warrant(_ symbol: String, exchange: String = "", currency: String = "") -> Contract {
        Contract(symbol: symbol, secType: "WAR", exchange: exchange, currency: currency)
    }

    /// A bond (`BOND`), identified by `secIDType` and `secID`; the symbol is empty.
    public static func bond(secIDType: String = "", secID: String = "", exchange: String = "",
                            currency: String = "") -> Contract {
        var c = Contract(symbol: "", secType: "BOND", exchange: exchange, currency: currency)
        c.secIDType = secIDType; c.secID = secID
        return c
    }

    /// A combination (`BAG`) of `legs`; the legs go out only with the requests that carry them.
    public static func bag(_ symbol: String, legs: [ComboLeg], exchange: String = "",
                           currency: String = "") -> Contract {
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

extension Contract {
    /// `symbol + currency`, as ib_async's `Forex.pair`: `EURUSD` for `forex("EURUSD")`.
    public var pair: String { symbol + currency }
}
