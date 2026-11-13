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
    var ocaType: Int
    var whatIf: Bool
    var status: OrderStatus
    var filled: Decimal
}

/// A stateful simulated broker over `FakeGateway` (composed, never forked): one wired gateway per connect, and one
/// book of orders, fills and positions shared by every client. Its frames are the live ones where a recording shows
/// them: order, fill and commission sequences copy Recorded/liveLimitOrderPlacesAndCancels.json and
/// liveOrderFillsWithCommission.json, and openOrder and completedOrder are that recording's frames with the order's
/// own values put in. Times, permIDs, execIds and new conIDs come from counters, so a scenario emits the same frames
/// on every run.
// @unchecked Sendable: every mutable member sits behind `lock`.
final class SimulatedBroker: @unchecked Sendable {
    private struct Session { var clientID: Int?; var positions = false; var account: String? }
    private struct Holding { var quantity: Decimal = 0; var averageCost: Decimal = 0; var realized: Decimal = 0 }
    private struct HoldingKey: Hashable, Comparable {
        var account: String, conID: Int
        static func < (a: Self, b: Self) -> Bool { (a.account, a.conID) < (b.account, b.conID) }
    }
    /// IB's description of a contract, as its replies carry it (strike in placeOrder's `0.0` form).
    private struct SimContract {
        var conID: Int
        var symbol, secType, lastTrade, strike, right, multiplier, primary, currency, localSymbol, tradingClass: String
    }
    private struct SimFill { var order: Int; var time: Int; var price, amount, fee: Decimal; var execution, report: [String] }

    private static let unset = "1.7976931348623157E308"
    /// AAPL as the live recordings describe it (positions on NASDAQ, trading class NMS).
    private static let recordedContracts = [
        SimContract(conID: 265598, symbol: "AAPL", secType: "STK", lastTrade: "", strike: "0.0", right: "",
                    multiplier: "", primary: "NASDAQ", currency: "USD", localSymbol: "AAPL", tradingClass: "NMS"),
    ]
    /// liveOrderFillsWithCommission.json's first openOrder (LMT BUY, PreSubmitted, deltaNeutralOrderType `None` and its
    /// 8 fields, 135 in all) and its completedOrder of a filled LMT BUY (100 fields).
    private static let openTemplate = template(25, "5", 135)
    private static let completedTemplate = template(8, "101", 100)

    private let lock = NSLock()
    private let accounts: [String], nextOrderID: Int
    private var clock: Int
    private var _gateways: [FakeGateway] = []
    private var sessions: [Session] = []   // per gateway
    private var orders: [SimOrder] = []
    private var placed: [[String]] = []    // per order, the placeOrder frame that set its terms
    private var contracts: [Int: SimContract]
    private var fills: [SimFill] = []
    private var holdings: [HoldingKey: Holding] = [:]
    private var marketPrices: [Int: Decimal] = [:]
    private var permIDs = 0, execIDs = 0, conIDs = 0
    private var _answers: [(request: [String], replies: [[String]])] = []
    private var pendingReject: (code: Int, text: String)?
    private var failures: [String: (code: Int, text: String)] = [:]   // by request message id
    private var replyDelay: Duration?
    private var down = false
    private var marketData: [(session: Int, requestID: String, conID: Int)] = []
    /// The what-if answers' account: flat, this equity with loan.
    private static let equity: Decimal = 1_000_000

    init(accounts: [String] = ["DU0000001"], nextOrderID: Int = 1, clock: Int = 1794321000) {
        (self.accounts, self.nextOrderID, self.clock) = (accounts, nextOrderID, clock)
        contracts = Dictionary(uniqueKeysWithValues: Self.recordedContracts.map { ($0.conID, $0) })
    }

    /// Hands out a new wired gateway per connect.
    var connector: Connector {
        { [weak self] _, _, _ in
            guard let self else { throw IBClientError.transport("no broker") }
            guard !self.lock.withLock({ self.down }) else { throw IBClientError.transport("broker down") }
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
        gateway.onRequest = { [weak self] in self?.answer($0, session: i); return [] }
        return gateway
    }

    var gateways: [FakeGateway] { lock.withLock { _gateways } }

    /// Every gateway's `fed`, in hand-out order.
    var emitted: [[String]] { gateways.flatMap(\.fed) }

    /// Every request the broker answered, with the frames it fed back, in arrival order.
    var answers: [(request: [String], replies: [[String]])] { lock.withLock { _answers } }

    /// Every order in the book, in the order placed.
    var bookedOrders: [SimOrder] { lock.withLock { orders } }

    /// Refuses the next placeOrder, a new order or a modification: IB's error `code` with `text` on its id is the
    /// whole answer and the book stays as it was. A fatal code ends a new order `.inactive` in the client; a warning
    /// (105, 321, …) on a modification leaves the order working with its old terms.
    // assumption: unrecorded live — the error alone, no openOrder or orderStatus
    func reject(nextOrderWith code: Int, text: String) { lock.withLock { pendingReject = (code, text) } }

    /// A mid-stream disconnect: closes every live gateway, then runs `outage` while connects are refused, so what it
    /// books (a fill) happens while every client is down, whatever a reconnect policy's delay.
    func drop(during outage: () -> Void = {}) {
        lock.withLock {
            down = true
            _gateways.forEach { $0.close() }
        }
        outage()
        lock.withLock { down = false }
    }

    /// Answers the next request with message id `messageID` with IB's error `code` and `text` on its reqId (-1 for
    /// a request without one) instead of its replies.
    // assumption: unrecorded live — the error alone and nothing booked, where IB keeps a market-data line it refused
    // for want of permission open (DECISIONS' accountSummary/pnlSingle row); the client's cancel then finds nothing
    func failNext(_ messageID: String, code: Int, text: String) {
        lock.withLock { failures[messageID] = (code, text) }
    }

    /// Feeds the replies to every later request `d` after it arrives. The sync's requests that `FakeGateway` ends
    /// itself (16, 99, 7, 61, 6) are never delayed, since their end markers would overtake them.
    func delayReplies(_ d: Duration) { lock.withLock { replyDelay = d } }

    /// A tickPrice (1, version 6) of `field` at `price` to every open market-data request for the contract.
    // assumption: unrecorded live — size 0, no attributes; liveMarketData.json records only refusals
    func tick(conID: Int, field: Int, price: Decimal) {
        lock.withLock {
            for m in marketData where m.conID == conID && !_gateways[m.session].isClosed {
                _gateways[m.session].feed(["1", "6", m.requestID, "\(field)", "\(price)", "0", "0"])
            }
        }
    }

    /// The reqIds of the market-data requests open on a live gateway (a dropped connection ends its lines).
    var openMarketData: [Int] {
        lock.withLock { marketData.filter { !_gateways[$0.session].isClosed }.compactMap { Int($0.requestID) } }
    }

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
    /// them, the portfolio to every client subscribed to the account. More than the order's remaining quantity is
    /// refused.
    // assumption: unrecorded live — a part fill: openOrder + orderStatus stay Submitted with filled and remaining
    func fill(orderID: Int, clientID: Int, shares: Decimal, price: Decimal, commission: Decimal = 1) {
        lock.withLock {
            guard let n = orders.firstIndex(where: { $0.clientID == clientID && $0.orderID == orderID }) else {
                Issue.record("SimulatedBroker.fill: no order \(orderID) of client \(clientID)")
                return
            }
            guard shares > 0, orders[n].filled + shares <= orders[n].quantity else {
                let o = orders[n]
                Issue.record("SimulatedBroker.fill: \(shares) of order \(orderID), \(o.filled) of \(o.quantity) filled")
                return
            }
            orders[n].filled += shares
            orders[n].status = orders[n].filled == orders[n].quantity ? .filled : .submitted
            let o = orders[n]
            let key = HoldingKey(account: account(placed[n]), conID: o.contract.conID)
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
            let time = clock
            clock += 1
            let amount = shares * price
            let average = Self.round((fills.filter { $0.order == n }.map(\.amount).reduce(0, +) + amount) / o.filled)
            let c = contracts[o.contract.conID]!
            let execution = ["11", "-1", "\(o.orderID)", "\(c.conID)", c.symbol, c.secType, c.lastTrade, c.strike,
                             c.right, c.multiplier, "IBKRATS", c.currency, c.localSymbol, c.tradingClass, execID,
                             Self.format(time, "yyyyMMdd-HH:mm:ss", "UTC"), key.account, "IBKRATS",
                             o.action == .buy ? "BOT" : "SLD", "\(shares)", "\(price)", "\(o.permID)", "\(o.clientID)",
                             "0", "\(o.filled)", "\(average)", "", "", "", "", "2", "0"]
            let report = ["59", "1", execID, "\(commission)", "USD", realized.map { "\($0)" } ?? Self.unset,
                          Self.unset, ""]
            fills.append(SimFill(order: n, time: time, price: price, amount: amount, fee: commission,
                                 execution: execution, report: report))

            var events = [execution] + openAndStatus(n)
            if o.status == .filled {
                events += openAndStatus(n, commission: fills.filter { $0.order == n }.map(\.fee).reduce(0, +))
            }
            events.append(report)
            events += consequences(of: n)
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

    /// What a fill of order `n` does to the owner's other orders: a filled parent sends its children to work
    /// (openOrder + Submitted each); a fill cancels the rest of its OCA group, and of its bracket (IB links a
    /// bracket's children as one group), each with the bare orderStatus Cancelled that ends the recorded cancel.
    // assumption: unrecorded live — children work only once the parent is wholly filled; ocaType 1 (cancel the rest)
    // only: 2 and 3 (reduce the rest) are refused, model them when a scenario uses them
    private func consequences(of n: Int) -> [[String]] {
        let o = orders[n]
        var out: [[String]] = []
        let mine = orders.indices.filter { $0 != n && orders[$0].clientID == o.clientID }
        if o.status == .filled {
            for k in mine where orders[k].parentID == o.orderID && orders[k].status == .preSubmitted {
                orders[k].status = .submitted
                out += openAndStatus(k)
            }
        }
        if !o.ocaGroup.isEmpty && o.ocaType != 1 {
            Issue.record("SimulatedBroker: ocaType \(o.ocaType) is not modelled")
            return out
        }
        for k in mine where !orders[k].status.isFinal
            && (o.ocaGroup.isEmpty ? o.parentID != 0 && orders[k].parentID == o.parentID
                                   : orders[k].ocaGroup == o.ocaGroup) {
            orders[k].status = .cancelled
            out.append(openAndStatus(k)[1])
        }
        return out
    }

    // MARK: - Requests

    /// Feeds the replies to one request from session `i` under the lock that guards the state they show, so a
    /// concurrent `fill` lands wholly before or after them; `FakeGateway`'s own end markers follow. Runs in the
    /// client's write path: it never blocks and never calls back into the client.
    private func answer(_ f: [String], session i: Int) {
        lock.withLock {
            let out = replies(f, session: i), gateway = _gateways[i]
            _answers.append((f, out))
            guard let d = replyDelay, !["16", "99", "7", "61", "6"].contains(f[0]) else {
                if !gateway.isClosed { out.forEach(gateway.feed) }
                return
            }
            Task {
                try? await Task.sleep(for: d)
                lock.withLock { if !gateway.isClosed { out.forEach(gateway.feed) } }
            }
        }
    }

    /// Where the reqId sits in the requests `failNext` can refuse; the others carry none.
    private static let requestIDIndex = ["1": 2, "92": 1, "94": 1]

    private func replies(_ f: [String], session i: Int) -> [[String]] {
        if let e = failures.removeValue(forKey: f[0]) {
            return [["4", "2", Self.requestIDIndex[f[0]].map { f[$0] } ?? "-1", "\(e.code)", e.text, ""]]
        }
        switch f.first {
        case "71": sessions[i].clientID = Int(f[2])
        case "3": return place(f, session: i)
        case "4": return cancel(f, session: i)
        case "16":   // assumption: unrecorded live — every client's working orders, openOrder + orderStatus each
            return orders.indices.filter { !orders[$0].status.isFinal }.flatMap { openAndStatus($0) }
        case "99":   // assumption: unrecorded live — completedOrder per final order
            return orders.indices.filter { orders[$0].status.isFinal }.map(completedFrame)
        case "7":   // as recorded: every execDetails under the request's id and in the login zone, then the reports
            // the filter's clientId 0 lists every client's fills (DECISIONS' ExecutionFilter row, live), another only
            // that client's (assumption: unrecorded live); the filter's other fields are ignored
            let listed = fills.filter { f[3] == "0" || "\(orders[$0.order].clientID)" == f[3] }
            return listed.map { replacing($0.execution, [1: f[2], 15: Self.eastern($0.time)]) } + listed.map(\.report)
        case "1":   // assumption: unrecorded live — no tick until `tick`
            marketData.append((i, f[2], Int(f[3]) ?? 0))
        case "2": marketData.removeAll { $0.session == i && $0.requestID == f[2] }
        case "49": return [["49", "1", "\(clock)"]]   // assumption: unrecorded live — the broker's clock
        case "92": return [pnlFrame(f[1], account: f[2])]
        case "94": return [pnlSingleFrame(f[1], HoldingKey(account: f[2], conID: Int(f[4]) ?? 0))]
        case "61":
            sessions[i].positions = true
            return holdings.keys.sorted().map(positionFrame)
        case "64": sessions[i].positions = false
        case "6" where f[2] == "1":   // assumption: unrecorded live — AccountCode, the portfolio, the time
            sessions[i].account = f[3]
            return [["6", "2", "AccountCode", f[3], "", f[3]]]
                + holdings.keys.filter { $0.account == f[3] }.sorted().map(portfolioFrame)
                + [["8", "1", Self.format(clock, "HH:mm", "UTC")]]
        case "6": sessions[i].account = nil
        // assumption: unrecorded live — client 0's reqAutoOpenOrders (15) binds TWS's manual orders, which the broker
        // has none of: every client's order events still go to their owner only
        default: break
        }
        return []
    }

    /// Books a placeOrder (docs/protocol-178.md's placeOrder indices: the base case, or with the 8-field
    /// delta-neutral group a modify of a decoded live order re-sends, R24) and answers as
    /// liveOrderFillsWithCommission.json: openOrder + PreSubmitted, openOrder + Submitted. A re-send of a known id is
    /// a modify; `whatIf` gets the what-if answer and books nothing; `transmit` off holds the order, unanswered, until
    /// a transmitting leg of its bracket sends the group.
    private func place(_ f: [String], session i: Int) -> [[String]] {
        let shift = f.count > 64 && !f[64].isEmpty ? 8 : 0
        guard f.count == 114 + shift else {
            Issue.record("SimulatedBroker: placeOrder with \(f.count) fields, not 114 (122 with delta-neutral); not booked")
            return []
        }
        if let r = pendingReject {
            pendingReject = nil
            return [["4", "2", f[1], "\(r.code)", r.text, ""]]
        }
        var contract = Contract(symbol: f[3], secType: f[4], exchange: f[9], currency: f[11], primaryExchange: f[10])
        contract.conID = resolve(f)
        let clientID = sessions[i].clientID ?? 0, orderID = Int(f[1]) ?? 0
        var order = SimOrder(
            clientID: clientID, orderID: orderID, permID: 0, contract: contract,
            action: OrderAction(rawValue: f[16]) ?? .buy, quantity: Decimal(string: f[17]) ?? 0, orderType: f[18],
            limitPrice: Decimal(string: f[19]), parentID: Int(f[28]) ?? 0, transmit: f[27] == "1", ocaGroup: f[22],
            ocaType: Int(f[46]) ?? 0, whatIf: f[84 + shift] == "1", status: .preSubmitted, filled: 0)
        if order.whatIf { return [whatIfFrame(order, f)] }
        if let n = orders.firstIndex(where: { $0.clientID == clientID && $0.orderID == orderID }) {
            // assumption: unrecorded live — a modify: new terms, same permID, status and fills, one openOrder +
            // orderStatus
            (order.permID, order.status, order.filled) = (orders[n].permID, orders[n].status, orders[n].filled)
            (orders[n], placed[n]) = (order, f)
            return openAndStatus(n)
        }
        permIDs += 1
        order.permID = 1_000_000_000 + permIDs
        orders.append(order)
        placed.append(f)
        let n = orders.count - 1
        // assumption: unrecorded live — an untransmitted leg gets no answer (ib_async leaves it PendingSubmit)
        guard order.transmit else { orders[n].status = .pendingSubmit; return [] }
        let held = orders.indices.filter { k in
            k != n && order.parentID != 0 && orders[k].clientID == clientID && orders[k].status == .pendingSubmit
                && (orders[k].orderID == order.parentID || orders[k].parentID == order.parentID)
        }
        return (held + [n]).flatMap(submit)
    }

    /// openOrder + PreSubmitted, then openOrder + Submitted; a child of a parent not yet filled stays PreSubmitted.
    // assumption: unrecorded live — a bracket's children wait PreSubmitted
    private func submit(_ n: Int) -> [[String]] {
        orders[n].status = .preSubmitted
        let preSubmitted = openAndStatus(n)
        let o = orders[n]
        if o.parentID != 0,
           orders.first(where: { $0.clientID == o.clientID && $0.orderID == o.parentID })?.status != .filled {
            return preSubmitted
        }
        orders[n].status = .submitted
        return preSubmitted + openAndStatus(n)
    }

    /// Cancels the client's working order as liveLimitOrderPlacesAndCancels.json: openOrder + orderStatus
    /// PendingCancel twice, orderStatus Cancelled, error 202 with a bare reason.
    private func cancel(_ f: [String], session i: Int) -> [[String]] {
        let clientID = sessions[i].clientID ?? 0
        // shortcut: an unknown or final id gets no answer where live sends 10147; add it when a scenario needs it
        guard let n = orders.firstIndex(where: { $0.clientID == clientID && "\($0.orderID)" == f[2] }),
              !orders[n].status.isFinal else { return [] }
        orders[n].status = .pendingCancel
        let pending = openAndStatus(n)
        orders[n].status = .cancelled
        return pending + pending + [openAndStatus(n)[1], ["4", "2", f[2], "202", "Order Canceled - reason:", ""]]
    }

    /// IB's conID for placeOrder's contract: the one it names, else a known contract with the same terms, else a new
    /// one. A contract no recording describes keeps the terms placeOrder sent.
    private func resolve(_ f: [String]) -> Int {
        let c = SimContract(conID: Int(f[2]) ?? 0, symbol: f[3], secType: f[4], lastTrade: f[5], strike: f[6],
                            right: f[7], multiplier: f[8], primary: f[10].isEmpty ? f[9] : f[10], currency: f[11],
                            localSymbol: f[12].isEmpty ? f[3] : f[12], tradingClass: f[13])
        if c.conID != 0 { if contracts[c.conID] == nil { contracts[c.conID] = c }; return c.conID }
        let same = { (k: SimContract) in
            (k.symbol, k.secType, k.lastTrade, k.strike, k.right, k.currency) ==
                (c.symbol, c.secType, c.lastTrade, c.strike, c.right, c.currency)
        }
        if let known = contracts.values.sorted(by: { $0.conID < $1.conID }).first(where: same) { return known.conID }
        conIDs += 1
        let id = 900_000_000 + conIDs   // assumption: unrecorded live — a contract the recordings never traded
        contracts[id] = SimContract(conID: id, symbol: c.symbol, secType: c.secType, lastTrade: c.lastTrade,
                                    strike: c.strike, right: c.right, multiplier: c.multiplier, primary: c.primary,
                                    currency: c.currency, localSymbol: c.localSymbol, tradingClass: c.tradingClass)
        return id
    }

    // MARK: - Frames

    /// placeOrder's account, else the first managed one.
    private func account(_ f: [String]) -> String { f[23].isEmpty ? accounts[0] : f[23] }

    /// The recorded openOrder with order `n`'s values, and its orderStatus.
    private func openAndStatus(_ n: Int, commission: Decimal? = nil) -> [[String]] {
        let o = orders[n]
        var open = openFrame(o, placed[n])
        if let commission { open = replacing(open, [103: "\(commission)", 106: "USD"]) }
        let own = fills.filter { $0.order == n }
        let average = o.filled == 0 ? 0 : Self.round(own.map(\.amount).reduce(0, +) / o.filled)
        let status = ["3", "\(o.orderID)", o.status.rawValue, "\(o.filled)", "\(o.quantity - o.filled)", "\(average)",
                      "\(o.permID)", "\(o.parentID)", "\(own.last?.price ?? 0)", "\(o.clientID)", "", "0"]
        return [open, status]
    }

    /// The recorded openOrder with the values of `o`, placed by placeOrder `f`. An OCA order echoes its ocaType where
    /// the template has live's 3 for a plain order.
    // assumption: unrecorded live — the OCA echo
    private func openFrame(_ o: SimOrder, _ f: [String]) -> [String] {
        let c = contracts[o.contract.conID]!
        return replacing(Self.openTemplate, [
            1: "\(o.orderID)", 2: "\(c.conID)", 3: c.symbol, 4: c.secType, 5: c.lastTrade,
            6: c.strike == "0.0" ? "0" : c.strike, 7: c.right.isEmpty ? "?" : c.right, 8: c.multiplier,
            9: o.contract.exchange, 10: c.currency, 11: c.localSymbol, 12: c.tradingClass,
            13: o.action.rawValue, 14: "\(o.quantity)", 15: o.orderType, 16: Self.price(f[19]), 17: Self.price(f[20]),
            18: f[21], 19: o.ocaGroup, 20: account(f), 23: f[26], 24: "\(o.clientID)", 25: "\(o.permID)", 26: f[33],
            30: "\(o.permID).0/\(account(f))/100", 53: o.ocaGroup.isEmpty ? Self.openTemplate[53] : "\(o.ocaType)",
            57: "\(o.parentID)", 93: o.status.rawValue, 113: Self.trailStopPrice(o)])
    }

    /// The what-if answer: `o`'s openOrder with whatIf set (92), the nine margins (94–102) and the commission.
    // assumption: unrecorded live — one PreSubmitted openOrder, no orderStatus; Reg T margins (50 % initial, 25 %
    // maintenance of the notional at the limit, else the market price) on a flat account, equity with loan less the
    // commission of 1
    private func whatIfFrame(_ o: SimOrder, _ f: [String]) -> [String] {
        let notional = o.quantity * (o.limitPrice ?? marketPrices[o.contract.conID] ?? 0), commission: Decimal = 1
        let before: [Decimal] = [0, 0, Self.equity], change = [notional / 2, notional / 4, -commission]
        let margins = before + change + zip(before, change).map { $0 + $1 }
        var changes = [92: "1", 103: "\(commission)", 106: "USD"]
        for (k, m) in margins.enumerated() { changes[94 + k] = "\(m)" }
        return replacing(openFrame(o, f), changes)
    }

    /// The recorded completedOrder with order `n`'s values; a filled one carries totalQuantity 0, as live.
    private func completedFrame(_ n: Int) -> [String] {
        let o = orders[n], f = placed[n], c = contracts[o.contract.conID]!
        return replacing(Self.completedTemplate, [
            1: "\(c.conID)", 2: c.symbol, 3: c.secType, 4: c.lastTrade, 5: c.strike == "0.0" ? "0" : c.strike,
            6: c.right.isEmpty ? "?" : c.right, 7: c.multiplier, 8: o.contract.exchange, 9: c.currency,
            10: c.localSymbol, 11: c.tradingClass, 12: o.action.rawValue, 13: o.status == .filled ? "0" : "\(o.quantity)",
            14: o.orderType, 15: Self.price(f[19]), 16: Self.price(f[20]), 17: f[21], 18: o.ocaGroup, 19: account(f),
            22: f[26], 23: "\(o.permID)", 24: f[33], 76: o.status.rawValue, 80: Self.trailStopPrice(o),
            86: "\(o.filled)", 93: fills.last { $0.order == n }.map { Self.eastern($0.time) } ?? "",
            94: o.status == .filled ? "Filled Size: \(o.filled)" : o.status.rawValue])
    }

    /// position (61, version 3) as the live gateway sends it: the primary exchange, `0.0` for a flat position's cost.
    private func positionFrame(_ key: HoldingKey) -> [String] {
        let h = holdings[key] ?? Holding(), c = contracts[key.conID]!
        return ["61", "3", key.account, "\(c.conID)", c.symbol, c.secType, c.lastTrade, c.strike, c.right,
                c.multiplier, c.primary, c.currency, c.localSymbol, c.tradingClass, "\(h.quantity)",
                h.quantity == 0 ? "0.0" : "\(h.averageCost)"]
    }

    /// portfolioValue (7, version 8), valued at the market price, else the contract's last fill price.
    // assumption: unrecorded live — no recording subscribes to account updates
    private func portfolioFrame(_ key: HoldingKey) -> [String] {
        let h = holdings[key] ?? Holding(), c = contracts[key.conID]!, price = marketPrice(key.conID)
        return ["7", "8", "\(c.conID)", c.symbol, c.secType, c.lastTrade, c.strike, c.right, c.multiplier, c.primary,
                c.currency, c.localSymbol, c.tradingClass, "\(h.quantity)", "\(price)",
                "\(Self.round(price * h.quantity))", "\(h.averageCost)", "\(unrealized(key))", "\(h.realized)",
                key.account]
    }

    /// The account's P&L (94), valued as the portfolio is: daily = unrealized + realized, as the recorded pnlSingle
    /// (liveOrderFillsWithCommission.json#38) adds up.
    // assumption: unrecorded live — one answer at the request (no prior day, no update after a fill or a price)
    private func pnlFrame(_ id: String, account: String) -> [String] {
        let keys = holdings.keys.filter { $0.account == account }
        let unrealized = keys.map(unrealized).reduce(0, +), realized = keys.map { holdings[$0]!.realized }.reduce(0, +)
        return ["94", id, "\(unrealized + realized)", "\(unrealized)", "\(realized)"]
    }

    /// One position's P&L (95) as the recorded one: position, daily, unrealized, realized, value.
    // assumption: unrecorded live — one answer at the request, as `pnlFrame`
    private func pnlSingleFrame(_ id: String, _ key: HoldingKey) -> [String] {
        let h = holdings[key] ?? Holding(), unrealized = unrealized(key)
        return ["95", id, "\(h.quantity)", "\(unrealized + h.realized)", "\(unrealized)", "\(h.realized)",
                "\(Self.round(marketPrice(key.conID) * h.quantity))"]
    }

    /// The market price, else the contract's last fill price.
    private func marketPrice(_ conID: Int) -> Decimal {
        marketPrices[conID] ?? fills.last { orders[$0.order].contract.conID == conID }?.price ?? 0
    }

    private func unrealized(_ key: HoldingKey) -> Decimal {
        let h = holdings[key] ?? Holding()
        return Self.round((marketPrice(key.conID) - h.averageCost) * h.quantity)
    }

    /// openOrder / completedOrder price text: live sends `0.0` for placeOrder's unset `""`.
    private static func price(_ placeOrderText: String) -> String { placeOrderText.isEmpty ? "0.0" : placeOrderText }

    /// Live sends lmtPrice + 1 for every recorded LMT order.
    // assumption: unrecorded live — any other order type's value
    private static func trailStopPrice(_ o: SimOrder) -> String {
        o.orderType == "LMT" ? o.limitPrice.map { "\($0 + 1)" } ?? unset : unset
    }

    private static func template(_ index: Int, _ id: String, _ count: Int) -> [String] {
        let f = try! recording("liveOrderFillsWithCommission")[index]
        precondition(f.first == id && f.count == count, "liveOrderFillsWithCommission.json#\(index) moved")
        return f
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

    /// A time as the recorded replay and completedOrder carry it: the login zone, named.
    private static func eastern(_ epoch: Int) -> String {
        format(epoch, "yyyyMMdd HH:mm:ss", "America/New_York") + " US/Eastern"
    }

    private static func format(_ epoch: Int, _ pattern: String, _ zone: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: zone)
        f.dateFormat = pattern
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }
}
