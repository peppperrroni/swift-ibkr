import Foundation

extension IBClient {
    /// The latest `Ticker` of an open `tickers(_:…)` stream for `contract`, matched as `ib_async`'s `Contract.__eq__`
    /// matches (contract.py:154-159): by `conID` when both carry the same non-zero one, else field by field. `nil`
    /// when none is open; with two open for one contract, the older one's.
    public func ticker(for contract: Contract) -> Ticker? {
        tickerRegistry.sorted { $0.key < $1.key }.first {
            (contract.conID != 0 && contract.conID == $0.value.contract.conID) || contract == $0.value.contract
        }?.value
    }

    /// The latest `Ticker` of every open `tickers(_:…)` stream, oldest stream first (`ib_async`'s `tickers()`). A
    /// stream is listed from its call, with an empty ticker, until it ends, however it ends.
    public func activeTickers() -> [Ticker] {
        tickerRegistry.sorted { $0.key < $1.key }.map(\.value)
    }

    /// A fresh stream on every call, of the ticker each `tickers(_:…)` fold step changed, as `[ticker]`, from now on
    /// (`ib_async`'s `pendingTickersEvent`, per update rather than per packet). Unbounded, like `messages()`.
    public func pendingTickers() -> AsyncStream<[Ticker]> {
        pendingTickerSubscribers.stream { [weak self] id in Task { await self?.unsubscribe(pendingTickers: id) } }
    }

    /// The latest value of each open `pnl` stream, oldest first, filtered by `account` and `modelCode` where they
    /// are not empty (`ib_async`'s `pnl()`, ib.py:554-570). A stream is listed once its first value arrives.
    public func pnlValues(account: String = "", modelCode: String = "") -> [AccountPnL] {
        accountPnLs.sorted { $0.key < $1.key }.map(\.value).filter {
            (account.isEmpty || $0.account == account) && (modelCode.isEmpty || $0.modelCode == modelCode)
        }
    }

    /// The latest value of each open `pnlSingle` stream, oldest first, filtered by `account`, `modelCode` and `conID`
    /// where they are not empty or `nil` (`ib_async`'s `pnlSingle()`, ib.py:572-590). A stream is listed once its
    /// first value arrives.
    public func pnlSingleValues(account: String = "", modelCode: String = "", conID: Int? = nil) -> [PnL] {
        positionPnLs.sorted { $0.key < $1.key }.map(\.value).filter {
            (account.isEmpty || $0.account == account) && (modelCode.isEmpty || $0.modelCode == modelCode)
                && (conID == nil || $0.conID == conID)
        }
    }

    /// Every news tick (`Tick.news`) received on any request since the last manual `connect`, and a fresh stream of
    /// each one from now on, taken together so none falls between them (`ib_async`'s `newsTicks()`). The snapshot
    /// grows for the whole session, as in `ib_async`; a reconnect keeps it.
    public func newsTicks() -> (snapshot: [NewsTick], updates: AsyncStream<NewsTick>) {
        (newsTickLog, newsTickSubscribers.stream { [weak self] id in Task { await self?.unsubscribe(newsTick: id) } })
    }

    /// Every news bulletin received since the last manual `connect`, one per `msgID` (the last received wins), in
    /// the order each id was first seen (`ib_async`'s `newsBulletins()`). A reconnect keeps them.
    public func receivedBulletins() -> [NewsBulletin] { bulletins }

    /// Keeps the ticker of `tickers` stream `key` and publishes it on `pendingTickers()`; `nil` is the stream's end.
    /// A step that comes after the entry went (the connection ended) is dropped.
    func recordTicker(_ key: Int, _ ticker: Ticker?) {
        guard tickerRegistry[key] != nil else { return }
        tickerRegistry[key] = ticker
        if let ticker { pendingTickerSubscribers.yield([ticker]) }
    }

    /// Collects news ticks and bulletins from every message, whoever asked for them.
    func recordNews(_ message: IBMessage) {
        switch message {
        case .tick(_, .news(let tick)):
            newsTickLog.append(tick)
            newsTickSubscribers.yield(tick)
        case .newsBulletin(let b):
            if let i = bulletins.firstIndex(where: { $0.msgID == b.msgID }) { bulletins[i] = b } else { bulletins.append(b) }
        default: break
        }
    }

    /// Forgets request `id` in every per-request registry: its stream ended.
    func dropSubscription(_ id: Int) {
        (liveBars[id], accountPnLs[id], positionPnLs[id]) = (nil, nil, nil)
    }

    func unsubscribe(pendingTickers id: Int) { pendingTickerSubscribers.remove(id) }
    func unsubscribe(newsTick id: Int) { newsTickSubscribers.remove(id) }
}
