import Foundation

extension IBClient {
    /// Every option chain IB lists for `underlying` (one per exchange and trading class), once IB's end marker
    /// arrives. `underlying` needs its `conID`; `futFopExchange` is for futures options only. IB has no cancel for it.
    public func optionChains(for underlying: Contract, futFopExchange: String = "")
        async throws(IBClientError) -> [OptionChain] {
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

    /// IB's implied volatility (and greeks) of option `contract` at `optionPrice` with the underlying at `underPrice`.
    /// The first computation answers; IB's cancel follows it, as `ib_async` sends.
    /// Throws like `marketData` on a refusal.
    public func calculateImpliedVolatility(_ contract: Contract, optionPrice: Decimal, underPrice: Decimal,
                                           options: [TagValue] = []) async throws(IBClientError) -> OptionComputation {
        try requireConnected()
        let id = nextRequestID()
        return try await answer(.calculateImpliedVolatility(requestID: id, contract: contract, optionPrice: optionPrice,
                                                            underPrice: underPrice, options: options),
                                id: id, cancel: .cancelCalculateImpliedVolatility(requestID: id), thenCancel: true,
                                pick: Self.computation)
    }

    /// IB's price (and greeks) of option `contract` at `volatility` with the underlying at `underPrice`; answers,
    /// cancels and throws like `calculateImpliedVolatility`.
    public func calculateOptionPrice(_ contract: Contract, volatility: Decimal, underPrice: Decimal,
                                     options: [TagValue] = []) async throws(IBClientError) -> OptionComputation {
        try requireConnected()
        let id = nextRequestID()
        return try await answer(.calculateOptionPrice(requestID: id, contract: contract, volatility: volatility,
                                                      underPrice: underPrice, options: options),
                                id: id, cancel: .cancelCalculateOptionPrice(requestID: id), thenCancel: true,
                                pick: Self.computation)
    }

    /// The price-increment steps of market rule `marketRuleID` (the ids in `ContractDetails.marketRuleIDs`).
    /// IB's answer carries the rule id and no reqId, so each call takes only its own rule's answer; IB has no error
    /// path for it.
    public func marketRule(_ marketRuleID: Int) async throws(IBClientError) -> [PriceIncrement] {
        try requireConnected()
        return try await answer(.marketRule(marketRuleID: marketRuleID)) {
            if case .marketRule(marketRuleID, let steps) = $0 { steps } else { nil }
        }
    }

    /// Each account's family code. IB addresses no error to it.
    public func familyCodes() async throws(IBClientError) -> [FamilyCode] {
        try requireConnected()
        return try await answer(.familyCodes) { if case .familyCodes(let codes) = $0 { codes } else { nil } }
    }

    /// The soft-dollar tiers IB offers this account.
    public func softDollarTiers() async throws(IBClientError) -> [SoftDollarTier] {
        try requireConnected()
        let id = nextRequestID()
        return try await answer(.softDollarTiers(requestID: id), id: id) {
            if case .softDollarTiers(_, let tiers) = $0 { tiers } else { nil }
        }
    }

    /// The answer is tick 21 under the calculation's own reqId, so a quote stream's 21 never reaches it.
    @Sendable private static func computation(_ message: IBMessage) -> OptionComputation? {
        if case .tick(_, .optionComputation(_, let c)) = message { c } else { nil }
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
