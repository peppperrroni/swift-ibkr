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

/// IB's market-data type: which kind of data `reqMktData` gets without a subscription.
public enum MarketDataType: Int, Sendable { case realtime = 1, frozen, delayed, delayedFrozen }

/// IB's tick field number. A struct, not an enum, so a number this library does not name survives.
public struct TickField: RawRepresentable, Hashable, Sendable {
    public var rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let bidSize = TickField(rawValue: 0)
    public static let bid = TickField(rawValue: 1)
    public static let ask = TickField(rawValue: 2)
    public static let askSize = TickField(rawValue: 3)
    public static let last = TickField(rawValue: 4)
    public static let lastSize = TickField(rawValue: 5)
    public static let high = TickField(rawValue: 6)
    public static let low = TickField(rawValue: 7)
    public static let volume = TickField(rawValue: 8)
    public static let close = TickField(rawValue: 9)
    public static let open = TickField(rawValue: 14)
    public static let lastTimestamp = TickField(rawValue: 45)
    public static let halted = TickField(rawValue: 49)

    private static let delayedTwin: [Int: Int] = [
        66: 1, 67: 2, 68: 4, 69: 0, 70: 3, 71: 5, 72: 6, 73: 7, 74: 8, 75: 9, 76: 14, 88: 45,
    ]
    /// A delayed field's real-time twin; any other field is itself.
    public var live: TickField { TickField(rawValue: Self.delayedTwin[rawValue] ?? rawValue) }
}

/// One historical bar. `time` is the bar's start: epoch seconds for intraday bars, 00:00 UTC of the calendar day
/// for daily and longer bars. `volume` keeps IB's `-1` for "not reported".
public struct Bar: Sendable, Equatable {
    public var time: Date
    public var open, high, low, close, volume: Decimal
    public var average: Decimal?
    public var count: Int
}

public enum BarEvent: Sendable, Equatable {
    case history([Bar])
    case update(Bar)
}

public enum Tick: Sendable, Equatable {
    case price(TickField, price: Decimal?, size: Decimal?)
    case size(TickField, Decimal?)
    case generic(TickField, Decimal)
    case string(TickField, String)
    case dataType(MarketDataType)
}
