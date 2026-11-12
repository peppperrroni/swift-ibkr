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
    /// The exchange this chain trades on.
    public var exchange: String
    /// The underlying's contract id.
    public var underlyingConID: Int
    /// The trading class of the chain's options.
    public var tradingClass: String
    /// IB's contract multiplier as text.
    public var multiplier: String
    /// `yyyyMMdd`, in IB's order.
    public var expirations: [String]
    /// Every strike of the chain, in IB's order.
    public var strikes: [Decimal]

    /// Creates a chain with every field given.
    public init(exchange: String, underlyingConID: Int, tradingClass: String, multiplier: String,
                expirations: [String], strikes: [Decimal]) {
        self.exchange = exchange; self.underlyingConID = underlyingConID; self.tradingClass = tradingClass
        self.multiplier = multiplier; self.expirations = expirations; self.strikes = strikes
    }
}

/// One step of an exchange's price-increment rule: from `lowEdge` upward, prices move in steps of `increment`.
public struct PriceIncrement: Sendable, Equatable {
    /// The lowest price this step applies to.
    public var lowEdge: Decimal
    /// The price step from `lowEdge` upward.
    public var increment: Decimal

    /// Creates a price increment with every field given.
    public init(lowEdge: Decimal, increment: Decimal) { self.lowEdge = lowEdge; self.increment = increment }
}

/// An account and its family code (`ib_async`'s `FamilyCode`); `familyCodeStr` is empty for an account with none.
public struct FamilyCode: Sendable, Equatable {
    /// The account id.
    public var accountID: String
    /// IB's `familyCodeStr`; empty for an account with none.
    public var familyCodeStr: String

    /// Creates a family code with every field given.
    public init(accountID: String, familyCodeStr: String) {
        self.accountID = accountID; self.familyCodeStr = familyCodeStr
    }
}
