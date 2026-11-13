# ``IBKR``

A pure-Swift client for Interactive Brokers' IB Gateway and TWS, speaking the TWS API socket protocol directly.

## Overview

``IBClient`` is one actor per connection. Account state (orders, fills, positions, portfolio, account values) is
synced at connect and offered as a snapshot plus a stream of changes; every other request is either a one-shot
`async throws` call or a stream whose end sends IB's cancel. Errors are typed (``IBClientError``), money is
`Decimal`, and the wire protocol is pinned to server version 178.

> Important: Not affiliated with Interactive Brokers. Pointed at a live account the library places real orders; try
> everything on a paper account first.

## Topics

### Essentials
- <doc:GettingStarted>
- ``IBClient``
- ``ConnectionState``
- ``ReconnectPolicy``
- ``ConnectOptions``
- ``StartupFetch``
- ``ConnectionStats``
- ``IBLogLevel``
- ``IBLogHandler``
- ``IBClientError``

### Contracts
- ``Contract``
- ``ContractDetails``
- ``ContractDescription``
- ``ContractQualification``
- ``ComboLeg``
- ``DeltaNeutralContract``

### Placing orders
- <doc:Orders>
- ``Order``
- ``OrderAction``
- ``BracketOrder``
- ``OrderCondition``
- ``TagValue``
- ``OrderSnapshot``
- ``OrderStatus``
- ``OrderState``
- ``ExerciseAction``

### Executions, positions and account
- ``Fill``
- ``Execution``
- ``CommissionReport``
- ``ExecutionFilter``
- ``Position``
- ``PortfolioItem``
- ``AccountValue``
- ``AccountPnL``
- ``PnL``

### Market data
- <doc:MarketData>
- ``Tick``
- ``Ticker``
- ``TickField``
- ``GenericTick``
- ``MarketDataType``
- ``OptionComputation``
- ``DepthBook``
- ``TickByTick``
- ``TickByTickType``

### History
- ``Bar``
- ``BarEvent``
- ``LiveBars``
- ``HistoricalSchedule``
- ``HistoricalSession``
- ``HistogramData``

### Options and reference data
- ``OptionChain``
- ``PriceIncrement``
- ``FamilyCode``
- ``SoftDollarTier``

### Scanner, news and research
- ``ScannerSubscription``
- ``ScanData``
- ``NewsProvider``
- ``NewsArticle``
- ``HistoricalNews``
- ``NewsBulletin``
- ``WshEventData``
- ``FADataType``
- ``ServerLogLevel``

### State trackers
- ``OrderTracker``
- ``ExecutionTracker``
- ``PositionTracker``

### Wire protocol
- ``IBRequest``
- ``IBMessage``
- ``IBErrorMessage``
- ``ErrorCode``
- ``ErrorKind``
- ``IBDecoder``
- ``Handshake``
- ``IBProtocolError``
- ``IBEncodingError``

### Coming from ib_async
- <doc:MigratingFromIbAsync>
