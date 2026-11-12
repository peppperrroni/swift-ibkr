import Foundation
import Testing
@testable import IBKR

/// A two-row scannerData (20) frame under reqId `id`: AAPL at rank 0, MSFT at rank 1.
func scan(_ id: String) -> [String] {
    ["20", "3", id, "2",
     "0", "265598", "AAPL", "STK", "", "0", "", "SMART", "USD", "AAPL", "NMS", "NMS", "", "", "", "",
     "1", "272093", "MSFT", "STK", "", "0", "", "SMART", "USD", "MSFT", "NMS", "NMS", "", "", "", ""]
}

@Suite struct ResearchCodecTests {
    @Test func scannerSubscriptionEncodes() throws {
        #expect(try IBRequest.scannerSubscription(requestID: 7, subscription: ScannerSubscription(), options: [],
                                                  filterOptions: []).body()
            == body(["22", "7", "-1"] + Array(repeating: "", count: 16) + ["0"] + Array(repeating: "", count: 5)))
        let top = ScannerSubscription(instrument: "STK", locationCode: "STK.US.MAJOR", scanCode: "TOP_PERC_GAIN",
                                      numberOfRows: 10, abovePrice: d("5"), aboveVolume: 100000)
        #expect(try IBRequest.scannerSubscription(requestID: 7, subscription: top, options: [],
                                                  filterOptions: [TagValue(tag: "marketCapAbove1e6", value: "1000")]).body()
            == body(["22", "7", "10", "STK", "STK.US.MAJOR", "TOP_PERC_GAIN", "5", "", "100000"]
                    + Array(repeating: "", count: 10) + ["0", "", "", "", "marketCapAbove1e6=1000;", ""]))
    }

    @Test func scannerSmallMessagesCodec() throws {
        #expect(try IBRequest.cancelScannerSubscription(requestID: 7).body() == body("23", "1", "7"))
        #expect(try IBRequest.scannerParameters.body() == body("24", "1"))
        #expect(IBDecoder.decode(body("19", "1", "<ScanParameterResponse/>")) == .scannerParameters("<ScanParameterResponse/>"))
    }

    @Test func scannerDataDecodes() throws {
        func row(_ rank: Int, _ symbol: String, _ conID: Int) -> ScanData {
            var c = Contract(symbol: symbol)
            c.conID = conID; c.strike = 0; c.localSymbol = symbol; c.tradingClass = "NMS"
            return ScanData(rank: rank, contract: c, marketName: "NMS", distance: "", benchmark: "", projection: "",
                            legsStr: "")
        }
        #expect(IBDecoder.decode(body(scan("7"))) == .scannerData(requestID: 7, [row(0, "AAPL", 265598), row(1, "MSFT", 272093)]))
        guard case .malformed = IBDecoder.decode(body("20", "3", "7", "-1")) else { Issue.record("not malformed"); return }
    }

    @Test func newsLookupsCodec() throws {
        #expect(try IBRequest.newsProviders.body() == body("85"))
        #expect(try IBRequest.newsArticle(requestID: 7, providerCode: "BRFG", articleID: "BRFG$12345", options: []).body()
                == body("84", "7", "BRFG", "BRFG$12345", ""))
        // ib_async's text date, `yyyyMMdd HH:mm:ss UTC`, not the `-` form history uses
        #expect(try IBRequest.historicalNews(requestID: 7, conID: 265598, providerCodes: ["BRFG", "DJNL"],
                                             start: Date(timeIntervalSince1970: 1794321000), end: nil, totalResults: 10,
                                             options: []).body()
                == body("86", "7", "265598", "BRFG+DJNL", "20261110 14:30:00 UTC", "", "10", ""))
        #expect(IBDecoder.decode(body("85", "2", "BRFG", "Briefing.com General Market Columns", "DJNL", "Dow Jones Newsletters"))
                == .newsProviders([NewsProvider(code: "BRFG", name: "Briefing.com General Market Columns"),
                                   NewsProvider(code: "DJNL", name: "Dow Jones Newsletters")]))
        #expect(IBDecoder.decode(body("83", "7", "0", "Apple beats estimates"))
                == .newsArticle(requestID: 7, NewsArticle(articleType: 0, articleText: "Apple beats estimates")))
        #expect(IBDecoder.decode(body("86", "7", "2026-11-10 14:30:00.0", "BRFG", "BRFG$12345", "Apple headline"))
                == .historicalNews(requestID: 7, HistoricalNews(time: "2026-11-10 14:30:00.0", providerCode: "BRFG",
                                                                articleID: "BRFG$12345", headline: "Apple headline")))
        #expect(IBDecoder.decode(body("87", "7", "1")) == .historicalNewsEnd(requestID: 7, hasMore: true))
        guard case .malformed = IBDecoder.decode(body("85", "-1")) else { Issue.record("not malformed"); return }
    }

    @Test func newsBulletinsCodec() throws {
        #expect(try IBRequest.newsBulletins(allMessages: true).body() == body("12", "1", "1"))
        #expect(try IBRequest.cancelNewsBulletins.body() == body("13", "1"))
        #expect(IBDecoder.decode(body("14", "1", "3", "1", "Exchange halted", "NYSE"))
                == .newsBulletin(NewsBulletin(msgID: 3, msgType: 1, message: "Exchange halted", origExchange: "NYSE")))
    }
}
