import Foundation
import Testing
@testable import IBKR

// The differential oracle's JSON (Tests/IBKRTests/Oracle, written by Scripts/differential/generate.py) and the
// helpers that compare swift-ibkr with it. Swift reads only this JSON; Python never runs in `swift test`.

/// One wrapper callback ib_async makes: its method name and every argument flattened to `{path: canonical string}`.
struct OracleCall: Equatable, Decodable {
    var method: String
    var args: [String: String]
}

/// One frame of decode.json: ib_async's calls for it, or the exception its decoder logged.
struct OracleFrame: Decodable {
    var name: String
    var fields: [String]
    var calls: [OracleCall]?
    var error: String?
}

struct OracleDecodeFile: Decodable {
    var ibAsync: String
    var serverVersion: Int
    var handlers: [Int]
    var frames: [OracleFrame]
}

/// One input frame of corpus.json: `recorded/<file>#<i>`, `fixtures/<name>`, `fakegateway/<name>`,
/// `sweep/<File>.swift:<line>` (`sweep/outgoing/…` for a request body a test built), `sim/<scenario>/<n>`.
struct CorpusFrame: Codable {
    var name: String
    var source: String
    var fields: [String]
}

/// One allowlist.json entry (docs/DECISIONS.md, the oracle row; CONTRIBUTING «Differential oracle»).
struct AllowEntry: Decodable {
    /// `in <id>` or `out <id>`.
    var scope: String
    /// A dotted path, `[]` for any index (`bar.date`, `order.conditions[].price`), or `#calls`, `#error`,
    /// `#uncovered`, `#count`.
    var field: String
    /// A glob over frame or case names; `*` when absent.
    var frames: String?
    /// `[ours, theirs]`: only this exact pair is accepted. Without it (and `equalAsNumbers`) the field is not compared.
    var pair: [String]?
    /// The two texts are accepted when they are the same number (IB's unset markers equal `""`).
    var equalAsNumbers: Bool?
    /// `protocol-178 Disagreements <n>` or `DECISIONS: <verbatim text of exactly one row>`.
    var cite: String
    /// Anything the citation leaves out, e.g. the ib_async line that does it.
    var note: String?
}

/// `Oracle/<name>` beside the calling test file.
func oracleFile<T: Decodable>(_ name: String, file: String = #filePath) throws -> T {
    let url = URL(fileURLWithPath: file).deletingLastPathComponent().appendingPathComponent("Oracle/\(name)")
    return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
}

// The canonical form never folds a sentinel: a Swift value that kept IB's 2147483647 shows as a mismatch.
func canon(_ d: Decimal?) -> String { d.map { "\($0)" } ?? "" }
func canon(_ i: Int?) -> String { i.map(String.init) ?? "" }
func canon(_ b: Bool) -> String { b ? "true" : "false" }
func canon(_ t: Date?) -> String {
    t.map { canon(Decimal(string: "\($0.timeIntervalSince1970)", locale: Locale(identifier: "en_US_POSIX"))) } ?? ""
}

struct Mismatch: CustomStringConvertible {
    var name, scope, field, ours, theirs: String
    var description: String { "\(name) \(scope) \(field): ours \(ours) ib_async \(theirs)" }
}

/// The mismatches between our calls and ib_async's that no allowlist entry accepts; `used` collects the indices of
/// the entries that accepted one. Keys are compared over the union: a key on one side only is `<absent>` on the other.
func compare(_ ours: [OracleCall], _ theirs: [OracleCall], name: String, scope: String, allow: [AllowEntry],
             used: inout Set<Int>) -> [Mismatch] {
    var found: [Mismatch] = []
    if ours.map(\.method) != theirs.map(\.method) {
        found.append(Mismatch(name: name, scope: scope, field: "#calls", ours: "\(ours.map(\.method))",
                              theirs: "\(theirs.map(\.method))"))
    } else {
        for (o, t) in zip(ours, theirs) {
            for key in Set(o.args.keys).union(t.args.keys).sorted() {
                let a = o.args[key] ?? "<absent>", b = t.args[key] ?? "<absent>"
                if a != b { found.append(Mismatch(name: name, scope: scope, field: key, ours: a, theirs: b)) }
            }
        }
    }
    return unallowed(found, allow: allow, used: &used)
}

/// `mismatches` minus those an entry accepts.
func unallowed(_ mismatches: [Mismatch], allow: [AllowEntry], used: inout Set<Int>) -> [Mismatch] {
    mismatches.filter { m in
        guard let i = allow.indices.first(where: { allow[$0].accepts(m) }) else { return true }
        used.insert(i)
        return false
    }
}

extension AllowEntry {
    func accepts(_ m: Mismatch) -> Bool {
        guard scope == m.scope, field == anyIndex(m.field), globMatches(frames ?? "*", m.name) else { return false }
        if let pair { return pair == [m.ours, m.theirs] }
        if equalAsNumbers == true { return sameNumber(m.ours, m.theirs) }
        return true
    }
}

/// `a[3].b[0]` → `a[].b[]`.
private func anyIndex(_ path: String) -> String {
    var out = "", inIndex = false
    for c in path {
        if inIndex { if c == "]" { out.append("]"); inIndex = false }; continue }
        out.append(c)
        if c == "[" { inIndex = true }
    }
    return out
}

/// `*` matches any run of characters, `?` one character.
func globMatches(_ pattern: String, _ s: String) -> Bool {
    let p = Array(pattern), t = Array(s)
    func match(_ i: Int, _ j: Int) -> Bool {
        if i == p.count { return j == t.count }
        if p[i] == "*" { return (j...t.count).contains { match(i + 1, $0) } }
        return j < t.count && (p[i] == "?" || p[i] == t[j]) && match(i + 1, j + 1)
    }
    return match(0, 0)
}

private let unsetTexts: Set<String> = ["", "2147483647", "9223372036854775807", "-9223372036854775808",
                                       "1.7976931348623157E308", "1.7976931348623157e+308"]

/// Sentinels fold on ib_async's side only, so a Swift value that kept one still mismatches (Review Focus 2).
private func sameNumber(_ ours: String, _ theirs: String) -> Bool {
    func n(_ s: String) -> String { FieldReader.plainDecimal(s).map { "\($0)" } ?? s }
    return n(ours) == (unsetTexts.contains(theirs) ? "" : n(theirs))
}

/// What is wrong with `entries`: an unknown scope or field word, a bare `*`, a bare placeOrder index across every
/// case, or a citation that does not name exactly one DECISIONS row or Disagreements item.
func allowlistProblems(_ entries: [AllowEntry], decisions: String, protocol178: String) -> [String] {
    let rows = decisions.split(whereSeparator: \.isNewline).filter { $0.hasPrefix("|") }
    let disagreements = protocol178.components(separatedBy: "## Disagreements").dropFirst().joined()
        .split(whereSeparator: \.isNewline)
    var problems: [String] = []
    for (i, e) in entries.enumerated() {
        func problem(_ s: String) { problems.append("allowlist[\(i)] \(e.scope) \(e.field): \(s)") }
        let scope = e.scope.split(separator: " ")
        if scope.count != 2 || !["in", "out"].contains(scope[0]) || Int(scope[1]) == nil { problem("scope is not `in <id>` or `out <id>`") }
        if e.field.isEmpty || e.field.contains("*") { problem("field is empty or a glob") }
        if e.field.hasPrefix("#"), !["#calls", "#error", "#uncovered", "#count"].contains(e.field) { problem("unknown field word") }
        if e.scope == "out 3", Int(e.field) != nil, (e.frames ?? "*") == "*" { problem("a bare placeOrder index needs a case glob") }
        if let pair = e.pair, pair.count != 2 { problem("pair is not [ours, theirs]") }
        if e.pair != nil, e.equalAsNumbers == true { problem("pair and equalAsNumbers together") }
        let decision = "DECISIONS: ", disagreement = "protocol-178 Disagreements "
        var hits = -1
        if e.cite.hasPrefix(decision) {
            let text = e.cite.dropFirst(decision.count)
            hits = text.isEmpty ? 0 : rows.filter { $0.contains(text) }.count
        } else if e.cite.hasPrefix(disagreement), let n = Int(e.cite.dropFirst(disagreement.count)) {
            hits = disagreements.filter { $0.hasPrefix("\(n). **") }.count
        }
        if hits != 1 { problem("cite «\(e.cite)» does not name exactly one row (\(hits == -1 ? "bad form" : "\(hits) rows"))") }
    }
    return problems
}

/// The decode entries (`in …`, not `#uncovered`, not for a pending id) that accepted no mismatch.
func unusedDecodeEntries(_ allow: [AllowEntry], used: Set<Int>, pending: Set<Int>) -> [AllowEntry] {
    allow.indices.filter { i in
        let e = allow[i]
        guard e.scope.hasPrefix("in "), e.field != "#uncovered", let id = Int(e.scope.dropFirst(3)) else { return false }
        return !pending.contains(id) && !used.contains(i)
    }.map { allow[$0] }
}

/// docs/DECISIONS.md and docs/protocol-178.md, for the citation check.
func oracleDocs(file: String = #filePath) throws -> (decisions: String, protocol178: String) {
    let docs = URL(fileURLWithPath: file).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("docs")
    return (try String(contentsOf: docs.appendingPathComponent("DECISIONS.md"), encoding: .utf8),
            try String(contentsOf: docs.appendingPathComponent("protocol-178.md"), encoding: .utf8))
}

/// Records one issue per frame missing from corpus.json, with the entry to paste.
func expectInCorpus(_ frames: [[String]], source: String, sourceLocation: SourceLocation = #_sourceLocation) {
    let corpus: [CorpusFrame]
    do { corpus = try oracleFile("corpus.json") } catch {
        Issue.record("cannot read Tests/IBKRTests/Oracle/corpus.json: \(error)", sourceLocation: sourceLocation)
        return
    }
    let known = Set(corpus.map(\.fields))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    for (i, f) in frames.enumerated() where !known.contains(f) {
        let entry = CorpusFrame(name: frames.count == 1 ? source : "\(source)#\(i)",
                                source: String(source.prefix { $0 != "/" }), fields: f)
        let json = (try? encoder.encode(entry)).map { String(decoding: $0, as: UTF8.self) } ?? "\(f)"
        let run = "`python -I Scripts/differential/generate.py`"
        Issue.record("frame missing from Tests/IBKRTests/Oracle/corpus.json: add \(json), then run \(run)",
                     sourceLocation: sourceLocation)
    }
}
