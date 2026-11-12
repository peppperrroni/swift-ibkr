import Foundation
import Testing
import IBKRFlex

/// A hand-built Flex report: an account line, two trades, two containers without attributes.
let flexReportXML = """
<?xml version="1.0" encoding="UTF-8"?>
<FlexQueryResponse queryName="Trades" type="AF">
<FlexStatements count="1">
<FlexStatement accountId="DU0000001" fromDate="20261102" toDate="20261106" period="LastWeek" whenGenerated="20261107;101500">
<AccountInformation accountId="DU0000001" currency="USD" name="" />
<Trades>
<Trade accountId="DU0000001" symbol="T" description="AT&amp;T INC" quantity="10" tradePrice="22.75" ibCommission="-1" tradeDate="20261103" />
<Trade accountId="DU0000001" symbol="MSFT" description="MICROSOFT CORP" quantity="-5" tradePrice="410.25" ibCommission="-1.0025" tradeDate="20261104" />
</Trades>
<CashTransactions />
</FlexStatement>
</FlexStatements>
</FlexQueryResponse>
"""

@Suite struct FlexReportTests {
    let report = try! FlexReport(data: Data(flexReportXML.utf8))

    @Test func topicsAreTagsWithAttributesAtAnyDepth() {
        #expect(report.topics == ["FlexQueryResponse", "FlexStatements", "FlexStatement", "AccountInformation", "Trade"])
        #expect(report.data == Data(flexReportXML.utf8))
    }

    @Test func extractReturnsEveryElementInDocumentOrder() {
        let trades = report.extract("Trade")
        #expect(trades.map { $0["symbol"] } == ["T", "MSFT"])
        #expect(trades[0] == FlexRecord(topic: "Trade", attributes: [
            "accountId": "DU0000001", "symbol": "T", "description": "AT&T INC", "quantity": "10",
            "tradePrice": "22.75", "ibCommission": "-1", "tradeDate": "20261103",
        ]))
        #expect(report.extract("Trades") == [FlexRecord(topic: "Trades", attributes: [:])])
        #expect(report.extract("Order") == [])
    }

    @Test func attributesStayStringsAndEmptyIsKept() {
        let account = report.extract("AccountInformation")[0]
        #expect(account["name"] == "")
        #expect(account["missing"] == nil)
        #expect(account.decimal("name") == nil)
        #expect(account.decimal("missing") == nil)
        #expect(report.extract("Trade")[0]["tradeDate"] == "20261103")
    }

    @Test func decimalReadsOnlyWholeNumbers() {
        let trades = report.extract("Trade")
        #expect(trades[0].decimal("tradePrice") == Decimal(string: "22.75"))
        #expect(trades[1].decimal("quantity") == Decimal(-5))
        #expect(trades[1].decimal("ibCommission") == Decimal(string: "-1.0025"))
        let odd = FlexRecord(topic: "X", attributes: [
            "exponent": "1E-4", "junk": "12abc", "space": " 5", "thousands": "1,000", "word": "abc", "dot": "1.",
            "minus": "-", "arabicDigits": "\u{0661}\u{0662}", "hugeExponent": "1E999999",
        ])
        #expect(odd.decimal("exponent") == Decimal(string: "0.0001"))
        for key in ["junk", "space", "thousands", "word", "dot", "minus", "arabicDigits", "hugeExponent"] { #expect(odd.decimal(key) == nil, "\(key)") }
    }

    @Test func malformedXMLThrows() {
        for xml in ["<a><b></a>", "", "not xml", "<FlexQueryResponse>", "<a><b/>", "<a x=\"1\"><b>"] {
            do { _ = try FlexReport(data: Data(xml.utf8)); Issue.record("parsed \(xml)") }
            catch FlexError.malformedXML {}
            catch { Issue.record("\(error)") }
        }
    }
}
