# Stage 13: Release 1.0.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make swift-ibkr releasable as 1.0.0: a doc comment on every public declaration, DocC catalogs with four
articles published to GitHub Pages, a Swift Package Index config, a console example, and the release documents
(README with the complete `ib_async` → swift-ibkr table, CHANGELOG 1.0.0, podspec 1.0.0, CONTRIBUTING, issue
templates).

**Architecture:** No library behaviour changes.
- Tasks 1–4 document the public API file group by file group. Task 1 first adds `Scripts/doc-coverage.py`, which
  reads the compiler's symbol graphs (`swift build … -emit-symbol-graph`, any OS) and lists every public symbol
  without a doc comment; each doc task ends with that list empty for its files, Task 4 with it empty everywhere.
- Task 5 adds the DocC catalogs, Task 6 the docs workflow (macOS: `xcodebuild docbuild` with warnings as errors,
  one static-hosting folder per module under one Pages site, plus the coverage gate) and `.spi.yml`, Task 7 a
  separate example package, Task 8 the release documents and the leftover minors.

**Tech Stack:** Swift 6 (tools 6.0), SwiftPM, Swift Testing, DocC (`xcodebuild docbuild`, `xcrun docc`), GitHub
Actions (Pages), Python 3 standard library (the coverage script; 3.10 is the oldest it must run on).

**Spec:** `docs/superpowers/specs/2026-11-12-parity-and-1.0-design.md`: goal 7 (lines 52–59: doc comments on all
public API, DocC with the four articles on GitHub Pages, `.spi.yml`, `Examples/`, CHANGELOG, CONTRIBUTING, issue
templates, podspec, semantic versions), goal 8 (line 60: `xcodebuild docbuild` and `docc`, no docc plugin), stage 13
(lines 164–169), the live run (line 177), the owner's steps (lines 182–190). The controller's rulings for this stage
are below and are not open.

## Controller rulings (decided, not open)

1. Task order and split as below: T1 coverage script + IBKRFlex + order files; T2 market data; T3 wire layer and
   client; T4 the rest, audit at zero; T5 DocC; T6 `docs.yml` + `.spi.yml`; T7 `Examples/`; T8 release documents +
   minors. Each doc task is verified by the audit over its files plus `timeout 900 swift test` (487 tests, unchanged).
2. Doc comments are accurate one-liners written from the code, `docs/protocol-178.md` and `ib_async`, never
   invented. More than one line only where the semantics need it: units, what `nil` means, which IB message, how a
   stream ends or is cancelled. A memberwise `init` gets one line («Creates a … with every field given.»), no
   parameter list. `IBRequest` / `IBMessage` cases name the IB message id. Each doc task also wraps the lines over 120
   columns in the `Sources` files it touches (a frame or string literal may stay long); long lines in `Tests` stay.
3. DocC catalogs `Sources/IBKR/IBKR.docc` (landing `IBKR.md` with `## Topics`; articles `GettingStarted.md`,
   `Orders.md`, `MarketData.md`, `MigratingFromIbAsync.md`) and `Sources/IBKRFlex/IBKRFlex.docc` (`IBKRFlex.md`).
   Every ``` ``Symbol`` ``` link must resolve: the docs build runs with `--warnings-as-errors`. No swift-docc-plugin.
4. `docs.yml`: push (all branches), pull_request, workflow_dispatch; build on `macos-latest`; deploy from `main` only
   with `actions/deploy-pages`. Never call the Pages API: the owner enables Pages.
5. `.spi.yml`: version 1, documentation targets `IBKR` and `IBKRFlex`.
6. `Examples/IBKRExample`: its own package, depends on the root by path, read-only, no tests; CI builds it on macOS
   and Linux. The root package gains no product.
7. Release documents in T8 only (README, CHANGELOG, podspec, CONTRIBUTING, issue templates, DECISIONS, KNOWN-GAPS);
   Tasks 1–7 leave the documents of record alone. No CHANGELOG compare links.
8. Every commit keeps `timeout 900 swift test` green. The real paper account id never appears; examples use
   `DU0000001`.

**Decided in this plan:**
- The deploy job, not the whole workflow, carries the `pages` concurrency group: a workflow-level group would queue
  every branch's doc build behind one another and cancel waiting ones.
- README's semantic-versioning wording counts new cases in the protocol enums (`IBRequest`, `IBMessage`, `Tick`,
  `IBClientError` …) as minor changes: they mirror IB's protocol, which grows. A DECISIONS row records it.
- The `1.0.0` tag and the GitHub Release are not tasks here: the controller creates them after `main` is green.
- No live run: no paper Gateway listens on 127.0.0.1:4002, so README's «a live run is due in stage 13» becomes «not
  yet run live» and KNOWN-GAPS says what the run would have checked.

## Global Constraints

- Repository `C:\Users\viohn\swift-ibkr`, branch `stage-13-release` (from `main` at cbeee39, 487 tests). Do not push
  and do not touch `main`: the controller pushes, which is also what runs the CI changes of Tasks 6 and 7.
- `// swift-tools-version: 6.0`, platforms macOS 13 / iOS 16, no package dependency: all unchanged.
- No public signature changes in any task. A doc comment that would need one to be true is a stop-and-report.
- Comment style follows the code's own: `///` above the declaration, IB's message names and ids as in
  `docs/protocol-178.md` («placeOrder (out 3)», «tickPrice (in 1)»), `ib_async` names in backticks. When a field's
  meaning is not evident from the code, protocol-178 or `ib_async`, the comment names the wire field and the
  `ib_async` attribute it carries (`/// ib_async's \`Order.scaleInitLevelSize\`, sent in placeOrder (out 3).`) rather
  than guessing.
- **The audit** (run from the repository root; on this Windows machine `python3` is the Store stub, so use `python`;
  CI uses `python3`):

  ```bash
  mkdir -p .build/symbol-graphs
  for t in IBKR IBKRFlex; do
    swift build --target $t -Xswiftc -emit-symbol-graph -Xswiftc -emit-symbol-graph-dir -Xswiftc .build/symbol-graphs
  done
  python Scripts/doc-coverage.py .build/symbol-graphs/*.symbols.json
  ```

  A task's check pipes that last line through `grep -E '<its files>'` and expects no output.
- Long lines: `awk 'length > 120 {print FILENAME ":" FNR}' <files>` lists them; what remains must be a frame or
  string literal.
- Run tests as `timeout 900 swift test`, in the foreground. Expected: `Test run with 487 tests … passed`.
- No new DU id: `git show HEAD | grep -E '^\+.*DU[0-9]{5,}' | grep -v DU0000001` prints nothing for every commit.
- Commit messages are one imperative sentence, then the reasoning (what was tried, rejected, why). Read `git log -5`
  first. The last line is exactly `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A DocC link that does not resolve.** With `--warnings-as-errors` one stale ``` ``IBClient/…`` ``` link turns the
   docs build red on every push. Check: Task 5 Step 4 (links against the symbol graph); Task 6's first CI run.
2. **A coverage gate that passes vacuously.** If no graph is emitted, or Windows' `file://C:\…` URIs are misread, the
   script could print nothing. Check: Task 1 Step 3 (it lists `FlexRecord.swift` before the docs exist; no argument
   is an error).
3. **`.docc` folders breaking a non-Apple build or the pod.** SwiftPM on Linux/Windows must ignore them and
   `pod lib lint` must still pass. Check: Task 5 Step 5 (no «unhandled» warning, 487 tests); CI's pod-lint job.
4. **The example trading or hanging.** It must never place or cancel an order and must exit, not hang, without a
   gateway. Check: Task 7 Step 3 (grep for order calls) and Step 4 (exits 1 within seconds when nothing listens).
5. **The bounded Flex test still hanging.** If cancellation broke, `cancellingStopsThePolling` must fail in about
   10 s, not hang for 11 minutes. Check: Task 8 Step 2 (the mutation run).

---

### Task 1: The coverage script; IBKRFlex and the order files documented

**Files:**
- Create: `Scripts/doc-coverage.py`
- Modify (docs + long lines): `Sources/IBKRFlex/FlexRecord.swift` (4 undocumented),
  `Sources/IBKRFlex/FlexReport+Download.swift` (5 long lines), `Sources/IBKR/Models/Order.swift` (137),
  `Models/OrderParts.swift` (24), `Models/OrderState.swift` (15), `Models/OrderStatus.swift` (25),
  `Models/OrderCondition.swift` (8), `Models/OrderHelpers.swift` (8), `State/OrderTracker.swift` (18, 10 long
  lines), `Messages/OrderDecoding.swift` (17, 7 long lines)

**Interfaces:**
- Produces: `python3 Scripts/doc-coverage.py GRAPH.symbols.json [GRAPH …]` prints one line per undocumented public
  or open symbol that has a source location, `<path relative to cwd, forward slashes>:<1-based line> <kind without
  "swift."> <pathComponents joined by ".">`, sorted by path and line; exit 1 if any, 0 if none, an error exit with a
  usage line when given no path. Tasks 2–4 and 6 rely on this exact output format.

- [ ] **Step 1: Write `Scripts/doc-coverage.py`**

```python
#!/usr/bin/env python3
"""Lists every public symbol without a doc comment in the given symbol graphs and exits 1 if there is any.

Usage: python3 Scripts/doc-coverage.py .build/symbol-graphs/*.symbols.json
Symbols without a source location (synthesized, inherited) are skipped.
"""
import json
import os
import re
import sys
from urllib.parse import unquote


def source_path(uri):
    # macOS and Linux write file:///Users/..., Windows writes file://C:\Users\...
    path = unquote(uri[len("file://"):] if uri.startswith("file://") else uri)
    if re.match(r"^/[A-Za-z]:", path):
        path = path[1:]
    try:
        path = os.path.relpath(path)
    except ValueError:  # another drive on Windows
        pass
    return path.replace("\\", "/")


def main(paths):
    if not paths:
        sys.exit("usage: doc-coverage.py GRAPH.symbols.json [GRAPH.symbols.json ...]")
    missing = set()
    for graph_path in paths:
        with open(graph_path, encoding="utf-8") as graph:
            symbols = json.load(graph)["symbols"]
        for symbol in symbols:
            location = symbol.get("location")
            if symbol.get("accessLevel") not in ("public", "open") or symbol.get("docComment") or not location:
                continue
            missing.add((source_path(location["uri"]), location["position"]["line"] + 1,
                         symbol["kind"]["identifier"].removeprefix("swift."), ".".join(symbol["pathComponents"])))
    for path, line, kind, name in sorted(missing):
        print(f"{path}:{line} {kind} {name}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

- [ ] **Step 2: Run the audit** (Global Constraints). Expected: exit 1, 824 lines (820 for IBKR, 4 for IBKRFlex).
- [ ] **Step 3: Check the script's edges**
  - `python Scripts/doc-coverage.py; echo $?` → the usage line, exit 1.
  - The output contains `Sources/IBKRFlex/FlexRecord.swift:` lines with real line numbers (open the file at one and
    see an undocumented declaration there): this proves the Windows URI form is read.
- [ ] **Step 4: Document the files listed above**, one-liners per the rulings. Pointers from the code:
  - `Order.swift`: each property is an `ib_async` `Order` field sent in placeOrder (out 3); `orderType` and `tif`
    are IB's strings (DECISIONS row 1); prices are `Decimal?` where `nil` goes out as `""`; `ExerciseAction` and
    `OrderAction` cases carry IB's wire values.
  - `OrderStatus.swift`: each static is IB's status text («IB's `Submitted` status.»); `OrderStatusMessage` fields
    are orderStatus (in 3).
  - `OrderState.swift`: the margins and commissions are `nil` when IB sends `""` or its unset marker
    (DECISIONS: «`OrderState` holds openOrder's nine margins …»).
  - `OrderTracker.swift`: `OrderSnapshot` fields (`filled`/`remaining` in shares or contracts, `completedTime` IB's
    text, `rejectReason` from a warning or 202); `OrderTracker`'s public methods say which message they fold in.
  - `OrderDecoding.swift`: `OpenOrderMessage` is openOrder (in 5), `CompletedOrderMessage` completedOrder (in 101).
  - `FlexRecord.swift`: `topic` is the element's tag, `attributes` its attribute strings as IB wrote them, the
    `init` the memberwise line, the subscript «the attribute named `key`, or `nil`».
- [ ] **Step 5: Wrap the long lines** in those files.
- [ ] **Step 6: Verify**
  - Audit piped through
    `grep -E 'Sources/IBKRFlex/|Models/(Order|OrderParts|OrderState|OrderStatus|OrderCondition|OrderHelpers)\.swift:|State/OrderTracker\.swift:|Messages/OrderDecoding\.swift:'`
    → no output.
  - The long-line check over the same files → literals only.
  - `timeout 900 swift test` → 487 passed.
- [ ] **Step 7: Commit** `Scripts/doc-coverage.py` and the touched sources: «Add a doc-coverage audit and document
  IBKRFlex and the order types». The body says the script reads the compiler's symbol graph so it runs on every OS
  (docc is macOS-only), and that Windows writes `file://C:\…` URIs.

### Task 2: Market data, ticker, history and depth documented

**Files:** Modify (docs + long lines): `Sources/IBKR/Models/MarketData.swift` (153, 5 long lines),
`Models/Ticker.swift` (28, 1), `Models/History.swift` (12), `State/DepthBook.swift` (5)

**Interfaces:** Consumes Task 1's script and the audit.

- [ ] **Step 1: Run the audit** filtered by `grep -E 'Models/(MarketData|Ticker|History)\.swift:|State/DepthBook\.swift:'`
  → 198 lines.
- [ ] **Step 2: Document them.** Pointers:
  - `Tick` cases: which message each comes from (tickPrice 1 with its size, tickSize 2, tickGeneric 45, tickString
    46, marketDataType 58, tickOptionComputation 21, tickEFP 47, tickReqParams 81, tickNews 84); `price` and `size`
    are `nil` for IB's unset markers as the decoder maps them.
  - `TickField` statics: IB's tick type number and name; `live` as in its existing comment.
  - `GenericTick`, `MarketDataType` (IB's numbers 1–4), `TickByTickType` (IB's strings), `TickByTick` cases (in 99
    by type), `Bar` (volume, WAP and count are IB's `-1` on MIDPOINT/BID/ASK, kept), `BarEvent` (`.history` the
    initial set, `.update` a keepUpToDate bar), `DepthLevel`, `DepthUpdate` (updateMktDepth 12 / L2 13),
    `ContractDetails` (contractData 10, bond fields from 18), `ContractDescription` (symbolSamples 79),
    `DepthMarketDataDescription` (80), `SmartComponent` (82), `EFPData`, `NewsTick`, `OptionComputation` (its
    existing type comment says which values are `nil`).
  - `Ticker` properties: the named fields as the type comment lists them; `depth` the book when `depthRows` was
    asked for, else empty.
  - `History.swift`: `HistoricalSchedule` / `HistoricalSession` (in 106; times as IB sends them, check the code),
    `HistogramData` (in 89: price and trade count).
  - `DepthBook`: bids and asks by position; what `apply` does with insert, update, delete and 317.
- [ ] **Step 3: Wrap the long lines** in the four files.
- [ ] **Step 4: Verify:** the filtered audit → no output; long lines → literals only; `timeout 900 swift test` → 487.
- [ ] **Step 5: Commit:** «Document the market data, ticker, history and depth types».

### Task 3: The wire layer, the client and its errors documented

**Files:** Modify (docs + long lines): `Sources/IBKR/Messages/IBRequest.swift` (81, 8 long lines),
`Messages/IBMessage.swift` (75), `Messages/ErrorCode.swift` (6), `Messages/IBDecoder.swift` (1, 19 long lines),
`Messages/MarketDataDecoding.swift` (2 long lines), `Messages/PlaceOrderEncoding.swift` (1 long line),
`Errors.swift` (10), `Client/IBClientError.swift` (9), `Client/IBClient.swift` (5, 27 long lines),
`Client/IBClient+Research.swift` (7 long lines), `Client/IBClient+Reference.swift` (3 long lines),
`Client/ReconnectPolicy.swift` (1), `Client/TCPSocket.swift` (4 long lines), `Client/Transport.swift` (1),
`Client/Subscribers.swift` (1), `Wire/Handshake.swift` (2, 2 long lines)

**Interfaces:** Consumes the audit.

- [ ] **Step 1: Run the audit** filtered by
  `grep -E 'Messages/(IBRequest|IBMessage|ErrorCode|IBDecoder)\.swift:|Sources/IBKR/Errors\.swift:|Sources/IBKR/Client/|Sources/IBKR/Wire/'`
  → 190 lines.
- [ ] **Step 2: Document them.** Pointers:
  - Each `IBRequest` case: «<IB message name> (out N).» plus one clause when the case's use is not obvious (e.g.
    `.allOpenOrders` is sent by `connect`'s sync). Ids from `IBRequest`'s own `encode` switch and protocol-178.
  - Each `IBMessage` case: «<IB message name> (in N).», ids from `IBDecoder.decode`'s switch.
  - `IBErrorMessage` fields (error 4: `requestID` -1 when it names no request, `code`, `text` `\uXXXX`-decoded,
    `advancedOrderRejectJSON` raw); `ErrorKind` cases per the DECISIONS error-code table; `ErrorCode` members.
  - `IBClientError` cases: `.notConnected` (a call before `connect`), `.alreadyConnected`, `.timeout` (`connect`'s
    timeout or the reconnect probe), `.connectionClosed` (peer closed or reset), `.transport` (socket error text),
    `.protocolError`, `.encoding`, `.ib(code:text:)` (IB's error for the request); `IBProtocolError` and
    `IBEncodingError` cases from where they are thrown.
  - `ConnectionState` cases (`.disconnected(nil)` after `disconnect()`, else the error), `IBClient.init`, and the
    `ReconnectPolicy` / `Handshake` members left.
- [ ] **Step 3: Wrap the long lines** in every file listed (the `IBClient*.swift` signatures included).
- [ ] **Step 4: Verify:** the filtered audit → no output; long lines → literals only; `timeout 900 swift test` → 487.
- [ ] **Step 5: Commit:** «Document the wire layer, the client and its errors».

### Task 4: The rest documented; the audit at zero

**Files:** Modify (docs + long lines): `Sources/IBKR/Models/Research.swift` (58, 3 long lines), `Models/Account.swift`
(31), `Models/Contract.swift` (30, 3), `Models/Execution.swift` (26), `Models/ExecutionFilter.swift` (9),
`Models/Reference.swift` (12, 1), `Models/Session.swift` (5), `State/ExecutionTracker.swift` (7, 1),
`State/PositionTracker.swift` (2)

**Interfaces:** Consumes the audit.

- [ ] **Step 1: Run the audit** (unfiltered) → 180 lines, all in the files above.
- [ ] **Step 2: Document them.** Pointers: `Contract` fields are `ib_async`'s `Contract` attributes (`conID` IB's
  contract id, `secType` IB's code, `exchange` `SMART` by default); `Position.quantity` (shares or contracts, negative
  short), `averageCost` (IB's average cost per unit, multiplier included as IB sends it); `AccountValue.value` IB's
  string; `PnL` / `AccountPnL` fields `nil` for IB's unset value; `Execution` fields (execDetails 11; `time` IB's raw
  text, see KNOWN-GAPS); `CommissionReport` (59); `ExecutionFilter` (`nil` sends IB's «any»); `ScannerSubscription`
  fields (`nil` unset, per DECISIONS); `FADataType` (IB's 1–3); `ServerLogLevel` (IB's 1–5).
- [ ] **Step 3: Wrap the long lines** in those files.
- [ ] **Step 4: Verify:** the audit → no output, **exit 0**, for both modules; long-line check over all of
  `Sources/` → literals only; `timeout 900 swift test` → 487.
- [ ] **Step 5: Commit:** «Document the remaining public API, bringing the doc-coverage audit to zero».

### Task 5: DocC catalogs

**Files:**
- Create: `Sources/IBKR/IBKR.docc/IBKR.md`, `GettingStarted.md`, `Orders.md`, `MarketData.md`,
  `MigratingFromIbAsync.md`; `Sources/IBKRFlex/IBKRFlex.docc/IBKRFlex.md`

**Interfaces:** Consumes Task 4's complete symbol graph. Produces the article references `<doc:GettingStarted>`,
`<doc:Orders>`, `<doc:MarketData>`, `<doc:MigratingFromIbAsync>` (Task 8's README links the published site, not
these).

Every code sample below is either written here or copied from README's Guide section named, which is checked
against the code. No sample places an order against an unnamed account; account ids are `DU0000001`.

- [ ] **Step 1: `IBKR.md`**, exactly as below, except that each `### group`'s comma-separated entries become one
  `- ` list item per line in the file.

````markdown
# ``IBKR``

A pure-Swift client for Interactive Brokers' IB Gateway and TWS, speaking the TWS API socket protocol directly.

## Overview

``IBClient`` is one actor per connection. Account state (orders, fills, positions, portfolio, account values) is
synced at connect and offered as a snapshot plus a stream of changes; every other request is either a one-shot
`async throws` call or a stream whose end sends IB's cancel. Errors are typed (``IBClientError``), money is
`Decimal`, and the wire protocol is pinned to server version 178.

> Important: Not affiliated with Interactive Brokers. Pointed at a live account the library places real orders; try
> everything on a paper account first.

## Topics

### Essentials
<doc:GettingStarted>, ``IBClient``, ``ConnectionState``, ``ReconnectPolicy``, ``IBClientError``

### Contracts
``Contract``, ``ContractDetails``, ``ContractDescription``, ``ContractQualification``, ``ComboLeg``, ``DeltaNeutralContract``

### Orders
<doc:Orders>, ``Order``, ``OrderAction``, ``BracketOrder``, ``OrderCondition``, ``TagValue``, ``OrderSnapshot``, ``OrderStatus``, ``OrderState``, ``ExerciseAction``

### Executions, positions and account
``Fill``, ``Execution``, ``CommissionReport``, ``ExecutionFilter``, ``Position``, ``PortfolioItem``, ``AccountValue``, ``AccountPnL``, ``PnL``

### Market data
<doc:MarketData>, ``Tick``, ``Ticker``, ``TickField``, ``GenericTick``, ``MarketDataType``, ``OptionComputation``, ``DepthBook``, ``TickByTick``, ``TickByTickType``

### History
``Bar``, ``BarEvent``, ``HistoricalSchedule``, ``HistoricalSession``, ``HistogramData``

### Options and reference data
``OptionChain``, ``PriceIncrement``, ``FamilyCode``, ``SoftDollarTier``

### Scanner, news and research
``ScannerSubscription``, ``ScanData``, ``NewsProvider``, ``NewsArticle``, ``HistoricalNews``, ``NewsBulletin``, ``WshEventData``, ``FADataType``, ``ServerLogLevel``

### State trackers
``OrderTracker``, ``ExecutionTracker``, ``PositionTracker``

### Wire protocol
``IBRequest``, ``IBMessage``, ``IBErrorMessage``, ``ErrorCode``, ``ErrorKind``, ``IBDecoder``, ``Handshake``, ``IBProtocolError``, ``IBEncodingError``

### Coming from ib_async
<doc:MigratingFromIbAsync>
````

- [ ] **Step 2: The four articles.** Each starts `# <Title>`, then a one-sentence abstract, then the sections below.
  - `GettingStarted.md`, «Getting Started», abstract «Add the package, reach a paper IB Gateway and read your
    account.» Sections: *Add the package* (the SPM snippet with
    `.package(url: "https://github.com/peppperrroni/swift-ibkr.git", from: "1.0.0")` and
    `.product(name: "IBKR", package: "swift-ibkr")`; the CocoaPods line with `:tag => '1.0.0'`). *Prepare the
    gateway* (Enable ActiveX and Socket Clients; Read-Only API off only to place orders; README's ports table).
    *Connect and read* with this sample:

    ```swift
    import IBKR

    let client = IBClient()
    Task { for await state in await client.states() { print(state) } }   // the current state first
    try await client.connect(port: 4002, clientID: 7)                      // paper IB Gateway on 127.0.0.1
    print(try await client.currentTime())
    print(try await client.managedAccounts())
    for position in await client.positions().snapshot {
        print(position.contract.symbol, position.quantity, position.averageCost)
    }
    await client.disconnect()
    ```

    *Staying connected* (README «Connecting» bullets on reconnect, condensed, with its `ReconnectPolicy()` sample).
    *Next* (points to `Examples/IBKRExample`, <doc:Orders>, <doc:MarketData>). Links:
    ``IBClient/connect(host:port:clientID:timeout:reconnect:)``, ``IBClient/states()``, ``IBClient/currentTime()``,
    ``IBClient/managedAccounts()``, ``IBClient/positions()``, ``IBClient/disconnect()``, ``ReconnectPolicy``.
  - `Orders.md`, «Orders», abstract «Place, follow, modify and cancel orders.» Sections and samples from README
    «Orders» (all four code blocks) and «Executions, positions and portfolio» (the `executions()` line): *Placing
    and following*, *Brackets and OCA groups*, *Conditions and algos*, *What-if and exercise*, *How IB's errors
    reach an order* (README «Errors»: warnings record `rejectReason`, 202 confirms a cancel). Links:
    ``IBClient/placeOrder(_:_:)``, ``IBClient/orders()``, ``IBClient/modifyOrder(_:_:_:)``,
    ``IBClient/cancelOrder(_:manualCancelOrderTime:)``, ``IBClient/cancelAllOrders()``,
    ``Order/market(_:quantity:)``, ``Order/limit(_:quantity:price:)``, ``Order/stop(_:quantity:stopPrice:)``,
    ``Order/stopLimit(_:quantity:limitPrice:stopPrice:)``,
    ``Order/bracket(_:quantity:limitPrice:takeProfitPrice:stopLossPrice:)``, ``IBClient/placeBracket(_:_:)``,
    ``Order/oneCancelsAll(_:group:type:)``, ``OrderCondition``, ``IBClient/whatIfOrder(_:_:)``,
    ``IBClient/exerciseOptions(_:action:quantity:account:override:)``, ``IBClient/executions()``,
    ``OrderSnapshot``, ``OrderStatus``, ``IBEncodingError/nonASCII(field:)``.
  - `MarketData.md`, «Market Data», abstract «Quotes, tickers, bars, depth and history, and what happens without a
    subscription.» Samples from README «Market data» and «History». Sections: *Without a subscription*
    (`setMarketDataType(.delayed)` after every connect; refusals end the stream with
    ``IBClientError/noMarketDataPermission(code:text:)``), *Quotes and tickers*, *Bars, depth and tick-by-tick*,
    *History*, *Stopping a stream* (leaving `for try await` sends the cancel). Links:
    ``IBClient/setMarketDataType(_:)``, ``IBClient/marketData(_:genericTicks:snapshot:regulatorySnapshot:)``,
    ``IBClient/tickers(_:genericTicks:depthRows:smartDepth:)``, ``IBClient/tickers(for:regulatorySnapshot:)``,
    ``Ticker/apply(_:)``, ``IBClient/realTimeBars(_:whatToShow:rth:)``, ``IBClient/marketDepth(_:rows:smart:)``,
    ``IBClient/tickByTick(_:_:)``, ``IBClient/historicalBars(_:end:duration:barSize:whatToShow:rth:keepUpToDate:)``,
    ``IBClient/historicalTicks(_:start:end:count:whatToShow:rth:ignoreSize:)``,
    ``IBClient/headTimeStamp(_:whatToShow:rth:)``, ``IBClient/histogramData(_:period:rth:)``,
    ``IBClient/historicalSchedule(_:days:end:rth:)``.
  - `MigratingFromIbAsync.md`, «Migrating from ib_async», abstract «How ib_async's calls and events map onto
    swift-ibkr.» Sections: *One actor instead of an event loop* (no `ib.sleep`/`waitOnUpdate`; `await`), *Names*
    (README's naming rule and its four exceptions), *State instead of events* (`trades()`/`fills()`/`positions()`
    and their events → snapshot plus stream from ``IBClient/orders()``, ``IBClient/executions()``,
    ``IBClient/positions()``; raw frames on ``IBClient/messages()``), *Requests* (one-shots return; streams send
    the cancel when the loop ends, so there is no `cancel…` call), *Errors* (thrown ``IBClientError`` instead of
    `errorEvent`), *Numbers* (`Decimal`, `nil` for IB's unset values instead of `nan`), *Reconnect*
    (``ReconnectPolicy`` instead of `Watchdog`; no IBC), *The full table* (one sentence: README's «ib_async →
    swift-ibkr» section maps every call). One side-by-side sample:

    ```python
    ib = IB()
    ib.connect('127.0.0.1', 4002, clientId=7)
    trade = ib.placeOrder(Stock('AAPL', 'SMART', 'USD'), LimitOrder('BUY', 1, 180))
    ```

    ```swift
    let client = IBClient()
    try await client.connect(port: 4002, clientID: 7)
    let id = try await client.placeOrder(.stock("AAPL", exchange: "SMART", currency: "USD"),
                                         .limit(.buy, quantity: 1, price: 180))
    ```

- [ ] **Step 3: `IBKRFlex.md`**: `# ``IBKRFlex```, abstract «Download Interactive Brokers Flex reports and read them
  as records.», *Overview* (a separate product, Foundation only, no link to `IBKR`, SwiftPM only; token and query id
  from Client Portal), *Usage* with README «Flex reports»'s sample, prose links ``FlexReport/download(token:queryID:url:pollInterval:transport:)``,
  ``FlexReport/init(data:)``, ``FlexReport/topics``, ``FlexReport/extract(_:)``, ``FlexRecord/decimal(_:)``, and
  `## Topics` / `### Reports` with ``FlexReport``, ``FlexRecord``, ``FlexError``, ``FlexTransport``.
- [ ] **Step 4: Check every link against the symbol graph** (after the audit's builds):

```bash
python - <<'EOF'
import glob, json, re
known = set()
for p in glob.glob('.build/symbol-graphs/*.symbols.json'):
    known |= {'/'.join(s['pathComponents']) for s in json.load(open(p, encoding='utf-8'))['symbols']}
for md in glob.glob('Sources/*/*.docc/*.md'):
    for link in re.findall(r'``([^`]+)``', open(md, encoding='utf-8').read()):
        if re.sub(r'^(IBKR|IBKRFlex)/', '', link) not in known | {'IBKR', 'IBKRFlex'}:
            print(md, link)
EOF
```

  Expected: no output. Also `grep -o '<doc:[A-Za-z]*>' Sources/IBKR/IBKR.docc/*.md | sort -u` names only the four
  article files.
- [ ] **Step 5: Verify SwiftPM ignores the catalogs:** `swift build 2>&1 | grep -i unhandled` → nothing;
  `timeout 900 swift test` → 487. (DocC itself builds only on macOS: Task 6's CI run is its check.)
- [ ] **Step 6: Commit:** «Add DocC catalogs for IBKR and IBKRFlex with four articles». Body: links checked against
  the symbol graph because docc is not in the Windows toolchain; the first macOS docs build is the real check.

### Task 6: The docs workflow and `.spi.yml`

**Files:** Create: `.github/workflows/docs.yml`, `.spi.yml`

**Interfaces:** Consumes `Scripts/doc-coverage.py` (Task 1), the catalogs (Task 5). Produces the site
`https://peppperrroni.github.io/swift-ibkr/` (landing), `…/ibkr/documentation/ibkr/`,
`…/ibkrflex/documentation/ibkrflex/`, which Task 8 links.

- [ ] **Step 1: Write `.github/workflows/docs.yml`**

```yaml
name: Docs

on:
  push:
    branches: ["**"]
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v7
      - name: Doc coverage
        run: |
          mkdir -p .build/symbol-graphs
          for t in IBKR IBKRFlex; do
            swift build --target $t -Xswiftc -emit-symbol-graph -Xswiftc -emit-symbol-graph-dir -Xswiftc .build/symbol-graphs
          done
          python3 Scripts/doc-coverage.py .build/symbol-graphs/*.symbols.json
      - name: Build the DocC archives
        run: >
          xcodebuild docbuild -scheme swift-ibkr-Package -destination 'generic/platform=macOS'
          -derivedDataPath .build/docbuild OTHER_DOCC_FLAGS=--warnings-as-errors
      - name: Transform for static hosting
        run: |
          for module in IBKR IBKRFlex; do
            lower=$(echo "$module" | tr '[:upper:]' '[:lower:]')
            archive=$(find .build/docbuild -type d -name "$module.doccarchive" | head -n 1)
            test -n "$archive"
            xcrun docc process-archive transform-for-static-hosting "$archive" \
              --output-path "site/$lower" --hosting-base-path "swift-ibkr/$lower"
          done
          cat > site/index.html <<'HTML'
          <!doctype html>
          <html lang="en">
          <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
          <title>swift-ibkr documentation</title></head>
          <body>
          <h1>swift-ibkr</h1>
          <ul>
          <li><a href="ibkr/documentation/ibkr/">IBKR</a>: the TWS API client</li>
          <li><a href="ibkrflex/documentation/ibkrflex/">IBKRFlex</a>: Flex Web Service reports</li>
          </ul>
          </body>
          </html>
          HTML
          test -f site/ibkr/documentation/ibkr/index.html
          test -f site/ibkrflex/documentation/ibkrflex/index.html
      - uses: actions/upload-pages-artifact@v4
        with:
          path: site

  deploy:
    needs: build
    if: github.ref == 'refs/heads/main' && github.event_name != 'pull_request'
    runs-on: ubuntu-latest
    permissions:
      pages: write
      id-token: write
    concurrency:
      group: pages
      cancel-in-progress: false
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

  The YAML literal block strips the common indent, so the heredoc's `HTML` terminator lands in column 0.
  `upload-pages-artifact@v4` and `deploy-pages@v4` are the majors current at writing; the first CI run verifies
  them (a «not found» or deprecation annotation means bump the major). The deploy job fails until the owner enables
  Pages (Settings → Pages → Source: GitHub Actions); KNOWN-GAPS (Task 8) says so.
- [ ] **Step 2: Write `.spi.yml`**

```yaml
version: 1
builder:
  configs:
    - documentation_targets: [IBKR, IBKRFlex]
```

- [ ] **Step 3: Verify locally** what Windows can: it cannot run the workflow, so read both files once against the
  blocks above; run the «Doc coverage» step's commands (the audit) → exit 0;
  `timeout 900 swift test` → 487. The controller's push runs the workflow; a DocC warning it reports is fixed in a
  follow-up commit on the file it names, and the run repeated until green.
- [ ] **Step 4: Commit:** «Build the DocC docs on every push and publish them to GitHub Pages from main». Body: one
  static-hosting folder per module under one site with a landing page instead of `docc merge`; the coverage gate
  runs before the docs build; deploy only from `main`, concurrency on the deploy job only; the Pages switch is the
  owner's.

### Task 7: The console example

**Files:**
- Create: `Examples/IBKRExample/Package.swift`, `Examples/IBKRExample/Sources/ibkr-example/main.swift`
- Modify: `.github/workflows/ci.yml` (macOS job after `swift test`, Linux job after `swift test`)

**Interfaces:** Consumes the public `IBClient` API only. Produces `swift run --package-path Examples/IBKRExample
ibkr-example [port] [clientID]`, which Task 8's README and CONTRIBUTING cite.

- [ ] **Step 1: `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

// The dependency's identity is the repository folder's name, `swift-ibkr` in a default clone and in CI.
let package = Package(
    name: "IBKRExample",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(name: "ibkr-example", dependencies: [.product(name: "IBKR", package: "swift-ibkr")]),
    ]
)
```

- [ ] **Step 2: `main.swift`**

```swift
import Foundation
import IBKR

// Read-only: connects to a paper IB Gateway, prints the server time, accounts, positions and an account summary,
// then disconnects. It never places or cancels an order.
// Usage: ibkr-example [port, default 4002] [clientID, default 7]
let arguments = Array(CommandLine.arguments.dropFirst())
let port = arguments.first.flatMap { Int($0) } ?? 4002
let clientID = arguments.dropFirst().first.flatMap { Int($0) } ?? 7

let client = IBClient()
do {
    try await client.connect(host: "127.0.0.1", port: port, clientID: clientID)
    print("Server time:", try await client.currentTime())
    print("Accounts:", try await client.managedAccounts().joined(separator: ", "))
    for position in await client.positions().snapshot {
        print("Position:", position.account, position.contract.symbol, position.quantity, position.averageCost)
    }
    for try await summary in try await client.accountSummary(tags: ["NetLiquidation", "TotalCashValue", "BuyingPower"]) {
        for value in summary { print("Summary:", value.account, value.tag, value.value, value.currency) }
        break   // the first whole set is enough; leaving the loop cancels the subscription
    }
} catch {
    print("Failed:", error)
    await client.disconnect()
    exit(1)
}
await client.disconnect()
```

- [ ] **Step 3: Check it is read-only:** `grep -nE 'placeOrder|placeBracket|modifyOrder|cancelOrder|cancelAllOrders|exerciseOptions' Examples -r`
  → nothing.
- [ ] **Step 4: Build and run without a gateway:** `swift build --package-path Examples/IBKRExample` → succeeds;
  `timeout 60 swift run --package-path Examples/IBKRExample ibkr-example 4999; echo $?` → a `Failed:` line and
  exit 1 within seconds (nothing listens on 4999).
- [ ] **Step 5: CI:** in `.github/workflows/ci.yml` add `- run: swift build --package-path Examples/IBKRExample` as
  the step after `- run: swift test` in the `macos` job and in the `linux` job. Windows is left out (ruling 6).
- [ ] **Step 6: Verify the root package is unchanged:** `git diff --stat Package.swift` → empty;
  `timeout 900 swift test` → 487.
- [ ] **Step 7: Commit:** «Add a read-only console example as its own package, built by CI». Body: a separate
  package so the root keeps its products and the example shows a consumer's own manifest; no test, it needs a
  gateway.

### Task 8: Release documents and the leftover minors

**Files:**
- Modify: `README.md` (badges line 3, Status 46–63, Installation 75–95, «ib_async names» 441–481, Documents table
  517–522), `CHANGELOG.md` (line 5), `SwiftIBKR.podspec` (line 4), `docs/DECISIONS.md` (lines 82, 92, new rows
  after the last row of the main table), `docs/KNOWN-GAPS.md`,
  `Tests/IBKRFlexTests/FlexDownloadTests.swift:123-130`
- Create: `CONTRIBUTING.md`, `.github/ISSUE_TEMPLATE/bug_report.md`, `.github/ISSUE_TEMPLATE/feature_request.md`

**Interfaces:** Consumes the site URLs (Task 6), the example command (Task 7), the script (Task 1).

- [ ] **Step 1: Bound `cancellingStopsThePolling`.** Add after `query(_:)` in `FlexDownloadTests.swift`:

```swift
/// The task's result, or nil when it has not finished within `limit`. A hung task is left behind, not awaited.
private func result<T: Sendable>(of task: Task<T, any Error>, within limit: Duration) async -> Result<T, any Error>? {
    let results = AsyncStream<Result<T, any Error>?> { continuation in
        Task { continuation.yield(await task.result) }
        Task { try? await Task.sleep(for: limit); continuation.yield(nil) }
    }
    for await first in results { return first }
    return nil
}
```

  and replace the test's body:

```swift
    @Test func cancellingStopsThePolling() async throws {
        let fake = FakeFlexService([.success(sendSuccess)] + Array(repeating: .success(inProgress), count: 10))
        let task = Task { try await download(fake, pollInterval: .seconds(60)) }
        let deadline = ContinuousClock.now + .seconds(10)
        while await fake.urls.isEmpty {
            guard ContinuousClock.now < deadline else { task.cancel(); Issue.record("no SendRequest in 10 s"); return }
            await Task.yield()
        }
        task.cancel()
        guard let outcome = await result(of: task, within: .seconds(10)) else {
            Issue.record("still polling 10 s after the cancel"); return
        }
        #expect(throws: CancellationError.self) { try outcome.get() }
        #expect(await fake.urls.count == 1)
    }
```

  Why it is bounded: `download` cancels inside the 60 s sleep before the first GetStatement, so with working
  cancellation `task.result` arrives in milliseconds and wins the race. If cancellation were ignored, the task would
  sleep 60 s per poll (11 minutes over the ten replies), so the 10 s timer yields `nil` first and the test fails in
  10 s; if SendRequest never went out, the deadline loop fails it in 10 s. Neither waiter is a child task, so the
  test returns without waiting for the hung download.
- [ ] **Step 2: Show it** (the mutation run, then revert): in `Sources/IBKRFlex/FlexReport+Download.swift`, replace
  `try await Task.sleep(for: pollInterval)` with `try await Task.detached { try await Task.sleep(for: pollInterval) }.value`
  (a detached sleep ignores the cancel); `timeout 120 swift test --filter cancellingStopsThePolling` → FAIL with
  «still polling 10 s after the cancel» in about 10 s. `git checkout Sources/IBKRFlex/FlexReport+Download.swift`;
  the same filter → PASS.
- [ ] **Step 3: README.**
  - Line 3: after the CI badge add
    `[![Docs](https://github.com/peppperrroni/swift-ibkr/actions/workflows/docs.yml/badge.svg)](https://peppperrroni.github.io/swift-ibkr/)`.
    After the intro paragraph (line 6) add: «Documentation, with articles on getting started, orders, market data
    and migrating from `ib_async`: <https://peppperrroni.github.io/swift-ibkr/>.»
  - Status rows: replace every «a live run is due in stage 13» with «not yet run live (see KNOWN-GAPS)».
  - Line 63 becomes: «Releases follow [Semantic Versioning](https://semver.org/): from 1.0.0 on, a change that breaks
    the public API comes only with a new major version. New cases in the protocol enums (`IBRequest`, `IBMessage`,
    `Tick`, `IBClientError` and the like) follow IB's protocol and arrive in minor versions, so an exhaustive `switch`
    over one may need a new branch after an update.»
  - Installation: the SPM line becomes `.package(url: "https://github.com/peppperrroni/swift-ibkr.git", from: "1.0.0"),`;
    the pod line `pod 'SwiftIBKR', :git => 'https://github.com/peppperrroni/swift-ibkr.git', :tag => '1.0.0'`; the
    sentence «Publication to the CocoaPods trunk is pending.» becomes «Publication to the CocoaPods trunk is
    pending, so install the pod from the tag as above.» After the ports table add: «A runnable, read-only example is
    in [`Examples/IBKRExample`](Examples/IBKRExample): `swift run --package-path Examples/IBKRExample ibkr-example
    [port] [clientID]` prints the server time, accounts, positions and an account summary.»
  - Documents table: add the row
    `` | [`CONTRIBUTING.md`](CONTRIBUTING.md) | how to build, test, check doc coverage and send a change | ``.
  - Replace lines 441–481 (heading, intro, table) with exactly:

```markdown
## ib_async → swift-ibkr

Every `ib_async` call that reaches the socket has a counterpart below. Names are `ib_async`'s minus a leading
`req`, with `Id` written `ID`, except `faData`, `optionChains`, `displayGroups` and `displayGroupUpdates`
(DECISIONS). There is no `cancel…` call: leaving a stream's `for await` sends IB's cancel. «none» marks what the
library leaves out.

| ib_async | swift-ibkr |
|---|---|
| `connect` / `connectAsync` (with `startApi`) | `connect(host:port:clientID:timeout:reconnect:)` |
| `disconnect` | `disconnect()` |
| `isConnected`, `connectedEvent`, `disconnectedEvent` | `states()` (the current state first) |
| `Watchdog` | `ReconnectPolicy`, passed as `connect(…, reconnect:)` |
| `IBC` | none |
| `sleep`, `waitOnUpdate`, `loopUntil`, `setTimeout` | none: `async`/`await` |
| `errorEvent` and the other raw events | thrown `IBClientError`s, the streams below, and `messages()` for every decoded frame |
| `reqCurrentTime` | `currentTime()` |
| `managedAccounts` / `reqManagedAccts` | `managedAccounts()` |
| `reqIds` | `nextOrderID()` |
| `reqUserInfo` | `userInfo()` |
| `setServerLogLevel` | `setServerLogLevel(_:)` |
| `reqAutoOpenOrders` | `setAutoOpenOrders(_:)` |
| `reqMarketDataType` | `setMarketDataType(_:)` |
| `placeOrder` (a new order) | `placeOrder(_:_:)`, which returns the order id |
| `placeOrder` (an existing order) | `modifyOrder(_:_:_:)` |
| `cancelOrder` | `cancelOrder(_:manualCancelOrderTime:)` |
| `reqGlobalCancel` | `cancelAllOrders()` |
| `whatIfOrder` | `whatIfOrder(_:_:)` |
| `exerciseOptions` | `exerciseOptions(_:action:quantity:account:override:)` |
| `trades`, `openTrades`, `orders`, `openOrders`, `reqOpenOrders`, `reqAllOpenOrders`, `reqCompletedOrders` | `orders()` (open and completed orders, synced at connect) |
| `Trade` | `OrderSnapshot` |
| `fills`, `executions`, `reqExecutions` | `executions()` (synced at connect) |
| `Fill` | `Fill` |
| `MarketOrder`, `LimitOrder`, `StopOrder`, `StopLimitOrder` | `Order.market(_:quantity:)`, `.limit(_:quantity:price:)`, `.stop(_:quantity:stopPrice:)`, `.stopLimit(_:quantity:limitPrice:stopPrice:)` |
| `bracketOrder` | `Order.bracket(_:quantity:limitPrice:takeProfitPrice:stopLossPrice:)`, placed with `placeBracket(_:_:)` |
| `oneCancelsAll` | `Order.oneCancelsAll(_:group:type:)` |
| `PriceCondition`, `TimeCondition`, `MarginCondition`, `ExecutionCondition`, `VolumeCondition`, `PercentChangeCondition` | `OrderCondition.price`, `.time`, `.margin`, `.execution`, `.volume`, `.percentChange` |
| `positions`, `reqPositions` | `positions()` |
| `portfolio`, `reqAccountUpdates` | `portfolio()` (synced at connect, one managed account only) |
| `accountValues` | `accountValues()` |
| `accountSummary` / `reqAccountSummary` | `accountSummary(tags:group:)` (a stream) |
| `reqAccountUpdatesMulti` | `accountUpdatesMulti(account:modelCode:ledgerAndNLV:)` (a stream) |
| `reqPositionsMulti` | `positionsMulti(account:modelCode:)` (a stream) |
| `pnl` / `reqPnL` | `pnl(account:modelCode:)` (a stream) |
| `pnlSingle` / `reqPnLSingle` | `pnlSingle(account:conID:modelCode:)` (a stream) |
| `reqContractDetails` | `contractDetails(_:)` |
| `reqMatchingSymbols` | `matchingSymbols(_:)` |
| `qualifyContracts` | `qualifyContracts(_:)` |
| `Stock`, `Option`, `Future`, `ContFuture`, `Forex`, `Index`, `CFD`, `Commodity`, `Bond`, `FuturesOption`, `MutualFund`, `Warrant`, `Bag`, `Crypto` | `Contract.stock`, `.option`, `.future`, `.contFuture`, `.forex`, `.index`, `.cfd`, `.commodity`, `.bond`, `.futuresOption`, `.mutualFund`, `.warrant`, `.bag`, `.crypto` |
| `reqSecDefOptParams` | `optionChains(for:futFopExchange:)` |
| `calculateImpliedVolatility` | `calculateImpliedVolatility(_:optionPrice:underPrice:options:)` |
| `calculateOptionPrice` | `calculateOptionPrice(_:volatility:underPrice:options:)` |
| `reqMarketRule` | `marketRule(_:)` |
| `reqFamilyCodes` | `familyCodes()` |
| `reqSoftDollarTiers` | `softDollarTiers()` |
| `reqMktData`, `ticker` | `marketData(_:genericTicks:snapshot:regulatorySnapshot:)` (raw ticks) or `tickers(_:genericTicks:depthRows:smartDepth:)` (whole `Ticker`s), both streams |
| `reqTickers` | `tickers(for:regulatorySnapshot:)` |
| `pendingTickers` | none: each `tickers` stream yields its own `Ticker` |
| `Ticker` | `Ticker` |
| `Ticker.marketPrice`, `Ticker.midpoint`, the tick filters and bar builders | none |
| `newsTicks` | `Tick.news` from `marketData` with the news generic ticks |
| `reqMktDepth` | `marketDepth(_:rows:smart:)` (whole `DepthBook`s), or `tickers` with `depthRows` |
| `reqMktDepthExchanges` | `depthExchanges()` |
| `reqSmartComponents` | `smartComponents(_:)` |
| `reqTickByTickData` | `tickByTick(_:_:)` |
| `reqRealTimeBars`, `realtimeBars` | `realTimeBars(_:whatToShow:rth:)` |
| `reqHistoricalData` | `historicalBars(_:end:duration:barSize:whatToShow:rth:keepUpToDate:)` |
| `reqHistoricalTicks` | `historicalTicks(_:start:end:count:whatToShow:rth:ignoreSize:)` |
| `reqHeadTimeStamp` | `headTimeStamp(_:whatToShow:rth:)` |
| `reqHistogramData` | `histogramData(_:period:rth:)` |
| `reqHistoricalSchedule` | `historicalSchedule(_:days:end:rth:)` |
| `reqScannerSubscription` | `scannerSubscription(_:options:filterOptions:)` (a stream) |
| `reqScannerData` | `scannerData(_:options:filterOptions:)` |
| `reqScannerParameters` | `scannerParameters()` |
| `reqNewsProviders` | `newsProviders()` |
| `reqNewsArticle` | `newsArticle(providerCode:articleID:options:)` |
| `reqHistoricalNews` | `historicalNews(conID:providerCodes:start:end:totalResults:options:)` |
| `reqNewsBulletins` | `newsBulletins(allMessages:)` (a stream) |
| `reqFundamentalData` | `fundamentalData(_:reportType:options:)` |
| `reqWshMetaData` / `getWshMetaData` | `wshMetaData()` |
| `reqWshEventData` / `getWshEventData` | `wshEventData(_:)` |
| `requestFA` | `faData(_:)` |
| `replaceFA` | `replaceFA(_:xml:)` |
| `queryDisplayGroups` | `displayGroups()` |
| `subscribeToGroupEvents` | `displayGroupUpdates(_:)` (a stream; stopping it unsubscribes) |
| `updateDisplayGroup` | `updateDisplayGroup(_:contractInfo:)` |
| `verifyRequest` | `verifyRequest(apiName:apiVersion:)` |
| `verifyMessage` | `verifyMessage(_:)` |
| `verifyAndAuthRequest` | `verifyAndAuthRequest(apiName:apiVersion:opaqueISVKey:)` |
| `verifyAndAuthMessage` | `verifyAndAuthMessage(_:xyzResponse:)` |
| `FlexReport(token, queryId)` / `download` | `FlexReport.download(token:queryID:)` |
| `FlexReport(path=)` / `load` / `save` | `FlexReport(data:)` / `report.data.write(to:)` |
| `extract` | `extract(_:)` (strings; `decimal(_:)` for numbers) |
| `topics` | `topics` |
| `FlexError` | `FlexError` (four cases) |
| `df` | none |
```

- [ ] **Step 4: CHANGELOG.** Line 5 `## [Unreleased]` becomes `## [Unreleased]`, a blank line, then
  `## [1.0.0] - 2026-11-12`. At the top of that release's `### Added` insert:

```markdown
- Doc comments on every public declaration of `IBKR` and `IBKRFlex`, checked by `Scripts/doc-coverage.py`, which reads the compiler's symbol graph.
- DocC catalogs for `IBKR` (articles: Getting Started, Orders, Market Data, Migrating from ib_async) and `IBKRFlex`, built with warnings as errors on every push by `.github/workflows/docs.yml` and published to GitHub Pages from `main` at <https://peppperrroni.github.io/swift-ibkr/>.
- `.spi.yml`, so the Swift Package Index builds the documentation of both modules.
- `Examples/IBKRExample`, a read-only console example (server time, accounts, positions, account summary), built by CI on macOS and Linux.
- `CONTRIBUTING.md` and GitHub issue templates for bug reports and feature requests.
```

  and at the top of its `### Changed`: `- The podspec version is 1.0.0, and README installs from the 1.0.0 tag.`
- [ ] **Step 5: podspec** line 4: `s.version      = '1.0.0'`.
- [ ] **Step 6: DECISIONS.**
  - Line 82: «version 0.5.0» → «version 1.0.0 (0.5.0 before the 1.0 release)».
  - Line 92: «(ruling R4) Like» → «(ruling R4). Like».
  - Append after the last row of the main table (the `FlexReport.urlSession` row, before `## Error-code table`):

```markdown
| Docs: `.github/workflows/docs.yml` builds both DocC archives with `xcodebuild docbuild` and `--warnings-as-errors`, transforms each for static hosting into its own folder (`ibkr/`, `ibkrflex/`) under one Pages site with a hand-written landing page, and deploys from `main` only; branches and pull requests build and check without deploying | the two modules share no types, so two archives with their own base paths need no merge step; building on every push catches a broken link before `main`; Pages is switched on by the owner, so the library never calls the Pages API | `docc merge` into one archive; the swift-docc-plugin dependency; deploying from every branch |
| Doc coverage: `Scripts/doc-coverage.py` reads the symbol graphs `swift build -emit-symbol-graph` writes and fails on any public symbol without a doc comment; the docs workflow runs it before the docs build | DocC does not report missing comments, and the symbol graph is built on every OS, so the check also runs on Windows, where docc is missing | a lint rule; leaving coverage to review |
| `Examples/IBKRExample` is its own package that depends on the root by path; it only reads (time, accounts, positions, summary), has no test and is built by CI on macOS and Linux | the root package keeps its products, and the example's manifest is the one a consumer writes; a test would need a gateway | an executable target in the root package; an example that places an order |
| Semantic versioning from 1.0.0, with new cases in the protocol enums (`IBRequest`, `IBMessage`, `Tick`, `IBClientError` …) shipped in minor versions | the enums mirror IB's protocol, which keeps growing; a major version per new IB message would make majors meaningless | treating every new case as breaking; promising exhaustive enums the protocol cannot keep |
```

- [ ] **Step 7: KNOWN-GAPS.**
  - Title `# Known gaps after stage 13`; in the intro «stages 1 to 12» becomes «stages 1 to 13» and «Flex reports)»
    becomes «Flex reports; the 1.0 release: doc comments, DocC, the example)».
  - First bullet under «To confirm against a live gateway»: «- The end-of-stage-13 live run did not happen: no paper
    IB Gateway was listening on 127.0.0.1:4002. It would have rerun `LiveTests` (connect and sync, a limit order
    placed and cancelled, the account summary, the contract lookups, the market data refusals) and been the first
    live sight of the stage 5–11 calls README's Status marks «not yet run live».»
  - Under «Not covered by CI» add: «- build the DocC docs anywhere but macOS, or build `Examples/IBKRExample` on
    Windows;» and «- deploy the docs
    until the owner enables GitHub Pages (Settings → Pages → Source: GitHub Actions): until then the docs
    workflow's deploy job fails on `main`.»
  - New section before «Sockets»:

```markdown
## Owner steps

These need the owner's accounts:

- Enable GitHub Pages with GitHub Actions as the source; the docs then appear at https://peppperrroni.github.io/swift-ibkr/.
- `pod trunk push SwiftIBKR.podspec` from the 1.0.0 tag (needs a CocoaPods trunk registration; trunk is announced
  to turn read-only on 2 December 2026, after which the pod installs from the git tag only).
- Submit the package to the Swift Package Index (a pull request to its package list); `.spi.yml` is ready.
- Live checks: market data once there is a subscription, `IBKRFlex` with a real token.
```

- [ ] **Step 8: `CONTRIBUTING.md`** with these sections, in this order:
  - *Building and testing*: `swift build` and `swift test` on macOS 13+, Linux (Swift 6.0 or later) and Windows
    (Swift 6.x toolchain; the same commands in PowerShell or Git Bash). The unit tests need no gateway.
  - *Live tests*: the commands from README «Development» (`IBKR_LIVE=1 swift test --filter LiveTests`,
    `IBKR_LIVE_FILL=1` with `IBKR_LIVE_FILL_PRICE`, `IBKR_FLEX_TOKEN` / `IBKR_FLEX_QUERY` with
    `--filter FlexLiveTests`, the PowerShell `$env:` form and `Remove-Item Env:…`). The guard: nothing is placed
    unless every managed account starts with `DU` (paper); recordings replace account ids with `DU0000001`. Never
    commit a real account id or a Flex token.
  - *Doc comments*: every public declaration has one; CONTRIBUTING carries the audit block from this plan's Global
    Constraints verbatim (with `python3`, and a note that Windows' `python3` may be a Store stub, use `python`). DocC builds on macOS:
    `xcodebuild docbuild -scheme swift-ibkr-Package -destination 'generic/platform=macOS'`.
  - *The example*: `swift build --package-path Examples/IBKRExample`; it must stay read-only.
  - *Commits*: one imperative sentence, then the reasoning (what was tried, rejected, why); lines up to 120 columns
    in `Sources`.
  - *Documents of record*: a behaviour change updates `README.md`, `CHANGELOG.md` (`Unreleased`),
    `docs/DECISIONS.md`, `docs/KNOWN-GAPS.md` and `docs/protocol-178.md` in the same commit.
  - *IB's code*: no code from IB's official API (`ibapi`) or other clients; wire layouts follow `ib_async` as read and
    `docs/protocol-178.md`, and every new message gets a codec test on a hand-built frame.
- [ ] **Step 9: Issue templates.** `bug_report.md`:

````markdown
---
name: Bug report
about: Something in swift-ibkr does not work as documented
labels: bug
---

**What happened, and what you expected**

**Minimal code that shows it**

```swift
```

**Versions**
- swift-ibkr version (tag or commit):
- OS and Swift version (`swift --version`):
- IB Gateway or TWS, and its version:
- Server version (from `ConnectionState.connected(serverVersion:accounts:)`):

**IB's error code and text, if any**

> Do not paste account ids, Flex tokens or anything else that identifies your account. Replace an account id with `DU0000001`.
````

  `feature_request.md`: front matter `name: Feature request`, `about: An ib_async call, an IB message or an API
  change swift-ibkr lacks`, `labels: enhancement`; sections *What you want to do*, *The ib_async call or IB message
  it maps to, if any*, *What you do today instead*.
- [ ] **Step 10: Verify.**
  - `grep -n 'due in stage 13\|no tagged releases\|branch: "main"\|<version>' README.md` → nothing.
  - Every right-column name in the new table is a public declaration: for each `name(` in it,
    `grep -rn "func name(" Sources` finds one (the signatures were taken from the code when this plan was written).
  - `grep -n '^## \[' CHANGELOG.md` → `[Unreleased]`, `[1.0.0] - 2026-11-12`, `[0.4.0] - 2026-11-11`.
  - `grep -n "s.version" SwiftIBKR.podspec` → `'1.0.0'`.
  - `timeout 900 swift test` → 487 passed; no new DU id (Global Constraints).
- [ ] **Step 11: Commit:** «Prepare the 1.0.0 release: version, changelog, README table, contributing guide and
  issue templates». Body: no live run (no gateway), so Status says «not yet run live»; the Flex cancel test is now
  bounded by a 10 s race and was shown to fail fast under a detached sleep; semver treats new protocol enum cases
  as minor.
