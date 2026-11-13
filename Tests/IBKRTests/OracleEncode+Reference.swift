import Foundation
import Testing
@testable import IBKR

/// The reference, scanner, news, research, FA, display-group and verify requests (out 9, 12, 13, 18, 19, 22-24, 52-57,
/// 65-70, 72, 73, 78-81, 84-86, 91, 100-103) from ib_async's `Client` arguments; `nil` for another family's method.
func referenceRequest(for c: EncodeCase) throws -> IBRequest? {
    var a = CaseArgs(c.args, c.name)
    let r: IBRequest
    switch c.method {
    case "reqContractDetails":
        r = .contractDetails(requestID: try a.int("reqId"), contract: try contract(from: a.value("contract")))
    case "reqMatchingSymbols": r = .matchingSymbols(requestID: try a.int("reqId"), pattern: try a.text("pattern"))
    case "reqSecDefOptParams":
        r = .secDefOptParams(requestID: try a.int("reqId"), underlyingSymbol: try a.text("underlyingSymbol"),
                             futFopExchange: try a.text("futFopExchange"),
                             underlyingSecType: try a.text("underlyingSecType"),
                             underlyingConID: try a.int("underlyingConId"))
    case "calculateImpliedVolatility":
        r = .calculateImpliedVolatility(requestID: try a.int("reqId"), contract: try contract(from: a.value("contract")),
                                        optionPrice: try a.decimal("optionPrice"), underPrice: try a.decimal("underPrice"),
                                        options: try a.tagValues("implVolOptions"))
    case "calculateOptionPrice":
        r = .calculateOptionPrice(requestID: try a.int("reqId"), contract: try contract(from: a.value("contract")),
                                  volatility: try a.decimal("volatility"), underPrice: try a.decimal("underPrice"),
                                  options: try a.tagValues("optPrcOptions"))
    case "cancelCalculateImpliedVolatility": r = .cancelCalculateImpliedVolatility(requestID: try a.int("reqId"))
    case "cancelCalculateOptionPrice": r = .cancelCalculateOptionPrice(requestID: try a.int("reqId"))
    case "reqMarketRule": r = .marketRule(marketRuleID: try a.int("marketRuleId"))
    case "reqFamilyCodes": r = .familyCodes
    case "reqSoftDollarTiers": r = .softDollarTiers(requestID: try a.int("reqId"))
    case "reqScannerSubscription":
        let reqID = try a.int("reqId")
        let sub = try scannerSubscription(a.value("subscription"), c.name)
        // the two lists are read by name; the wire order (filter options first, client.py:871-872) is the encoder's
        r = .scannerSubscription(requestID: reqID, subscription: sub,
                                 options: try a.tagValues("scannerSubscriptionOptions"),
                                 filterOptions: try a.tagValues("scannerSubscriptionFilterOptions"))
    case "cancelScannerSubscription": r = .cancelScannerSubscription(requestID: try a.int("reqId"))
    case "reqScannerParameters": r = .scannerParameters
    case "reqNewsProviders": r = .newsProviders
    case "reqNewsBulletins": r = .newsBulletins(allMessages: try a.bool("allMsgs"))
    case "cancelNewsBulletins": r = .cancelNewsBulletins
    case "reqNewsArticle":
        r = .newsArticle(requestID: try a.int("reqId"), providerCode: try a.text("providerCode"),
                         articleID: try a.text("articleId"), options: try a.tagValues("newsArticleOptions"))
    case "reqHistoricalNews":
        let reqID = try a.int("reqId"), conID = try a.int("conId"), codes = try a.text("providerCodes")
        let start = try dateText(&a, "startDateTime", c), end = try dateText(&a, "endDateTime", c)
        // ib.py passes the codes as one `+`-joined string; swift-ibkr joins a list
        let providers = codes.isEmpty ? [] : codes.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        r = .historicalNews(requestID: reqID, conID: conID, providerCodes: providers, start: start, end: end,
                            totalResults: try a.int("totalResults"), options: try a.tagValues("historicalNewsOptions"))
    case "reqFundamentalData":
        r = .fundamentalData(requestID: try a.int("reqId"), contract: try contract(from: a.value("contract")),
                             reportType: try a.text("reportType"), options: try a.tagValues("fundamentalDataOptions"))
    case "cancelFundamentalData": r = .cancelFundamentalData(requestID: try a.int("reqId"))
    case "reqWshMetaData": r = .wshMetaData(requestID: try a.int("reqId"))
    case "cancelWshMetaData": r = .cancelWshMetaData(requestID: try a.int("reqId"))
    case "reqWshEventData":
        let reqID = try a.int("reqId")
        var d = try CaseArgs(a.value("data"), type: "WshEventData", "\(c.name).data")
        // ib_async's unset conId and totalLimit are 2147483647, which swift-ibkr's nil sends (makeEmpty=False)
        let event = WshEventData(conID: try d.optionalInt("conId"), filter: try d.text("filter"),
                                 fillWatchlist: try d.bool("fillWatchlist"), fillPortfolio: try d.bool("fillPortfolio"),
                                 fillCompetitors: try d.bool("fillCompetitors"), startDate: try d.text("startDate"),
                                 endDate: try d.text("endDate"), totalLimit: try d.optionalInt("totalLimit"))
        try d.done()
        r = .wshEventData(requestID: reqID, data: event)
    case "cancelWshEventData": r = .cancelWshEventData(requestID: try a.int("reqId"))
    case "requestFA": r = .requestFA(try faType(&a, c))
    case "replaceFA": r = .replaceFA(requestID: try a.int("reqId"), type: try faType(&a, c), xml: try a.text("cxml"))
    case "queryDisplayGroups": r = .queryDisplayGroups(requestID: try a.int("reqId"))
    case "subscribeToGroupEvents":
        r = .subscribeToGroupEvents(requestID: try a.int("reqId"), groupID: try a.int("groupId"))
    case "updateDisplayGroup":
        r = .updateDisplayGroup(requestID: try a.int("reqId"), contractInfo: try a.text("contractInfo"))
    case "unsubscribeFromGroupEvents": r = .unsubscribeFromGroupEvents(requestID: try a.int("reqId"))
    case "verifyRequest": r = .verifyRequest(apiName: try a.text("apiName"), apiVersion: try a.text("apiVersion"))
    case "verifyMessage": r = .verifyMessage(apiData: try a.text("apiData"))
    case "verifyAndAuthRequest":
        r = .verifyAndAuthRequest(apiName: try a.text("apiName"), apiVersion: try a.text("apiVersion"),
                                  opaqueISVKey: try a.text("opaqueIsvKey"))
    case "verifyAndAuthMessage":
        r = .verifyAndAuthMessage(apiData: try a.text("apiData"), xyzResponse: try a.text("xyzResponse"))
    default: return nil
    }
    try a.done()
    return r
}

private func faType(_ a: inout CaseArgs, _ c: EncodeCase) throws -> FADataType {
    let n = try a.int("faData")
    guard let type = FADataType(rawValue: n) else { throw CaseError("\(c.name): faData \(n) is not 1, 2 or 3") }
    return type
}

/// An ib_async `ScannerSubscription`: every attribute is read; its unset values (`-1` rows, unset float and int) are
/// swift-ibkr's `nil`, which goes out as `-1` and as an empty field.
private func scannerSubscription(_ v: CaseValue, _ context: String) throws -> ScannerSubscription {
    var a = try CaseArgs(v, type: "ScannerSubscription", "\(context).subscription")
    let rows = try a.int("numberOfRows")
    let s = ScannerSubscription(
        instrument: try a.text("instrument"), locationCode: try a.text("locationCode"), scanCode: try a.text("scanCode"),
        numberOfRows: rows == -1 ? nil : rows, abovePrice: try a.optionalDecimal("abovePrice"),
        belowPrice: try a.optionalDecimal("belowPrice"), aboveVolume: try a.optionalInt("aboveVolume"),
        marketCapAbove: try a.optionalDecimal("marketCapAbove"), marketCapBelow: try a.optionalDecimal("marketCapBelow"),
        moodyRatingAbove: try a.text("moodyRatingAbove"), moodyRatingBelow: try a.text("moodyRatingBelow"),
        spRatingAbove: try a.text("spRatingAbove"), spRatingBelow: try a.text("spRatingBelow"),
        maturityDateAbove: try a.text("maturityDateAbove"), maturityDateBelow: try a.text("maturityDateBelow"),
        couponRateAbove: try a.optionalDecimal("couponRateAbove"),
        couponRateBelow: try a.optionalDecimal("couponRateBelow"), excludeConvertible: try a.bool("excludeConvertible"),
        averageOptionVolumeAbove: try a.optionalInt("averageOptionVolumeAbove"),
        scannerSettingPairs: try a.text("scannerSettingPairs"), stockTypeFilter: try a.text("stockTypeFilter"))
    try a.done()
    return s
}
