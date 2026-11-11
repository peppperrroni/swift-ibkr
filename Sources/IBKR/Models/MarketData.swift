import Foundation

public struct ContractDetails: Sendable, Equatable {
    public var contract: Contract
    public var marketName: String
    public var minTick: Decimal
    public var priceMagnifier: Int
    public var longName: String
    public var stockType: String
    public var orderTypes: [String]
    public var validExchanges: [String]
    public var timeZoneID: String
    public var tradingHours: String
    public var liquidHours: String
    public var minSize: Decimal?
    public var sizeIncrement: Decimal?
    public var suggestedSizeIncrement: Decimal?
}

/// One reqMatchingSymbols hit. Its contract has no exchange, only a primary one.
public struct ContractDescription: Sendable, Equatable {
    public var contract: Contract
    public var derivativeSecTypes: [String]
    public var description: String
    public var issuerID: String
}
