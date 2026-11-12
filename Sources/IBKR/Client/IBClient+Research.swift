import Foundation

extension IBClient {
    /// A market scan, yielded whole each time IB refreshes it. Never ends itself; IB's error ends it with `.ib`.
    /// Every element is a whole scan, so a slow consumer keeps only the newest. Stopping it sends IB's cancel.
    /// `filterOptions` are the scanner's filter tags (from `scannerParameters()`), `options` IB's scanner options.
    public func scannerSubscription(_ subscription: ScannerSubscription, options: [TagValue] = [],
                                    filterOptions: [TagValue] = [])
        throws(IBClientError) -> AsyncThrowingStream<[ScanData], any Error> {
        try requireConnected()
        let id = nextRequestID()
        return try openStream(.scannerSubscription(requestID: id, subscription: subscription, options: options,
                                                   filterOptions: filterOptions),
                              id: id, cancel: .cancelScannerSubscription(requestID: id),
                              buffering: .bufferingNewest(1)) { message, out in
            if case .scannerData(_, let rows) = message { out.yield(rows) }
            return false
        }
    }

    /// The first scan IB sends for `subscription`, then IB's cancel, as `ib_async`'s `reqScannerDataAsync` does.
    /// IB's error throws `.ib` and sends no cancel.
    public func scannerData(_ subscription: ScannerSubscription, options: [TagValue] = [],
                            filterOptions: [TagValue] = []) async throws(IBClientError) -> [ScanData] {
        try requireConnected()
        let id = nextRequestID()
        let stream = try openStream(.scannerSubscription(requestID: id, subscription: subscription, options: options,
                                                         filterOptions: filterOptions),
                                    id: id, cancel: .cancelScannerSubscription(requestID: id)) { (message, out: AsyncThrowingStream<[ScanData], any Error>.Continuation) in
            guard case .scannerData(_, let rows) = message else { return false }
            out.yield(rows); out.finish(); return false   // false: the termination hop sends the cancel
        }
        guard let rows = try await collect(stream).first else { throw .cancelled }
        return rows
    }

    /// IB's scanner parameters XML: every instrument, location, scan code and filter it offers. IB addresses no
    /// error to it.
    public func scannerParameters() async throws(IBClientError) -> String {
        try requireConnected()
        return try await answer(.scannerParameters) { if case .scannerParameters(let xml) = $0 { xml } else { nil } }
    }

    /// The news providers this account may read. IB addresses no error to it.
    public func newsProviders() async throws(IBClientError) -> [NewsProvider] {
        try requireConnected()
        return try await answer(.newsProviders) { if case .newsProviders(let list) = $0 { list } else { nil } }
    }

    /// IB's news bulletins; `allMessages` also asks for today's earlier ones. Never ends itself; stopping it sends IB's
    /// cancel. IB holds one bulletin subscription per connection, so while one stream is open another throws
    /// `.alreadySubscribed` and sends nothing. IB addresses no error to it.
    public func newsBulletins(allMessages: Bool = false)
        throws(IBClientError) -> AsyncThrowingStream<NewsBulletin, any Error> {
        try requireConnected()
        if let key = newsBulletinKey, hasStream(key) { throw .alreadySubscribed }
        let key = nextLocalID()
        let stream = try openStream(.newsBulletins(allMessages: allMessages), id: key, cancel: .cancelNewsBulletins) {
            (message, out: AsyncThrowingStream<NewsBulletin, any Error>.Continuation) in
            if case .newsBulletin(let b) = message { out.yield(b) }
            return false   // never ends itself, and lets the other id-less waiters see each message
        }
        newsBulletinKey = key
        return stream
    }

    /// One article's text, by the provider code and article id a headline carries.
    public func newsArticle(providerCode: String, articleID: String, options: [TagValue] = [])
        async throws(IBClientError) -> NewsArticle {
        try requireConnected()
        let id = nextRequestID()
        return try await answer(.newsArticle(requestID: id, providerCode: providerCode, articleID: articleID, options: options),
                                id: id) { if case .newsArticle(_, let article) = $0 { article } else { nil } }
    }

    /// Headlines for `conID` from the `+`-joined `providerCodes`, in IB's order, up to `totalResults`. Reads to IB's
    /// end marker and sends no cancel (IB has none); like `ib_async`, drops the marker's `hasMore`.
    public func historicalNews(conID: Int, providerCodes: [String], start: Date? = nil, end: Date? = nil,
                               totalResults: Int, options: [TagValue] = []) async throws(IBClientError) -> [HistoricalNews] {
        try requireConnected()
        let id = nextRequestID()
        let stream = try openStream(.historicalNews(requestID: id, conID: conID, providerCodes: providerCodes, start: start,
                                                    end: end, totalResults: totalResults, options: options),
                                    id: id, cancel: nil) { (message, out: AsyncThrowingStream<HistoricalNews, any Error>.Continuation) in
            switch message {
            case .historicalNews(_, let item): out.yield(item); return false
            case .historicalNewsEnd: out.finish(); return true
            default: return false
            }
        }
        return try await collect(stream)
    }
}
