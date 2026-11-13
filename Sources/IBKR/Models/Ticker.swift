import Foundation

/// A contract's market data folded into one value, as `ib_async`'s `Ticker`. `apply(_:at:)` keys every tick by its
/// live field, so delayed ticks land where real-time ones do; the one exception is the delayed last timestamp (88),
/// which sets `delayedLastTimestamp`, not `lastTimestamp`, as in `ib_async`. Bid, ask, last, OHLC, volume, the
/// timestamps, the five greeks, the request parameters and the values before each bid, ask and last change (`prev…`)
/// are stored fields; every other tick goes into `prices`, `sizes`, `generics`, `strings` or `efp`, and `ib_async`'s
/// other names (`low52Week`, `bidExchange`, `shortableShares`, `bidEFP`, …) are computed properties over those
/// dictionaries, `nil` until the tick arrives (a generic tick of 0 or less reads `nil`, so `halted` 0 does too).
/// `hasBidAsk`, `midpoint` and `marketPrice` follow `ib_async`. RT volume (48, 77), fundamental ratios (47) and
/// dividends (59) are parsed into `rtVolume`, `rtTradeVolume`, `rtTime`, `vwap`, `fundamentalRatios` and
/// `dividends`, and their raw strings stay in `strings`; RT volume does not move `last` or `lastSize`, unlike
/// `ib_async`: `last` comes from tick 4 (or a tick-by-tick trade) only. A bid or ask with size 0 has its price `nil`.
/// News ticks are not kept. `ticks`, `tickByTicks` and `domTicks` collect what each update brought: `tickers` clears
/// them before every update, so each element holds its own (and those of any element a slow consumer skipped);
/// `apply` alone only appends, so a ticker folded by hand, or a `tickers(for:)` snapshot, keeps every one.
public struct Ticker: Sendable, Equatable, Encodable {
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
    /// Every string tick (46) except the two last-trade timestamps (45, 88), keyed by its live field.
    public var strings: [TickField: String]
    /// Every EFP quote (47), keyed by its live field.
    public var efp: [TickField: EFPData]
    /// The depth book when `depthRows` was asked for; empty otherwise.
    public var depth: DepthBook
    /// When `tickers` folded in the latest update; `nil` until it does (`ib_async`'s `time` and `timestamp`).
    public var time: Date?
    /// The bid, bid size, ask, ask size, last and last size before their latest change, as `ib_async` keeps them.
    public var prevBid, prevBidSize, prevAsk, prevAskSize, prevLast, prevLastSize: Decimal?
    /// The day's volume from RT volume (48) and from RT trade volume (77); `nil` until one arrives.
    public var rtVolume, rtTradeVolume: Decimal?
    /// The time of the trade the latest RT volume (48, 77) reports; `nil` until one arrives.
    public var rtTime: Date?
    /// The volume-weighted average price from RT volume (48, 77); `nil` until one arrives.
    public var vwap: Decimal?
    /// The time of the last delayed trade (tick 88); `nil` until a tick sets it.
    public var delayedLastTimestamp: Date?
    /// The dividends from tick 59; `nil` until it arrives.
    public var dividends: Dividends?
    /// The fundamental ratios from tick 47; `nil` until it arrives.
    public var fundamentalRatios: FundamentalRatios?
    /// The price and size ticks of the latest update, with their time (see the type's note on clearing).
    public var ticks: [TickData]
    /// The tick-by-tick events of the latest update (see the type's note on clearing).
    public var tickByTicks: [TickByTick]
    /// The depth updates of the latest update, with their time (see the type's note on clearing).
    public var domTicks: [DepthTick]

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
        depth: DepthBook = DepthBook(),
        time: Date? = nil,
        prevBid: Decimal? = nil,
        prevBidSize: Decimal? = nil,
        prevAsk: Decimal? = nil,
        prevAskSize: Decimal? = nil,
        prevLast: Decimal? = nil,
        prevLastSize: Decimal? = nil,
        rtVolume: Decimal? = nil,
        rtTradeVolume: Decimal? = nil,
        rtTime: Date? = nil,
        vwap: Decimal? = nil,
        delayedLastTimestamp: Date? = nil,
        dividends: Dividends? = nil,
        fundamentalRatios: FundamentalRatios? = nil,
        ticks: [TickData] = [],
        tickByTicks: [TickByTick] = [],
        domTicks: [DepthTick] = []
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
        self.time = time
        self.prevBid = prevBid
        self.prevBidSize = prevBidSize
        self.prevAsk = prevAsk
        self.prevAskSize = prevAskSize
        self.prevLast = prevLast
        self.prevLastSize = prevLastSize
        self.rtVolume = rtVolume
        self.rtTradeVolume = rtTradeVolume
        self.rtTime = rtTime
        self.vwap = vwap
        self.delayedLastTimestamp = delayedLastTimestamp
        self.dividends = dividends
        self.fundamentalRatios = fundamentalRatios
        self.ticks = ticks
        self.tickByTicks = tickByTicks
        self.domTicks = domTicks
    }

    /// Folds one tick in, after `ib_async`'s `wrapper.py` (priceSizeTick, tickSize, tickGeneric, tickString,
    /// tickOptionComputation), and appends to `ticks` what `ib_async` records, stamped `time`. It never sets the
    /// ticker's own `time` and never clears `ticks`; `tickers` does both. A string that does not parse leaves its
    /// parsed field unchanged; the raw string still goes into `strings`.
    public mutating func apply(_ tick: Tick, at time: Date = Date()) {
        switch tick {
        case let .price(field, p, s, _):
            var p = p
            switch field.live {
            case .bid:
                if s == 0 { p = nil }
                prevBid = bid; prevBidSize = bidSize; bid = p; bidSize = s
            case .ask:
                if s == 0 { p = nil }
                prevAsk = ask; prevAskSize = askSize; ask = p; askSize = s
            case .last:
                // An empty last after a close is IB's "no last"; TICK-NYSE has no close and -1 is a real value there.
                if p == -1 && s == 0 && (close ?? 0) > 0 { p = nil }
                prevLast = last; prevLastSize = lastSize; last = p; lastSize = s
            case .high: high = p
            case .low: low = p
            case .close: close = p
            case .open: open = p
            case let k: prices[k] = p
            }
            record(field, p, s, at: time)
        case let .size(field, s):
            var price: Decimal?
            switch field.live {
            case .bidSize:
                guard s != bidSize else { return }
                prevBidSize = bidSize; bidSize = s
                if s == 0 { bid = nil } else { price = bid }
            case .askSize:
                guard s != askSize else { return }
                prevAskSize = askSize; askSize = s
                if s == 0 { ask = nil } else { price = ask }
            case .lastSize:
                guard let last else { return }
                price = last
                if s != lastSize { prevLastSize = lastSize; lastSize = s }
            case .volume: volume = s
            case let k: sizes[k] = s
            }
            record(field, price, s, at: time)
        case let .generic(field, v):
            generics[field.live] = v
            ticks.append(TickData(time: time, field: field, price: v > 0 ? v : nil, size: 0))
        case let .string(field, v):
            switch field.rawValue {
            case 45, 88:
                guard let n = Int(v), n != 0 else { break }
                let date = Date(timeIntervalSince1970: TimeInterval(n))
                if field.rawValue == 45 { lastTimestamp = date } else { delayedLastTimestamp = date }
            default:
                strings[field.live] = v
                switch field.rawValue {
                case 47: if let r = FundamentalRatios(ib: v) { fundamentalRatios = r }
                case 48, 77: applyRTVolume(field, v, at: time)
                case 59: if let d = Dividends(ib: v) { dividends = d }
                default: break
                }
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

    /// Folds one tick-by-tick event in, after `ib_async`'s wrapper.py:1111-1195: a trade moves `last` and `lastSize`
    /// (IB's -1 with size 0 is `nil`), a quote moves each side that changed (0 or less is `nil`), a midpoint moves
    /// nothing; each is appended to `tickByTicks` as IB sent it, with IB's own time, so `time` is not used.
    public mutating func apply(_ tick: TickByTick, at time: Date = Date()) {
        switch tick {
        case let .trade(_, price, size, _, _, _, _):
            let empty = price == -1 && size == 0
            prevLast = last; prevLastSize = lastSize
            last = empty ? nil : price; lastSize = empty ? nil : size
        case let .bidAsk(_, bidPrice, askPrice, bidSize, askSize, _, _):
            if bidPrice != bid { prevBid = bid; bid = bidPrice > 0 ? bidPrice : nil }
            if bidSize != self.bidSize { prevBidSize = self.bidSize; self.bidSize = bidSize > 0 ? bidSize : nil }
            if askPrice != ask { prevAsk = ask; ask = askPrice > 0 ? askPrice : nil }
            if askSize != self.askSize { prevAskSize = self.askSize; self.askSize = askSize > 0 ? askSize : nil }
        case .midPoint:
            break
        }
        tickByTicks.append(tick)
    }

    /// Folds one depth update into `depth` and records it in `domTicks`; a delete is recorded with the removed row's
    /// price and size 0, as wrapper.py:1338 does.
    mutating func apply(_ update: DepthUpdate, at time: Date) {
        var recorded = update
        if update.operation == .delete {
            recorded.size = 0
            let rows = update.side == .bid ? depth.bidsByPosition : depth.asksByPosition
            if let row = rows[update.position] { recorded.price = row.price }
        }
        depth.apply(update)
        domTicks.append(DepthTick(time: time, update: recorded))
    }

    /// Empties `depth` on IB's reset (317), recording one delete per row, asks first, as wrapper.py:1681 does.
    mutating func resetDepth(at time: Date) {
        for (side, rows) in [(DepthUpdate.Side.ask, depth.asks), (.bid, depth.bids)] {
            domTicks += rows.map {
                DepthTick(time: time, update: DepthUpdate(position: 0, marketMaker: "", operation: .delete, side: side,
                                                          price: $0.price, size: 0))
            }
        }
        depth.reset()
    }

    /// `ib_async`'s `if price or size`, with `nil` (IB's empty value, `ib_async`'s NaN) counting as set.
    private mutating func record(_ field: TickField, _ price: Decimal?, _ size: Decimal?, at time: Date) {
        if price != 0 || size != 0 { ticks.append(TickData(time: time, field: field, price: price, size: size)) }
    }

    /// RT volume `price;size;ms;totalVolume;vwap;singleTrade` (wrapper.py:482): each part that reads sets its field,
    /// and a trade with a price is recorded in `ticks`; `last` and `lastSize` stay as they are (see DECISIONS).
    private mutating func applyRTVolume(_ field: TickField, _ v: String, at time: Date) {
        let p = v.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard p.count == 6 else { return }
        if let n = FieldReader.plainDecimal(p[3]) {
            if field.rawValue == 48 { rtVolume = n } else { rtTradeVolume = n }
        }
        if let n = FieldReader.plainDecimal(p[4]) { vwap = n }
        if let ms = Int(p[2]) { rtTime = Date(timeIntervalSince1970: Double(ms) / 1000) }
        if let price = FieldReader.plainDecimal(p[0]), let size = FieldReader.plainDecimal(p[1]) {
            ticks.append(TickData(time: time, field: field, price: price, size: size))
        }
    }
}
