# Contributing to swift-ibkr

## Building and testing

```bash
swift build
swift test
```

This works on macOS 13+, on Linux with Swift 6.0 or later, and on Windows with a Swift 6.x toolchain (the same
commands in PowerShell or Git Bash). The unit tests need no gateway: they use a fake gateway and the frames recorded
in `Tests/IBKRTests/Recorded/`.

## Live tests

The live tests run against a **paper** IB Gateway on 127.0.0.1:4002 and are skipped unless you ask for them:

```bash
IBKR_LIVE=1 swift test --filter LiveTests
```

To also buy and sell back 1 AAPL with marketable limits, add `IBKR_LIVE_FILL=1` and
`IBKR_LIVE_FILL_PRICE=<current AAPL price>`. The Flex live test downloads your own Flex query:

```bash
IBKR_FLEX_TOKEN=<token> IBKR_FLEX_QUERY=<query id> swift test --filter FlexLiveTests
```

On Windows PowerShell, set the variables with `$env:IBKR_LIVE="1"` and remove them afterwards
(`Remove-Item Env:IBKR_LIVE, Env:IBKR_LIVE_FILL, Env:IBKR_LIVE_FILL_PRICE`), so that a later `swift test` in the
same shell does not trade.

Nothing is placed unless every managed account starts with `DU`, which marks a paper account. Recordings replace
the account id with `DU0000001`. Never commit a real account id or a Flex token.

## Doc comments

Every public declaration has a doc comment. The audit lists any that lacks one, and prints nothing when all have
one (run from the repository root):

```bash
dir="$PWD/.build/symbol-graphs"
mkdir -p "$dir"
for t in IBKR IBKRFlex; do
  swift build --target $t -Xswiftc -emit-symbol-graph -Xswiftc -emit-symbol-graph-dir -Xswiftc "$dir"
done
python3 Scripts/doc-coverage.py "$dir"/*.symbols.json
```

On Windows `python3` may be the Microsoft Store stub; use `python` there.

The DocC documentation builds on macOS:

```bash
xcodebuild docbuild -scheme swift-ibkr-Package -destination 'generic/platform=macOS' \
  OTHER_DOCC_FLAGS=--warnings-as-errors
```

## The example

```bash
swift build --package-path Examples/IBKRExample
```

The example must stay read-only: it never places, modifies or cancels an order.

## Commits

A commit message is one imperative sentence about what changed, then the reasoning that would otherwise be lost:
what was tried, what was rejected, and why. Lines in `Sources` stay within 120 columns.

## Documents of record

A behaviour change updates `README.md`, `CHANGELOG.md` (under `Unreleased`), `docs/DECISIONS.md`,
`docs/KNOWN-GAPS.md` and `docs/protocol-178.md` in the same commit.

## IB's code

No code from IB's official API (`ibapi`) or from other clients. Wire layouts follow `ib_async` as read and
[`docs/protocol-178.md`](docs/protocol-178.md), and every new message gets a codec test on a hand-built frame.
`ib_async` itself runs only in the oracle's generator, offline; nothing of it is copied into `Sources/`.

## Differential oracle

`Tests/IBKRTests/Oracle/` holds `ib_async` 2.1.0's answers for every frame the tests use and the fields its `Client`
sends for every encode case, and the Swift tests compare `IBDecoder` and `IBRequest.body()` with them. Python is
needed only to regenerate them:

```bash
python3.12 -m venv .venv            # Windows: py -3.12 -m venv .venv
.venv/bin/pip install -r Scripts/differential/requirements.txt   # Windows: .venv\Scripts\pip
.venv/bin/python -I Scripts/differential/generate.py             # rewrites decode.json and encode.json
```

- **A new frame.** A new recording or a new `Fixtures.corpusFrames` entry (a new `Fixtures` builder or base call
  joins that list) fails the tests until its frames are in `corpus.json`; the failure prints the entry to paste.
  Add it (names: `recorded/<file>#<i>`, `fixtures/<name>`, `fakegateway/<name>`, `sweep/<File>.swift:<line>`,
  `sim/<scenario>/<n>`), regenerate and commit both files. A frame a new codec test builds inline is not found
  automatically: add it the same way. Variants of a message (unset values, counts, branches) go in
  `Scripts/differential/variants.py`.
- **A new encode case.** A case is `(name, Client method, kwargs)` in `Scripts/differential/cases.py`, named
  `<method>/<variant>`, with the arguments `ib.py` would pass the `Client` (a prepared one names the ib.py line;
  dates go through `cases.ib_datetime`, tz-aware UTC only); a `Client` attribute the method reads instead of an
  argument goes under `_client` and in `CLIENT_ATTRS`. Each request has a case at its defaults and one with every
  argument non-default, neighbouring arguments of one kind distinct. Regenerate, then map the method in its family's
  `OracleEncode+<Family>.swift` (`CaseArgs` reads every argument by its Swift type; `contract(from:)` reads a
  `Contract`). An `IBRequest` case without a mapping does not compile (`ibAsyncMethod`); a method with no case fails
  `everyRequestKindHasACase`.
- **A difference.** Our bug: a failing codec test first, then the fix. A recorded deliberate difference: one entry in
  `allowlist.json` with `scope` (`in 4`, `out 4`), `field` (the argument path, `[]` for any index, never `*`; for a
  request the field's index, `#count` or `#error`; for placeOrder the protocol-178 field name the test reports, such
  as `conditions[].price`), `frames` (a glob over frame names; one exact case name for a request, except placeOrder's
  case globs), `pair` (`[ours, theirs]`, the exact pair; required on a request's `#count`)
  or `equalAsNumbers`, and `cite`: `protocol-178 Disagreements <n>` or `DECISIONS: <verbatim text of exactly one
  row>`, plus an optional `note`. An entry that cites nothing, or that no mismatch uses, fails the tests. A
  difference with no row is not allowlisted until one is written.
- **A new scenario.** A scenario drives the real `IBClient` against `SimulatedBroker` and ends with
  `expectInCorpus(broker.emitted, source: "sim/<scenario>")`. Run it: each frame the broker sent that is not yet in
  `corpus.json` fails with the entry to paste; add them as `sim/<scenario>/<n>`, regenerate, and run the oracle tests.
  A frame `ib_async` decodes differently is a simulator bug, unless a recorded difference covers it (then an
  allowlist entry citing it). A broker sequence no recording shows gets `// assumption: unrecorded live` and a
  KNOWN-GAPS line.
- CI's `oracle` job regenerates the JSON and fails on any diff, so commit the generator's output as it wrote it.
