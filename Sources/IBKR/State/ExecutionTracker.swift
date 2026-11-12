import Foundation

/// One completed trade: an execution joined with its commission report.
public struct Fill: Sendable, Equatable {
    /// The instrument traded.
    public var contract: Contract
    /// The execution (execDetails, in 11).
    public var execution: Execution
    /// Its commission report (in 59), matched by execution id.
    public var commission: CommissionReport

    /// Creates a fill with every field given.
    public init(contract: Contract, execution: Execution, commission: CommissionReport) {
        self.contract = contract
        self.execution = execution
        self.commission = commission
    }
}

/// Joins IB's execDetails and commissionReport (matched by execId, in either order) into whole fills. Pure
/// value, no I/O: the owner publishes whatever `apply` returns.
public struct ExecutionTracker: Sendable {
    private var all: [Fill] = []
    private var pendingExecs: [String: (contract: Contract, execution: Execution)] = [:]
    private var pendingCommissions: [String: CommissionReport] = [:]
    private var byCorrectionKey: [String: Int] = [:]
    private var byExecID: [String: Int] = [:]

    /// Creates a tracker with no fills.
    public init() {}

    /// First-seen order; a correction replaces its fill in place.
    public var fills: [Fill] { all }

    /// Feeds one message; returns the fills it completes or corrects, else none.
    public mutating func apply(_ message: IBMessage) -> [Fill] {
        switch message {
        case .execDetails(_, let contract, let execution):
            guard !isSuperseded(execution.execID) else { return [] }
            pendingExecs[execution.execID] = (contract, execution)
            return join(execution.execID)
        case .commissionReport(let report):
            guard !isSuperseded(report.execID) else { return [] }
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
    private static func correctionKey(_ id: String) -> String {
        id.lastIndex(of: ".").map { String(id[..<$0]) } ?? id
    }

    /// Compares the last segments numerically when both parse, else lexically. 
    private static func isNewer(_ a: String, than b: String) -> Bool {
        let (x, y) = (a.split(separator: ".").last.map(String.init) ?? a,
                      b.split(separator: ".").last.map(String.init) ?? b)
        if let m = Int(x), let n = Int(y) { return m > n }
        return x > y
    }

    private mutating func join(_ id: String) -> [Fill] {
        guard let e = pendingExecs[id], let c = pendingCommissions[id] else { return [] }
        pendingExecs[id] = nil; pendingCommissions[id] = nil
        let fill = Fill(contract: e.contract, execution: e.execution, commission: c)
        let key = Self.correctionKey(id)
        let i = byCorrectionKey[key] ?? all.count
        if i < all.count {
            guard !Self.isNewer(all[i].execution.execID, than: id), all[i] != fill else { return [] }
            all[i] = fill
        } else {
            all.append(fill)
            byCorrectionKey[key] = i
        }
        byExecID[id] = i
        return [fill]
    }
}
