import Foundation
import Testing
@testable import IBKR

// The differential oracle's JSON (Tests/IBKRTests/Oracle, written by Scripts/differential/generate.py) and the
// helpers that compare swift-ibkr with it. Swift reads only this JSON; Python never runs in `swift test`.

/// One wrapper callback ib_async makes: its method name and every argument flattened to `{path: canonical string}`.
struct OracleCall: Equatable, Decodable, Sendable {
    var method: String
    var args: [String: String]
}

/// One frame of decode.json: ib_async's calls for it, or the exception its decoder logged.
struct OracleFrame: Decodable, Sendable {
    var name: String
    var fields: [String]
    var calls: [OracleCall]?
    var error: String?
}

struct OracleDecodeFile: Decodable, Sendable {
    var ibAsync: String
    var serverVersion: Int
    var handlers: [Int]
    var frames: [OracleFrame]
}

/// One argument of an encode.json case (plan decision 10): a scalar as text (`bool` `true`/`false`, `float` its
/// `repr`), a list, a dataclass as an object of all its fields plus `_type`, or `None`.
indirect enum CaseValue: Decodable, Sendable {
    case text(String), list([CaseValue]), object([String: CaseValue]), null

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let s = try? c.decode(String.self) { self = .text(s) }
        else if let l = try? c.decode([CaseValue].self) { self = .list(l) }
        else { self = .object(try c.decode([String: CaseValue].self)) }
    }
}

/// One encode.json case: the `Client` method ib_async ran, every argument it took (`_client`: the `Client` attributes
/// it read), and the fields it sent.
struct EncodeCase: Decodable, Sendable {
    var name: String
    var method: String
    var args: [String: CaseValue]
    var fields: [String]
}

struct OracleEncodeFile: Decodable, Sendable {
    var cases: [EncodeCase]
}

struct CaseError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

/// The arguments of a case, or the fields of one object in it, read by ib_async name and parsed by the Swift type
/// (numbers through `FieldReader.plainDecimal`, never `Double`); `done()` throws on a key nothing read.
struct CaseArgs {
    private let values: [String: CaseValue]
    private let context: String
    private var read: Set<String> = []

    init(_ values: [String: CaseValue], _ context: String) { self.values = values; self.context = context }

    /// An object argument; `type` (when given) must be its `_type`.
    init(_ value: CaseValue, type: String?, _ context: String) throws {
        guard case .object(let o) = value else { throw CaseError("\(context): not an object: \(value)") }
        if let type {
            guard case .text(let t)? = o["_type"], t == type else { throw CaseError("\(context): _type is not \(type)") }
        }
        self.init(o, context)
        read.insert("_type")
    }

    mutating func value(_ key: String) throws -> CaseValue {
        guard let v = values[key] else { throw CaseError("\(context): no \(key)") }
        read.insert(key)
        return v
    }

    mutating func text(_ key: String) throws -> String {
        guard case .text(let s) = try value(key) else { throw CaseError("\(context).\(key): not text") }
        return s
    }

    mutating func int(_ key: String) throws -> Int {
        let s = try text(key)
        guard let i = Int(s) else { throw CaseError("\(context).\(key): not an int: \(s)") }
        return i
    }

    /// A Python `bool` (`true`/`false`).
    mutating func bool(_ key: String) throws -> Bool {
        switch try text(key) {
        case "true": return true
        case "false": return false
        case let s: throw CaseError("\(context).\(key): not a bool: \(s)")
        }
    }

    /// An int flag ib.py passes as 0 or 1.
    mutating func flag(_ key: String) throws -> Bool {
        switch try text(key) {
        case "1": return true
        case "0": return false
        case let s: throw CaseError("\(context).\(key): not 0 or 1: \(s)")
        }
    }

    mutating func decimal(_ key: String) throws -> Decimal {
        let s = try text(key)
        guard let d = FieldReader.plainDecimal(s) else { throw CaseError("\(context).\(key): not a number: \(s)") }
        return d
    }

    mutating func list(_ key: String) throws -> [CaseValue] {
        guard case .list(let l) = try value(key) else { throw CaseError("\(context).\(key): not a list") }
        return l
    }

    /// A value swift-ibkr does not model: it must hold ib_async's default, or the case cannot be built.
    mutating func unmodelled(_ key: String, default expected: String) throws {
        let s = try text(key)
        if s != expected { throw CaseError("\(context).\(key): swift-ibkr does not model it, so it must be «\(expected)», not «\(s)»") }
    }

    /// Throws if the case holds a key nothing read.
    func done() throws {
        let unread = Set(values.keys).subtracting(read)
        if !unread.isEmpty { throw CaseError("\(context): unmapped \(unread.sorted())") }
    }
}

/// An ib_async `Contract` (any subclass): every attribute is read; `description`, which swift-ibkr does not model,
/// must be empty.
func contract(from v: CaseValue) throws -> Contract {
    var a = try CaseArgs(v, type: nil, "contract")
    var c = Contract(symbol: try a.text("symbol"))
    c.secType = try a.text("secType")
    c.exchange = try a.text("exchange")
    c.currency = try a.text("currency")
    c.primaryExchange = try a.text("primaryExchange")
    c.conID = try a.int("conId")
    c.lastTradeDateOrContractMonth = try a.text("lastTradeDateOrContractMonth")
    c.strike = try a.decimal("strike")
    c.right = try a.text("right")
    c.multiplier = try a.text("multiplier")
    c.localSymbol = try a.text("localSymbol")
    c.tradingClass = try a.text("tradingClass")
    c.includeExpired = try a.bool("includeExpired")
    c.secIDType = try a.text("secIdType")
    c.secID = try a.text("secId")
    try a.unmodelled("description", default: "")
    c.issuerID = try a.text("issuerId")
    c.comboLegsDescrip = try a.text("comboLegsDescrip")
    c.comboLegs = try a.list("comboLegs").map { leg in
        var l = try CaseArgs(leg, type: "ComboLeg", "contract.comboLegs[]")
        let action = try l.text("action")
        guard let side = OrderAction(rawValue: action) else { throw CaseError("contract.comboLegs[].action: \(action)") }
        var built = ComboLeg(conID: try l.int("conId"), ratio: 0, action: side, exchange: "")
        built.ratio = try l.int("ratio")
        built.exchange = try l.text("exchange")
        built.openClose = try l.int("openClose")
        built.shortSaleSlot = try l.int("shortSaleSlot")
        built.designatedLocation = try l.text("designatedLocation")
        built.exemptCode = try l.int("exemptCode")
        try l.done()
        return built
    }
    let dnc = try a.value("deltaNeutralContract")
    if case .null = dnc {
        c.deltaNeutralContract = nil
    } else {
        var d = try CaseArgs(dnc, type: "DeltaNeutralContract", "contract.deltaNeutralContract")
        let conID = try d.int("conId"), delta = try d.decimal("delta"), price = try d.decimal("price")
        c.deltaNeutralContract = DeltaNeutralContract(conID: conID, delta: delta, price: price)
        try d.done()
    }
    try a.done()
    return c
}

/// One input frame of corpus.json: `recorded/<file>#<i>`, `fixtures/<name>`, `fakegateway/<name>`,
/// `sweep/<File>.swift:<line>` (`sweep/outgoing/…` for a request body a test built), `sim/<scenario>/<n>`.
struct CorpusFrame: Codable, Sendable {
    var name: String
    var source: String
    var fields: [String]
}

/// One allowlist.json entry (docs/DECISIONS.md, the oracle row; CONTRIBUTING «Differential oracle»).
struct AllowEntry: Decodable, Sendable {
    /// `in <id>` or `out <id>`.
    var scope: String
    /// A dotted path, `[]` for any index (`bar.date`, `order.conditions[].price`), or `#calls`, `#error`,
    /// `#uncovered`, `#count`.
    var field: String
    /// The one frame or case the entry is for, by its exact name (absent only on `#uncovered`).
    var frames: String?
    /// `[ours, theirs]`: only this exact pair is accepted. Every entry but `#uncovered` has it or `equalAsNumbers`.
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

// The oracle's CPU-bound work (reading the JSON, comparing 2000+ frames) runs once and off the cooperative pool: a CI
// runner has two or three pool threads, and timed tests beside it (a 50 ms probe) starve when the oracle holds them.
private let decodeFile = Result { () throws -> OracleDecodeFile in try oracleFile("decode.json") }
private let allowlistFile = Result { () throws -> [AllowEntry] in try oracleFile("allowlist.json") }
private let encodeFile = Result { () throws -> OracleEncodeFile in try oracleFile("encode.json") }
private let corpusFile = Result { () throws -> [CorpusFrame] in try oracleFile("corpus.json") }

func oracleDecode() async throws -> OracleDecodeFile { try await offPool { try decodeFile.get() } }
func oracleAllowlist() async throws -> [AllowEntry] { try await offPool { try allowlistFile.get() } }
func oracleEncode() async throws -> OracleEncodeFile { try await offPool { try encodeFile.get() } }

/// `work` on a thread of its own, so a waiting test task holds no cooperative thread.
func offPool<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { c in Thread { c.resume(with: Result(catching: work)) }.start() }
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
        guard scope == m.scope, field == anyIndex(m.field), frames == m.name else { return false }
        if let pair { return pair == [m.ours, m.theirs] }
        return equalAsNumbers == true && sameNumber(m.ours, m.theirs)
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

private let unsetTexts: Set<String> = ["", "2147483647", "9223372036854775807", "-9223372036854775808",
                                       "1.7976931348623157E308", "1.7976931348623157e+308"]

/// Sentinels fold on ib_async's side only, so a Swift value that kept one still mismatches (Review Focus 2).
private func sameNumber(_ ours: String, _ theirs: String) -> Bool {
    func n(_ s: String) -> String { FieldReader.plainDecimal(s).map { "\($0)" } ?? s }
    return n(ours) == (unsetTexts.contains(theirs) ? "" : n(theirs))
}

/// What is wrong with `entries`: an unknown scope or field word, a bare `*`, an entry (`#uncovered` aside) without one
/// exact frame or case name or without exactly one of `pair` / `equalAsNumbers`, an encode `#count` without its
/// `pair`, an encode entry (not placeOrder) whose field is not an index, `#count` or `#error`, or a citation that does
/// not name exactly one DECISIONS row or Disagreements item. A name that exists nowhere accepts no mismatch, and the
/// oracle tests fail an unused entry.
func allowlistProblems(_ entries: [AllowEntry], decisions: String, protocol178: String) -> [String] {
    let rows = decisions.split(whereSeparator: \.isNewline).filter { $0.hasPrefix("|") }
    let disagreements = protocol178.components(separatedBy: "## Disagreements").dropFirst().joined()
        .split(whereSeparator: \.isNewline)
    var problems: [String] = []
    var rowsCited: [String: Int] = [:]   // by cite: a few dozen distinct ones over 2000+ entries
    for (i, e) in entries.enumerated() {
        func problem(_ s: String) { problems.append("allowlist[\(i)] \(e.scope) \(e.field): \(s)") }
        let scope = e.scope.split(separator: " ")
        if scope.count != 2 || !["in", "out"].contains(scope[0]) || Int(scope[1]) == nil { problem("scope is not `in <id>` or `out <id>`") }
        if e.field.isEmpty || e.field.contains("*") { problem("field is empty or a glob") }
        if e.field.hasPrefix("#"), !["#calls", "#error", "#uncovered", "#count"].contains(e.field) { problem("unknown field word") }
        if e.field != "#uncovered" {
            let exact = e.frames.map { !$0.isEmpty && !$0.contains("*") && !$0.contains("?") } ?? false
            if !exact { problem("an entry names one exact frame or case") }
            if (e.pair != nil) == (e.equalAsNumbers == true) { problem("an entry has exactly one of pair and equalAsNumbers") }
        }
        if e.scope.hasPrefix("out "), e.field == "#count", e.pair == nil { problem("an encode #count entry needs its pair (R23)") }
        // P7: placeOrder alone names a field by its protocol-178 name
        if e.scope.hasPrefix("out "), e.scope != "out 3", Int(e.field) == nil, !["#count", "#error"].contains(e.field) {
            problem("an encode field is an index, #count or #error")
        }
        if let pair = e.pair, pair.count != 2 { problem("pair is not [ours, theirs]") }
        let decision = "DECISIONS: ", disagreement = "protocol-178 Disagreements "
        let hits = rowsCited[e.cite] ?? {
            var hits = -1
            if e.cite.hasPrefix(decision) {
                let text = e.cite.dropFirst(decision.count)
                hits = text.isEmpty ? 0 : rows.filter { $0.contains(text) }.count
            } else if e.cite.hasPrefix(disagreement), let n = Int(e.cite.dropFirst(disagreement.count)) {
                hits = disagreements.filter { $0.hasPrefix("\(n). **") }.count
            }
            rowsCited[e.cite] = hits
            return hits
        }()
        if hits != 1 { problem("cite «\(e.cite)» does not name exactly one row (\(hits == -1 ? "bad form" : "\(hits) rows"))") }
    }
    return problems
}

/// The decode entries (`in …`, not `#uncovered`) that accepted no mismatch.
func unusedDecodeEntries(_ allow: [AllowEntry], used: Set<Int>) -> [AllowEntry] {
    allow.indices.filter { i in
        let e = allow[i]
        guard e.scope.hasPrefix("in "), e.field != "#uncovered" else { return false }
        return !used.contains(i)
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
func expectInCorpus(_ frames: [[String]], source: String, sourceLocation: SourceLocation = #_sourceLocation) async {
    let corpus: [CorpusFrame]
    do { corpus = try await offPool { try corpusFile.get() } } catch {
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
