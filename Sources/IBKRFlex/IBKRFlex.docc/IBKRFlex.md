# ``IBKRFlex``

Download Interactive Brokers Flex reports and read them as records.

## Overview

`IBKRFlex` is a separate product with `import IBKRFlex`. It needs only Foundation, does not depend on `IBKR`, and is
Swift Package Manager only. The token and the query id come from Client Portal: Settings, Flex Web Service gives the
token, and each Flex query shows its id.

## Usage

``FlexReport/download(token:queryID:url:pollInterval:transport:)`` polls until IB has the report ready; cancel the
task to stop the polling. ``FlexReport/init(data:)`` loads a saved report, ``FlexReport/topics`` lists every tag that
has attributes, and ``FlexReport/extract(_:)`` returns the records of one tag. Records keep IB's strings, with dates
in the format the query sets; ``FlexRecord/decimal(_:)`` is `nil` for anything that is not entirely a number.

```swift
import IBKRFlex

let report = try await FlexReport.download(token: token, queryID: "123456")   // polls until IB has it ready
for trade in report.extract("Trade") {
    print(trade["symbol"] ?? "", trade["tradeDate"] ?? "", trade.decimal("quantity") ?? 0, trade.decimal("tradePrice") ?? 0)
}
try report.data.write(to: URL(fileURLWithPath: "trades.xml"))                      // save
let saved = try FlexReport(data: Data(contentsOf: URL(fileURLWithPath: "trades.xml")))  // load
```

## Topics

### Reports
- ``FlexReport``
- ``FlexRecord``
- ``FlexError``
- ``FlexTransport``
