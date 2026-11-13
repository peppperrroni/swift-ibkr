import Foundation
import Testing
@testable import IBKR

/// One order as the broker booked it from a placeOrder frame.
struct SimOrder {
    var clientID, orderID, permID: Int
    var contract: Contract
    var action: OrderAction
    var quantity: Decimal
    var orderType: String
    var limitPrice: Decimal?
    var parentID: Int
    var transmit: Bool
    var ocaGroup: String
    var whatIf: Bool
    var status: OrderStatus
    var filled: Decimal
}

/// A stateful simulated broker over `FakeGateway` (composed, never forked): one wired gateway per connect, and one
/// book of orders, fills and positions shared by every client. Order, fill and commission sequences copy
/// Recorded/liveLimitOrderPlacesAndCancels.json and liveOrderFillsWithCommission.json; times, permIDs and execIds
/// come from counters, so a scenario emits the same frames on every run.
// @unchecked Sendable: every mutable member sits behind `lock`.
final class SimulatedBroker: @unchecked Sendable {
    private struct Session { var clientID: Int?; var positions = false; var account: String? }
    private struct Holding { var quantity: Decimal = 0; var averageCost: Decimal = 0; var realized: Decimal = 0 }
    private struct HoldingKey: Hashable, Comparable {
        var account: String, conID: Int
        static func < (a: Self, b: Self) -> Bool { (a.account, a.conID) < (b.account, b.conID) }
    }
    private struct SimFill { var order: Int; var price, amount, fee: Decimal; var execution, report: [String] }

    private static let unset = "1.7976931348623157E308"
    private static let noContract = Array(repeating: "", count: 12)

    private let lock = NSLock()
    private let accounts: [String], nextOrderID: Int
    private var clock: Int
    private var _gateways: [FakeGateway] = []
    private var sessions: [Session] = []   // per gateway
    private var orders: [SimOrder] = []
    private var orderAccounts: [String] = []   // per order: placeOrder's account, else the first managed one
    private var contractBlocks: [Int: [String]] = [:]   // conID → placeOrder fields 2–13, echoed back as sent
    private var fills: [SimFill] = []
    private var holdings: [HoldingKey: Holding] = [:]
    private var marketPrices: [Int: Decimal] = [:]
    private var permIDs = 0, execIDs = 0

    init(accounts: [String] = ["DU0000001"], nextOrderID: Int = 1, clock: Int = 1794321000) {
        (self.accounts, self.nextOrderID, self.clock) = (accounts, nextOrderID, clock)
    }

    /// Hands out a new wired gateway per connect.
    var connector: Connector {
        { [weak self] _, _, _ in
            guard let self else { throw IBClientError.transport("no broker") }
            return self.newGateway()
        }
    }

    /// A new gateway wired to the book, as `connector` hands out; a loopback bridge takes one directly.
    func newGateway() -> FakeGateway {
        let gateway = FakeGateway(nextValidID: nextOrderID, accounts: accounts.joined(separator: ","))
        let i = lock.withLock { () -> Int in
            _gateways.append(gateway)
            sessions.append(Session())
            return _gateways.count - 1
        }
        gateway.onRequest = { [weak self] in self?.answer($0, session: i) ?? [] }
        return gateway
    }

    var gateways: [FakeGateway] { lock.withLock { _gateways } }

    /// Every gateway's `fed`, in hand-out order.
    var emitted: [[String]] { gateways.flatMap(\.fed) }

    func order(clientID: Int, orderID: Int) -> SimOrder? {
        lock.withLock { orders.first { $0.clientID == clientID && $0.orderID == orderID } }
    }

    func position(account: String, conID: Int) -> (quantity: Decimal, averageCost: Decimal) {
        lock.withLock {
            let h = holdings[HoldingKey(account: account, conID: conID)] ?? Holding()
            return (h.quantity, h.averageCost)
        }
    }

    /// The price the portfolio (7) values a contract at, fed at once to every client subscribed to an account that
    /// holds it; until set, the contract's last fill price.
    // assumption: unrecorded live — IB's portfolio updates follow the market on its own schedule
    func setMarketPrice(conID: Int, _ price: Decimal) {
        lock.withLock {
            marketPrices[conID] = price
            for key in holdings.keys.sorted() where key.conID == conID {
                for i in sessions.indices where sessions[i].account == key.account && !_gateways[i].isClosed {
                    _gateways[i].feed(portfolioFrame(key))
                }
            }
        }
    }

    /// Executes `shares` of the order at `price`, as liveOrderFillsWithCommission.json: position, execDetails,
    /// openOrder + orderStatus (twice when filled, the second with the commission), commission report, the
    /// position after commission. Order events go to the owning client only, positions to every client that asked for
    /// them, the portfolio to every client subscribed to the account.
    // assumption: unrecorded live — a part fill: openOrder + orderStatus stay Submitted with filled and remaining
    func fill(orderID: Int, clientID: Int, shares: Decimal, price: Decimal, commission: Decimal = 1) {
        lock.withLock {
            guard let n = orders.firstIndex(where: { $0.clientID == clientID && $0.orderID == orderID }) else {
                Issue.record("SimulatedBroker.fill: no order \(orderID) of client \(clientID)")
                return
            }
            orders[n].filled += shares
            orders[n].status = orders[n].filled >= orders[n].quantity ? .filled : .submitted
            let o = orders[n]
            let key = HoldingKey(account: orderAccounts[n], conID: o.contract.conID)
            let signed = o.action == .buy ? shares : -shares
            var h = holdings[key] ?? Holding()
            let pnl = Self.trade(&h, signed, at: price)
            holdings[key] = h
            let before = positionFrame(key)
            var realized: Decimal?
            if let pnl {
                realized = Self.round(pnl - commission)
                h.realized += realized ?? 0
            } else {   // IB counts an opening trade's commission into the average cost
                h.averageCost = Self.round(h.averageCost + (signed > 0 ? commission : -commission) / abs(h.quantity))
            }
            holdings[key] = h

            execIDs += 1
            let execID = String(format: "0000e0d5.%08x.01.01", execIDs)
            let time = Self.format(clock, "yyyyMMdd-HH:mm:ss")
            clock += 1
            let amount = shares * price
            let average = Self.round((fills.filter { $0.order == n }.map(\.amount).reduce(0, +) + amount) / o.filled)
            let b = contractBlocks[o.contract.conID] ?? Self.noContract
            let execution = ["11", "-1", "\(o.orderID)"] + b[0..<7] + ["IBKRATS"] + b[9..<12]
                + [execID, time, key.account, "IBKRATS", o.action == .buy ? "BOT" : "SLD", "\(shares)", "\(price)",
                   "\(o.permID)", "\(o.clientID)", "0", "\(o.filled)", "\(average)", "", "", "", "", "2", "0"]
            let report = ["59", "1", execID, "\(commission)", "USD", realized.map { "\($0)" } ?? Self.unset,
                          Self.unset, ""]
            fills.append(SimFill(order: n, price: price, amount: amount, fee: commission, execution: execution,
                                 report: report))

            var events = [execution] + openAndStatus(n)
            if o.status == .filled {
                events += openAndStatus(n, commission: fills.filter { $0.order == n }.map(\.fee).reduce(0, +))
            }
            events.append(report)
            for i in sessions.indices where !_gateways[i].isClosed {
                let s = sessions[i]
                var frames: [[String]] = s.positions ? [before] : []
                if s.clientID == o.clientID { frames += events }
                if s.positions { frames.append(positionFrame(key)) }
                if s.account == key.account { frames.append(portfolioFrame(key)) }
                frames.forEach(_gateways[i].feed)
            }
        }
    }

    // MARK: - Requests

    /// The replies to one request from session `i`, fed before `FakeGateway`'s own end markers. Runs in the client's
    /// write path: it never blocks and never calls back into the client.
    private func answer(_ f: [String], session i: Int) -> [[String]] {
        lock.withLock {
            switch f.first {
            case "71": sessions[i].clientID = Int(f[2])
            case "3": return place(f, session: i)
            case "16":   // assumption: unrecorded live — every client's working orders, openOrder + orderStatus each
                return orders.indices.filter { !orders[$0].status.isFinal }.flatMap { openAndStatus($0) }
            case "99":   // assumption: unrecorded live — completedOrder per final order
                return orders.indices.filter { orders[$0].status.isFinal }.map(completedFrame)
            case "7":   // as recorded: every execDetails under the request's id, then the commission reports
                // assumption: unrecorded live — the replay keeps the live fill's UTC time form
                return fills.map { replacing($0.execution, [1: f[2]]) } + fills.map(\.report)
            case "61":
                sessions[i].positions = true
                return holdings.keys.sorted().map(positionFrame)
            case "64": sessions[i].positions = false
            case "6" where f[2] == "1":   // assumption: unrecorded live — AccountCode, the portfolio, the time
                sessions[i].account = f[3]
                return [["6", "2", "AccountCode", f[3], "", f[3]]]
                    + holdings.keys.filter { $0.account == f[3] }.sorted().map(portfolioFrame)
                    + [["8", "1", Self.format(clock, "HH:mm")]]
            case "6": sessions[i].account = nil
            default: break
            }
            return []
        }
    }

    /// Books a base-case placeOrder (docs/protocol-178.md's placeOrder indices) and answers as
    /// liveOrderFillsWithCommission.json: openOrder + PreSubmitted, openOrder + Submitted.
    private func place(_ f: [String], session i: Int) -> [[String]] {
        guard f.count == 114 else {
            Issue.record("SimulatedBroker: placeOrder with \(f.count) fields, not the base case's 114; not booked")
            return []
        }
        var contract = Contract(symbol: f[3], secType: f[4], exchange: f[9], currency: f[11], primaryExchange: f[10])
        contract.conID = Int(f[2]) ?? 0
        contractBlocks[contract.conID] = Array(f[2...13])
        let clientID = sessions[i].clientID ?? 0, orderID = Int(f[1]) ?? 0
        var order = SimOrder(
            clientID: clientID, orderID: orderID, permID: 0, contract: contract,
            action: OrderAction(rawValue: f[16]) ?? .buy, quantity: Decimal(string: f[17]) ?? 0, orderType: f[18],
            limitPrice: Decimal(string: f[19]), parentID: Int(f[28]) ?? 0, transmit: f[27] == "1", ocaGroup: f[22],
            whatIf: f[84] == "1", status: .preSubmitted, filled: 0)
        let account = f[23].isEmpty ? accounts[0] : f[23]
        if let n = orders.firstIndex(where: { $0.clientID == clientID && $0.orderID == orderID }) {
            // a re-send of a known id: new terms, same permID, status and fills
            (order.permID, order.status, order.filled) = (orders[n].permID, orders[n].status, orders[n].filled)
            (orders[n], orderAccounts[n]) = (order, account)
            return openAndStatus(n)
        }
        permIDs += 1
        order.permID = 1_000_000_000 + permIDs
        orders.append(order)
        orderAccounts.append(account)
        let n = orders.count - 1
        let preSubmitted = openAndStatus(n)
        orders[n].status = .submitted
        return preSubmitted + openAndStatus(n)
    }

    // MARK: - Frames

    /// openOrder (Fixtures.openOrderFields with the book's contract id, OCA group and account) and orderStatus.
    private func openAndStatus(_ n: Int, commission: Decimal? = nil) -> [[String]] {
        let o = orders[n]
        var open = Fixtures.openOrderFields(
            orderID: o.orderID, permID: o.permID, clientID: o.clientID, symbol: o.contract.symbol,
            action: o.action.rawValue, quantity: "\(o.quantity)", orderType: o.orderType,
            limitPrice: o.limitPrice.map { "\($0)" } ?? Self.unset, auxPrice: Self.unset, tif: "DAY",
            parentID: "\(o.parentID)", outsideRTH: "0", orderRef: "", status: o.status.rawValue)
        open = replacing(open, [2: "\(o.contract.conID)", 19: o.ocaGroup, 20: orderAccounts[n]])
        if let commission { open = replacing(open, [95: "\(commission)", 98: "USD"]) }
        let own = fills.filter { $0.order == n }
        let average = o.filled == 0 ? 0 : Self.round(own.map(\.amount).reduce(0, +) / o.filled)
        let status = ["3", "\(o.orderID)", o.status.rawValue, "\(o.filled)", "\(o.quantity - o.filled)", "\(average)",
                      "\(o.permID)", "\(o.parentID)", "\(own.last?.price ?? 0)", "\(o.clientID)", "", "0"]
        return [open, status]
    }

    /// completedOrder (Fixtures.completedOrderFields with the book's contract id and account).
    private func completedFrame(_ n: Int) -> [String] {
        let o = orders[n]
        let f = Fixtures.completedOrderFields(
            orderID: o.orderID, permID: o.permID, clientID: o.clientID, symbol: o.contract.symbol,
            action: o.action.rawValue, quantity: "\(o.quantity)", orderType: o.orderType,
            limitPrice: o.limitPrice.map { "\($0)" } ?? Self.unset, auxPrice: Self.unset, tif: "DAY",
            parentID: "\(o.parentID)", outsideRTH: "0", orderRef: "", status: o.status.rawValue,
            completedTime: fills.last { $0.order == n }?.execution[15] ?? "",
            completedStatus: o.status == .filled ? "Filled Size: \(o.filled)" : o.status.rawValue,
            filledQuantity: "\(o.filled)")
        return replacing(f, [1: "\(o.contract.conID)", 19: orderAccounts[n]])
    }

    /// position (61, version 3) as the live gateway sends it.
    private func positionFrame(_ key: HoldingKey) -> [String] {
        let h = holdings[key] ?? Holding()
        let b = contractBlocks[key.conID] ?? Self.noContract
        return ["61", "3", key.account] + b[0..<8] + b[9..<12] + ["\(h.quantity)", "\(h.averageCost)"]
    }

    /// portfolioValue (7, version 8), valued at the market price, else the contract's last fill price.
    private func portfolioFrame(_ key: HoldingKey) -> [String] {
        let h = holdings[key] ?? Holding()
        let b = contractBlocks[key.conID] ?? Self.noContract
        let price = marketPrices[key.conID] ?? fills.last { orders[$0.order].contract.conID == key.conID }?.price ?? 0
        return ["7", "8"] + b[0..<7] + b[8..<12]
            + ["\(h.quantity)", "\(price)", "\(Self.round(price * h.quantity))", "\(h.averageCost)",
               "\(Self.round((price - h.averageCost) * h.quantity))", "\(h.realized)", key.account]
    }

    // MARK: - Arithmetic

    /// Books a signed quantity at `price`; returns the P&L of the part it closed before commission, or nil when it
    /// only opened or added (then the average cost moves, commission excluded).
    // shortcut: a trade that flips the position books the whole commission on the closing part; refine when a
    // scenario flips one
    private static func trade(_ h: inout Holding, _ q: Decimal, at price: Decimal) -> Decimal? {
        if h.quantity == 0 || (h.quantity > 0) == (q > 0) {
            let n = h.quantity + q
            h.averageCost = round((abs(h.quantity) * h.averageCost + abs(q) * price) / abs(n))
            h.quantity = n
            return nil
        }
        let closed = min(abs(q), abs(h.quantity))
        let pnl = (price - h.averageCost) * closed * (h.quantity > 0 ? 1 : -1)
        h.quantity += q
        if h.quantity == 0 { h.averageCost = 0 } else if (h.quantity > 0) == (q > 0) { h.averageCost = price }
        return pnl
    }

    /// Six decimals, as IB's money fields: a longer `Decimal` would not survive ib_async's float.
    private static func round(_ x: Decimal) -> Decimal {
        var x = x, out = Decimal()
        NSDecimalRound(&out, &x, 6, .plain)
        return out
    }

    private static func format(_ epoch: Int, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = pattern
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }
}
