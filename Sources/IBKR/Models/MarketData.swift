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

    public init(
        contract: Contract,
        marketName: String,
        minTick: Decimal,
        priceMagnifier: Int,
        longName: String,
        stockType: String,
        orderTypes: [String] = [],
        validExchanges: [String] = [],
        timeZoneID: String,
        tradingHours: String,
        liquidHours: String,
        minSize: Decimal? = nil,
        sizeIncrement: Decimal? = nil,
        suggestedSizeIncrement: Decimal? = nil
    ) {
        self.contract = contract
        self.marketName = marketName
        self.minTick = minTick
        self.priceMagnifier = priceMagnifier
        self.longName = longName
        self.stockType = stockType
        self.orderTypes = orderTypes
        self.validExchanges = validExchanges
        self.timeZoneID = timeZoneID
        self.tradingHours = tradingHours
        self.liquidHours = liquidHours
        self.minSize = minSize
        self.sizeIncrement = sizeIncrement
        self.suggestedSizeIncrement = suggestedSizeIncrement
    }
}

/// One reqMatchingSymbols hit. Its contract has no exchange, only a primary one.
public struct ContractDescription: Sendable, Equatable {
    public var contract: Contract
    public var derivativeSecTypes: [String]
    public var description: String
    public var issuerID: String

    public init(contract: Contract, derivativeSecTypes: [String] = [], description: String, issuerID: String) {
        self.contract = contract
        self.derivativeSecTypes = derivativeSecTypes
        self.description = description
        self.issuerID = issuerID
    }
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
        66: 1, 67: 2, 68: 4, 69: 0, 70: 3, 71: 5, 72: 6, 73: 7, 74: 8, 75: 9, 76: 14, 80: 10, 81: 11, 82: 12, 83: 13, 88: 45, 103: 50, 104: 51,
    ]
    /// A delayed field's real-time twin; any other field is itself.
    public var live: TickField { TickField(rawValue: Self.delayedTwin[rawValue] ?? rawValue) }
}

/// One historical bar. `time` is the bar's start: epoch seconds for intraday bars, 00:00 UTC of the calendar day
/// for daily and longer bars. `volume` keeps IB's `-1` for "not reported", as do `average` and `count` on real-time
/// MIDPOINT, BID and ASK bars.
public struct Bar: Sendable, Equatable {
    public var time: Date
    public var open, high, low, close, volume: Decimal
    public var average: Decimal?
    public var count: Int

    public init(
        time: Date,
        open: Decimal,
        high: Decimal,
        low: Decimal,
        close: Decimal,
        volume: Decimal,
        average: Decimal? = nil,
        count: Int
    ) {
        self.time = time
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
        self.average = average
        self.count = count
    }
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
    case optionComputation(TickField, OptionComputation)
    case efp(TickField, EFPData)
    /// tickReqParams (81): the minimum tick, the BBO exchange code and the snapshot permissions of this request.
    case requestParameters(minTick: Decimal?, bboExchange: String, snapshotPermissions: Int)
    case news(NewsTick)
}

/// One tickOptionComputation (21). A value IB has not computed (`-1` for impliedVol, optPrice, pvDividend and
/// undPrice; `-2` for delta, gamma, vega and theta) is `nil`.
public struct OptionComputation: Sendable, Equatable {
    public var tickAttrib: Int
    public var impliedVol, delta, optPrice, pvDividend, gamma, vega, theta, undPrice: Decimal?

    public init(
        tickAttrib: Int,
        impliedVol: Decimal? = nil,
        delta: Decimal? = nil,
        optPrice: Decimal? = nil,
        pvDividend: Decimal? = nil,
        gamma: Decimal? = nil,
        vega: Decimal? = nil,
        theta: Decimal? = nil,
        undPrice: Decimal? = nil
    ) {
        self.tickAttrib = tickAttrib
        self.impliedVol = impliedVol
        self.delta = delta
        self.optPrice = optPrice
        self.pvDividend = pvDividend
        self.gamma = gamma
        self.vega = vega
        self.theta = theta
        self.undPrice = undPrice
    }
}

/// One tickEFP (47): an exchange-for-physical quote.
public struct EFPData: Sendable, Equatable {
    public var basisPoints: Decimal?
    public var formattedBasisPoints: String
    public var impliedFuture: Decimal?
    public var holdDays: Int?
    public var futureLastTradeDate: String
    public var dividendImpact: Decimal?
    public var dividendsToLastTradeDate: Decimal?

    public init(
        basisPoints: Decimal? = nil,
        formattedBasisPoints: String = "",
        impliedFuture: Decimal? = nil,
        holdDays: Int? = nil,
        futureLastTradeDate: String = "",
        dividendImpact: Decimal? = nil,
        dividendsToLastTradeDate: Decimal? = nil
    ) {
        self.basisPoints = basisPoints
        self.formattedBasisPoints = formattedBasisPoints
        self.impliedFuture = impliedFuture
        self.holdDays = holdDays
        self.futureLastTradeDate = futureLastTradeDate
        self.dividendImpact = dividendImpact
        self.dividendsToLastTradeDate = dividendsToLastTradeDate
    }
}

/// One tickNews (84). `timeStamp` is IB's raw number: its unit is undocumented.
public struct NewsTick: Sendable, Equatable {
    public var timeStamp: Int
    public var providerCode: String
    public var articleID: String
    public var headline: String
    public var extraData: String

    public init(timeStamp: Int, providerCode: String, articleID: String, headline: String, extraData: String = "") {
        self.timeStamp = timeStamp
        self.providerCode = providerCode
        self.articleID = articleID
        self.headline = headline
        self.extraData = extraData
    }
}

/// What `reqTickByTickData` is asked for; the raw value is the text IB's request carries.
public enum TickByTickType: String, Sendable { case last = "Last", allLast = "AllLast", bidAsk = "BidAsk", midPoint = "MidPoint" }

/// One tick-by-tick event. `time` is IB's epoch seconds. The attribute masks are read: a trade's become
/// `pastLimit` (bit 0) and `unreported` (bit 1); a quote's is dropped.
public enum TickByTick: Sendable, Equatable {
    case trade(time: Date, price: Decimal, size: Decimal, exchange: String, conditions: String, pastLimit: Bool, unreported: Bool)
    case bidAsk(time: Date, bidPrice: Decimal, askPrice: Decimal, bidSize: Decimal, askSize: Decimal)
    case midPoint(time: Date, price: Decimal)
}

/// One row of the depth book. `marketMaker` is empty unless IB names one (message 13 on non-smart depth).
public struct DepthLevel: Sendable, Equatable {
    public var price: Decimal
    public var size: Decimal
    public var marketMaker: String

    public init(price: Decimal, size: Decimal, marketMaker: String) {
        self.price = price
        self.size = size
        self.marketMaker = marketMaker
    }
}

/// One exchange that offers market depth, as IB lists it (message 80).
public struct DepthMarketDataDescription: Sendable, Equatable {
    public var exchange: String
    public var secType: String
    public var listingExchange: String
    public var serviceDataType: String
    public var aggGroup: Int?

    public init(exchange: String, secType: String, listingExchange: String, serviceDataType: String, aggGroup: Int? = nil) {
        self.exchange = exchange
        self.secType = secType
        self.listingExchange = listingExchange
        self.serviceDataType = serviceDataType
        self.aggGroup = aggGroup
    }
}

/// One exchange behind a SMART route, with its bit in the BBO exchange mask (message 82).
public struct SmartComponent: Sendable, Equatable {
    public var bitNumber: Int
    public var exchange: String
    public var exchangeLetter: String

    public init(bitNumber: Int, exchange: String, exchangeLetter: String) {
        self.bitNumber = bitNumber
        self.exchange = exchange
        self.exchangeLetter = exchangeLetter
    }
}

/// One change to the book, as IB sends it (messages 12 and 13).
public struct DepthUpdate: Sendable, Equatable {
    public enum Operation: Int, Sendable { case insert = 0, update, delete }
    public enum Side: Int, Sendable { case ask = 0, bid }
    public var position: Int
    public var marketMaker: String
    public var operation: Operation
    public var side: Side
    public var price: Decimal
    public var size: Decimal

    public init(position: Int, marketMaker: String, operation: Operation, side: Side, price: Decimal, size: Decimal) {
        self.position = position
        self.marketMaker = marketMaker
        self.operation = operation
        self.side = side
        self.price = price
        self.size = size
    }
}
