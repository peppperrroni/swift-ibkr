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
}
