import Foundation

/// Which financial-advisor configuration `faData(_:)` and `replaceFA(_:xml:)` read or write (`ib_async`'s `faDataType`).
public enum FADataType: Int, Sendable {
    case groups = 1, profiles = 2, aliases = 3
}

/// What `wshEventData(_:)` asks Wall Street Horizon for (`ib_async`'s `WshEventData`). `filter` is IB's JSON text;
/// dates are IB's `yyyyMMdd`. A `nil` `conID` or `totalLimit` goes out as `2147483647`, as `ib_async` sends it.
public struct WshEventData: Sendable, Equatable {
    public var conID: Int?
    public var filter: String
    public var fillWatchlist: Bool
    public var fillPortfolio: Bool
    public var fillCompetitors: Bool
    public var startDate: String
    public var endDate: String
    public var totalLimit: Int?

    public init(conID: Int? = nil, filter: String = "", fillWatchlist: Bool = false, fillPortfolio: Bool = false,
                fillCompetitors: Bool = false, startDate: String = "", endDate: String = "", totalLimit: Int? = nil) {
        self.conID = conID; self.filter = filter; self.fillWatchlist = fillWatchlist
        self.fillPortfolio = fillPortfolio; self.fillCompetitors = fillCompetitors
        self.startDate = startDate; self.endDate = endDate; self.totalLimit = totalLimit
    }
}

/// What a market scan looks for (`ib_async`'s `ScannerSubscription`). `instrument`, `locationCode` and `scanCode`
/// come from `scannerParameters()`; every other filter is unset by default. A `nil` `numberOfRows` asks for IB's default.
public struct ScannerSubscription: Sendable, Equatable {
    public var numberOfRows: Int?
    public var instrument: String
    public var locationCode: String
    public var scanCode: String
    public var abovePrice: Decimal?
    public var belowPrice: Decimal?
    public var aboveVolume: Int?
    public var marketCapAbove: Decimal?
    public var marketCapBelow: Decimal?
    public var moodyRatingAbove: String
    public var moodyRatingBelow: String
    public var spRatingAbove: String
    public var spRatingBelow: String
    public var maturityDateAbove: String
    public var maturityDateBelow: String
    public var couponRateAbove: Decimal?
    public var couponRateBelow: Decimal?
    public var excludeConvertible: Bool
    public var averageOptionVolumeAbove: Int?
    public var scannerSettingPairs: String
    public var stockTypeFilter: String

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
    public var rank: Int
    public var contract: Contract
    public var marketName: String
    public var distance: String
    public var benchmark: String
    public var projection: String
    public var legsStr: String

    public init(rank: Int, contract: Contract, marketName: String, distance: String, benchmark: String,
                projection: String, legsStr: String) {
        self.rank = rank; self.contract = contract; self.marketName = marketName; self.distance = distance
        self.benchmark = benchmark; self.projection = projection; self.legsStr = legsStr
    }
}

/// A news provider IB offers: its code (`BRFG`) and display name.
public struct NewsProvider: Sendable, Equatable {
    public var code: String
    public var name: String

    public init(code: String, name: String) { self.code = code; self.name = name }
}

/// One news article: IB's type code (0 plain text, 1 binary or HTML) and its text.
public struct NewsArticle: Sendable, Equatable {
    public var articleType: Int
    public var articleText: String

    public init(articleType: Int, articleText: String) { self.articleType = articleType; self.articleText = articleText }
}

/// One historical headline. `time` is IB's raw text (`2026-11-10 14:30:00.0`).
public struct HistoricalNews: Sendable, Equatable {
    public var time: String
    public var providerCode: String
    public var articleID: String
    public var headline: String

    public init(time: String, providerCode: String, articleID: String, headline: String) {
        self.time = time; self.providerCode = providerCode; self.articleID = articleID; self.headline = headline
    }
}

/// One news bulletin. `msgType` is IB's: 1 a regular bulletin, 2 an exchange no longer trades, 3 it trades again.
public struct NewsBulletin: Sendable, Equatable {
    public var msgID: Int
    public var msgType: Int
    public var message: String
    public var origExchange: String

    public init(msgID: Int, msgType: Int, message: String, origExchange: String) {
        self.msgID = msgID; self.msgType = msgType; self.message = message; self.origExchange = origExchange
    }
}
