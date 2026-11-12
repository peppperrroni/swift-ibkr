# Stage 5: Framework Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make swift-ibkr buildable and tested on macOS, Linux, Windows and iOS in CI. Let consumers build every
public model, and add the CocoaPods spec and the CHANGELOG that the later stages extend.

**Architecture:** There is no new protocol work.
- Public memberwise `init`s go on the existing models.
- One GitHub Actions workflow (`.github/workflows/ci.yml`) has one job per OS. CI is the first time the Darwin
  and Glibc branches of `TCPSocket.swift` get compiled, so this stage also fixes whatever breaks there.
- A podspec plus a CI `pod lib lint` job; `CHANGELOG.md` in Keep a Changelog form.

**Tech Stack:** Swift 6 (tools 6.0), SwiftPM, swift-testing, GitHub Actions, CocoaPods (lint only).

**Spec:** `docs/superpowers/specs/2026-11-12-parity-and-1.0-design.md` (stage 5, "Цели" 6–8, "Решения после
проверки строителем" 3). The base spec is `docs/superpowers/specs/2026-11-09-swift-ibkr-design.md`.

## Global Constraints

- No package dependencies. `Package.swift` keeps `// swift-tools-version: 6.0`.
- Platforms: `.macOS(.v13)`, `.iOS(.v16)`. Linux (Ubuntu, Swift 6.x) and Windows (Swift 6.x) are tested in CI.
- Money stays `Decimal`, and unset values stay `nil`. Never copy code from IB's `ibapi`.
- Commit messages:
  - one imperative sentence, then the reasoning;
  - the last line is exactly `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`;
  - read `git log` before writing one.
- Documents of record change in the same commit as the behaviour they describe: `README.md`, `docs/DECISIONS.md`,
  `docs/KNOWN-GAPS.md`, `docs/protocol-178.md`, `CHANGELOG.md`.
- Run every local `swift test` as `timeout 900 swift test`, in the foreground.
- The real paper account id must never appear in the repo. Recordings use `DU0000001`.
- Pushing the branch `stage-5-foundation` to `origin` to run CI is allowed. Pushing `main` is the controller's job,
  not the implementer's.

## Review Focus

1. **Peer closes the socket, then we write.** On macOS and Linux this must throw `.connectionClosed`, not kill the
   process with SIGPIPE. CI runs the existing `TCPSocketTests` on all three OSes. Task 2 adds a test for this case
   if `TCPSocketTests` has none.
2. **A consumer builds a model with only `import IBKR`** (no `@testable`), e.g. a fake `Execution` in their own
   tests. Task 1 pins this with a plain-import test file.
3. **The package builds for iOS** (`xcodebuild` with a generic iOS destination). Availability errors such as
   `ContinuousClock` or `makeStream` only show up there. Task 2's CI job pins this.
4. **Linux Foundation differences**: `DateFormatter` and time-zone parsing (`US/Eastern`), and `Decimal(string:)`.
   The existing codec and recorded-frame tests run on Linux in CI (Task 2).
5. **`pod lib lint` passes on the podspec** as it is in the repo, without a tag (Task 3).

---

### Task 1: Public initializers on every public model

**Files:**
- Modify: every file under `Sources/IBKR/Models/`. Also every other public struct a consumer receives from the
  public API but cannot build today, e.g. `OrderSnapshot`, `ExecutionSnapshot`/`Fill` and the depth book types
  (find them with `grep -rn "public struct" Sources/IBKR`).
- Modify: `Sources/IBKR/State/OrderTracker.swift`, only to make `OrderKey` `internal` if no public declaration uses
  it.
- Create: `Tests/IBKRTests/PublicAPITests.swift`.
- Modify: `CHANGELOG.md` (Task 3 creates it; if Task 1 runs first, create it here with the header and an
  `## [Unreleased]` section).

**Interfaces:**
- Produces: a `public init` on each public struct, with every stored property as a parameter in declaration order.
  Optional properties default to `nil`. Collection properties default to empty. Keep any `public init` that
  already exists, and keep its defaults (e.g. `Contract(symbol:secType:exchange:…)`).

- [ ] **Step 1: Write the failing test.** `Tests/IBKRTests/PublicAPITests.swift` starts with `import IBKR` and
  `import Testing`, and has NO `@testable`. It has one test, `everyPublicModelIsConstructible`, that builds one
  value of each public struct through its public init and `#expect`s one field of each. At minimum it covers
  `Position`, `AccountValue`, `PnL`, `Execution`, `CommissionReport`, `ContractDetails`, `ContractDescription`,
  `Bar`, `DepthLevel`, `DepthUpdate`, `OrderStatusMessage`, and the snapshot types the client publishes. Example
  line: `#expect(PnL(daily: 1, unrealized: nil, realized: nil, value: nil, position: nil).daily == 1)`, using
  whatever fields `PnL` really has.
- [ ] **Step 2: Run** `timeout 900 swift test --filter PublicAPITests`. Expected: a compile FAIL listing the
  inaccessible initializers.
- [ ] **Step 3: Add the public initializers** described under Interfaces. Make `OrderKey` internal if nothing
  public uses it.
- [ ] **Step 4: Run** `timeout 900 swift test`. Expected: all tests PASS (211 or more).
- [ ] **Step 5:** In CHANGELOG `Unreleased → Added`, add "public memberwise initializers on all models". Then commit.

### Task 2: Platforms and CI on macOS, Linux, Windows, iOS

**Files:**
- Modify: `Package.swift` (platforms `[.macOS(.v13), .iOS(.v16)]`).
- Create: `.github/workflows/ci.yml`.
- Modify: `Sources/IBKR/Client/TCPSocket.swift` and any other source that fails to compile or test on macOS or
  Linux.
- Modify: `Tests/IBKRTests/TCPSocketTests.swift`, only for Review Focus 1 if it is missing.
- Modify: `README.md` (Requirements: list the platforms and add a CI badge), `docs/KNOWN-GAPS.md` (drop "Darwin
  branch never compiled" and "Linux not tried"; add what CI does not cover), `docs/DECISIONS.md` (one row: the CI
  matrix and why), `CHANGELOG.md`.

**Interfaces:**
- Produces: a workflow named `CI` that triggers on `push` to any branch and on `pull_request`. Its jobs:
  - `macos`: `runs-on: macos-latest`. Runs `swift build`, then `swift test`, then
    `xcodebuild -scheme IBKR -destination 'generic/platform=iOS' build` (if `xcodebuild -list` names the SwiftPM
    scheme `swift-ibkr` or `IBKR-Package`, use that name).
  - `linux`: `runs-on: ubuntu-latest`, `container: swift:${{ matrix.swift }}`, with matrix `swift: ["6.0",
    "latest"]`. Runs `swift test`.
  - `windows`: `runs-on: windows-latest`. Sets up Swift 6.x with a maintained action
    (`compnerd/gha-setup-swift`, pinned to a tag or SHA), then runs `swift test`.
  - Live tests skip themselves because `IBKR_LIVE` is unset. Do not set it in CI.
  - `IBKR` is the name later stages use for the `pod lib lint` job in Task 3.

- [ ] **Step 1: Add the platforms** to `Package.swift`. Run `timeout 900 swift test` locally on Windows. Expected:
  PASS.
- [ ] **Step 2: Write `.github/workflows/ci.yml`** as described under Interfaces. Push the branch
  (`git push -u origin stage-5-foundation`) and watch the run with
  `gh run watch --exit-status $(gh run list --branch stage-5-foundation --limit 1 --json databaseId -q '.[0].databaseId')`.
  Expected on the first run: some jobs FAIL. That is the failing test this task fixes.
- [ ] **Step 3: Fix each failure at its root.**
  - Socket constants and types per OS.
  - Availability annotations: add `@available` only where the platform floor cannot be raised.
  - Linux Foundation gaps: prefer a portable call over `#if`.
  - Never weaken or skip a test to get green. If a test is genuinely platform-specific, guard it with a
    `.enabled(if:)` trait and a one-line reason.
- [ ] **Step 4: Review Focus 1.** If `TCPSocketTests` has no test where the peer closes and we then write, add
  `writeAfterPeerCloseThrowsConnectionClosed`. It accepts a connection on a loopback listener, closes the accepted
  socket, writes twice, and expects a thrown `IBClientError.connectionClosed` (or whatever error the socket layer
  already maps a closed peer to), not a crash.
- [ ] **Step 5: Repeat Steps 2–3 until every job is green.** `gh run view --log-failed` shows the failing lines.
- [ ] **Step 6: Update the docs** listed under Files. Run `timeout 900 swift test` locally. Commit, push, and wait
  for a green run.

### Task 3: Podspec, `pod lib lint` in CI, CHANGELOG

**Files:**
- Create: `SwiftIBKR.podspec`.
- Modify: `.github/workflows/ci.yml` (job `pod-lint` on `macos-latest`: `pod lib lint SwiftIBKR.podspec`).
- Create or modify: `CHANGELOG.md`.
- Modify: `README.md` (Installation: a CocoaPods subsection), `docs/DECISIONS.md` (the pod name row).

**Interfaces:**
- Podspec values:
  - `name 'SwiftIBKR'`, `module_name 'IBKR'`, `version '0.5.0'`;
  - `summary 'Pure-Swift client for Interactive Brokers IB Gateway and TWS (TWS API socket protocol).'`;
  - `homepage` and `source` are `https://github.com/peppperrroni/swift-ibkr`; `source` uses `:tag => s.version.to_s`;
  - `license { :type => 'MIT', :file => 'LICENSE' }`, `author 'peppperrroni'`;
  - `swift_versions ['6.0']`, `ios.deployment_target '16.0'`, `osx.deployment_target '13.0'`;
  - `source_files 'Sources/IBKR/**/*.swift'`.

  The pod is named `SwiftIBKR` because the bare `IBKR` reads as IB's own. The module stays `IBKR`, so
  `import IBKR` works the same under SPM and CocoaPods.
- CHANGELOG format: Keep a Changelog 1.1.0 with semantic versioning.
  - `## [Unreleased]` holds stage 5's entries.
  - `## [0.4.0] - 2026-11-11` summarises stages 1–4 as Added bullets (connection, orders, executions, positions,
    account summary/P&L, contract lookup, market data), one line each.
  - Do not create the tag. The 0.4.0 heading only records history.

- [ ] **Step 1: Write the podspec** and the `pod-lint` job. Push, then watch CI as in Task 2. Expected: the
  `pod-lint` job PASSES. If lint fails because the tag `0.5.0` does not exist, use `pod lib lint` (local source)
  rather than `pod spec lint`; it must not need the tag.
- [ ] **Step 2: Write `CHANGELOG.md`** and the README CocoaPods subsection. Its snippet is
  `pod 'SwiftIBKR', :git => 'https://github.com/peppperrroni/swift-ibkr.git', :tag => '<version>'`. Add one sentence
  saying trunk publication is pending.
- [ ] **Step 3:** Add a DECISIONS row: the pod name and why, the module name kept as `IBKR`, and that docs build
  without the docc plugin dependency. Commit, push, and wait for green CI.
