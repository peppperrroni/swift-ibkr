import Foundation
@testable import IBKR

/// Every ib_async `ContractDetails` dataclass field under `prefix` (its contract under `prefix + "contract."`), as the
/// canonical flatten names them. Task 8's scanner mapping reuses it. `mdSizeMultiplier` is obsolete and never on the
/// wire at 178 (decoder.py:263-322 read it only below 164), so it is the 1 ib_async leaves in it; `orderTypes`,
/// `validExchanges` and `marketRuleIds` are ib_async's raw comma text (Disagreements 12), so ours are joined.
/// `secIdList` is a list of `TagValue` NamedTuples, flattened by position as the history ticks are. A bond's fields
/// are only on the 18 wire (decoder.py:346-424), so `coupon` is the 0 ib_async's dataclass leaves in it unless
/// `bond` (R9: a field the decoder never reads maps to ib_async's default).
func contractDetailsArgs(_ d: ContractDetails, prefix: String, bond: Bool = false) -> [String: String] {
    var a: [String: String] = [
        "marketName": d.marketName, "minTick": canon(d.minTick), "orderTypes": d.orderTypes.joined(separator: ","),
        "validExchanges": d.validExchanges.joined(separator: ","), "priceMagnifier": canon(d.priceMagnifier),
        "underConId": canon(d.underConID), "longName": d.longName, "contractMonth": d.contractMonth,
        "industry": d.industry, "category": d.category, "subcategory": d.subcategory, "timeZoneId": d.timeZoneID,
        "tradingHours": d.tradingHours, "liquidHours": d.liquidHours, "evRule": d.evRule,
        "evMultiplier": canon(d.evMultiplier), "mdSizeMultiplier": "1", "aggGroup": canon(d.aggGroup),
        "underSymbol": d.underSymbol, "underSecType": d.underSecType,
        "marketRuleIds": d.marketRuleIDs.map { canon($0) }.joined(separator: ","),
        "secIdList.#": canon(d.secIDList.count), "realExpirationDate": d.realExpirationDate,
        "lastTradeTime": d.lastTradeTime, "stockType": d.stockType, "minSize": canon(d.minSize),
        "sizeIncrement": canon(d.sizeIncrement), "suggestedSizeIncrement": canon(d.suggestedSizeIncrement),
        "cusip": d.cusip, "ratings": d.ratings, "descAppend": d.descAppend, "bondType": d.bondType,
        "couponType": d.couponType, "callable": canon(d.callable), "putable": canon(d.putable),
        "coupon": bond ? canon(d.coupon) : "0", "convertible": canon(d.convertible), "maturity": d.maturity,
        "issueDate": d.issueDate, "nextOptionDate": d.nextOptionDate, "nextOptionType": d.nextOptionType,
        "nextOptionPartial": canon(d.nextOptionPartial), "notes": d.notes,
    ]
    for (i, t) in d.secIDList.enumerated() {
        a["secIdList[\(i)].#"] = "2"; a["secIdList[\(i)][0]"] = t.tag; a["secIdList[\(i)][1]"] = t.value
    }
    let own = Dictionary(uniqueKeysWithValues: a.map { (prefix + $0.key, $0.value) })
    return own.merging(contractArgs(d.contract, prefix: prefix + "contract.")) { a, _ in a }
}

/// in 10, 18, 52, 75, 76, 77, 78, 79, 80, 82, 93 under ib_async's wrapper names (18 is `bondContractDetails`, whose
/// arguments are 10's: one `ContractDetails`). ib_async's `PriceIncrement` is a NamedTuple, flattened by position:
/// `[0]` lowEdge, `[1]` increment, width 2 (a property of its type, as the history ticks' widths). ib_async's symbol
/// samples keep IB's description and issuer id on the `Contract` (176+), where `ContractDescription` holds them.
func referenceCalls(id: Int, _ m: IBMessage) -> [OracleCall]? {
    func call(_ method: String, _ args: [String: String]) -> [OracleCall] { [OracleCall(method: method, args: args)] }
    switch m {
    case .contractData(let reqId, let d):
        return call(id == 18 ? "bondContractDetails" : "contractDetails",
                    contractDetailsArgs(d, prefix: "contractDetails.", bond: id == 18)
                        // 18's decoder never reads the contract's strike (decoder.py:346-424): ib_async's default 0.0
                        .merging(id == 18 ? ["contractDetails.contract.strike": "0"] : [:]) { _, new in new }
                        .merging(["reqId": canon(reqId)]) { a, _ in a })
    case .contractDataEnd(let reqId): return call("contractDetailsEnd", ["reqId": canon(reqId)])
    case .securityDefinitionOptionParameter(let reqId, let c):
        var a = ["reqId": canon(reqId), "exchange": c.exchange, "underlyingConId": canon(c.underlyingConID),
                 "tradingClass": c.tradingClass, "multiplier": c.multiplier,
                 "expirations.#": canon(c.expirations.count), "strikes.#": canon(c.strikes.count)]
        for (i, e) in c.expirations.enumerated() { a["expirations[\(i)]"] = e }
        for (i, s) in c.strikes.enumerated() { a["strikes[\(i)]"] = canon(s) }
        return call("securityDefinitionOptionParameter", a)
    case .securityDefinitionOptionParameterEnd(let reqId):
        return call("securityDefinitionOptionParameterEnd", ["reqId": canon(reqId)])
    case .softDollarTiers(let reqId, let tiers):
        var a = ["reqId": canon(reqId), "tiers.#": canon(tiers.count)]
        for (i, t) in tiers.enumerated() {
            a["tiers[\(i)].name"] = t.name; a["tiers[\(i)].val"] = t.value; a["tiers[\(i)].displayName"] = t.displayName
        }
        return call("softDollarTiers", a)
    case .familyCodes(let codes):
        var a = ["familyCodes.#": canon(codes.count)]
        for (i, c) in codes.enumerated() {
            a["familyCodes[\(i)].accountID"] = c.accountID; a["familyCodes[\(i)].familyCodeStr"] = c.familyCodeStr
        }
        return call("familyCodes", a)
    case .symbolSamples(let reqId, let samples):
        var a = ["reqId": canon(reqId), "contractDescriptions.#": canon(samples.count)]
        for (i, s) in samples.enumerated() {
            let p = "contractDescriptions[\(i)]"
            a.merge(contractArgs(s.contract, prefix: "\(p).contract.")) { _, new in new }
            a["\(p).contract.strike"] = "0"  // 79's decoder never reads it (decoder.py:695-719): ib_async's default 0.0
            a["\(p).contract.description"] = s.description; a["\(p).contract.issuerId"] = s.issuerID
            a["\(p).derivativeSecTypes.#"] = canon(s.derivativeSecTypes.count)
            for (k, t) in s.derivativeSecTypes.enumerated() { a["\(p).derivativeSecTypes[\(k)]"] = t }
        }
        return call("symbolSamples", a)
    case .depthExchanges(let rows):
        var a = ["depthMktDataDescriptions.#": canon(rows.count)]
        for (i, r) in rows.enumerated() {
            let p = "depthMktDataDescriptions[\(i)]"
            a["\(p).exchange"] = r.exchange; a["\(p).secType"] = r.secType; a["\(p).listingExch"] = r.listingExchange
            a["\(p).serviceDataType"] = r.serviceDataType; a["\(p).aggGroup"] = canon(r.aggGroup)
        }
        return call("mktDepthExchanges", a)
    case .smartComponents(let reqId, let components):
        var a = ["reqId": canon(reqId), "components.#": canon(components.count)]
        for (i, c) in components.enumerated() {
            a["components[\(i)].bitNumber"] = canon(c.bitNumber); a["components[\(i)].exchange"] = c.exchange
            a["components[\(i)].exchangeLetter"] = c.exchangeLetter
        }
        return call("smartComponents", a)
    case .marketRule(let ruleId, let increments):
        var a = ["marketRuleId": canon(ruleId), "priceIncrements.#": canon(increments.count)]
        for (i, p) in increments.enumerated() {
            a["priceIncrements[\(i)].#"] = "2"; a["priceIncrements[\(i)][0]"] = canon(p.lowEdge)
            a["priceIncrements[\(i)][1]"] = canon(p.increment)
        }
        return call("marketRule", a)
    default: return nil
    }
}
