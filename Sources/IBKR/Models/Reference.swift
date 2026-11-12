import Foundation

/// What `qualifyContracts` made of one input contract.
public enum ContractQualification: Sendable, Equatable {
    /// IB's one matching contract, with `SMART` kept as its exchange when the input asked for `SMART`.
    case qualified(Contract)
    /// Several matches: those of the input's secType when it had one (possibly none), else all of them, in IB's order.
    case ambiguous([Contract])
    /// IB knows no such contract (error 200, or an empty answer).
    case notFound
}

/// One exchange's option chain for an underlying: every expiration and strike it lists, for one trading class.
public struct OptionChain: Sendable, Equatable {
    public var exchange: String
    public var underlyingConID: Int
    public var tradingClass: String
    public var multiplier: String
    /// `yyyyMMdd`, in IB's order.
    public var expirations: [String]
    public var strikes: [Decimal]

    public init(exchange: String, underlyingConID: Int, tradingClass: String, multiplier: String,
                expirations: [String], strikes: [Decimal]) {
        self.exchange = exchange; self.underlyingConID = underlyingConID; self.tradingClass = tradingClass
        self.multiplier = multiplier; self.expirations = expirations; self.strikes = strikes
    }
}

/// One step of an exchange's price-increment rule: from `lowEdge` upward, prices move in steps of `increment`.
public struct PriceIncrement: Sendable, Equatable {
    public var lowEdge: Decimal
    public var increment: Decimal

    public init(lowEdge: Decimal, increment: Decimal) { self.lowEdge = lowEdge; self.increment = increment }
}

/// An account and its family code (`ib_async`'s `FamilyCode`); `familyCodeStr` is empty for an account with none.
public struct FamilyCode: Sendable, Equatable {
    public var accountID: String
    public var familyCodeStr: String

    public init(accountID: String, familyCodeStr: String) { self.accountID = accountID; self.familyCodeStr = familyCodeStr }
}
