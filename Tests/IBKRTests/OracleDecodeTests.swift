import Foundation
import Testing
@testable import IBKR

// Decode cross-check (C1): each decode.json frame through IBDecoder, mapped to ib_async's wrapper callbacks by the
// per-family OracleDecode+<Family>.swift files, compared with what ib_async 2.1.0 called.

/// Incoming ids no family maps yet; the comparison and the coverage test skip them. Each decode task removes its own.
let pendingDecodeIDs: Set<Int> = [
    1, 2, 10, 12, 13, 14, 16, 17, 18, 19, 20, 21,
    45, 46, 47,
    50, 51, 52, 56, 57, 58,
    65, 66, 67, 68, 69, 70, 75, 76, 77, 78, 79, 80,
    81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 96, 97, 98, 99,
    103, 104, 105, 106,
]

/// The wrapper calls ib_async would make for what IBDecoder produced; `nil` when no family maps this message.
func ibAsyncCalls(id: Int, _ m: IBMessage) -> [OracleCall]? {
    sessionCalls(id: id, m) ?? accountCalls(id: id, m) ?? orderCalls(id: id, m)
}

/// Review Focus 1: a frame ib_async rejects carries `error`, and swift-ibkr rejects it too.
@Test func oracleRecordsIbAsyncExceptions() throws {
    let file: OracleDecodeFile = try oracleFile("decode.json")
    let canary = try #require(file.frames.first { $0.name == "gen/canary/short-openOrder" })
    #expect(canary.fields == ["5", "1"])
    #expect(canary.error?.isEmpty == false)
    #expect(canary.calls == nil)
    guard case .malformed = IBDecoder.decode(body(canary.fields)) else { Issue.record("not malformed"); return }
}

/// Review Focus 2: the Python side folds IB's sentinels to "", the Swift side never does.
@Test func swiftCanonicalNeverFoldsSentinels() {
    #expect(canon(Int?(2147483647)) == "2147483647")
    #expect(canon(Decimal?(nil)) == "")
    #expect(canon(d("100.0")) == "100")
    #expect(canon(Date(timeIntervalSince1970: 1794321000)) == "1794321000")
    #expect(canon(true) == "true")
}

/// Review Focus 4: every entry is narrow and cites one recorded row (whether each is used is checked by
/// `ibAsyncDecodesLikeSwiftIBKR`); the checks reject the bad entries they exist for.
@Test func allowlistEntriesAreNarrowCitedAndUsed() throws {
    let allow: [AllowEntry] = try oracleFile("allowlist.json")
    let docs = try oracleDocs()
    for p in allowlistProblems(allow, decisions: docs.decisions, protocol178: docs.protocol178) { Issue.record("\(p)") }

    let good = AllowEntry(scope: "in 4", field: "errorString", cite: "protocol-178 Disagreements 8")
    #expect(allowlistProblems([good], decisions: docs.decisions, protocol178: docs.protocol178).isEmpty)
    let bad = [
        AllowEntry(scope: "in 4", field: "*", cite: "protocol-178 Disagreements 8"),
        AllowEntry(scope: "in 4", field: "errorString", cite: "protocol-178 Disagreements 99"),
        AllowEntry(scope: "in 4", field: "errorString", cite: "DECISIONS: no row says this"),
        AllowEntry(scope: "in 4", field: "errorString", cite: "DECISIONS: | "),
        AllowEntry(scope: "in 4", field: "errorString", cite: "see the docs"),
        AllowEntry(scope: "in 4", field: "#whatever", cite: "protocol-178 Disagreements 8"),
        AllowEntry(scope: "out 3", field: "12", cite: "protocol-178 Disagreements 8"),
    ]
    for e in bad {
        #expect(allowlistProblems([e], decisions: docs.decisions, protocol178: docs.protocol178).count == 1, "\(e)")
    }
    var used: Set<Int> = []
    let same = [OracleCall(method: "nextValidId", args: ["reqId": "1"])]
    let unused = AllowEntry(scope: "in 9", field: "reqId", cite: "protocol-178 Disagreements 8")
    #expect(compare(same, same, name: "x", scope: "in 9", allow: [unused], used: &used).isEmpty)
    #expect(unusedDecodeEntries([unused], used: used, pending: []).count == 1)
}

@Test func ibAsyncDecodesLikeSwiftIBKR() throws {
    let file: OracleDecodeFile = try oracleFile("decode.json")
    let allow: [AllowEntry] = try oracleFile("allowlist.json")
    var used: Set<Int> = []
    for frame in file.frames {
        guard let id = Int(frame.fields[0]) else { Issue.record("\(frame.name): no message id"); continue }
        if pendingDecodeIDs.contains(id) { continue }
        let scope = "in \(id)"
        let ours = IBDecoder.decode(body(frame.fields))
        var mismatches: [Mismatch] = []
        if case .malformed(_, _, let reason) = ours {
            if frame.error == nil {
                mismatches = [Mismatch(name: frame.name, scope: scope, field: "#error", ours: "malformed: \(reason)",
                                       theirs: "decoded")]
            }
        } else if let error = frame.error {
            mismatches = [Mismatch(name: frame.name, scope: scope, field: "#error", ours: "decoded", theirs: error)]
        } else if let calls = ibAsyncCalls(id: id, ours) {
            mismatches = compare(calls, frame.calls ?? [], name: frame.name, scope: scope, allow: allow, used: &used)
        } else {
            Issue.record("\(frame.name): no ib_async mapping for \(ours)")
        }
        for m in unallowed(mismatches, allow: allow, used: &used) { Issue.record("\(m)") }
    }
    for e in unusedDecodeEntries(allow, used: used, pending: pendingDecodeIDs) {
        Issue.record("allowlist entry \(e.scope) \(e.field) (\(e.frames ?? "*")) accepts no mismatch: remove it")
    }
}
