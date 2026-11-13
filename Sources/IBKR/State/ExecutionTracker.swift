import Foundation

/// One completed trade: an execution joined with its commission report.
public struct Fill: Sendable, Equatable, Encodable {
    /// The instrument traded.
    public var contract: Contract
    /// The execution (execDetails, in 11).
    public var execution: Execution
    /// Its commission report (in 59), matched by execution id.
    public var commission: CommissionReport
    /// When the fill happened as the client knows it: a live execDetails' arrival, else `execution.date`.
    public var time: Date?

    /// Creates a fill with every field given.
    public init(contract: Contract, execution: Execution, commission: CommissionReport, time: Date? = nil) {
        self.contract = contract
        self.execution = execution
        self.commission = commission
        self.time = time
    }
}

/// Joins IB's execDetails and commissionReport (matched by execId, in either order) into whole fills. Pure
/// value, no I/O: the owner publishes whatever `apply` returns.
public struct ExecutionTracker: Sendable {
    private var all: [Fill] = []
    private var pendingExecs: [String: (contract: Contract, execution: Execution, time: Date?)] = [:]
    private var pendingCommissions: [String: CommissionReport] = [:]
    private var byCorrectionKey: [String: Int] = [:]
    private var byExecID: [String: Int] = [:]
    private var pendingOrder: [String] = []   // execIds with a half waiting, oldest first
    private let maxPending: Int

    /// Creates a tracker with no fills. It keeps at most 10 000 execDetails / commission halves waiting for their
    /// other half and drops the oldest beyond that.
    public init() { self.init(maxPending: 10_000) }

    /// A tracker that keeps at most `maxPending` unmatched halves.
    init(maxPending: Int) { self.maxPending = maxPending }

    /// First-seen order; a correction replaces its fill in place.
    public var fills: [Fill] { all }

    /// The whole fill for `execID`, or the correction that replaced it; `nil` while a half is missing.
    func fill(execID: String) -> Fill? { byExecID[execID].map { all[$0] } }

    /// Feeds one message; returns the fills it completes or corrects, else none. `receivedAt` is the arrival time of a
    /// live execDetails (reqId -1); without it a fill's time is `execution.date`, as `ib_async` does for a request's reply.
    public mutating func apply(_ message: IBMessage, receivedAt: Date? = nil) -> [Fill] {
        switch message {
        case .execDetails(_, let contract, let execution):
            guard !isSuperseded(execution.execID) else { return [] }
            wait(execution.execID)
            pendingExecs[execution.execID] = (contract, execution, receivedAt ?? execution.date)
            return join(execution.execID)
        case .commissionReport(let report):
            guard !isSuperseded(report.execID) else { return [] }
            wait(report.execID)
            pendingCommissions[report.execID] = report
            return join(report.execID)
        default:
            return []
        }
    }

    // MARK: -

    /// An execId whose fill has since been corrected: IB resending it must not bring the old fill back.
    private func isSuperseded(_ id: String) -> Bool {
        byExecID[id].map { all[$0].execution.execID != id } ?? false
    }

    /// A correction reuses the execId up to its last `.`-segment (`….01.02` corrects `….01.01`).
    static func correctionKey(_ id: String) -> String {
        id.lastIndex(of: ".").map { String(id[..<$0]) } ?? id
    }

    /// Compares the last segments numerically when both parse, else lexically. 
    private static func isNewer(_ a: String, than b: String) -> Bool {
        let (x, y) = (a.split(separator: ".").last.map(String.init) ?? a,
                      b.split(separator: ".").last.map(String.init) ?? b)
        if let m = Int(x), let n = Int(y) { return m > n }
        return x > y
    }

    /// Queues `id` as waiting for its other half (once), dropping the oldest waiting halves above `maxPending`.
    private mutating func wait(_ id: String) {
        guard pendingExecs[id] == nil, pendingCommissions[id] == nil else { return }
        pendingOrder.append(id)
        while pendingOrder.count > maxPending {
            let oldest = pendingOrder.removeFirst()
            pendingExecs[oldest] = nil; pendingCommissions[oldest] = nil
        }
    }

    private mutating func join(_ id: String) -> [Fill] {
        guard let e = pendingExecs[id], let c = pendingCommissions[id] else { return [] }
        pendingExecs[id] = nil; pendingCommissions[id] = nil
        pendingOrder.removeAll { $0 == id }
        let fill = Fill(contract: e.contract, execution: e.execution, commission: c, time: e.time)
        let key = Self.correctionKey(id)
        let i = byCorrectionKey[key] ?? all.count
        if i < all.count {
            let old = all[i]   // a resend differs in `time` only
            guard !Self.isNewer(old.execution.execID, than: id),
                  old.contract != fill.contract || old.execution != fill.execution || old.commission != fill.commission
            else { return [] }
            all[i] = fill
        } else {
            all.append(fill)
            byCorrectionKey[key] = i
        }
        byExecID[id] = i
        return [fill]
    }
}
