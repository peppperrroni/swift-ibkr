extension IBClient {
    /// Every option chain IB lists for `underlying` (one per exchange and trading class), once IB's end marker
    /// arrives. `underlying` needs its `conID`; `futFopExchange` is for futures options only. IB has no cancel for it.
    public func optionChains(for underlying: Contract, futFopExchange: String = "") async throws(IBClientError) -> [OptionChain] {
        try requireConnected()
        let id = nextRequestID()
        return try await collect(try openStream(
            .secDefOptParams(requestID: id, underlyingSymbol: underlying.symbol, futFopExchange: futFopExchange,
                             underlyingSecType: underlying.secType, underlyingConID: underlying.conID),
            id: id, cancel: nil) { message, out in
            switch message {
            case .securityDefinitionOptionParameter(_, let chain): out.yield(chain); return false
            case .securityDefinitionOptionParameterEnd: out.finish(); return true
            default: return false
            }
        })
    }

    /// One `ContractQualification` per input, in input order; every lookup runs at once, as `ib_async` gathers them.
    /// Refuses a `BAG` before sending anything. IB's 200 is `.notFound`; any other error throws, and the lookups
    /// still open are dropped (contract details have no cancel message).
    public func qualifyContracts(_ contracts: [Contract]) async throws(IBClientError) -> [ContractQualification] {
        if contracts.contains(where: { $0.secType == "BAG" }) { throw .encoding(.unsupported("secType BAG")) }
        do {
            return try await withThrowingTaskGroup(of: (Int, ContractQualification).self) { group in
                for (i, contract) in contracts.enumerated() {
                    group.addTask { (i, try await self.qualify(contract)) }
                }
                var got = [ContractQualification](repeating: .notFound, count: contracts.count)
                for try await (i, q) in group { got[i] = q }
                return got
            }
        } catch {
            throw error as? IBClientError ?? .cancelled
        }
    }

    private func qualify(_ contract: Contract) async throws(IBClientError) -> ContractQualification {
        let details: [ContractDetails]
        do throws(IBClientError) { details = try await contractDetails(contract) } catch {
            if case .ib(code: 200, _) = error { return .notFound }
            throw error
        }
        var candidates = details.map(\.contract)
        // ib_async keeps only the requested secType, even when that leaves none.
        if candidates.count > 1, !contract.secType.isEmpty {
            candidates = candidates.filter { $0.secType == contract.secType }
        }
        guard candidates.count == 1, var c = candidates.first else {
            return details.isEmpty ? .notFound : .ambiguous(candidates)
        }
        if contract.exchange == "SMART" { c.exchange = "SMART" }
        return .qualified(c)
    }
}
