import Foundation

/// The named fields of `ib_async`'s `Ticker`, each reading the live-keyed dictionaries `apply(_:at:)` fills; `nil`
/// until the tick arrives. A delayed tick lands on the same name as its real-time twin.
extension Ticker {
    // MARK: Strings

    /// The bid exchange (tick 32); `nil` until a tick sets it.
    public var bidExchange: String? { strings[TickField(rawValue: 32)] }

    /// The ask exchange (tick 33); `nil` until a tick sets it.
    public var askExchange: String? { strings[TickField(rawValue: 33)] }

    /// The last-trade exchange (tick 84); `nil` until a tick sets it.
    public var lastExchange: String? { strings[TickField(rawValue: 84)] }

    /// The last regulatory time (tick 85); `nil` until a tick sets it.
    public var lastRegTime: String? { strings[TickField(rawValue: 85)] }

    /// The option bid exchange (tick 25); `nil` until a tick sets it.
    public var optionBidExchange: String? { strings[TickField(rawValue: 25)] }

    /// The option ask exchange (tick 26); `nil` until a tick sets it.
    public var optionAskExchange: String? { strings[TickField(rawValue: 26)] }

    /// The Reuters mutual funds data (tick 91); `nil` until a tick sets it.
    public var reutersMutualFunds: String? { strings[TickField(rawValue: 91)] }

    /// The social market analytics data (tick 100); `nil` until a tick sets it.
    public var socialMarketAnalytics: String? { strings[TickField(rawValue: 100)] }

    // MARK: Prices

    /// The 13-week low (tick 15); `nil` until a tick sets it.
    public var low13Week: Decimal? { prices[TickField(rawValue: 15)] }

    /// The 13-week high (tick 16); `nil` until a tick sets it.
    public var high13Week: Decimal? { prices[TickField(rawValue: 16)] }

    /// The 26-week low (tick 17); `nil` until a tick sets it.
    public var low26Week: Decimal? { prices[TickField(rawValue: 17)] }

    /// The 26-week high (tick 18); `nil` until a tick sets it.
    public var high26Week: Decimal? { prices[TickField(rawValue: 18)] }

    /// The 52-week low (tick 19); `nil` until a tick sets it.
    public var low52Week: Decimal? { prices[TickField(rawValue: 19)] }

    /// The 52-week high (tick 20); `nil` until a tick sets it.
    public var high52Week: Decimal? { prices[TickField(rawValue: 20)] }

    /// The bid yield (tick 50); `nil` until a tick sets it.
    public var bidYield: Decimal? { prices[TickField(rawValue: 50)] }

    /// The ask yield (tick 51); `nil` until a tick sets it.
    public var askYield: Decimal? { prices[TickField(rawValue: 51)] }

    /// The last yield (tick 52); `nil` until a tick sets it.
    public var lastYield: Decimal? { prices[TickField(rawValue: 52)] }

    /// The mark price (tick 37); `nil` until a tick sets it.
    public var markPrice: Decimal? { prices[TickField(rawValue: 37)] }

    /// The last regular-trading-hours trade price (tick 57); `nil` until a tick sets it.
    public var lastRTHTrade: Decimal? { prices[TickField(rawValue: 57)] }

    /// The Creditman mark price (tick 78); `nil` until a tick sets it.
    public var creditmanMarkPrice: Decimal? { prices[TickField(rawValue: 78)] }

    /// The Creditman slow mark price (tick 79); `nil` until a tick sets it.
    public var creditmanSlowMarkPrice: Decimal? { prices[TickField(rawValue: 79)] }

    /// The ETF NAV close (tick 92); `nil` until a tick sets it.
    public var etfNavClose: Decimal? { prices[TickField(rawValue: 92)] }

    /// The ETF NAV prior close (tick 93); `nil` until a tick sets it.
    public var etfNavPriorClose: Decimal? { prices[TickField(rawValue: 93)] }

    /// The ETF NAV bid (tick 94); `nil` until a tick sets it.
    public var etfNavBid: Decimal? { prices[TickField(rawValue: 94)] }

    /// The ETF NAV ask (tick 95); `nil` until a tick sets it.
    public var etfNavAsk: Decimal? { prices[TickField(rawValue: 95)] }

    /// The ETF NAV last (tick 96); `nil` until a tick sets it.
    public var etfNavLast: Decimal? { prices[TickField(rawValue: 96)] }

    /// The ETF frozen NAV last (tick 97); `nil` until a tick sets it.
    public var etfFrozenNavLast: Decimal? { prices[TickField(rawValue: 97)] }

    /// The ETF NAV high (tick 98); `nil` until a tick sets it.
    public var etfNavHigh: Decimal? { prices[TickField(rawValue: 98)] }

    /// The ETF NAV low (tick 99); `nil` until a tick sets it.
    public var etfNavLow: Decimal? { prices[TickField(rawValue: 99)] }

    /// The estimated IPO midpoint (tick 101); `nil` until a tick sets it.
    public var estimatedIPOMidpoint: Decimal? { prices[TickField(rawValue: 101)] }

    /// The final IPO last price (tick 102); `nil` until a tick sets it.
    public var finalIPOLast: Decimal? { prices[TickField(rawValue: 102)] }

    /// The auction price (tick 35); `nil` until a tick sets it.
    public var auctionPrice: Decimal? { prices[TickField(rawValue: 35)] }

    // MARK: Sizes

    /// The average volume (tick 21); `nil` until a tick sets it.
    public var averageVolume: Decimal? { sizes[TickField(rawValue: 21)] }

    /// The open interest (tick 22); `nil` until a tick sets it.
    public var openInterest: Decimal? { sizes[TickField(rawValue: 22)] }

    /// The option call open interest (tick 27); `nil` until a tick sets it.
    public var callOpenInterest: Decimal? { sizes[TickField(rawValue: 27)] }

    /// The option put open interest (tick 28); `nil` until a tick sets it.
    public var putOpenInterest: Decimal? { sizes[TickField(rawValue: 28)] }

    /// The option call volume (tick 29); `nil` until a tick sets it.
    public var callVolume: Decimal? { sizes[TickField(rawValue: 29)] }

    /// The option put volume (tick 30); `nil` until a tick sets it.
    public var putVolume: Decimal? { sizes[TickField(rawValue: 30)] }

    /// The auction volume (tick 34); `nil` until a tick sets it.
    public var auctionVolume: Decimal? { sizes[TickField(rawValue: 34)] }

    /// The auction imbalance (tick 36); `nil` until a tick sets it.
    public var auctionImbalance: Decimal? { sizes[TickField(rawValue: 36)] }

    /// The regulatory imbalance (tick 61); `nil` until a tick sets it.
    public var regulatoryImbalance: Decimal? { sizes[TickField(rawValue: 61)] }

    /// The 3-minute volume rate (tick 63); `nil` until a tick sets it.
    public var volumeRate3Min: Decimal? { sizes[TickField(rawValue: 63)] }

    /// The 5-minute volume rate (tick 64); `nil` until a tick sets it.
    public var volumeRate5Min: Decimal? { sizes[TickField(rawValue: 64)] }

    /// The 10-minute volume rate (tick 65); `nil` until a tick sets it.
    public var volumeRate10Min: Decimal? { sizes[TickField(rawValue: 65)] }

    /// The futures open interest (tick 86); `nil` until a tick sets it.
    public var futuresOpenInterest: Decimal? { sizes[TickField(rawValue: 86)] }

    /// The average option volume (tick 87); `nil` until a tick sets it.
    public var averageOptionVolume: Decimal? { sizes[TickField(rawValue: 87)] }

    /// The number of shares available to short (tick 89); `nil` until a tick sets it.
    public var shortableShares: Decimal? { sizes[TickField(rawValue: 89)] }

    // MARK: Generic ticks (0 or less reads as nil, as ib_async; so halted 0, "not halted", is nil)

    /// The index future premium (tick 31); `nil` until a tick sets it.
    public var indexFuturePremium: Decimal? { generics[TickField(rawValue: 31)].flatMap { $0 > 0 ? $0 : nil } }

    /// The historical volatility (tick 23); `nil` until a tick sets it.
    public var histVolatility: Decimal? { generics[TickField(rawValue: 23)].flatMap { $0 > 0 ? $0 : nil } }

    /// The option implied volatility (tick 24); `nil` until a tick sets it.
    public var impliedVolatility: Decimal? { generics[TickField(rawValue: 24)].flatMap { $0 > 0 ? $0 : nil } }

    /// The shortable level (tick 46); `nil` until a tick sets it.
    public var shortable: Decimal? { generics[TickField(rawValue: 46)].flatMap { $0 > 0 ? $0 : nil } }

    /// The halted flag (tick 49); `nil` until a tick sets it.
    public var halted: Decimal? { generics[TickField(rawValue: 49)].flatMap { $0 > 0 ? $0 : nil } }

    /// The trade count (tick 54); `nil` until a tick sets it.
    public var tradeCount: Decimal? { generics[TickField(rawValue: 54)].flatMap { $0 > 0 ? $0 : nil } }

    /// The trade rate (tick 55); `nil` until a tick sets it.
    public var tradeRate: Decimal? { generics[TickField(rawValue: 55)].flatMap { $0 > 0 ? $0 : nil } }

    /// The volume rate (tick 56); `nil` until a tick sets it.
    public var volumeRate: Decimal? { generics[TickField(rawValue: 56)].flatMap { $0 > 0 ? $0 : nil } }

    /// The real-time historical volatility (tick 58); `nil` until a tick sets it.
    public var rtHistVolatility: Decimal? { generics[TickField(rawValue: 58)].flatMap { $0 > 0 ? $0 : nil } }

    /// The bond factor multiplier (tick 60); `nil` until a tick sets it.
    public var bondFactorMultiplier: Decimal? { generics[TickField(rawValue: 60)].flatMap { $0 > 0 ? $0 : nil } }

    /// The delayed halted flag (tick 90); `nil` until a tick sets it.
    public var delayedHalted: Decimal? { generics[TickField(rawValue: 90)].flatMap { $0 > 0 ? $0 : nil } }

    // MARK: EFP quotes

    /// The bid EFP quote (tick 38); `nil` until a tick sets it.
    public var bidEFP: EFPData? { efp[TickField(rawValue: 38)] }

    /// The ask EFP quote (tick 39); `nil` until a tick sets it.
    public var askEFP: EFPData? { efp[TickField(rawValue: 39)] }

    /// The last EFP quote (tick 40); `nil` until a tick sets it.
    public var lastEFP: EFPData? { efp[TickField(rawValue: 40)] }

    /// The open EFP quote (tick 41); `nil` until a tick sets it.
    public var openEFP: EFPData? { efp[TickField(rawValue: 41)] }

    /// The high EFP quote (tick 42); `nil` until a tick sets it.
    public var highEFP: EFPData? { efp[TickField(rawValue: 42)] }

    /// The low EFP quote (tick 43); `nil` until a tick sets it.
    public var lowEFP: EFPData? { efp[TickField(rawValue: 43)] }

    /// The close EFP quote (tick 44); `nil` until a tick sets it.
    public var closeEFP: EFPData? { efp[TickField(rawValue: 44)] }

    // MARK: Bid, ask and market price

    /// Whether bid and ask are both set, neither is -1, and both sizes are above 0.
    public var hasBidAsk: Bool {
        guard let bid, let ask, let bidSize, let askSize else { return false }
        return bid != -1 && ask != -1 && bidSize > 0 && askSize > 0
    }

    /// The average of bid and ask; `nil` unless `hasBidAsk`.
    public var midpoint: Decimal? { hasBidAsk ? (bid! + ask!) / 2 : nil }

    /// The last price when it lies within bid and ask or there is no bid/ask, else the midpoint; `nil` when there is
    /// nothing to give.
    public var marketPrice: Decimal? {
        guard hasBidAsk else { return last }
        if let last, bid! <= last, last <= ask! { return last }
        return midpoint
    }
}
