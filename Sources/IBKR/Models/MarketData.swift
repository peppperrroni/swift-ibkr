import Foundation

/// One contractData (10) answer: the contract IB resolved and its trading rules.
public struct ContractDetails: Sendable, Equatable, Encodable {
    /// The fully specified contract, with its `conId`.
    public var contract: Contract
    /// IB's market name for the contract.
    public var marketName: String
    /// The smallest price increment.
    public var minTick: Decimal
    /// IB's price magnifier, as contractData (10) sends it; `0` on a bond (18).
    public var priceMagnifier: Int
    /// The instrument's long name; contractData (10) is unescaped, a bond's (18) is kept as IB sends it.
    public var longName: String
    /// IB's stock type; empty when not sent.
    public var stockType: String
    /// The order types the contract accepts.
    public var orderTypes: [String]
    /// The exchanges the contract trades on.
    public var validExchanges: [String]
    /// The time zone of `tradingHours` and `liquidHours`; empty when IB sends none.
    public var timeZoneID: String
    /// The trading sessions, as IB's text; empty when not sent.
    public var tradingHours: String
    /// The regular-trading-hours sessions, as IB's text; empty when not sent.
    public var liquidHours: String
    /// The smallest order size; `nil` when IB sends none.
    public var minSize: Decimal?
    /// The step between order sizes; `nil` when IB sends none.
    public var sizeIncrement: Decimal?
    /// The step IB suggests for order sizes; `nil` when IB sends none.
    public var suggestedSizeIncrement: Decimal?
    // Declared with defaults and kept out of the init, as `Order` is: set them on the value after it.
    /// The underlying's `conId`; `0` when none.
    public var underConID = 0
    /// The contract month, the industry, the category and the subcategory, as IB's text.
    public var contractMonth = "", industry = "", category = "", subcategory = ""
    /// IB's EV rule text, with `evMultiplier`; empty when none.
    public var evRule = ""
    /// IB's EV multiplier; `nil` when none.
    public var evMultiplier: Decimal? = nil
    /// The contract's other identifiers (tag and value pairs).
    public var secIDList: [TagValue] = []
    /// IB's aggregate group; `nil` when none.
    public var aggGroup: Int? = nil
    /// The underlying's symbol and security type; empty when none.
    public var underSymbol = "", underSecType = ""
    /// The ids of the market rules that give the price increments, one per exchange.
    public var marketRuleIDs: [Int] = []
    /// The real expiration date and the last trade time, as IB's text.
    public var realExpirationDate = "", lastTradeTime = ""
    // Bonds (in 18)
    /// A bond's CUSIP, ratings, description suffix, bond type and coupon type; empty for other contracts.
    public var cusip = "", ratings = "", descAppend = "", bondType = "", couponType = ""
    /// A bond's coupon; `nil` for other contracts.
    public var coupon: Decimal? = nil
    /// Whether a bond is convertible, callable or putable.
    public var convertible = false, callable = false, putable = false
    /// A bond's maturity, issue date and next option date and type, as IB's text.
    public var maturity = "", issueDate = "", nextOptionDate = "", nextOptionType = ""
    /// Whether a bond's next option is partial.
    public var nextOptionPartial = false
    /// Free text IB attaches to the contract.
    public var notes = ""

    /// Creates a contract's details with the fields every contractData carries; set the rest on the value after.
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

/// One reqMatchingSymbols hit (symbolSamples 79). Its contract has no exchange, only a primary one.
public struct ContractDescription: Sendable, Equatable, Encodable {
    /// The matching contract.
    public var contract: Contract
    /// The security types of the derivatives on it.
    public var derivativeSecTypes: [String]
    /// IB's description of the instrument.
    public var description: String
    /// IB's issuer id.
    public var issuerID: String

    /// Creates a symbol match with every field given.
    public init(contract: Contract, derivativeSecTypes: [String] = [], description: String, issuerID: String) {
        self.contract = contract
        self.derivativeSecTypes = derivativeSecTypes
        self.description = description
        self.issuerID = issuerID
    }
}

/// IB's market-data type: which kind of data `reqMktData` gets without a subscription.
public enum MarketDataType: Int, Sendable, Encodable {
    /// Live data (IB's `1`).
    case realtime = 1
    /// The last close, once the market is shut (IB's `2`).
    case frozen
    /// Delayed data (IB's `3`).
    case delayed
    /// Delayed data frozen at the last close (IB's `4`).
    case delayedFrozen
}

/// One entry of reqMktData's generic tick list: IB's number (`233`) or a tagged entry (`"mdoff"`, `"292:BRFG"`).
public struct GenericTick: RawRepresentable, Hashable, Sendable,
    ExpressibleByIntegerLiteral, ExpressibleByStringLiteral, Encodable
{
    /// The entry as it goes on the wire.
    public var rawValue: String
    /// Creates an entry from its wire text.
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Creates an entry from IB's tick number.
    public init(integerLiteral value: Int) { rawValue = String(value) }
    /// Creates an entry from its wire text.
    public init(stringLiteral value: String) { rawValue = value }
}

/// IB's tick field number. A struct, not an enum, so a number this library does not name survives.
public struct TickField: RawRepresentable, Hashable, Sendable, Encodable {
    /// IB's tick type number.
    public var rawValue: Int
    /// Creates a field from IB's tick type number.
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// IB's tick type 0, bid size.
    public static let bidSize = TickField(rawValue: 0)
    /// IB's tick type 1, bid price.
    public static let bid = TickField(rawValue: 1)
    /// IB's tick type 2, ask price.
    public static let ask = TickField(rawValue: 2)
    /// IB's tick type 3, ask size.
    public static let askSize = TickField(rawValue: 3)
    /// IB's tick type 4, last trade price.
    public static let last = TickField(rawValue: 4)
    /// IB's tick type 5, last trade size.
    public static let lastSize = TickField(rawValue: 5)
    /// IB's tick type 6, the day's high.
    public static let high = TickField(rawValue: 6)
    /// IB's tick type 7, the day's low.
    public static let low = TickField(rawValue: 7)
    /// IB's tick type 8, the day's volume.
    public static let volume = TickField(rawValue: 8)
    /// IB's tick type 9, the previous close.
    public static let close = TickField(rawValue: 9)
    /// IB's tick type 14, the day's open.
    public static let open = TickField(rawValue: 14)
    /// IB's tick type 45, the time of the last trade.
    public static let lastTimestamp = TickField(rawValue: 45)
    /// IB's tick type 49, the halted flag.
    public static let halted = TickField(rawValue: 49)

    private static let delayedTwin: [Int: Int] = [
        66: 1, 67: 2, 68: 4, 69: 0, 70: 3, 71: 5, 72: 6, 73: 7, 74: 8, 75: 9, 76: 14,
        80: 10, 81: 11, 82: 12, 83: 13, 88: 45, 103: 50, 104: 51,
    ]
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { Int(stringValue) }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { stringValue = String(intValue) }
    }
    /// A delayed field's real-time twin; any other field is itself.
    public var live: TickField { TickField(rawValue: Self.delayedTwin[rawValue] ?? rawValue) }
}

/// Lets `[TickField: V]` encode as a JSON object keyed by the tick number.
extension TickField: CodingKeyRepresentable {
    /// The tick number as a dictionary key (`"1"` for `.bid`).
    public var codingKey: any CodingKey { Key(stringValue: String(rawValue)) }
    /// Reads a tick number back from a dictionary key; `nil` when the key is not a number.
    public init?<T: CodingKey>(codingKey: T) {
        guard let n = Int(codingKey.stringValue) else { return nil }
        self.init(rawValue: n)
    }
}

/// One historical bar. `time` is the bar's start: epoch seconds for intraday bars, 00:00 UTC of the calendar day
/// for daily and longer bars. `volume` keeps IB's `-1` for "not reported", as do `average` and `count` on real-time
/// MIDPOINT, BID and ASK bars.
public struct Bar: Sendable, Equatable, Encodable {
    /// The bar's start.
    public var time: Date
    /// The bar's open, high, low and close prices, and its volume.
    public var open, high, low, close, volume: Decimal
    /// The volume-weighted average price; `nil` when IB sends none.
    public var average: Decimal?
    /// The number of trades in the bar; IB's `-1` on real-time MIDPOINT, BID and ASK bars is kept.
    public var count: Int

    /// Creates a bar with every field given.
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

/// What a historical-data stream with `keepUpToDate` yields.
public enum BarEvent: Sendable, Equatable, Encodable {
    /// The initial set of bars (historicalData 17).
    case history([Bar])
    /// A bar that is still forming, or the one that just closed (historicalDataUpdate 90).
    case update(Bar)
}

/// One market-data tick, as `reqMktData` streams them; each case names the IB message it comes from.
public enum Tick: Sendable, Equatable, Encodable {
    /// tickPrice (1): a price with its size and attributes. `price` and `size` are `nil` where IB sends an empty or
    /// unset value.
    case price(TickField, price: Decimal?, size: Decimal?, attributes: TickAttrib = TickAttrib())
    /// tickSize (2). The size is `nil` where IB sends an empty or unset value.
    case size(TickField, Decimal?)
    /// tickGeneric (45).
    case generic(TickField, Decimal)
    /// tickString (46).
    case string(TickField, String)
    /// marketDataType (58): the kind of data this request now gets.
    case dataType(MarketDataType)
    /// tickOptionComputation (21).
    case optionComputation(TickField, OptionComputation)
    /// tickEFP (47).
    case efp(TickField, EFPData)
    /// tickReqParams (81): the minimum tick, the BBO exchange code and the snapshot permissions of this request.
    case requestParameters(minTick: Decimal?, bboExchange: String, snapshotPermissions: Int)
    /// tickNews (84).
    case news(NewsTick)
}

/// tickPrice's (1) attribute mask, `ib_async`'s `TickAttrib`. ib_async drops the mask; the bits are IB's API
/// documentation (0 `canAutoExecute`, 1 `pastLimit`, 2 `preOpen`), not yet seen live.
public struct TickAttrib: Sendable, Equatable, Encodable {
    /// Whether the quote can be executed automatically.
    public var canAutoExecute: Bool
    /// Whether the bid is below the day's low or the ask above the day's high.
    public var pastLimit: Bool
    /// Whether the quote is from the pre-open session.
    public var preOpen: Bool

    /// Creates attributes with every flag given; all `false` by default.
    public init(canAutoExecute: Bool = false, pastLimit: Bool = false, preOpen: Bool = false) {
        self.canAutoExecute = canAutoExecute
        self.pastLimit = pastLimit
        self.preOpen = preOpen
    }

    /// Reads IB's mask: bit 0 `canAutoExecute`, bit 1 `pastLimit`, bit 2 `preOpen`.
    public init(mask: Int) {
        self.init(canAutoExecute: mask & 1 != 0, pastLimit: mask & 2 != 0, preOpen: mask & 4 != 0)
    }
}

/// One tickOptionComputation (21). A value IB has not computed (`-1` for impliedVol, optPrice, pvDividend and
/// undPrice; `-2` for delta, gamma, vega and theta) is `nil`.
public struct OptionComputation: Sendable, Equatable, Encodable {
    /// IB's tick attribute mask for the computation.
    public var tickAttrib: Int
    /// The implied volatility, the delta, the option price, the present value of dividends, the gamma, the vega,
    /// the theta and the underlying's price.
    public var impliedVol, delta, optPrice, pvDividend, gamma, vega, theta, undPrice: Decimal?

    /// Creates an option computation with every field given.
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
public struct EFPData: Sendable, Equatable, Encodable {
    /// The basis points; `nil` when IB sends none.
    public var basisPoints: Decimal?
    /// The basis points as IB formats them.
    public var formattedBasisPoints: String
    /// The implied future price; `nil` when IB sends none.
    public var impliedFuture: Decimal?
    /// The days until the future's last trade; `nil` when IB sends none.
    public var holdDays: Int?
    /// The future's last trade date, as IB's text.
    public var futureLastTradeDate: String
    /// The dividend impact; `nil` when IB sends none.
    public var dividendImpact: Decimal?
    /// The dividends expected until the last trade date; `nil` when IB sends none.
    public var dividendsToLastTradeDate: Decimal?

    /// Creates an EFP quote with every field given.
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
public struct NewsTick: Sendable, Equatable, Encodable {
    /// IB's time stamp, as sent.
    public var timeStamp: Int
    /// The news provider's code.
    public var providerCode: String
    /// The article's id.
    public var articleID: String
    /// The article's headline.
    public var headline: String
    /// IB's extra data text; empty when none.
    public var extraData: String

    /// Creates a news tick with every field given.
    public init(timeStamp: Int, providerCode: String, articleID: String, headline: String, extraData: String = "") {
        self.timeStamp = timeStamp
        self.providerCode = providerCode
        self.articleID = articleID
        self.headline = headline
        self.extraData = extraData
    }
}

/// What `reqTickByTickData` is asked for; the raw value is the text IB's request carries.
public enum TickByTickType: String, Sendable, Encodable {
    /// Trades from the regular session (IB's `Last`).
    case last = "Last"
    /// All trades, including those `last` leaves out (IB's `AllLast`).
    case allLast = "AllLast"
    /// Bid and ask quotes (IB's `BidAsk`).
    case bidAsk = "BidAsk"
    /// The midpoint of bid and ask (IB's `MidPoint`).
    case midPoint = "MidPoint"
}

/// One tick-by-tick event. `time` is IB's epoch seconds. The attribute masks are read: a trade's become
/// `pastLimit` (bit 0) and `unreported` (bit 1); a quote's become `bidPastLow` and `askPastHigh`, whose bit order
/// differs between tickByTick (99) and historicalTicks (97), as in `ib_async`.
public enum TickByTick: Sendable, Equatable, Encodable {
    /// A trade, from the `Last` and `AllLast` types (tickByTick 99, type 1 and 2).
    case trade(
        time: Date, price: Decimal, size: Decimal, exchange: String, conditions: String,
        pastLimit: Bool, unreported: Bool)
    /// A bid and ask quote, from the `BidAsk` type (tickByTick 99, type 3) or historicalTicks (97). `bidPastLow` and
    /// `askPastHigh` are `ib_async`'s `TickAttribBidAsk`.
    case bidAsk(time: Date, bidPrice: Decimal, askPrice: Decimal, bidSize: Decimal, askSize: Decimal,
                bidPastLow: Bool = false, askPastHigh: Bool = false)
    /// A midpoint, from the `MidPoint` type (tickByTick 99, type 4).
    case midPoint(time: Date, price: Decimal)
}

/// One row of the depth book. `marketMaker` is empty unless IB names one (message 13 on non-smart depth).
public struct DepthLevel: Sendable, Equatable, Encodable {
    /// The row's price.
    public var price: Decimal
    /// The row's size.
    public var size: Decimal
    /// The market maker's id; empty unless IB names one.
    public var marketMaker: String

    /// Creates a depth row with every field given.
    public init(price: Decimal, size: Decimal, marketMaker: String) {
        self.price = price
        self.size = size
        self.marketMaker = marketMaker
    }
}

/// One exchange that offers market depth, as IB lists it (message 80).
public struct DepthMarketDataDescription: Sendable, Equatable, Encodable {
    /// The exchange that offers depth.
    public var exchange: String
    /// The security type it offers depth for.
    public var secType: String
    /// The listing exchange.
    public var listingExchange: String
    /// IB's service data type text.
    public var serviceDataType: String
    /// IB's aggregate group; `nil` when none.
    public var aggGroup: Int?

    /// Creates a depth exchange with every field given.
    public init(
        exchange: String, secType: String, listingExchange: String, serviceDataType: String, aggGroup: Int? = nil
    ) {
        self.exchange = exchange
        self.secType = secType
        self.listingExchange = listingExchange
        self.serviceDataType = serviceDataType
        self.aggGroup = aggGroup
    }
}

/// One exchange behind a SMART route, with its bit in the BBO exchange mask (message 82).
public struct SmartComponent: Sendable, Equatable, Encodable {
    /// The exchange's bit in the BBO exchange mask.
    public var bitNumber: Int
    /// The exchange's name.
    public var exchange: String
    /// The exchange's letter code.
    public var exchangeLetter: String

    /// Creates a SMART component with every field given.
    public init(bitNumber: Int, exchange: String, exchangeLetter: String) {
        self.bitNumber = bitNumber
        self.exchange = exchange
        self.exchangeLetter = exchangeLetter
    }
}

/// One change to the book, as IB sends it (messages 12 and 13).
public struct DepthUpdate: Sendable, Equatable, Encodable {
    /// What the update does to the row at `position`.
    public enum Operation: Int, Sendable, Encodable {
        /// Adds a row at the position (IB's `0`).
        case insert = 0
        /// Replaces the row at the position (IB's `1`).
        case update
        /// Removes the row at the position (IB's `2`).
        case delete
    }
    /// The side of the book the update is for.
    public enum Side: Int, Sendable, Encodable {
        /// The ask side (IB's `0`).
        case ask = 0
        /// The bid side (IB's `1`).
        case bid
    }
    /// The row's position in its side, from 0.
    public var position: Int
    /// The market maker's id; empty on updateMktDepth (12).
    public var marketMaker: String
    /// What the update does.
    public var operation: Operation
    /// The side it applies to.
    public var side: Side
    /// The row's price.
    public var price: Decimal
    /// The row's size.
    public var size: Decimal

    /// Creates a depth update with every field given.
    public init(position: Int, marketMaker: String, operation: Operation, side: Side, price: Decimal, size: Decimal) {
        self.position = position
        self.marketMaker = marketMaker
        self.operation = operation
        self.side = side
        self.price = price
        self.size = size
    }
}

extension OptionComputation {
    /// ib_async's `+`: the six fields add with an unset one read as 0, so a result is never `nil` there; `undPrice`
    /// is the left one's, `pvDividend` is dropped and `tickAttrib` is 0.
    public static func + (a: OptionComputation, b: OptionComputation) -> OptionComputation {
        a.sixFields(b) { ($0 ?? 0) + ($1 ?? 0) }
    }

    /// ib_async's `-`: as `+`, subtracting.
    public static func - (a: OptionComputation, b: OptionComputation) -> OptionComputation {
        a.sixFields(b) { ($0 ?? 0) - ($1 ?? 0) }
    }

    /// ib_async's `*`: each of the six fields times `k`, an unset one read as 0; `undPrice` is kept.
    public static func * (a: OptionComputation, k: Decimal) -> OptionComputation {
        a.sixFields(a) { x, _ in (x ?? 0) * k }
    }

    /// `f` applied to the left and right value of impliedVol, delta, optPrice, gamma, vega and theta.
    private func sixFields(_ b: OptionComputation, _ f: (Decimal?, Decimal?) -> Decimal) -> OptionComputation {
        OptionComputation(
            tickAttrib: 0, impliedVol: f(impliedVol, b.impliedVol), delta: f(delta, b.delta),
            optPrice: f(optPrice, b.optPrice), gamma: f(gamma, b.gamma), vega: f(vega, b.vega),
            theta: f(theta, b.theta), undPrice: undPrice)
    }
}
