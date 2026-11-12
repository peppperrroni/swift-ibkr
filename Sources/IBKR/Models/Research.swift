import Foundation

/// Which financial-advisor configuration `faData(_:)` and `replaceFA(_:xml:)` read or write
/// (`ib_async`'s `faDataType`).
public enum FADataType: Int, Sendable {
    /// IB's FA data type 1.
    case groups = 1
    /// IB's FA data type 2.
    case profiles = 2
    /// IB's FA data type 3.
    case aliases = 3
}

/// What `wshEventData(_:)` asks Wall Street Horizon for (`ib_async`'s `WshEventData`). `filter` is IB's JSON text;
/// dates are IB's `yyyyMMdd`. A `nil` `conID` or `totalLimit` goes out as `2147483647`, as `ib_async` sends it.
public struct WshEventData: Sendable, Equatable {
    /// The contract to ask about; `nil` goes out as `2147483647`.
    public var conID: Int?
    /// IB's JSON filter text; empty for none.
    public var filter: String
    /// Also covers the watchlist (`fillWatchlist`).
    public var fillWatchlist: Bool
    /// Also covers the portfolio (`fillPortfolio`).
    public var fillPortfolio: Bool
    /// Also covers competitors (`fillCompetitors`).
    public var fillCompetitors: Bool
    /// `yyyyMMdd`; empty for none.
    public var startDate: String
    /// `yyyyMMdd`; empty for none.
    public var endDate: String
    /// The most events to return; `nil` goes out as `2147483647`.
    public var totalLimit: Int?

    /// Creates a request with every field given.
    public init(conID: Int? = nil, filter: String = "", fillWatchlist: Bool = false, fillPortfolio: Bool = false,
                fillCompetitors: Bool = false, startDate: String = "", endDate: String = "", totalLimit: Int? = nil) {
        self.conID = conID; self.filter = filter; self.fillWatchlist = fillWatchlist
        self.fillPortfolio = fillPortfolio; self.fillCompetitors = fillCompetitors
        self.startDate = startDate; self.endDate = endDate; self.totalLimit = totalLimit
    }
}

/// What a market scan looks for (`ib_async`'s `ScannerSubscription`). `instrument`, `locationCode` and `scanCode`
/// come from `scannerParameters()`; every other filter is unset by default. A `nil` `numberOfRows` asks for IB's
/// default.
public struct ScannerSubscription: Sendable, Equatable {
    /// `nil` goes out as `-1`, IB's default row count.
    public var numberOfRows: Int?
    /// An instrument from `scannerParameters()`, such as `STK`.
    public var instrument: String
    /// A location from `scannerParameters()`, such as `STK.US.MAJOR`.
    public var locationCode: String
    /// A scan code from `scannerParameters()`, such as `TOP_PERC_GAIN`.
    public var scanCode: String
    /// The scan's `abovePrice` filter; `nil` sends an empty field.
    public var abovePrice: Decimal?
    /// The scan's `belowPrice` filter; `nil` sends an empty field.
    public var belowPrice: Decimal?
    /// The scan's `aboveVolume` filter; `nil` sends an empty field.
    public var aboveVolume: Int?
    /// The scan's `marketCapAbove` filter; `nil` sends an empty field.
    public var marketCapAbove: Decimal?
    /// The scan's `marketCapBelow` filter; `nil` sends an empty field.
    public var marketCapBelow: Decimal?
    /// The scan's `moodyRatingAbove` filter; empty sends an empty field.
    public var moodyRatingAbove: String
    /// The scan's `moodyRatingBelow` filter; empty sends an empty field.
    public var moodyRatingBelow: String
    /// The scan's `spRatingAbove` filter; empty sends an empty field.
    public var spRatingAbove: String
    /// The scan's `spRatingBelow` filter; empty sends an empty field.
    public var spRatingBelow: String
    /// The scan's `maturityDateAbove` filter; empty sends an empty field.
    public var maturityDateAbove: String
    /// The scan's `maturityDateBelow` filter; empty sends an empty field.
    public var maturityDateBelow: String
    /// The scan's `couponRateAbove` filter; `nil` sends an empty field.
    public var couponRateAbove: Decimal?
    /// The scan's `couponRateBelow` filter; `nil` sends an empty field.
    public var couponRateBelow: Decimal?
    /// The scan's `excludeConvertible` flag, sent as `0` or `1`.
    public var excludeConvertible: Bool
    /// The scan's `averageOptionVolumeAbove` filter; `nil` sends an empty field.
    public var averageOptionVolumeAbove: Int?
    /// IB's `scannerSettingPairs` text, passed as given; empty sends an empty field.
    public var scannerSettingPairs: String
    /// IB's `stockTypeFilter` text, passed as given; empty sends an empty field.
    public var stockTypeFilter: String

    /// Creates a subscription with every field given.
    public init(instrument: String = "", locationCode: String = "", scanCode: String = "", numberOfRows: Int? = nil,
                abovePrice: Decimal? = nil, belowPrice: Decimal? = nil, aboveVolume: Int? = nil,
                marketCapAbove: Decimal? = nil, marketCapBelow: Decimal? = nil,
                moodyRatingAbove: String = "", moodyRatingBelow: String = "", spRatingAbove: String = "",
                spRatingBelow: String = "", maturityDateAbove: String = "", maturityDateBelow: String = "",
                couponRateAbove: Decimal? = nil, couponRateBelow: Decimal? = nil, excludeConvertible: Bool = false,
                averageOptionVolumeAbove: Int? = nil, scannerSettingPairs: String = "", stockTypeFilter: String = "") {
        self.numberOfRows = numberOfRows; self.instrument = instrument; self.locationCode = locationCode
        self.scanCode = scanCode; self.abovePrice = abovePrice; self.belowPrice = belowPrice
        self.aboveVolume = aboveVolume; self.marketCapAbove = marketCapAbove; self.marketCapBelow = marketCapBelow
        self.moodyRatingAbove = moodyRatingAbove; self.moodyRatingBelow = moodyRatingBelow
        self.spRatingAbove = spRatingAbove; self.spRatingBelow = spRatingBelow
        self.maturityDateAbove = maturityDateAbove; self.maturityDateBelow = maturityDateBelow
        self.couponRateAbove = couponRateAbove; self.couponRateBelow = couponRateBelow
        self.excludeConvertible = excludeConvertible; self.averageOptionVolumeAbove = averageOptionVolumeAbove
        self.scannerSettingPairs = scannerSettingPairs; self.stockTypeFilter = stockTypeFilter
    }
}

/// One row of a scan: its rank (from 0) and contract, with IB's text for the rest.
public struct ScanData: Sendable, Equatable {
    /// The row's rank in the scan, from 0.
    public var rank: Int
    /// The instrument; only the fields scannerData carries are set.
    public var contract: Contract
    /// scannerData's `marketName`, IB's text.
    public var marketName: String
    /// scannerData's `distance`, IB's text.
    public var distance: String
    /// scannerData's `benchmark`, IB's text.
    public var benchmark: String
    /// scannerData's `projection`, IB's text.
    public var projection: String
    /// scannerData's `legsStr`, IB's text.
    public var legsStr: String

    /// Creates a row with every field given.
    public init(rank: Int, contract: Contract, marketName: String, distance: String, benchmark: String,
                projection: String, legsStr: String) {
        self.rank = rank; self.contract = contract; self.marketName = marketName; self.distance = distance
        self.benchmark = benchmark; self.projection = projection; self.legsStr = legsStr
    }
}

/// A news provider IB offers: its code (`BRFG`) and display name.
public struct NewsProvider: Sendable, Equatable {
    /// The provider's code, such as `BRFG`.
    public var code: String
    /// The provider's display name.
    public var name: String

    /// Creates a provider with every field given.
    public init(code: String, name: String) { self.code = code; self.name = name }
}

/// One news article: IB's type code (0 plain text, 1 binary or HTML) and its text.
public struct NewsArticle: Sendable, Equatable {
    /// 0 for plain text, 1 for binary or HTML.
    public var articleType: Int
    /// The article's text, as IB sends it.
    public var articleText: String

    /// Creates an article with every field given.
    public init(articleType: Int, articleText: String) {
        self.articleType = articleType; self.articleText = articleText
    }
}

/// One historical headline. `time` is IB's raw text (`2026-11-10 14:30:00.0`).
public struct HistoricalNews: Sendable, Equatable {
    /// IB's raw text.
    public var time: String
    /// The provider's code.
    public var providerCode: String
    /// IB's id for the article, for `newsArticle`.
    public var articleID: String
    /// The headline text.
    public var headline: String

    /// Creates a headline with every field given.
    public init(time: String, providerCode: String, articleID: String, headline: String) {
        self.time = time; self.providerCode = providerCode; self.articleID = articleID; self.headline = headline
    }
}

/// One news bulletin. `msgType` is IB's: 1 a regular bulletin, 2 an exchange no longer trades, 3 it trades again.
public struct NewsBulletin: Sendable, Equatable {
    /// IB's bulletin id.
    public var msgID: Int
    /// 1 a regular bulletin, 2 an exchange no longer trades, 3 it trades again.
    public var msgType: Int
    /// The bulletin's text.
    public var message: String
    /// The exchange the bulletin concerns.
    public var origExchange: String

    /// Creates a bulletin with every field given.
    public init(msgID: Int, msgType: Int, message: String, origExchange: String) {
        self.msgID = msgID; self.msgType = msgType; self.message = message; self.origExchange = origExchange
    }
}
