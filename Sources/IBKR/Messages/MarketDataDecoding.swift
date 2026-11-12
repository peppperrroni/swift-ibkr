import Foundation

extension IBDecoder {
    /// tickOptionComputation (21), no version.
    static func optionComputation(_ r: inout FieldReader) throws -> IBMessage {
        let id = try r.int(), f = TickField(rawValue: try r.int()), attrib = try r.int()
        // IB marks an uncomputed value -1 (prices and vol) or -2 (greeks).
        func value(_ uncomputed: Decimal) throws -> Decimal? {
            let v = try r.optionalDecimal()
            return v == uncomputed ? nil : v
        }
        return .tick(requestID: id, .optionComputation(f, OptionComputation(
            tickAttrib: attrib, impliedVol: try value(-1), delta: try value(-2), optPrice: try value(-1),
            pvDividend: try value(-1), gamma: try value(-2), vega: try value(-2), theta: try value(-2),
            undPrice: try value(-1))))
    }

    /// tickEFP (47), with a version.
    static func efp(_ r: inout FieldReader) throws -> IBMessage {
        try r.skip()
        let id = try r.int(), f = TickField(rawValue: try r.int())
        return .tick(requestID: id, .efp(f, EFPData(
            basisPoints: try r.optionalDecimal(), formattedBasisPoints: try r.string(),
            impliedFuture: try r.optionalDecimal(), holdDays: try r.optionalInt(), futureLastTradeDate: try r.string(),
            dividendImpact: try r.optionalDecimal(), dividendsToLastTradeDate: try r.optionalDecimal())))
    }

    /// mktDepthExchanges (80): no version, no reqId.
    static func depthExchanges(_ r: inout FieldReader) throws -> IBMessage {
        .depthExchanges(try (0..<wireCount(&r)).map { _ in
            DepthMarketDataDescription(
                exchange: try r.string(), secType: try r.string(), listingExchange: try r.string(),
                serviceDataType: try r.string(), aggGroup: try r.optionalInt())
        })
    }

    /// smartComponents (82): no version.
    static func smartComponents(_ r: inout FieldReader) throws -> IBMessage {
        let id = try r.int()
        return .smartComponents(requestID: id, try (0..<wireCount(&r)).map { _ in
            SmartComponent(bitNumber: try r.int(), exchange: try r.string(), exchangeLetter: try r.string())
        })
    }

    /// historicalSchedule (106): no version.
    static func historicalSchedule(_ r: inout FieldReader) throws -> IBMessage {
        let id = try r.int(), start = try r.string(), end = try r.string(), zone = try r.string()
        return .historicalSchedule(requestID: id, HistoricalSchedule(
            startDateTime: start, endDateTime: end, timeZone: zone, sessions: try (0..<wireCount(&r)).map { _ in
                HistoricalSession(startDateTime: try r.string(), endDateTime: try r.string(), refDate: try r.string())
            }))
    }

    /// historicalTicks (96 midpoint, 97 bid/ask, 98 last): no version; the same shape with a different row.
    static func historicalTicks(_ r: inout FieldReader, _ kind: Int) throws -> IBMessage {
        let reqID = try r.int()
        let ticks: [TickByTick] = try (0..<wireCount(&r)).map { _ in
            let time = Date(timeIntervalSince1970: Double(try r.int()))
            switch kind {
            case 96:
                try r.skip()  // unused
                let price = try r.decimal()
                try r.skip()  // size
                return .midPoint(time: time, price: price)
            case 97:
                try r.skip()  // attribMask
                let bid = try r.decimal(), ask = try r.decimal()
                return .bidAsk(time: time, bidPrice: bid, askPrice: ask, bidSize: try r.decimal(), askSize: try r.decimal())
            default:
                let mask = try r.int(), price = try r.decimal(), size = try r.decimal()
                return .trade(time: time, price: price, size: size, exchange: try r.string(), conditions: try r.string(),
                              pastLimit: mask & 1 != 0, unreported: mask & 2 != 0)
            }
        }
        return .historicalTicks(requestID: reqID, ticks, done: try r.bool())
    }

    /// tickNews (84), no version.
    static func news(_ r: inout FieldReader) throws -> IBMessage {
        let id = try r.int()
        return .tick(requestID: id, .news(NewsTick(
            timeStamp: try r.int(), providerCode: try r.string(), articleID: try r.string(), headline: try r.string(),
            extraData: try r.string())))
    }
}

extension IBDecoder {
    /// histogramData (89): no version.
    static func histogramData(_ r: inout FieldReader) throws -> IBMessage {
        let id = try r.int()
        return .histogramData(requestID: id, try (0..<wireCount(&r)).map { _ in
            HistogramData(price: try r.decimal(), count: try wireCount(&r))
        })
    }
}
