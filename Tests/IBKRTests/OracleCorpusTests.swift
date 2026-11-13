import Foundation
import Testing
@testable import IBKR

// The oracle's inputs: every frame the tests build is in corpus.json, and every corpus frame has ib_async's answer.

@Test func everyRecordedFrameIsInTheCorpus() throws {
    for name in recordings { expectInCorpus(try recording(name), source: "recorded/\(name).json") }
}

@Test func everyFixtureFrameIsInTheCorpus() {
    for f in Fixtures.corpusFrames { expectInCorpus([f.fields], source: "fixtures/\(f.name)") }
}

@Test func everyCorpusFrameHasAnOracleAnswer() throws {
    let corpus: [CorpusFrame] = try oracleFile("corpus.json")
    let answers = Dictionary(try (oracleFile("decode.json") as OracleDecodeFile).frames.map { ($0.name, $0.fields) },
                             uniquingKeysWith: { a, _ in a })
    #expect(Set(corpus.map(\.name)).count == corpus.count, "corpus names are unique")
    #expect(Set(corpus.map(\.fields)).count == corpus.count, "corpus frames are unique")
    for c in corpus where answers[c.name] != c.fields {
        Issue.record("\(c.name) has no up-to-date answer in decode.json: run `python -I Scripts/differential/generate.py`")
    }
}

@Test func oracleRunsIbAsync210At178() throws {
    let file: OracleDecodeFile = try oracleFile("decode.json")
    #expect(file.ibAsync == "2.1.0")
    #expect(file.serverVersion == 178)
    #expect(file.handlers.count == 82)
}

/// C6: every message ib_async decodes at 178 has a frame it accepts, unless an `#uncovered` entry says why not. A
/// request body (`sweep/outgoing/…`) is not a frame of the incoming message that shares its id.
@Test func everyHandlerHasACorpusEntry() throws {
    let file: OracleDecodeFile = try oracleFile("decode.json")
    let allow: [AllowEntry] = try oracleFile("allowlist.json")
    let covered = Set(file.frames.filter { $0.error == nil && !$0.name.hasPrefix("sweep/outgoing/") }
        .compactMap { Int($0.fields[0]) })
    let excused = Set(allow.filter { $0.field == "#uncovered" }.map(\.scope))
    for scope in excused where !file.handlers.contains(where: { "in \($0)" == scope }) {
        Issue.record("\(scope): an #uncovered entry names an id that has no handler")
    }
    for id in file.handlers {
        if !covered.contains(id) && !excused.contains("in \(id)") {
            Issue.record("in \(id) has no frame ib_async accepts: add one to Scripts/differential/variants.py")
        }
        if covered.contains(id) && excused.contains("in \(id)") { Issue.record("in \(id): unused #uncovered entry") }
    }
    #expect(!file.frames.contains { $0.name.hasPrefix("sweep/outgoing/") }, "request bodies are not decode inputs (R14)")
}
