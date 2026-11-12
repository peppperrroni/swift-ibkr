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

    /// tickNews (84), no version.
    static func news(_ r: inout FieldReader) throws -> IBMessage {
        let id = try r.int()
        return .tick(requestID: id, .news(NewsTick(
            timeStamp: try r.int(), providerCode: try r.string(), articleID: try r.string(), headline: try r.string(),
            extraData: try r.string())))
    }
}
