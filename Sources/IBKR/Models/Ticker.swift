import Foundation

/// A contract's market data folded into one value, as `ib_async`'s `Ticker`. `apply(_:)` keys every tick by its live
/// field, so delayed ticks land where real-time ones do. Bid, ask, last, OHLC, volume, the last timestamp, the five
/// greeks and the request parameters are named fields; every other tick goes into `prices`, `sizes`, `generics`,
/// `strings` or `efp` (RT volume, fundamental ratios and dividends stay raw strings; RT volume (48, 77) does not
/// move `last` or `lastSize`, unlike `ib_async`: `last` comes from tick 4 only). A bid or ask with size 0 has its
/// price `nil`. News ticks are not kept.
public struct Ticker: Sendable, Equatable {
    /// The contract the ticks are for.
    public var contract: Contract
    /// The kind of data the request gets now (marketDataType 58); `.realtime` until IB says otherwise.
    public var marketDataType: MarketDataType
    /// The minimum tick from tickReqParams (81); `nil` until it arrives.
    public var minTick: Decimal?
    /// The BBO exchange code from tickReqParams (81); empty until it arrives.
    public var bboExchange: String
    /// The snapshot permissions from tickReqParams (81); `0` until it arrives.
    public var snapshotPermissions: Int
    /// The bid, bid size, ask, ask size, last trade and last trade size; `nil` until a tick sets them.
    public var bid, bidSize, ask, askSize, last, lastSize: Decimal?
    /// The day's open, high and low, the previous close and the day's volume; `nil` until a tick sets them.
    public var open, high, low, close, volume: Decimal?
    /// The time of the last trade (tick 45); `nil` until a tick sets it.
    public var lastTimestamp: Date?
    /// The option greeks computed on the bid, the ask, the last trade, the model price and the customer's inputs.
    public var bidGreeks, askGreeks, lastGreeks, modelGreeks, custGreeks: OptionComputation?
    /// Every other price tick, keyed by its live field.
    public var prices: [TickField: Decimal]
    /// Every other size tick, keyed by its live field.
    public var sizes: [TickField: Decimal]
    /// Every generic tick (45), keyed by its live field.
    public var generics: [TickField: Decimal]
    /// Every string tick (46) except the last timestamp, keyed by its live field.
    public var strings: [TickField: String]
    /// Every EFP quote (47), keyed by its live field.
    public var efp: [TickField: EFPData]
    /// The depth book when `depthRows` was asked for; empty otherwise.
    public var depth: DepthBook

    /// Creates a ticker with every field given.
    public init(
        contract: Contract,
        marketDataType: MarketDataType = .realtime,
        minTick: Decimal? = nil,
        bboExchange: String = "",
        snapshotPermissions: Int = 0,
        bid: Decimal? = nil,
        bidSize: Decimal? = nil,
        ask: Decimal? = nil,
        askSize: Decimal? = nil,
        last: Decimal? = nil,
        lastSize: Decimal? = nil,
        open: Decimal? = nil,
        high: Decimal? = nil,
        low: Decimal? = nil,
        close: Decimal? = nil,
        volume: Decimal? = nil,
        lastTimestamp: Date? = nil,
        bidGreeks: OptionComputation? = nil,
        askGreeks: OptionComputation? = nil,
        lastGreeks: OptionComputation? = nil,
        modelGreeks: OptionComputation? = nil,
        custGreeks: OptionComputation? = nil,
        prices: [TickField: Decimal] = [:],
        sizes: [TickField: Decimal] = [:],
        generics: [TickField: Decimal] = [:],
        strings: [TickField: String] = [:],
        efp: [TickField: EFPData] = [:],
        depth: DepthBook = DepthBook()
    ) {
        self.contract = contract
        self.marketDataType = marketDataType
        self.minTick = minTick
        self.bboExchange = bboExchange
        self.snapshotPermissions = snapshotPermissions
        self.bid = bid
        self.bidSize = bidSize
        self.ask = ask
        self.askSize = askSize
        self.last = last
        self.lastSize = lastSize
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
        self.lastTimestamp = lastTimestamp
        self.bidGreeks = bidGreeks
        self.askGreeks = askGreeks
        self.lastGreeks = lastGreeks
        self.modelGreeks = modelGreeks
        self.custGreeks = custGreeks
        self.prices = prices
        self.sizes = sizes
        self.generics = generics
        self.strings = strings
        self.efp = efp
        self.depth = depth
    }

    /// Folds one tick in, after `ib_async`'s `wrapper.py` (priceSizeTick, tickSize, tickGeneric, tickString,
    /// tickOptionComputation), without its `prev…` fields.
    public mutating func apply(_ tick: Tick) {
        switch tick {
        case let .price(field, p, s):
            switch field.live {
            case .bid: bid = s == 0 ? nil : p; bidSize = s
            case .ask: ask = s == 0 ? nil : p; askSize = s
            // An empty last after a close is IB's "no last"; TICK-NYSE has no close and -1 is a real value there.
            case .last where p == -1 && s == 0 && (close ?? 0) > 0: last = nil; lastSize = 0
            case .last: last = p; lastSize = s
            case .high: high = p
            case .low: low = p
            case .close: close = p
            case .open: open = p
            case let k: prices[k] = p
            }
        case let .size(field, s):
            switch field.live {
            case .bidSize: bidSize = s; if s == 0 { bid = nil }
            case .askSize: askSize = s; if s == 0 { ask = nil }
            case .lastSize: if last != nil { lastSize = s }
            case .volume: volume = s
            case let k: sizes[k] = s
            }
        case let .generic(field, v):
            generics[field.live] = v
        case let .string(field, v):
            if field.live == .lastTimestamp {
                if let n = Int(v), n != 0 { lastTimestamp = Date(timeIntervalSince1970: TimeInterval(n)) }
            } else {
                strings[field.live] = v
            }
        case let .dataType(t):
            marketDataType = t
        case let .requestParameters(minTick, bboExchange, snapshotPermissions):
            self.minTick = minTick
            self.bboExchange = bboExchange
            self.snapshotPermissions = snapshotPermissions
        case let .optionComputation(field, c):
            switch field.live.rawValue {
            case 10: bidGreeks = c
            case 11: askGreeks = c
            case 12: lastGreeks = c
            case 13: modelGreeks = c
            case 53: custGreeks = c
            default: break
            }
        case let .efp(field, e):
            efp[field.live] = e
        case .news:
            break
        }
    }
}
