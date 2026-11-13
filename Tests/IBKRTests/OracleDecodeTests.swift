import Foundation
import Testing
@testable import IBKR

// Decode cross-check (C1): each decode.json frame through IBDecoder, mapped to ib_async's wrapper callbacks by the
// per-family OracleDecode+<Family>.swift files, compared with what ib_async 2.1.0 called.

/// The wrapper calls ib_async would make for what IBDecoder produced; `nil` when no family maps this message.
func ibAsyncCalls(id: Int, _ m: IBMessage) -> [OracleCall]? {
    sessionCalls(id: id, m) ?? accountCalls(id: id, m) ?? orderCalls(id: id, m) ?? marketDataCalls(id: id, m)
        ?? historyCalls(id: id, m) ?? referenceCalls(id: id, m) ?? researchCalls(id: id, m)
}

/// Review Focus 1: a frame ib_async rejects carries `error`, and swift-ibkr rejects it too.
@Test func oracleRecordsIbAsyncExceptions() throws {
    let file: OracleDecodeFile = try oracleDecode.get()
    let canary = try #require(file.frames.first { $0.name == "gen/canary/short-openOrder" })
    #expect(canary.fields == ["5", "1"])
    #expect(canary.error?.isEmpty == false)
    #expect(canary.calls == nil)
    guard case .malformed = IBDecoder.decode(body(canary.fields)) else { Issue.record("not malformed"); return }
    // the text is the same on every platform (an OSError's errno is not) and names the failure, not its context
    #expect(file.frames.allSatisfy { $0.error?.contains("[Errno") != true })
    let short = try #require(file.frames.first { $0.name == "gen/3/short-after-status" })
    #expect(short.error == "TypeError: missing a required argument: 'filled'")
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
    let allow: [AllowEntry] = try oracleAllowlist.get()
    let docs = try oracleDocs()
    for p in allowlistProblems(allow, decisions: docs.decisions, protocol178: docs.protocol178) { Issue.record("\(p)") }

    func entry(_ scope: String = "in 4", _ field: String = "errorString", frames: String? = "f",
               pair: [String]? = ["a", "b"], numbers: Bool? = nil, cite: String = "protocol-178 Disagreements 8")
        -> AllowEntry {
        AllowEntry(scope: scope, field: field, frames: frames, pair: pair, equalAsNumbers: numbers, cite: cite)
    }
    let good = entry()
    #expect(allowlistProblems([good], decisions: docs.decisions, protocol178: docs.protocol178).isEmpty)
    let bad = [
        entry("in 4", "*"),
        entry(cite: "protocol-178 Disagreements 99"),
        entry(cite: "DECISIONS: no row says this"),
        entry(cite: "DECISIONS: | "),
        entry(cite: "see the docs"),
        entry("in 4", "#whatever"),
        entry("out 3", "12", frames: nil),
        entry("in 5", "x", frames: "gen/5/*"),
        entry("in 5", "x", frames: "gen/5/x", pair: nil),
        entry("in 5", "x", frames: "gen/5/x", numbers: true),
    ]
    for e in bad {
        #expect(allowlistProblems([e], decisions: docs.decisions, protocol178: docs.protocol178).count == 1, "\(e)")
    }
    // equalAsNumbers folds IB's unset markers on ib_async's side only: a Swift value that kept one is a mismatch.
    let numbers = entry("in 5", "x", frames: "x", pair: nil, numbers: true)
    func accepts(_ ours: String, _ theirs: String) -> Bool {
        numbers.accepts(Mismatch(name: "x", scope: "in 5", field: "x", ours: ours, theirs: theirs))
    }
    #expect(accepts("", "1.7976931348623157E308"))
    #expect(accepts("12345.6", "12345.60"))
    #expect(!accepts("2147483647", ""))
    #expect(!accepts("1.7976931348623157E308", ""))
    var used: Set<Int> = []
    let same = [OracleCall(method: "nextValidId", args: ["reqId": "1"])]
    let unused = entry("in 9", "reqId", frames: "x")
    #expect(compare(same, same, name: "x", scope: "in 9", allow: [unused], used: &used).isEmpty)
    #expect(unusedDecodeEntries([unused], used: used).count == 1)
}

@Test func ibAsyncDecodesLikeSwiftIBKR() throws {
    let file: OracleDecodeFile = try oracleDecode.get()
    let allow: [AllowEntry] = try oracleAllowlist.get()
    var used: Set<Int> = []
    // every entry names one exact frame, so each frame is offered only its own (a linear scan of all is seconds)
    let byFrame = Dictionary(grouping: allow.indices) { allow[$0].frames ?? "" }
    for frame in file.frames {
        let mine = byFrame[frame.name] ?? [], own = mine.map { allow[$0] }
        var usedHere: Set<Int> = []
        defer { used.formUnion(usedHere.map { mine[$0] }) }
        guard let id = Int(frame.fields[0]) else { Issue.record("\(frame.name): no message id"); continue }
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
            mismatches = compare(calls, frame.calls ?? [], name: frame.name, scope: scope, allow: own, used: &usedHere)
        } else {
            Issue.record("\(frame.name): no ib_async mapping for \(ours)")
        }
        for m in unallowed(mismatches, allow: own, used: &usedHere) { Issue.record("\(m)") }
    }
    for e in unusedDecodeEntries(allow, used: used) {
        Issue.record("allowlist entry \(e.scope) \(e.field) (\(e.frames ?? "*")) accepts no mismatch: remove it")
    }
}
