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
