import Foundation

/// One price or size tick as `Ticker.ticks` records it, `ib_async`'s `TickData`: the arrival time, IB's raw tick
/// type (a delayed tick keeps its own number, 68 stays 68) and the price and size `ib_async` records for it.
public struct TickData: Sendable, Equatable, Encodable {
    /// When the update that carried the tick was folded in.
    public var time: Date
    /// IB's tick type, as sent.
    public var field: TickField
    /// The price; `nil` for a size-only tick with no price to give, or an emptied side.
    public var price: Decimal?
    /// The size; `nil` where IB sent none.
    public var size: Decimal?

    /// Creates a tick record with every field given.
    public init(time: Date, field: TickField, price: Decimal?, size: Decimal?) {
        self.time = time
        self.field = field
        self.price = price
        self.size = size
    }
}

/// One depth update as `Ticker.domTicks` records it, `ib_async`'s `MktDepthData`: the arrival time and the update.
public struct DepthTick: Sendable, Equatable, Encodable {
    /// When the update was folded in.
    public var time: Date
    /// The update; a delete carries the price of the row it removed and size 0, as `ib_async` records it.
    public var update: DepthUpdate

    /// Creates a depth record with every field given.
    public init(time: Date, update: DepthUpdate) {
        self.time = time
        self.update = update
    }
}

/// IB's dividend tick (59, `"0.83,0.92,20130219,0.23"`), `ib_async`'s `Dividends`; an empty part is `nil`.
public struct Dividends: Sendable, Equatable, Encodable {
    /// The dividends paid over the past twelve months.
    public var past12Months: Decimal?
    /// The dividends expected over the next twelve months.
    public var next12Months: Decimal?
    /// The next dividend date, 00:00 UTC of IB's `yyyyMMdd`.
    public var nextDate: Date?
    /// The next dividend's amount.
    public var nextAmount: Decimal?

    /// Creates dividends with every field given; all `nil` by default.
    public init(past12Months: Decimal? = nil, next12Months: Decimal? = nil, nextDate: Date? = nil,
                nextAmount: Decimal? = nil) {
        self.past12Months = past12Months
        self.next12Months = next12Months
        self.nextDate = nextDate
        self.nextAmount = nextAmount
    }

    /// Parses IB's four comma-separated parts; `nil` unless there are four and each non-empty one reads.
    init?(ib value: String) {
        let p = value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard p.count == 4 else { return nil }
        // .some(nil) is an empty part; nil is a part that does not read
        func number(_ s: String) -> Decimal?? {
            s.isEmpty ? .some(nil) : FieldReader.plainDecimal(s).map(Optional.some)
        }
        guard let past = number(p[0]), let next = number(p[1]), let amount = number(p[3]) else { return nil }
        var date: Date?
        if !p[2].isEmpty {
            guard let d = IBDecoder.barTime(p[2]) else { return nil }
            date = d
        }
        self.init(past12Months: past, next12Months: next, nextDate: date, nextAmount: amount)
    }
}

/// IB's fundamental ratios tick (47, `"CURRENCY=USD;MKTCAP=3000000.5;"`), `ib_async`'s `FundamentalRatios`: every
/// tag with IB's text, numbers read through `decimal(_:)`.
public struct FundamentalRatios: Sendable, Equatable, Encodable {
    /// IB's text for each tag.
    public var values: [String: String]

    /// Creates ratios from tag-to-text pairs.
    public init(values: [String: String] = [:]) { self.values = values }

    /// IB's text for `tag`; `nil` when IB sent no such tag.
    public subscript(_ tag: String) -> String? { values[tag] }

    /// The number for `tag`; `nil` when the tag is absent, not a number, or IB's `-99999.99` (not available).
    public func decimal(_ tag: String) -> Decimal? {
        guard let s = values[tag], s != "-99999.99" else { return nil }
        return FieldReader.plainDecimal(s)
    }

    /// Parses IB's `tag=value;` pairs; `nil` when a non-empty pair has no single `=`, as `ib_async` drops it whole.
    init?(ib value: String) {
        var values: [String: String] = [:]
        for pair in value.split(separator: ";") {
            let kv = pair.split(separator: "=", omittingEmptySubsequences: false)
            guard kv.count == 2 else { return nil }
            values[String(kv[0])] = String(kv[1])
        }
        self.init(values: values)
    }
}
