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
        return try await answer(.scannerSubscription(requestID: id, subscription: subscription, options: options,
                                                     filterOptions: filterOptions),
                                id: id, cancel: .cancelScannerSubscription(requestID: id), thenCancel: true) {
            if case .scannerData(_, let rows) = $0 { rows } else { nil }
        }
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

    /// One fundamentals report as IB's XML text (`ReportSnapshot`, `ReportsFinSummary`, ...), never parsed. IB's error
    /// throws `.ib`. Cancelling the calling task sends IB's cancel; an answer or an error sends none.
    public func fundamentalData(_ contract: Contract, reportType: String, options: [TagValue] = [])
        async throws(IBClientError) -> String {
        try requireConnected()
        let id = nextRequestID()
        return try await answer(.fundamentalData(requestID: id, contract: contract, reportType: reportType, options: options),
                                id: id, cancel: .cancelFundamentalData(requestID: id)) {
            if case .fundamentalData(_, let xml) = $0 { xml } else { nil }
        }
    }

    /// Wall Street Horizon's metadata as IB's JSON text. As `ib_async`'s `getWshMetaDataAsync`, the answered request
    /// stays open (IB wants it before event data) until the next call, which first sends IB's cancel (101) for it; at
    /// most one is held, and the connection's end drops it. IB's error throws `.ib` and holds nothing. Cancelling the
    /// calling task before the answer sends 101.
    public func wshMetaData() async throws(IBClientError) -> String {
        try requireConnected()
        if let held = wshMetaRequestID {
            wshMetaRequestID = nil
            try send(.cancelWshMetaData(requestID: held))
        }
        let id = nextRequestID()
        let json = try await answer(.wshMetaData(requestID: id), id: id, cancel: .cancelWshMetaData(requestID: id)) {
            if case .wshMetaData(_, let json) = $0 { json } else { nil }
        }
        guard (try? requireConnected()) != nil else { return json }   // the connection ended meanwhile: hold nothing
        if let other = wshMetaRequestID { try? send(.cancelWshMetaData(requestID: other)) }   // a concurrent call's
        wshMetaRequestID = id
        return json
    }

    /// Wall Street Horizon's events for `data` as IB's JSON text, then IB's cancel (103). IB's error throws `.ib` and
    /// sends no cancel.
    public func wshEventData(_ data: WshEventData) async throws(IBClientError) -> String {
        try requireConnected()
        let id = nextRequestID()
        return try await answer(.wshEventData(requestID: id, data: data), id: id, cancel: .cancelWshEventData(requestID: id),
                                thenCancel: true) {
            if case .wshEventData(_, let json) = $0 { json } else { nil }
        }
    }

    /// The account's financial-advisor configuration of `type` as IB's XML text, never parsed. 16 carries no reqId, so
    /// each call takes only an answer of its own type. A login that is not an FA account gets an error IB addresses
    /// to no request, so the call then waits until the caller cancels it.
    public func faData(_ type: FADataType) async throws(IBClientError) -> String {
        try requireConnected()
        return try await answer(.requestFA(type)) {
            if case .receiveFA(type, let xml) = $0 { xml } else { nil }
        }
    }

    /// Replaces the account's FA configuration of `type` with `xml` and returns IB's confirmation text (103). IB's
    /// error throws `.ib`. `ib_async` does not wait for the confirmation; this call does.
    public func replaceFA(_ type: FADataType, xml: String) async throws(IBClientError) -> String {
        try requireConnected()
        let id = nextRequestID()
        return try await answer(.replaceFA(requestID: id, type: type, xml: xml), id: id) {
            if case .replaceFAEnd(_, let text) = $0 { text } else { nil }
        }
    }

    /// TWS's display groups as IB's raw list, such as `"1|2|3"`.
    public func displayGroups() async throws(IBClientError) -> String {
        try requireConnected()
        let id = nextRequestID()
        return try await answer(.queryDisplayGroups(requestID: id), id: id) {
            if case .displayGroupList(_, let groups) = $0 { groups } else { nil }
        }
    }

    /// Each contract TWS shows in display group `groupID`, as IB's `contractInfo` text (`"265598@SMART"`). Never ends
    /// itself; IB's error ends it with `.ib`. Stopping it sends IB's unsubscribe. `requestID` is the one
    /// `updateDisplayGroup(_:contractInfo:)` takes.
    public func displayGroupUpdates(_ groupID: Int)
        throws(IBClientError) -> (requestID: Int, updates: AsyncThrowingStream<String, any Error>) {
        try requireConnected()
        let id = nextRequestID()
        let updates = try openStream(.subscribeToGroupEvents(requestID: id, groupID: groupID), id: id,
                                     cancel: .unsubscribeFromGroupEvents(requestID: id)) { message, out in
            if case .displayGroupUpdated(_, let info) = message { out.yield(info) }
            return false
        }
        return (id, updates)
    }

    /// Shows `contractInfo` (`"265598@SMART"`, or `"none"`) in the group the `displayGroupUpdates` stream of `requestID`
    /// follows.
    public func updateDisplayGroup(_ requestID: Int, contractInfo: String) throws(IBClientError) {
        try requireConnected()
        try send(.updateDisplayGroup(requestID: requestID, contractInfo: contractInfo))
    }

    /// IB's verify handshake for third-party API vendors. These four only send; IB's answers (`.verifyMessageAPI`,
    /// `.verifyCompleted`, `.verifyAndAuthMessageAPI`, `.verifyAndAuthCompleted`) reach `messages()` only. IB documents
    /// them before startApi, which `connect` sends itself.
    public func verifyRequest(apiName: String, apiVersion: String) throws(IBClientError) {
        try requireConnected()
        try send(.verifyRequest(apiName: apiName, apiVersion: apiVersion))
    }

    public func verifyMessage(_ apiData: String) throws(IBClientError) {
        try requireConnected()
        try send(.verifyMessage(apiData: apiData))
    }

    public func verifyAndAuthRequest(apiName: String, apiVersion: String, opaqueISVKey: String) throws(IBClientError) {
        try requireConnected()
        try send(.verifyAndAuthRequest(apiName: apiName, apiVersion: apiVersion, opaqueISVKey: opaqueISVKey))
    }

    public func verifyAndAuthMessage(_ apiData: String, xyzResponse: String) throws(IBClientError) {
        try requireConnected()
        try send(.verifyAndAuthMessage(apiData: apiData, xyzResponse: xyzResponse))
    }
}
