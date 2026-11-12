import Foundation

/// A contract's market data folded into one value, as `ib_async`'s `Ticker`. `apply(_:)` keys every tick by its live
/// field, so delayed ticks land where real-time ones do. Bid, ask, last, OHLC, volume, the last timestamp, the five
/// greeks and the request parameters are named fields; every other tick goes into `prices`, `sizes`, `generics`,
/// `strings` or `efp` (RT volume, fundamental ratios and dividends stay raw strings). A bid or ask with size 0 has its
/// price `nil`. News ticks are not kept.
public struct Ticker: Sendable, Equatable {
    public var contract: Contract
    public var marketDataType: MarketDataType
    public var minTick: Decimal?
    public var bboExchange: String
    public var snapshotPermissions: Int
    public var bid, bidSize, ask, askSize, last, lastSize: Decimal?
    public var open, high, low, close, volume: Decimal?
    public var lastTimestamp: Date?
    public var bidGreeks, askGreeks, lastGreeks, modelGreeks, custGreeks: OptionComputation?
    /// Every other price tick, keyed by its live field.
    public var prices: [TickField: Decimal]
    public var sizes: [TickField: Decimal]
    public var generics: [TickField: Decimal]
    public var strings: [TickField: String]
    public var efp: [TickField: EFPData]
    public var depth: DepthBook

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
