# Stage 15: Differential Oracle and Scenario Simulator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every incoming message ib_async 2.1.0 decodes and every request swift-ibkr sends is cross-checked against
ib_async itself, run offline, and a stateful simulated broker drives the real `IBClient` through order, account,
reconnect and multi-client scenarios with frames that same oracle has decoded.

**Architecture:** A deterministic Python generator (`Scripts/differential/`) feeds frames to ib_async's `Decoder`
with a recording wrapper and captures what ib_async's `Client` methods send, and writes both as committed JSON under
`Tests/IBKRTests/Oracle/`. Swift tests read only that JSON: they decode each frame with `IBDecoder`, map the result
to ib_async's names through an explicit per-message mapping, and compare; they build each encode case's
`IBRequest` through an explicit mapping and compare `body()` with ib_async's fields. Mismatches are fixed (our bug)
or allowlisted with a citation (a recorded deliberate difference); anything else stops for a ruling. Part 2 adds
`SimulatedBroker`, a stateful layer that composes `FakeGateway`, and scenario tests whose every emitted frame must be
in the oracle's corpus.

**Tech Stack:** Swift 6 (tools 6.0), SwiftPM, Swift Testing; Python 3.12 with ib_async 2.1.0 (generator and one CI
job only, never a package dependency); GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-12-parity-and-1.0-design.md`, section «Stage 15 — differential oracle and
scenario simulator» (added in this plan's commit), with its «Анти-цели» and «Проверка». The controller's brief
(`stage-15-controller-brief.md`, «Why», «Part 1», «Part 2», «Documents of record», «Standing rules») and the
rulings C1–C7 below are binding.

## Global Constraints

- Repository `C:\Users\viohn\swift-ibkr`, branch `stage-15-differential` (cut from `main` 15ceae2). Push only that
  branch; never touch `main`, never tag, never open the PR. No version bump (podspec stays as it is).
- No dependency in `Package.swift`. The only `Package.swift` change allowed: `"Oracle"` joins the test target's
  `exclude` list beside `"Recorded"`. Python and ib_async are never needed by `swift build` or `swift test`.
- Public API changes only when a bug found by the oracle requires one; it is then listed under CHANGELOG
  `[Unreleased]` as **Breaking**. Everything new in this stage lives in `Tests/`, `Scripts/differential/`,
  `.github/workflows/ci.yml` and the documents.
- ib_async runs only through the generator, as `<venv>/Scripts/python -I` locally and `python -I` in CI. It never
  calls `connect`/`run`/`connectAsync`, never opens a socket (ruling C3). No code of ib_async or of IB's `ibapi` is
  copied into `Sources/`; generator output is data.
- Account ids: `DU0000001` (recordings and simulator), `DU1`, `DU123456` (existing fixtures). the real-account-id `git grep` from the stage brief is
  empty before every push.
- Tests: `timeout 900 swift test`, in the foreground, before every commit (stage 14 ended at 635 + 18). Oracle tests
  are synchronous. A scenario test waits on any async event through `within2s` (`Tests/IBKRTests/Helpers.swift`,
  guarded by `Within2sTests.swift`); injected delays are tens of milliseconds, never seconds.
- Every commit leaves the full suite green: the staged sets of Task 1 and Task 9 keep the coverage tests honest
  while families are still unmapped.
- Commits: one imperative sentence, then the reasoning (read `git log -5` first). Last line exactly
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Documents of record change in the same commit as the behaviour they describe: README («Status» rows and the
  testing paragraphs under «Development»), `docs/KNOWN-GAPS.md`, `docs/protocol-178.md` («Disagreements»),
  `docs/DECISIONS.md`, `CONTRIBUTING.md`, CHANGELOG `## [Unreleased]`. KNOWN-GAPS: a «hand-built frames only» claim
  the oracle now covers becomes «cross-checked against ib_async 2.1.0, unseen live»; live items stay.
- Wire arrays in this plan were checked by running ib_async 2.1.0 offline (probe scripts outside the repo). Where a
  plan array and the generator disagree, the generator wins and the implementer reports it.

### The oracle loop (every decode and encode task runs it)

1. Remove the task's ids (decode) or ib_async methods (encode) from the staged set; run the family's tests: RED
   (no mapping).
2. Write the mapping; regenerate (`python -I Scripts/differential/generate.py`); run: each remaining failure is one
   mismatch, reported as `<frame or case name> <scope> <field>: ours <x> ib_async <y>`.
3. Classify each mismatch (ruling C5):
   - **Our bug** → a RED codec test in the existing `*CodecTests.swift` / `DecoderTests.swift` / `RequestTests.swift`
     / `PlaceOrderTests.swift` / `OpenOrderTests.swift` file that fails against the old code, then the fix in
     `Sources/`, then GREEN. CHANGELOG `### Fixed`.
   - **A recorded deliberate difference** (a `docs/protocol-178.md` «Disagreements» row or a `docs/DECISIONS.md`
     row says so) → one allowlist entry citing that row. Never «fix» toward ib_async against live evidence or a
     recorded decision.
   - **Neither** → STOP. Report `NEEDS_CONTEXT` with the frame, both values and the ib_async line; the controller
     rules and adds the Disagreements row; then the allowlist entry cites it.
4. Full `timeout 900 swift test`; documents; commit.

## Controller rulings (binding)

- **C1** Decode compares the decoder's output (one frame → swift-ibkr's `IBMessage`) with the wrapper callbacks
  ib_async's `Decoder` makes for the same fields (recorded by a recording wrapper), both normalised to canonical JSON
  (ib_async field name → string) through an explicit per-message mapping in the Swift test target. Tracker state
  (order/position merging) is above the wire and belongs to the Part 2 scenarios, not the oracle.
- **C2** Inputs are committed; the generator is deterministic and Python-only. Frames the Swift tests build
  (`Fixtures.swift`, `Recorded/`, inline codec-test frames, the simulator's frames) live in a committed corpus JSON;
  a Swift test fails, naming the frame and how to add it, on any Fixtures/Recorded/simulator frame missing from it.
  Inline codec-test frames are swept once by a scratch script. The generator adds its own variants (unset values:
  empty and MAX; nested counts 0/1/n; every tick type; every message-version/optional branch at 178) written from
  ib_async's decoder source. Generator output (expected decodes, expected encodes) is committed JSON under `Tests/`;
  Swift tests read only JSON. A new CI job (ubuntu-latest, `actions/setup-python`, Python 3.12) installs
  `Scripts/differential/requirements.txt` (ib_async==2.1.0 pinned), regenerates, and fails on `git diff --exit-code`.
- **C3** The harness is network-free by construction: no connect/run; the client's send path is replaced to capture
  fields; serverVersion is forced to 178; `socket.socket` (and asyncio's connection factories) are replaced with
  something that raises, so an accidental network call fails the generator.
- **C4** Encode compares, case by case, ib_async's captured field list with swift-ibkr's for the same inputs, as
  exact strings. Cases are defined once, in the generator, with ib_async attribute names; the Swift test builds the
  same request from the committed case JSON through an explicit, reviewed mapping.
- **C5** Mismatches: our bug → RED test first, then the fix; a recorded deliberate difference → one allowlist entry
  citing the exact Disagreements or DECISIONS row; a new difference with neither → the implementer stops and reports
  `NEEDS_CONTEXT` with evidence, the controller rules and adds a Disagreements row. The allowlist is a committed file
  whose every entry has a non-empty citation, checked by a test.
- **C6** A coverage test enumerates the handler-id table recorded in the generator output (ib_async's `Decoder`
  handlers at 178) and fails on any id with no corpus entry and no allowlist entry naming why.
- **C7** The simulator is a stateful layer in the test target that drives the existing `FakeGateway` (composition,
  not a fork), and every frame it emits is checked against the corpus by the C2 test.

## Decisions beyond the spec (recorded in DECISIONS in the task named)

1. **Counts (verified by running ib_async 2.1.0).** `len(Decoder(w, 178).handlers) == 82`: ids 1–21, 45–47, 49–59,
   61–107 (decoder.py:47-141). swift-ibkr's `IBRequest` has 80 cases, one per ib_async send site (out 1–25,
   49–104); the handshake hello is not a `send()` and stays outside the oracle (Disagreements 7 covers it).
2. **Files (Task 1, Task 9).** `Scripts/differential/generate.py` (harness, canonical form, I/O), `variants.py`
   (decode variants per handler id), `cases.py` (encode cases), `requirements.txt`, `README.md`.
   `Tests/IBKRTests/Oracle/`: `corpus.json` (input frames, edited by hand, the sweep and the simulator),
   `decode.json` and `encode.json` (generator output, never edited by hand), `allowlist.json` (hand). The Swift
   files stay flat beside the other tests: `OracleSupport.swift`, `OracleCorpusTests.swift`,
   `OracleDecodeTests.swift`, `OracleDecode+<Family>.swift`, `OracleEncodeTests.swift`, `OracleEncode+<Family>.swift`,
   `SimulatedBroker.swift`, `Scenario<Family>Tests.swift`. JSON is read through `#filePath`, as `recording(_:)` reads
   `Recorded/`.
3. **Recording wrapper (Task 1).** An object whose `__getattr__` returns a recorder for any method name (so the 9
   methods `Wrapper` lacks — `displayGroupList`, `displayGroupUpdated`, `replaceFAEnd`, `rerouteMktDataReq`,
   `rerouteMktDepthReq`, `verifyMessageAPI`, `verifyCompleted`, `verifyAndAuthMessageAPI`, `verifyAndAuthCompleted` —
   are still recorded), with `defaultTimezone = datetime.timezone.utc` and `ib.TimezoneTWS = None`
   (decoder.py:466-474, 788, 809, 830 read them), so execution and tick times resolve as swift-ibkr's do with
   `gatewayTimeZone` nil. Argument names come from `inspect.signature(Wrapper.<method>)` (leading `_` kept, e.g.
   `_reqId`); the 9 missing methods name their arguments `_1`, `_2`, … `interpret` swallows exceptions
   (decoder.py:176-183) and so does `wrap` (143-174): a handler on logger `ib_async.Decoder` turns any logged
   exception for a frame into `"error": "<message>"`, and the Swift side must then decode that frame `.malformed`.
4. **Network guard (Task 1, C3).** Installed right after `import ib_async`: asyncio's `ssl` subclasses
   `socket.socket` at import, so a plain function in its place breaks the import (verified). `socket.socket` becomes
   a subclass whose `__init__` raises; `socket.create_connection`, `socket.socketpair`,
   `asyncio.BaseEventLoop.create_connection` / `create_server` / `create_unix_connection`, `asyncio.open_connection`
   raise too. The generator asserts at start that `socket.socket()` raises.
5. **Canonical form (Task 1).** A frame's oracle answer is a list of calls `{"method": m, "args": {path: string}}`.
   Flattening: a dataclass → `<path>.<field>` for every dataclass field; a list or tuple → `<path>.#` (count) and
   `<path>[i]…`; a set → sorted, then as a list; `None` → `""`. Scalars: `str` as is; `bool` → `"true"`/`"false"`
   (checked before `int`); `int` → decimal text, except 2147483647, 9223372036854775807 and -9223372036854775808 →
   `""`; `float` → `""` for 1.7976931348623157e308 and NaN, `"Infinite"`/`"-Infinite"` for ±∞, else
   `format(Decimal(repr(x)).normalize(), "f")` with `"-0"` → `"0"` (so `100.0` → `"100"`, `1e-05` → `"0.00001"`);
   `datetime` → epoch seconds in the same number form. The Swift side never folds sentinels: `Decimal` → the same
   plain form, `Int` → decimal text, `Bool` → `"true"`/`"false"`, `Date` → epoch seconds, `nil` → `""`. So a Swift
   value that kept a sentinel still shows as a mismatch. Encode compares raw field strings, no canonical form.
6. **Corpus (Task 1, C2).** `corpus.json` is `[{"name", "source", "fields"}]`, unique by `fields`. Names:
   `recorded/<file>#<index>`, `fixtures/<name>`, `fakegateway/<name>`, `sweep/<File>.swift:<line>`,
   `sim/<scenario>/<n>`. Generator variants are not in `corpus.json`; they are named `gen/<id>/<variant>` in
   `decode.json`. Fixture frames cannot be enumerated by reflection, so `Fixtures.corpusFrames` (in
   `Fixtures.swift`, beside the builders) lists the calls the codec tests make; a new builder joins that list (a
   reviewer check). The inline sweep is one scratch run (not committed): `body(_ fields: [String])` in
   `Fixtures.swift` temporarily appends `(#fileID, #line, fields)` to a file during a full test run; frames whose
   first field is a handler id and that `IBDecoder` decodes to neither `.malformed` nor `.unknown` are added,
   deduplicated.
7. **Allowlist (Task 1, C5).** `allowlist.json` is `[{"scope", "field", "frames"?, "pair"?, "equalAsNumbers"?,
   "cite"}]`. `scope` is one message (`"in 17"`, `"out 20"`); `field` a dotted path with `[]` for any index (`bars[].date`),
   `#calls` (ib_async makes a different number of calls), `#error` (one side rejects the frame) or `#uncovered`
   (C6); `frames` a glob over frame or case names (default `*`); `pair` `[ours, theirs]` accepts only that exact
   pair, and without it the field is not compared; `equalAsNumbers` (encode only) compares `"1"` and `"1.0"` as
   equal. `cite` is `protocol-178 Disagreements <n>` or `DECISIONS: <verbatim substring of one row>`. Tests: every
   cite resolves (the Disagreements item `<n>. **` exists; the substring occurs in `docs/DECISIONS.md`); `field` is
   never a bare `*`; every entry matches at least one mismatch (an unused entry fails, so the list cannot rot or
   pre-widen).
8. **Staging (Tasks 1, 8, 9, 12).** `OracleDecodeTests.swift` holds `let pendingDecodeIDs: Set<Int>`, initially the
   77 ids Task 1 does not map; comparison and C6 skip them. Each decode task removes its ids; Task 8 deletes the
   constant. `OracleEncodeTests.swift` holds `let pendingRequestMethods: Set<String>` the same way, deleted by
   Task 12.
9. **Encode capture (Task 9, C3, C4).** `c = Client(wrapper)`, `c._serverVersion = 178`,
   `c.connState = Client.CONNECTED` (`send` refuses otherwise, client.py:245-252), `c.sendMsg = capture` (an
   instance attribute; `send` ends in `self.sendMsg(generated)`, client.py:321), capture splits on `\0` and drops the
   last empty element. Verified: `reqMktData(7, Stock("AAPL","SMART","USD"), "", False, False, [])` → 20 fields,
   `LimitOrder("BUY", 1, 351.5)` placeOrder → 114 fields, `cancelOrder(5, "")` → `["4","1","5",""]`. Cases call
   `Client` methods with the arguments `ib.py` would pass (dates through `util.formatIBDatetime`, ib.py:2353, 2385,
   2414-2415; util.py:574-590); each case names the ib.py line it imitates when it prepares an argument.
10. **Case serialization (Task 9).** `encode.json` is `{"cases": [{"name", "method", "args", "fields"}]}`. `args`
    holds every argument; scalars as JSON strings (`str` as is, `bool` `"true"`/`"false"`, `int` `str()`, `float`
    `repr()` so `"100.0"` stays visible), `None` as `null`, a dataclass as an object of **all** its fields plus
    `"_type"` (the class name, e.g. `PriceCondition`), a list as an array. The Swift mapping parses each attribute by
    its Swift type (`Decimal(string:)`, `Int(_:)`), never through `Double`, and fails on an unknown key; an attribute
    swift-ibkr does not model must hold ib_async's default or the case fails (`sharesAllocation`).
11. **Exhaustiveness (Task 9).** `ibAsyncMethod(_ r: IBRequest) -> String` in `OracleEncodeTests.swift` is an
    exhaustive `switch` over `IBRequest`; each case asserts `ibAsyncMethod(built) == case.method`, so a new
    `IBRequest` case does not compile until it is mapped.
12. **Requirements (Task 1).** `requirements.txt` pins ib_async and the four packages it pulls, at the versions the
    local venv holds: `aeventkit==2.1.0`, `ib_async==2.1.0`, `nest-asyncio==1.6.0`, `numpy==2.5.4`,
    `tzdata==2025.3` (a floating dependency could change the regenerated JSON between runs).
13. **Determinism (Task 1).** Output in corpus order, then variants by id, then cases in `cases.py` order;
    `json.dumps(…, indent=1, sort_keys=True, ensure_ascii=False)`, written with `newline="\n"`, one trailing
    newline. `generate.py` puts its own directory on `sys.path` (`-I` leaves it off).
14. **Simulator (Task 13, C7).** `SimulatedBroker` hands out one `FakeGateway` per connect, wired through
    `onRequest` (replies fed before `FakeGateway`'s own end markers) and `feed` (unsolicited frames). `FakeGateway`
    gains one additive member, `fed: [[String]]` (every frame passed to `feed`, the hello reply excluded), so «every
    frame it emits» includes `FakeGateway`'s defaults. Order, fill and cancel sequences copy the recorded live ones
    (`Recorded/liveLimitOrderPlacesAndCancels.json`: openOrder + orderStatus PreSubmitted; cancel → openOrder +
    PendingCancel twice, Cancelled, error 202; `liveOrderFillsWithCommission.json`: openOrder + PreSubmitted, openOrder
    + Submitted, position, execDetails, openOrder + Filled twice, commissionReport). Sequences with no recording
    (bracket, OCA, reject, what-if, multi-client) are assumptions, marked `// assumption: unrecorded live` and
    listed in KNOWN-GAPS. Times, permIDs and execIds come from counters, so every scenario emits the same frames on
    every run.
15. **«Over the socket» (Task 13).** Scenarios run through the real `IBClient` built with
    `IBClient(connector: broker.connector)`: framed bytes through `Frame`, `FieldReader` and the client's reader
    task, exactly as `FakeGateway` tests do. No loopback TCP listener (see «Decisions for the controller» 1).

## Decisions for the controller

1. **«Over the socket».** C7 says drive `FakeGateway`, which is a `Transport`, not a TCP socket. The plan runs the
   scenarios over the `Transport` seam (decision 15). If a real loopback socket is wanted, Task 13 needs a listener
   helper and the 2 s budget gets tighter on Windows (DECISIONS: the loopback SYN row).
2. **displaySize is not a recorded row.** The brief lists it as «recorded», but only KNOWN-GAPS (the modify line)
   says swift-ibkr decodes `2147483647` to `0` and re-sends `"0"` where ib_async sends `""`. Task 4 (decode) and
   Task 10 (encode, the modify-from-recording case) will hit it; a Disagreements row is needed to cite.
3. **tickPrice with an empty price.** ib_async calls nothing (`if price:`, decoder.py:200-206; verified with
   `["1","6","7","66","","0","0"]`); swift-ibkr yields `.tick(.price(…, price: nil, …))`. No row covers it; Task 5
   will stop on it.
4. **historicalData's start and end.** swift-ibkr skips them (IBDecoder.swift:59); ib_async passes them to
   `historicalDataEnd(reqId, _start, _end)`. No row; Task 6 will stop on it.
5. **Date text in requests.** swift-ibkr sends `yyyyMMdd-HH:mm:ss` (UTC) for historicalData's end and both
   historicalTicks dates; `ib.py` sends `yyyyMMdd HH:mm:ss UTC`. DECISIONS row «`historicalTicks(…)` returns
   `[TickByTick]`…» records it for historicalTicks only. Task 11 will stop on historicalData unless that row is
   widened first.
6. **Wrapper-level conversions are above the oracle.** ib_async turns the greeks' -1/-2 into `None` in the wrapper,
   not the decoder; swift-ibkr does it in the decoder. The plan cites DECISIONS row «tickOptionComputation (21) turns
   IB's "not computed" into `nil`» with `pair` entries; confirm that a row describing the wrapper's behaviour is an
   acceptable citation for a decoder-level difference.
7. **Requirements pin.** C2 pins ib_async; decision 12 also pins its four dependencies. Confirm.
8. **CHANGELOG for test-only work.** The plan adds one `### Added` line for the oracle (Task 1) and one for the
   simulator (Task 13), and `### Fixed` lines for bugs. Say if test infrastructure should stay out of CHANGELOG.

## Review Focus

1. **A frame ib_async rejects.** If ib_async logs an exception, the oracle must say so, not record «no calls» and
   so agree with a Swift decode that silently produced a value. Test: Task 1 `oracleRecordsIbAsyncExceptions`
   (the generator's canary `gen/canary/short-openOrder`, `["5","1"]`, carries `error`, and Swift decodes it
   `.malformed`).
2. **A Swift value that kept a sentinel.** The Python side folds sentinels to `""`; the Swift side must not, or a
   decoder that returns `2147483647` would pass. Test: Task 1 `swiftCanonicalNeverFoldsSentinels`.
3. **Line endings and platform data in regenerated JSON.** A Windows-generated `decode.json` must equal the Linux CI
   regeneration byte for byte (CRLF, float repr, zone data). Test: the CI job itself; Task 1 runs the generator
   twice and diffs locally, and `generate.py` writes with `newline="\n"`.
4. **An allowlist entry that widens silently.** A bare `*` field, an entry no mismatch uses, or a citation that no
   longer exists in the docs. Test: Task 1 `allowlistEntriesAreNarrowCitedAndUsed`.
5. **A simulator frame that varies between runs.** It would show as a flaky «missing from corpus». Test: Task 13
   runs `swift test --filter Scenario` three times and diffs `broker.emitted` dumps; Task 15 repeats it with the
   multi-client and reconnect scenarios.

---

### Task 1: Oracle harness, corpus and session decode (in 4, 9, 15, 49, 107) — opus

**Files:**
- Create: `Scripts/differential/generate.py`, `Scripts/differential/variants.py`,
  `Scripts/differential/requirements.txt`, `Scripts/differential/README.md`
- Create: `Tests/IBKRTests/Oracle/corpus.json`, `decode.json` (generated), `allowlist.json` (`[]` to start)
- Create: `Tests/IBKRTests/OracleSupport.swift`, `OracleCorpusTests.swift`, `OracleDecodeTests.swift`,
  `OracleDecode+Session.swift`
- Modify: `Package.swift` (exclude `"Oracle"`), `Tests/IBKRTests/Fixtures.swift` (`Fixtures.corpusFrames`),
  `.github/workflows/ci.yml` (job `oracle`)
- Docs: DECISIONS (one row: the oracle — runs ib_async 2.1.0 offline in the generator only; compares at the
  decoder/wrapper-callback layer (C1); canonical form; committed JSON; allowlist with citations; CI regenerates —
  why: frames and code came from one reading of ib_async, so a mock from that reading is circular | rejected:
  hand-built frames only, Python in `swift test`, comparing at the `Ticker`/tracker layer, an uncited allowlist);
  CONTRIBUTING (a «Differential oracle» section: set up the venv from `requirements.txt`, regenerate, add a frame to
  `corpus.json`, add an allowlist entry and what it must cite; «IB's code» gains: ib_async runs only in the
  generator, offline); README «Development» (one paragraph: the oracle, what it covers, how to regenerate);
  CHANGELOG `### Added` (the oracle, test-only)

**Interfaces:**
- Produces (Python): `canon(value) -> str | dict` and `flatten(prefix, value) -> dict[str, str]` per decision 5;
  `record(fields: list[str]) -> {"calls": [...]} | {"error": str}`; `VARIANTS: dict[int, list[tuple[str, list[str]]]]`
  in `variants.py`; `main()` writing `decode.json` = `{"ibAsync": "2.1.0", "serverVersion": 178,
  "handlers": [1, …, 107], "frames": [{"name", "fields", "calls" | "error"}]}`.
- Produces (Swift, `OracleSupport.swift`):
  - `struct OracleCall: Equatable, Decodable { var method: String; var args: [String: String] }`
  - `struct OracleFrame: Decodable { var name: String; var fields: [String]; var calls: [OracleCall]?; var error: String? }`
  - `struct OracleDecodeFile: Decodable { var ibAsync: String; var serverVersion: Int; var handlers: [Int]; var frames: [OracleFrame] }`
  - `struct CorpusFrame: Codable { var name: String; var source: String; var fields: [String] }`
  - `struct AllowEntry: Decodable { var scope: String; var field: String; var frames: String?; var pair: [String]?; var equalAsNumbers: Bool?; var cite: String }`
  - `func oracleFile<T: Decodable>(_ name: String, file: String = #filePath) throws -> T` (reads `Oracle/<name>`)
  - `func canon(_ d: Decimal?) -> String`, `canon(_ i: Int?)`, `canon(_ b: Bool)`, `canon(_ t: Date?)`
  - `struct Mismatch: CustomStringConvertible { var name, scope, field, ours, theirs: String }`
  - `func compare(_ ours: [OracleCall], _ theirs: [OracleCall], name: String, scope: String, allow: [AllowEntry], used: inout Set<Int>) -> [Mismatch]`
  - `func expectInCorpus(_ frames: [[String]], source: String, sourceLocation: SourceLocation = #_sourceLocation)`
    (records one `Issue` per frame not in `corpus.json`, with a ready-to-paste entry)
- Produces (`OracleDecodeTests.swift`): `func ibAsyncCalls(id: Int, _ m: IBMessage) -> [OracleCall]?` dispatching to
  one `<family>Calls(id:_:)` per family file (`nil` = not mapped); `let pendingDecodeIDs: Set<Int>`.
- Produces (`Fixtures.swift`): `static let corpusFrames: [(name: String, fields: [String])]`.

- [ ] **Step 1: Generator skeleton and guard.** `generate.py` per decisions 3, 4, 5, 12, 13; startup self-checks
  (`assert`): `socket.socket()` raises; `canon(100.0) == "100"`, `canon(1e-05) == "0.00001"`,
  `canon(1.7976931348623157e308) == ""`, `canon(2147483647) == ""`, `canon(True) == "true"`, `canon(-0.0) == "0"`.
  `python -I Scripts/differential/generate.py --self-test` exits 0 and writes nothing.
- [ ] **Step 2: Seed the corpus.** Every frame of every `Recorded/*.json` (`recorded/<file>#<i>`); the base
  `Fixtures.openOrderFields` / `completedOrderFields` calls the codec tests use (`fixtures/<name>`, mirrored in
  `Fixtures.corpusFrames`); `FakeGateway`'s fixed replies `["9","1","1"]`, `["15","1","DU1"]`, `["53","1"]`,
  `["102"]`, `["55","1","1"]`, `["62","1"]`, `["54","1","DU1"]`, `["74","1","1"]` (`fakegateway/…`); the one-time
  inline sweep (decision 6). Variants for Task 1's ids in `variants.py`: error (decoder.py:208-216) with and without
  `advancedOrderRejectJson`, reqId -1, a `\u00e9` escape in the text; nextValidId; managedAccounts with one and three
  accounts and a trailing comma; currentTime; userInfo with empty and non-empty branding; the canary
  `gen/canary/short-openOrder` `["5","1"]`.
- [ ] **Step 3: Write the failing Swift tests** in `OracleCorpusTests.swift` and `OracleDecodeTests.swift`:
  - `everyRecordedFrameIsInTheCorpus`, `everyFixtureFrameIsInTheCorpus` (`Fixtures.corpusFrames`) — via
    `expectInCorpus`.
  - `everyCorpusFrameHasAnOracleAnswer`: each `corpus.json` frame appears in `decode.json` with the same fields,
    else «run `python -I Scripts/differential/generate.py`».
  - `oracleRunsIbAsync210At178`: `ibAsync == "2.1.0"`, `serverVersion == 178`, `handlers.count == 82`.
  - `everyHandlerHasACorpusEntry` (C6): every id in `handlers` minus `pendingDecodeIDs` has a frame whose
    `fields[0]` is that id, or an allowlist entry with `field == "#uncovered"` and that scope.
  - `oracleRecordsIbAsyncExceptions` (Review Focus 1).
  - `swiftCanonicalNeverFoldsSentinels` (Review Focus 2): `canon(Int?(2147483647)) == "2147483647"`,
    `canon(Decimal?(nil)) == ""`, `canon(d("100.0")) == "100"`, `canon(Date(timeIntervalSince1970: 1794321000)) == "1794321000"`.
  - `allowlistEntriesAreNarrowCitedAndUsed` (Review Focus 4): the citation and narrowness checks of decision 7 (the
    «used» check lives in the comparison test, which records the indices it used).
  - `ibAsyncDecodesLikeSwiftIBKR`: for each `decode.json` frame whose id is not pending, `IBDecoder.decode(body(fields))`,
    `ibAsyncCalls(id:_:)` (unmapped → one `Issue`), then `compare`; an `error` frame must decode `.malformed`; at
    the end, every allowlist entry scoped `in …` and not pending must be used.
- [ ] **Step 4: Run** `timeout 900 swift test --filter Oracle`. Expected: FAIL (no mapping for 4, 9, 15, 49, 107;
  missing files until Step 2's JSON exists).
- [ ] **Step 5: Implement** `OracleDecode+Session.swift`: `sessionCalls(id:_:)` mapping `.error` → `error(reqId,
  errorCode, errorString, advancedOrderRejectJson)`, `.nextValidID` → `nextValidId(reqId)` (ib_async's name),
  `.managedAccounts` → `managedAccounts(accountsList)` (ib_async passes the raw comma string; swift-ibkr splits it:
  the mapping joins with `","` — if a trailing comma makes them differ, that is the oracle loop), `.currentTime` →
  `currentTime(time)`, `.userInfo` → `userInfo(reqId, whiteBrandingId)`. Run the oracle loop.
- [ ] **Step 6: CI job** `oracle` in `.github/workflows/ci.yml`: `runs-on: ubuntu-latest`; `actions/checkout@v7`;
  `actions/setup-python` at its current major (check `gh api repos/actions/setup-python/releases/latest`) with
  `python-version: "3.12"`; `pip install -r Scripts/differential/requirements.txt`;
  `python -I Scripts/differential/generate.py`; `git diff --exit-code`.
- [ ] **Step 7: Determinism check.** Run the generator twice; `git diff --exit-code Tests/IBKRTests/Oracle` after the
  second run is empty.
- [ ] **Step 8: Run** `timeout 900 swift test`. Expected: PASS.
- [ ] **Step 9: Docs, commit** («Cross-check the session messages against ib_async 2.1.0 run offline, with a committed
  corpus, generator output and a cited allowlist»).

**Named risks:** the error text's `\uXXXX` decoding (DECISIONS: «Error `text` is `\uXXXX`-decoded») differs from
ib_async by design — cite it, do not «fix» it; `Fixtures.corpusFrames` drifting from the builders' real call sites;
`decode.json` size (the reviewer checks it stays in the low megabytes; openOrder frames flatten ~240 paths each);
the sweep capturing outgoing frames whose first field happens to be a handler id (harmless: both sides decode the
same bytes, but they must not be mistaken for incoming evidence in the names).

### Task 2: Decode — account and portfolio (in 6, 7, 8, 54, 61, 62, 63, 64, 71, 72, 73, 74, 94, 95) — sonnet

**Files:**
- Create: `Tests/IBKRTests/OracleDecode+Account.swift`
- Modify: `Scripts/differential/variants.py`, `Tests/IBKRTests/OracleDecodeTests.swift` (pending set, dispatch),
  `Tests/IBKRTests/Oracle/{decode,allowlist}.json`; `Sources/IBKR/…` only for a confirmed bug
- Docs: README «Status» rows «Account» and «Positions» unchanged until Task 9 (encode); KNOWN-GAPS none (these are
  live-checked or listed under «Live gateway»); protocol-178 / DECISIONS only through the oracle loop

**Interfaces:**
- Consumes: Task 1's `OracleSupport.swift`.
- Produces: `func contractArgs(_ c: Contract, prefix: String) -> [String: String]` (every ib_async `Contract`
  dataclass field: `conId`, `symbol`, `secType`, `lastTradeDateOrContractMonth`, `strike`, `right`, `multiplier`,
  `exchange`, `primaryExchange`, `currency`, `localSymbol`, `tradingClass`, `includeExpired`, `secIdType`, `secId`,
  `description`, `issuerId`, `comboLegsDescrip`, `comboLegs`, `deltaNeutralContract`), reused by every later task.
  A field swift-ibkr does not model is left out of the map and gets a skip entry only if a row covers it.

- [ ] **Step 1:** Variants (handler table decoder.py:56-114; updatePortfolio 218-253; position 596-618;
  positionMulti 620-646): each id's base frame;
  `unset-empty` and `unset-max` for every numeric field (position, prices, P&L values); `updatePortfolio` with
  `primaryExchange` in the exchange slot; `pnlSingle` with every value unset (MAX double) and with value 0;
  `accountSummary` / `accountUpdateMulti` with an empty currency. Verified layout: position (61) is 16 fields,
  `["61","3","DU0000001","265598","AAPL","STK","","0","","","","USD","AAPL","NMS","40","351.5"]` →
  `position(account, contract, posSize, avgCost)`.
- [ ] **Step 2:** Remove the 14 ids from `pendingDecodeIDs`; run `timeout 900 swift test --filter Oracle`: RED.
- [ ] **Step 3:** `accountCalls(id:_:)` and `contractArgs`; the oracle loop. `pnl`/`pnlSingle` map `AccountPnL` /
  `PnL` to `dailyPnL`, `unrealizedPnL`, `realizedPnL` (+ `pos`, `value` for 95); the stage-14 fields `account`,
  `modelCode`, `conID` are set by the stream, not the decoder, so they are not in the map.
- [ ] **Step 4:** `timeout 900 swift test`: PASS. Commit («Cross-check the account, portfolio, position and P&L
  messages against ib_async»).

**Named risks:** in 7 the exchange slot is `primaryExchange` (DECISIONS: «In 7 the contract's `primaryExchange` is
read from the exchange slot»); ib_async's `float(x or 0)` turns `""` into `0` where swift-ibkr has `nil` — allowed
only as `pair ["", "0"]` on `*unset-empty*` frames with a cited row (DECISIONS: «One shared unset set»), never as a
blanket skip.

### Task 3: Decode — order events (in 3, 11, 53, 55, 59, 100, 102) — sonnet

**Files:**
- Create: `Tests/IBKRTests/OracleDecode+Orders.swift`
- Modify: `variants.py`, `OracleDecodeTests.swift`, `Oracle/*.json`; `Sources/` only for a bug
- Docs: none beyond the oracle loop (executions and order events are live-checked)

**Interfaces:**
- Consumes: `contractArgs` (Task 2).
- Produces: `func executionArgs(_ e: Execution, prefix: String) -> [String: String]` (`execId`, `time` from
  `Execution.date`, `acctNumber`, `exchange`, `side`, `shares`, `price`, `permId`, `clientId`, `orderId`,
  `liquidation`, `cumQty`, `avgPrice`, `orderRef`, `evRule`, `evMultiplier`, `modelCode`, `lastLiquidity`,
  `pendingPriceRevision`).

- [ ] **Step 1:** Variants. Verified layouts (ib_async 2.1.0 at 178):
  - orderStatus, 12 fields (decoder.py:51-55):
    `["3","5","Submitted","40","60","351.5","610467324","0","351.5","7","","0"]` → `orderStatus(orderId, status,
    filled, remaining, avgFillPrice, permId, parentId, lastFillPrice, clientId, whyHeld, mktCapPrice)`; variants
    with `mktCapPrice` set and unset.
  - execDetails, 32 fields (decoder.py:426-475):
    `["11","-1","5","265598","AAPL","STK","","0","","","ISLAND","USD","AAPL","NMS","0000e0d5.6564a7b1.01.01","20261110-11:56:31","DU0000001","ISLAND","BOT","40","351.5","610467324","7","0","40","351.5","","","","","1","0"]`;
    variants: time with a zone (`20261110 06:56:31 US/Eastern`), `evMultiplier` set, `pendingPriceRevision` `"1"`.
  - commissionReport, 8 fields (decoder.py:573-594):
    `["59","1","0000e0d5.6564a7b1.01.01","1","USD","1.7976931348623157E308","1.7976931348623157E308",""]`; a variant
    with realized P&L and yield set.
  - orderBound, 4 fields, no version (skip=1, decoder.py:136): `["100","610467324","7","5"]` →
    `orderBound(reqId, apiClientId, apiOrderId)` = (610467324, 7, 5); the three end markers.
- [ ] **Step 2:** Remove the 7 ids; RED.
- [ ] **Step 3:** `orderCalls(id:_:)` for these ids, `executionArgs`; the oracle loop.
- [ ] **Step 4:** `timeout 900 swift test`: PASS. Commit («Cross-check orderStatus, executions, commissions and the
  order end markers against ib_async»).

**Named risks:** ib_async names orderBound's fields `reqId, apiClientId, apiOrderId` (Disagreements 6 records the
`permId` name); a zone-less execution time is UTC on both sides only because the wrapper's `TimezoneTWS` is `None`
(decision 3) — DECISIONS row «Execution and order times stay IB's raw strings» records ib_async's machine-zone
default.

### Task 4: Decode — openOrder and completedOrder (in 5, 101) — opus

**Files:**
- Modify: `Tests/IBKRTests/OracleDecode+Orders.swift`, `variants.py`, `OracleDecodeTests.swift`, `Oracle/*.json`;
  `Sources/IBKR/Messages/OrderDecoding.swift` only for a bug
- Docs: KNOWN-GAPS «Conditions, algos, PEG and combo orders…» stays until Task 10 (encode); protocol-178
  Disagreements as ruled (decision for the controller 2: displaySize)

**Interfaces:**
- Consumes: `contractArgs`.
- Produces: `func orderArgs(_ o: Order, prefix: String) -> [String: String]` (every `Order` field swift-ibkr
  models, under ib_async's attribute names per DECISIONS' naming row: `lmtPrice` ← `limitPrice`, `algoId` ←
  `algoID`, …; `conditions[]` per condition dataclass; `algoParams[]`, `smartComboRoutingParams[]`,
  `orderComboLegs[]`, `orderMiscOptions[]`, `softDollarTier.name/val/displayName`), `func orderStateArgs(_ s:
  OrderState, prefix: String) -> [String: String]`. Task 10 reuses the attribute-name table.

- [ ] **Step 1:** Variants for both messages, one per branch of decoder.py at 178: deltaNeutralOrderType set (960;
  1218) with its 8 (completedOrder: 4) fields; combo legs 0/1/2 (986; 1238); order combo legs 0/1/2 (1004; 1256);
  smart combo routing params 0/1/2 (1011; 1263); scale price increment in range with its 7 extra fields (1020;
  1271); hedgeType set (1033; 1284); delta-neutral contract present (1045; 1289); algoStrategy with 0/1/2 params
  (1052; 1296); orderType `PEG BENCH` and `PEGBENCH` (1083; 1305); conditions 0, one of each of the six types, and
  two with both conjunctions (1094; 1316); what-if margins set and unset; `unset-empty` / `unset-max` over every
  numeric order field. All Recorded openOrder/completedOrder frames are already in the corpus (the live 135-field
  form with `None`).
- [ ] **Step 2:** Remove 5 and 101; RED.
- [ ] **Step 3:** `orderArgs`, `orderStateArgs`, the two mappings (openOrder → `openOrder(orderId, contract, order,
  orderState)`; completedOrder → `completedOrder(contract, order, orderState)`); the oracle loop. Every ib_async
  `Order` field swift-ibkr does not model gets a skip entry citing the DECISIONS row that leaves it out
  (`sharesAllocation`: «`Order` and `Contract` stay one flat struct each»); a field with no such row is a
  `NEEDS_CONTEXT`.
- [ ] **Step 4:** `timeout 900 swift test`: PASS (`RecordedFrameTests` unchanged). Commit («Cross-check openOrder
  and completedOrder, every optional group included, against ib_async»).

**Named risks:** `PEGBENCH` without the space (decoder.py:1083) must take the PEG group (OrderDecoding.swift:260
handles both — a variant pins it); conditions are parsed by ib_async through dataclass defaults (`self.parse(cond)`),
so a condition's numeric field may arrive as `float` where swift-ibkr keeps `Decimal` — compared through the
canonical form; the recorded `None` / `?` values (DECISIONS: «openOrder's values are kept as IB sends them»); the
displaySize sentinel (controller decision 2).

### Task 5: Decode — market data (in 1, 2, 12, 13, 21, 45, 46, 47, 50, 56, 57, 58, 81, 84, 91, 92, 99) — sonnet

**Files:**
- Create: `Tests/IBKRTests/OracleDecode+MarketData.swift`
- Modify: `variants.py`, `OracleDecodeTests.swift`, `Oracle/*.json`; `Sources/IBKR/Messages/MarketDataDecoding.swift`
  / `IBDecoder.swift` only for a bug
- Docs: KNOWN-GAPS: the `TickAttrib` line gains «ib_async drops the mask, so the oracle cannot check it» (it stays a
  live item); the market-data «hand-built frames» line waits for Task 11

**Interfaces:**
- Consumes: `contractArgs` (for 56's `DeltaNeutralContract`: `conId`, `delta`, `price`).
- Produces: `marketDataCalls(id:_:)`.

- [ ] **Step 1:** Variants: tickPrice (7 fields, decoder.py:200-206) for every key of `PRICE_TICK_MAP`
  (wrapper.py:82) with a size, without one, and with an empty price (ib_async makes no call — controller decision
  3); tickSize for every key of `SIZE_TICK_MAP` (wrapper.py:120); tickGeneric for every key of `GENERIC_TICK_MAP`
  (140); tickString for every key of `STRING_TICK_MAP`, `TIMESTAMP_TICK_MAP`, `RT_VOLUME_TICK_MAP` (176, 187, 192);
  tickOptionComputation for every key of `GREEKS_TICK_MAP` (154) with values set, with -1/-2, and with
  `tickAttrib` 0/1; tickEFP for every key of `EFP_TICK_MAP` (166); depth 12 and 13 for insert/update/delete on both
  sides, 13 with `isSmartDepth` 0/1; tickByTick types 1, 2, 3, 4 (decoder.py:838-880) with each mask bit; realtimeBar;
  56, 57, 58 (types 1–4), 81, 84, 91, 92.
- [ ] **Step 2:** Remove the 17 ids; RED.
- [ ] **Step 3:** `marketDataCalls(id:_:)`: `.tick(.price)` → `priceSizeTick(reqId, tickType, price, size)`;
  `.tick(.size)` → `tickSize`; `.generic` → `tickGeneric`; `.string` → `tickString`; `.optionComputation` →
  `tickOptionComputation` (ib_async passes `tickAttrib`; swift-ibkr's field for it, or a cited skip);
  `.efp` → `tickEFP`; `.depth` → `updateMktDepth` / `updateMktDepthL2` by frame id; `.tickByTick` →
  `tickByTickAllLast` / `tickByTickBidAsk` / `tickByTickMidPoint` with `tickAttribLast.pastLimit/unreported` and
  `tickAttribBidAsk.bidPastLow/askPastHigh`; the oracle loop.
- [ ] **Step 4:** `timeout 900 swift test`: PASS. Commit («Cross-check every tick type, depth, tick-by-tick and the
  market-data side messages against ib_async»).

**Named risks:** tickPrice's mask (Disagreements 11: ib_async drops it — a skip entry citing it); the two bid/ask
bit orders (Disagreements 10: the same mask must give opposite flags on 97 and 99 on both sides); the greeks'
-1/-2 (controller decision 6); the delayed fields 66–76 and 80–83 decode under their raw ids on both sides (the
`live` mapping is a `Ticker` concern, not the decoder's).

### Task 6: Decode — history (in 17, 88, 89, 90, 96, 97, 98, 106) — sonnet

**Files:**
- Create: `Tests/IBKRTests/OracleDecode+History.swift`
- Modify: `variants.py`, `OracleDecodeTests.swift`, `Oracle/*.json`; `Sources/` only for a bug
- Docs: the history «hand-built frames» wording waits for Task 11

**Interfaces:**
- Produces: `historyCalls(id:_:)`.

- [ ] **Step 1:** Variants: historicalData (decoder.py:477-494) with 0, 1 and 3 bars, epoch-second dates and an
  8-character day; historicalDataUpdate (496-511) with an empty field; histogramData 0/1/3 items; headTimestamp epoch
  and day; historicalTicks 96/97/98 with 0, 1 and 3 ticks and `done` 0/1, 97 with each mask bit, 98 with each mask
  bit and empty `specialConditions`; historicalSchedule (1361-1370) with 0, 1 and 2 sessions.
- [ ] **Step 2:** Remove the 8 ids; RED.
- [ ] **Step 3:** `historyCalls`: 17 → n× `historicalData(reqId, bar)` then `historicalDataEnd(reqId, _start, _end)`
  (swift-ibkr drops start/end — controller decision 4); bars as `BarData` fields `date`, `open`, `high`, `low`,
  `close`, `volume`, `average`, `barCount` (ib_async keeps `date` as IB's text; swift-ibkr's `Bar.time` is a
  `Date` — the mapping renders a formatDate-2 bar as epoch seconds, and a day bar's difference cites DECISIONS row
  «`Bar.time` is a `Date`»); the oracle loop.
- [ ] **Step 4:** `timeout 900 swift test`: PASS. Commit («Cross-check bars, bar updates, historical ticks, the head
  timestamp, histogram and schedule against ib_async»).

**Named risks:** the 96 midpoint size swift-ibkr drops (DECISIONS: «the midpoint size is dropped»); 97's bit order
(Disagreements 10); ib_async's historicalDataUpdate field order (`barCount` first, then `date`, `open`, `close`,
`high`, `low` — decoder.py:501-509) is not the bar order of 17.

### Task 7: Decode — contract details and reference data (in 10, 18, 52, 75, 76, 77, 78, 79, 80, 82, 93) — sonnet

**Files:**
- Create: `Tests/IBKRTests/OracleDecode+Reference.swift`
- Modify: `variants.py`, `OracleDecodeTests.swift`, `Oracle/*.json`; `Sources/` only for a bug
- Docs: wording waits for Task 12

**Interfaces:**
- Produces: `func contractDetailsArgs(_ d: ContractDetails, prefix: String) -> [String: String]` (Task 8's scanner
  reuses it), `referenceCalls(id:_:)`.

- [ ] **Step 1:** Variants: contractDetails (decoder.py:255-344) with `secIdList` 0/1/2, `lastTimes` with a date
  only, a date and time, and the `-` form; bondContractDetails (346-424) with the bond fields; symbolSamples with
  0/1/2 descriptions and 0/2 derivative types (695-719); optionParams with 0/1/3 expirations and strikes; soft-dollar
  tiers, family codes, depth exchanges (with and without `aggGroup`), smart components, market rule with 0/1/3
  increments — each with counts 0, 1 and n.
- [ ] **Step 2:** Remove the 11 ids; RED.
- [ ] **Step 3:** `contractDetailsArgs`, `referenceCalls` (18 → `bondContractDetails`); the oracle loop.
- [ ] **Step 4:** `timeout 900 swift test`: PASS. Commit («Cross-check contract details, bonds, symbol samples and
  the reference lookups against ib_async»).

**Named risks:** ib_async builds `securityDefinitionOptionParameter`'s expirations and strikes as lists in wire
order (canonical form keeps order; a set would be sorted — check decoder.py:648-672); `lastTimes` splitting
(DECISIONS: «`ContractDetails` gains every field `ib_async` decodes»).

### Task 8: Decode — scanner, news, fundamentals, WSH, FA, display groups, verify; close C6 (in 14, 16, 19, 20, 51, 65, 66, 67, 68, 69, 70, 83, 85, 86, 87, 103, 104, 105) — sonnet

**Files:**
- Create: `Tests/IBKRTests/OracleDecode+Research.swift`
- Modify: `variants.py`, `OracleDecodeTests.swift` (delete `pendingDecodeIDs` and its uses), `Oracle/*.json`;
  `Sources/` only for a bug
- Docs: protocol-178 (the closing sentence of «Disagreements» gains: «and every incoming table is cross-checked by
  running `ib_async` 2.1.0's decoder, `Tests/IBKRTests/Oracle/`»); README «Development» (the oracle paragraph says
  all 82 handlers)

**Interfaces:**
- Consumes: `contractDetailsArgs` (scannerData's rows).
- Produces: `researchCalls(id:_:)`; C6 strict.

- [ ] **Step 1:** Variants: scannerData (decoder.py:513-545) with 0, 1 and 3 rows; news providers 0/1/3; news
  article both types; historical news; news end with `hasMore` 0/1; bulletins; fundamentals, WSH meta and event JSON
  with `\0`-free text; receiveFA for each FA type; replaceFAEnd; display groups; the four verify answers (positional
  `_1`, `_2`: their wrapper methods are missing, decision 3).
- [ ] **Step 2:** Remove the 18 ids and then the whole `pendingDecodeIDs`; RED.
- [ ] **Step 3:** `researchCalls`; scannerData → n× `scannerData(reqId, rank, contractDetails, distance, benchmark,
  projection, legsStr)` then `scannerDataEnd(reqId)`; the oracle loop.
- [ ] **Step 4:** `timeout 900 swift test`: PASS, with `everyHandlerHasACorpusEntry` now covering all 82. Commit
  («Cross-check the scanner, news, research, FA, display-group and verify messages against ib_async, closing
  decode coverage at 82 handlers»).

**Named risks:** swift-ibkr's `ScanData` holds `contract` and `marketName`, not ib_async's `contractDetails`
(DECISIONS: «The scanner: `ScannerSubscription` uses `nil` for unset»); 87's `hasMore` is dropped on purpose
(DECISIONS: News row); missing wrapper methods mean ib_async the library ignores 65–70, 91, 92, 103 — the oracle
still checks the decoder's parse of them.

### Task 9: Encode harness and the session, account and order-side requests — opus

Requests (28; ib_async method → out id): `startApi` 71, `reqIds` 8, `reqCurrentTime` 49, `reqManagedAccts` 17,
`reqUserInfo` 104, `setServerLogLevel` 14, `reqMarketDataType` 59, `reqPositions` 61, `cancelPositions` 64,
`reqAccountSummary` 62, `cancelAccountSummary` 63, `reqPnLSingle` 94, `cancelPnLSingle` 95, `reqAccountUpdates` 6,
`reqPositionsMulti` 74, `cancelPositionsMulti` 75, `reqAccountUpdatesMulti` 76, `cancelAccountUpdatesMulti` 77,
`reqPnL` 92, `cancelPnL` 93, `cancelOrder` 4, `exerciseOptions` 21, `reqGlobalCancel` 58, `reqOpenOrders` 5,
`reqAllOpenOrders` 16, `reqAutoOpenOrders` 15, `reqCompletedOrders` 99, `reqExecutions` 7.

**Files:**
- Create: `Scripts/differential/cases.py`, `Tests/IBKRTests/Oracle/encode.json` (generated),
  `Tests/IBKRTests/OracleEncodeTests.swift`, `Tests/IBKRTests/OracleEncode+Session.swift`
- Modify: `Scripts/differential/generate.py` (capture), `Oracle/allowlist.json`; `Sources/IBKR/Messages/IBRequest.swift`
  only for a bug
- Docs: DECISIONS (one row: encode capture at `Client` level with ib.py-prepared arguments, decisions 9–11 —
  rejected: calling `IB` methods (they await answers), comparing after number normalisation by default); README
  «Status» rows «Session» and «Account»: «on the fake gateway» → «cross-checked against ib_async 2.1.0 and on the fake
  gateway; not yet run live»; CONTRIBUTING (adding an encode case)

**Interfaces:**
- Produces (Python): `CASES: list[tuple[str, str, dict]]` (name, `Client` method, kwargs with ib_async objects);
  `encode.json` per decision 10.
- Produces (Swift):
  - `indirect enum CaseValue: Decodable { case text(String), list([CaseValue]), object([String: CaseValue]), null }`
  - `struct EncodeCase: Decodable { var name: String; var method: String; var args: [String: CaseValue]; var fields: [String] }`
  - `func contract(from v: CaseValue) throws -> Contract` (every ib_async `Contract` attribute; unknown key throws)
  - `func ibAsyncMethod(_ r: IBRequest) -> String` (exhaustive) and `func request(for c: EncodeCase) throws -> IBRequest`
    dispatching to `<family>Request(for:)` per family file (`nil` = not this family)
  - `let pendingRequestMethods: Set<String>` (the 52 methods of Tasks 10–12)

- [ ] **Step 1:** Capture in `generate.py` (decision 9); cases in `cases.py` for the 28 methods: each with its
  arguments at their defaults and once with every argument non-default (e.g. `reqExecutions` with a full
  `ExecutionFilter` and with `clientId` 0; `exerciseOptions` with `override` 1; `reqAccountSummary` with
  `IBClient.defaultAccountSummaryTags` joined as ib.py:2247-2258 joins them; `cancelOrder` with a
  `manualCancelOrderTime`; `startApi` with `optCapab` set). Verified: `cancelOrder(5, "")` → `["4","1","5",""]`.
- [ ] **Step 2: Write the failing tests** in `OracleEncodeTests.swift`:
  - `everyRequestKindHasACase`: the set of `method` in `encode.json` plus `pendingRequestMethods` equals the 80
    ib_async method names (listed in the test).
  - `ibAsyncEncodesLikeSwiftIBKR`: for each case not pending, `request(for:)`, `ibAsyncMethod(built) == method`,
    `try built.body()` split on NUL equals `fields` exactly, except allowlisted fields (scope `out <id>`, field the
    index as text, or `#count`); every `out …` entry not pending is used.
- [ ] **Step 3: Run** `timeout 900 swift test --filter Oracle`. Expected: RED.
- [ ] **Step 4: Implement** `OracleEncode+Session.swift` (`sessionRequest(for:)`); the oracle loop.
- [ ] **Step 5: Run** `timeout 900 swift test`: PASS. Commit («Cross-check every session, account and order-side
  request against what ib_async sends for the same arguments»).

**Named risks:** `reqExecutions`' nil `clientId` sent as `"0"` (DECISIONS: «A nil `ExecutionFilter.clientID` is sent
as "0"»); `reqIds` always sends 1 id; `exerciseOptions`' contract block without primaryExchange (DECISIONS:
exerciseOptions row); `startApi`'s client id and capabilities come from `Client` attributes, not arguments.

### Task 10: Encode — placeOrder, every group, and modify (out 3) — opus

**Files:**
- Create: `Tests/IBKRTests/OracleEncode+PlaceOrder.swift`
- Modify: `cases.py`, `OracleEncodeTests.swift`, `Oracle/{encode,allowlist}.json`;
  `Sources/IBKR/Messages/PlaceOrderEncoding.swift` only for a bug
- Docs: KNOWN-GAPS «Conditions, algos, PEG and combo orders are checked on hand-built frames only» → «are
  cross-checked against ib_async 2.1.0 both ways, unseen live»; the what-if line likewise for the request and the
  margin decoding; README «Status» row «Orders» gains «cross-checked against ib_async 2.1.0»; protocol-178
  Disagreements as ruled (controller decision 2)

**Interfaces:**
- Consumes: `contract(from:)` (Task 9); Task 4's attribute-name table.
- Produces: `func order(from v: CaseValue) throws -> Order` (every ib_async `Order` attribute; an unmodelled one must
  equal ib_async's default), `OrderCondition` from each `_type`.

- [ ] **Step 1:** Cases (client.py:472-712): `LimitOrder("BUY", 1, 351.5)` (114 fields, verified) and a market, stop
  and stop-limit order; each of the six conditions alone, and two with `and`/`or` plus
  `conditionsIgnoreRth`/`conditionsCancelOrder`; an algo with 0 and 2 params; `PEG BENCH`, `PEGBENCH`, `PEG BEST`,
  `PEG MID`; a BAG with two legs, order combo legs with and without prices, smart combo routing params; delta-neutral
  order type with and without its contract fields; scale fields; hedge; what-if; soft-dollar tier; cash quantity;
  adjusted stop fields; the IBKRATS tail; the deprecated `eTradeOnly`/`firmQuoteOnly`/`nbboPriceCap`; `volatility`
  on `VOL` and on `LMT`; a bracket's three legs (parentId, transmit); OCA group and type; **modify**: the same order id
  sent twice, and `modify/recorded-openOrder` — the generator decodes `recorded/liveLimitOrderPlacesAndCancels.json`'s
  first openOrder with ib_async's `Decoder` and sends the resulting `Order` back through `placeOrder`; the Swift side
  decodes the same frame with `IBDecoder` and encodes `.placeOrder` with the decoded order.
- [ ] **Step 2:** Remove `placeOrder` from `pendingRequestMethods`; RED.
- [ ] **Step 3:** `order(from:)`, `placeOrderRequest(for:)`; the oracle loop. Float fields whose integral value
  ib_async writes as `"1.0"` where swift-ibkr writes `"1"` take `equalAsNumbers` entries citing Disagreements 4.
- [ ] **Step 4:** `timeout 900 swift test`: PASS (`PlaceOrderTests` unchanged unless a bug). Commit («Cross-check
  placeOrder's every field group, a bracket, OCA, what-if and a modify of a recorded live order against ib_async»).

**Named risks:** openClose `O` and usePriceMgmtAlgo `0` follow ib_async (Disagreements 1–2; they must match, not be
allowlisted); `volatility` only for `VOL…` (DECISIONS row); displaySize on the modify-from-recording case
(controller decision 2); the `modify/recorded-openOrder` case depends on Task 4's decode agreeing first.

### Task 11: Encode — market data and history (out 1, 2, 10, 11, 20, 25, 50, 51, 82, 83, 87, 88, 89, 90, 96, 97, 98) — sonnet

Methods: `reqMktData`, `cancelMktData`, `reqMktDepth`, `cancelMktDepth`, `reqHistoricalData`,
`cancelHistoricalData`, `reqRealTimeBars`, `cancelRealTimeBars`, `reqMktDepthExchanges`, `reqSmartComponents`,
`reqHeadTimeStamp`, `reqHistogramData`, `cancelHistogramData`, `cancelHeadTimeStamp`, `reqHistoricalTicks`,
`reqTickByTickData`, `cancelTickByTickData`.

**Files:**
- Create: `Tests/IBKRTests/OracleEncode+MarketData.swift`
- Modify: `cases.py`, `OracleEncodeTests.swift`, `Oracle/*.json`; `IBRequest.swift` only for a bug
- Docs: KNOWN-GAPS: «The tick, bar, depth and tick-by-tick decoders, and every stage 8–9 call (…), are checked only
  against hand-built frames» → «are cross-checked against ib_async 2.1.0 (decode and encode), unseen live»; README
  «Status» rows «Market data» and «History»

- [ ] **Step 1:** Cases (client.py:443-470, 759-783, 808-842, 915-924, 1063-1068, 1096-1109, 1125-1156): reqMktData
  with generic ticks (`"100,mdoff,292:BRFG"`), snapshot, regulatory snapshot, options, a BAG with legs, a
  delta-neutral contract; depth smart and not; historicalData with `includeExpired`, an end date (prepared by
  `util.formatIBDatetime`, ib.py:2353), keepUpToDate, chart options, a BAG, whatToShow `SCHEDULE` (formatDate 1);
  realTimeBars with options; headTimeStamp and histogram with `includeExpired`; historicalTicks with start, end,
  ignoreSize, misc options (ib.py:2414-2415); tickByTick each type with count and ignoreSize.
- [ ] **Step 2:** Remove the 17 methods; RED.
- [ ] **Step 3:** `marketDataRequest(for:)`; the oracle loop. The historicalTicks date text cites DECISIONS row
  «`historicalTicks(…)` returns `[TickByTick]`»; historicalData's date text is controller decision 5.
- [ ] **Step 4:** `timeout 900 swift test`: PASS. Commit («Cross-check every market-data and history request
  against ib_async»).

**Named risks:** `historicalBars` always sends formatDate 2 (DECISIONS: «`Bar.time` is a `Date`») — cases pass
formatDate 2 as the client would; a `BAG` is refused by every request but marketData and historicalData (DECISIONS
rows), so a BAG case exists only for those two.

### Task 12: Encode — reference, scanner, news, research, FA, display groups, verify; close encode coverage — sonnet

Methods (34): `reqContractDetails` 9, `reqMatchingSymbols` 81, `reqSecDefOptParams` 78, `calculateImpliedVolatility`
54, `calculateOptionPrice` 55, `cancelCalculateImpliedVolatility` 56, `cancelCalculateOptionPrice` 57,
`reqMarketRule` 91, `reqFamilyCodes` 80, `reqSoftDollarTiers` 79, `reqScannerSubscription` 22,
`cancelScannerSubscription` 23, `reqScannerParameters` 24, `reqNewsProviders` 85, `reqNewsBulletins` 12,
`cancelNewsBulletins` 13, `reqNewsArticle` 84, `reqHistoricalNews` 86, `reqFundamentalData` 52,
`cancelFundamentalData` 53, `reqWshMetaData` 100, `cancelWshMetaData` 101, `reqWshEventData` 102,
`cancelWshEventData` 103, `requestFA` 18, `replaceFA` 19, `queryDisplayGroups` 67, `subscribeToGroupEvents` 68,
`updateDisplayGroup` 69, `unsubscribeFromGroupEvents` 70, `verifyRequest` 65, `verifyMessage` 66,
`verifyAndAuthRequest` 72, `verifyAndAuthMessage` 73.

**Files:**
- Create: `Tests/IBKRTests/OracleEncode+Reference.swift`
- Modify: `cases.py`, `OracleEncodeTests.swift` (delete `pendingRequestMethods`), `Oracle/*.json`; `IBRequest.swift`
  only for a bug
- Docs: KNOWN-GAPS «Stages 10–11 are checked only against hand-built frames and the fake gateway» → «are
  cross-checked against ib_async 2.1.0 and run on the fake gateway, unseen live» (the WSH, display-group, bond and
  news-date checks stay as live items); README «Status» rows «Contract lookup», «Options and reference», «Scanner»,
  «News», «Fundamentals and Wall Street Horizon», «FA, display groups and verify»

- [ ] **Step 1:** Cases (client.py:743-757, 867-908, 925-978, 1037-1094, 1110-1112, 1160-1180, 802-807, 998-1023):
  contractDetails with `includeExpired`, `secIdType`/`secId`, `issuerId`; scanner subscription with every field
  unset and set, with options and filter options; the calculations with options; historicalNews with provider codes
  and dates (ib.py:2570 onward prepares them); fundamentals with options; WSH event data with every field and with
  `conId`/`totalLimit` unset (`makeEmpty=False`, client.py:1166-1178); replaceFA with XML.
- [ ] **Step 2:** Remove the 34 methods and then `pendingRequestMethods`; RED.
- [ ] **Step 3:** `referenceRequest(for:)`; the oracle loop.
- [ ] **Step 4:** `timeout 900 swift test`: PASS, `everyRequestKindHasACase` now strict at 80. Commit («Cross-check
  the reference, scanner, news, research, FA, display-group and verify requests against ib_async, closing encode
  coverage at 80 requests»).

**Named risks:** reqScannerSubscription sends filter options before options (IBRequest.swift:214); a `nil`
`numberOfRows` goes out as `-1` (DECISIONS: scanner row); WSH's unset `conId`/`totalLimit` are IB's
`2147483647`, not `""`.

### Task 13: Simulated broker, session and the fill lifecycle — opus

**Files:**
- Create: `Tests/IBKRTests/SimulatedBroker.swift`, `Tests/IBKRTests/ScenarioOrderTests.swift`
- Modify: `Tests/IBKRTests/FakeGateway.swift` (`fed`), `Tests/IBKRTests/Oracle/corpus.json` (`sim/…` frames),
  `decode.json` (regenerated)
- Docs: DECISIONS (one row: the simulator, decision 14 — rejected: a fork of `FakeGateway`, a mock that
  self-certifies its frames, non-deterministic times); README «Development» (a paragraph: the simulator and that its
  frames are oracle-checked, its sequences recorded live where noted); KNOWN-GAPS (under «Live gateway»: the
  simulator's unrecorded sequences — bracket, OCA, reject, what-if, several clients — are assumptions);
  CONTRIBUTING (adding a scenario: run it, paste the missing frames the test prints into `corpus.json`, regenerate);
  CHANGELOG `### Added` (test-only)

**Interfaces:**
- Consumes: `FakeGateway` (`init(nextValidID:accounts:)`, `onRequest`, `feed`, `close`), `expectInCorpus` (Task 1),
  `Fixtures.openOrderFields`.
- Produces:
  - `FakeGateway.fed: [[String]]` (lock-protected; appended in `feed(_:)`, the hello reply excluded).
  - `final class SimulatedBroker: @unchecked Sendable` (state behind one `NSLock`):
    - `init(accounts: [String] = ["DU0000001"], nextOrderID: Int = 1, clock: Int = 1794321000)`
    - `var connector: Connector` (a new wired `FakeGateway` per connect), `var gateways: [FakeGateway]`,
      `var emitted: [[String]]` (every gateway's `fed`, in hand-out order)
    - `func fill(orderID: Int, clientID: Int, shares: Decimal, price: Decimal, commission: Decimal = 1)`
    - `func setMarketPrice(conID: Int, _ price: Decimal)` (drives 7, 94, 95 values)
    - book reads for assertions: `func order(clientID: Int, orderID: Int) -> SimOrder?`,
      `func position(account: String, conID: Int) -> (quantity: Decimal, averageCost: Decimal)`
  - `struct SimOrder { var clientID, orderID, permID: Int; var contract: Contract; var action: OrderAction; var quantity: Decimal; var orderType: String; var limitPrice: Decimal?; var parentID: Int; var transmit: Bool; var ocaGroup: String; var whatIf: Bool; var status: OrderStatus; var filled: Decimal }`
  - placeOrder is read at the base-case indices of docs/protocol-178.md's placeOrder table (orderId 1, conId 2,
    symbol 3, action 16, totalQuantity 17, orderType 18, lmtPrice 19, ocaGroup 22, transmit 27, parentId 28,
    ocaType 46, whatIf 84); a frame with any conditional group present (field count ≠ the base count) records an
    `Issue` and is not booked.

- [ ] **Step 1: Write the failing scenario tests** (`ScenarioOrderTests.swift`, each ends with
  `expectInCorpus(broker.emitted, source: "SimulatedBroker")`):
  - `placedOrderGoesSubmittedPartialFilled`: `placeOrder` (LMT BUY 100) → `orders()` shows `.pendingSubmit`,
    `.preSubmitted`, `.submitted`; `fill(shares: 40)` → `filled 40`, `remaining 60`, one `Fill` on `executions()`
    with its commission; `fill(shares: 60)` → `.filled`, `filled 100`; `positions()` holds 100.
  - `syncReplaysTheBook`: a second client connecting to the same broker gets the open order (16), the fills (7) and
    the position (61) before `connect` returns.
- [ ] **Step 2: Run** `timeout 900 swift test --filter Scenario`. Expected: FAIL (no `SimulatedBroker`).
- [ ] **Step 3: Implement** `fed` and `SimulatedBroker` per decision 14: the place, fill and commission sequences of
  the two recordings; the sync answers (16 → openOrders, 99 → completedOrders, 7 → execDetails replay with the
  request's reqId, 61 → positions, 6 with subscribe `1` → account values and portfolio) returned from `onRequest`
  so `FakeGateway`'s end markers follow them.
- [ ] **Step 4: Run** the scenarios; paste the frames `expectInCorpus` prints into `corpus.json`; regenerate; run the
  oracle loop on any mismatch (a simulator frame ib_async decodes differently is a simulator bug unless it is a
  swift-ibkr decode bug).
- [ ] **Step 5: Determinism (Review Focus 5):** `timeout 900 swift test --filter Scenario` three times; no new
  corpus misses.
- [ ] **Step 6: Run** `timeout 900 swift test`: PASS. Commit («Add a simulated broker over FakeGateway whose every
  frame the ib_async oracle has decoded, with the place, partial-fill and fill lifecycle»).

**Named risks:** `onRequest` runs inside the client's write path, so it must not block or call back into the client;
fills arrive unsolicited through `feed` — ordering against a request's replies follows the order the test drives
them; IB sends an order's events only to its own client while reqAllOpenOrders lists all (DECISIONS: «OrderTracker
takes the connection's client id»).

### Task 14: Scenarios — modify, cancel, reject, bracket, OCA, what-if — opus

**Files:**
- Modify: `Tests/IBKRTests/SimulatedBroker.swift`, `Tests/IBKRTests/ScenarioOrderTests.swift`,
  `Oracle/{corpus,decode}.json`
- Docs: KNOWN-GAPS «Still hand-built: a bracket's three openOrders, an execution correction» → the bracket's frames
  are «cross-checked against ib_async 2.1.0, unseen live»; DECISIONS / Disagreements only through the oracle loop

**Interfaces:**
- Consumes: Task 13's broker.
- Produces: `func reject(nextOrderWith code: Int, text: String)`; bracket hold-until-transmit and OCA sibling
  cancellation in the broker.

- [ ] **Step 1: Write the failing tests:**
  - `modifyKeepsTheOrderAndLogsModified`: place, then `modifyOrder` with a new limit → `orderEvents()` yields
    `.modified`; the snapshot's log ends `Modify`, `Modified`; the broker's order has the new limit.
  - `cancelFollowsTheRecordedSequence`: `cancelOrder` → `.pendingCancel` then `.cancelled`; 202's reason handling
    as DECISIONS' 202 row.
  - `rejectedOrderEndsInactive`: `reject(nextOrderWith: 201, text: "Order rejected - reason:…")` → `.inactive` with
    `rejectReason`.
  - `bracketHoldsUntilTheLastLegAndCancelsTheSibling`: `placeBracket` → nothing working until the third leg
    (transmit); parent filled → children submitted; take-profit filled → stop-loss `.cancelled`.
  - `ocaFillCancelsTheOthers`: two orders in one OCA group (`Order.oneCancelsAll`) → one fill cancels the other.
  - `whatIfReturnsMarginsAndBooksNothing`: `whatIfOrder` returns the broker's margins; the book holds no order.
- [ ] **Step 2: Run** `timeout 900 swift test --filter ScenarioOrderTests`: RED.
- [ ] **Step 3: Implement** the broker rules (assumptions marked).
- [ ] **Step 4:** Corpus, regenerate, the oracle loop; three determinism runs.
- [ ] **Step 5: Run** `timeout 900 swift test`: PASS. Commit («Drive modify, cancel, reject, bracket, OCA and what-if
  through the simulated broker»).

**Named risks:** a bracket's child openOrders carry `parentId`, which the broker must echo at openOrder index 57
(`Fixtures.openOrderFields(parentID:)`); the what-if openOrder must carry margins at 86–94 and must not bump the
book (DECISIONS: what-if row).

### Task 15: Scenarios — account agreement, reconnect, several clients, cancellation, faults — opus

**Files:**
- Create: `Tests/IBKRTests/ScenarioSessionTests.swift`
- Modify: `SimulatedBroker.swift`, `Oracle/{corpus,decode}.json`
- Docs: KNOWN-GAPS (the reconnect and multi-client sequences are simulator assumptions); README «Development»
  (the scenario list)

**Interfaces:**
- Produces: `func drop()` (closes every live gateway: a mid-stream disconnect), `func failNext(_ messageID: String,
  code: Int, text: String)`, `func delayReplies(_ d: Duration)` (non-sync replies fed after `d`; 16 and 99 are
  never delayed, since `FakeGateway` feeds their end markers itself), market data: `func tick(conID: Int, field:
  Int, price: Decimal)` to every open 1 subscription, `var openMarketData: [Int]` (reqIds).

- [ ] **Step 1: Write the failing tests:**
  - `positionsPnlAndExecutionsAgreeAfterFills`: BUY 100 in two fills, SELL 40 → `positions()` 60 equals the signed
    sum of `executions()` shares; `portfolio()` position equals it; `pnlSingle` position equals it; `pnl` realized
    equals the sum of commission reports' realized P&L.
  - `reconnectMidStreamRecoversTheBook`: `connect(…, reconnect: ReconnectPolicy(delays: [.milliseconds(20)]))`;
    open order working; `drop()`; a fill booked while down; after reconnect `orders()`, `positions()` and
    `executions()` equal the broker's book, the fill appears once, and the `marketData` stream that was open ended
    with `.connectionClosed`.
  - `twoClientsSeeTheirOwnOrdersAndOneBook`: clients 1 and 2 each place id 1; each `orders()` holds only its own;
    both `positions()` show the combined position; `fetchAllOpenOrders()` on either lists both.
  - `stoppingAStreamSendsItsCancelAndTheBrokerStops`: `marketData`, `pnl` and `tickers` consumers stop → 2, 93 and
    the tickers' cancels reach the broker within 2 s; `openMarketData` is empty and no further tick is fed.
  - `faultsSurfaceTyped`: `failNext("1", code: 10197, …)` → `.noMarketDataPermission`; `delayReplies(.milliseconds(30))`
    keeps `currentTime()` answering within 2 s.
- [ ] **Step 2: Run** `timeout 900 swift test --filter Scenario`: RED.
- [ ] **Step 3: Implement** the broker's account values, P&L, market data, drop, faults.
- [ ] **Step 4:** Corpus, regenerate, the oracle loop; three determinism runs (Review Focus 5).
- [ ] **Step 5: Run** `timeout 900 swift test`: PASS. Commit («Check positions, P&L and executions agree, and drive
  reconnect, several clients, stream cancellation and faults through the simulated broker»).

**Named risks:** the reconnect scenario races the policy's first delay against the test's `drop()` — wait for
`.connecting` on `states()` before booking the outage fill; two clients share one broker lock, so a reply built for
one gateway must never be fed to the other; the 2 s budget on Windows CI.

### Task 16: Documents closure and final checks — sonnet

**Files:**
- Modify: `README.md`, `docs/KNOWN-GAPS.md`, `docs/DECISIONS.md`, `docs/protocol-178.md`, `CONTRIBUTING.md`,
  `CHANGELOG.md`, `Scripts/differential/README.md`

- [ ] **Step 1:** KNOWN-GAPS title and intro: «after stage 15», and the intro's stage list gains «the differential
  oracle and the scenario simulator»; every «hand-built» claim left (`git grep -n "hand-built" docs README.md
  CONTRIBUTING.md`) is either reworded with its covering task's wording or justified (Flex XML stays hand-written).
- [ ] **Step 2:** README «Status» rows agree with KNOWN-GAPS; «Development» names the oracle (82 handlers, 80
  requests, regenerate command) and the simulator; CONTRIBUTING's «IB's code» and «Documents of record» mention
  the oracle files; CHANGELOG `[Unreleased]` lists every `### Fixed` the oracle found and the two test-only
  `### Added` lines.
- [ ] **Step 3:** the real-account-id `git grep` from the stage brief empty; `python -I Scripts/differential/generate.py` then
  `git diff --exit-code`; `timeout 900 swift test`: PASS.
- [ ] **Step 4:** Commit («Bring README, KNOWN-GAPS, CONTRIBUTING and CHANGELOG in line with the oracle and the
  simulator»).
- [ ] **Step 5:** Per-commit check: `git rebase --exec "timeout 900 swift test > /dev/null" 15ceae2`.

**Named risks:** a Status row claiming «cross-checked» for a direction the oracle does not cover (the handshake,
`Ticker`/tracker state, Flex); a mismatch tally in the ledger that disagrees with `allowlist.json`.
