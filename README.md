# BudgetBot

Native iOS budget app. You feed it screenshots, photos, PDFs, or plain-text
descriptions of income and expenses — directly inside BudgetBot, or via the
system Share sheet from any app (Revolut, Mail, Files, Photos, Safari, …).
An AI agent using your own API key extracts the structured data, you confirm
in a review screen, and it lands in your books. Tracks bank, savings, credit,
and physical-cash accounts side-by-side, converts everything to your base
currency using daily ECB rates, charts in/out flows, asks the AI for
recommendations on cuts and savings, and answers free-form questions about
your spending.

## Stack

- **SwiftUI** + **SwiftData** (iOS 17+), versioned schema (`SchemaV1`) on a
  named on-disk store, migration plan stub for future versions.
- **Sign in with Apple** for auth. Profile lives in SwiftData.
- **Share Extension** (system Share sheet target). Drops attachments in the
  App Group container; the main app ingests on foreground.
- **VisionKit** (`VNDocumentCameraViewController`) for receipt scanning,
  **PhotosUI** for the library, **PDFKit** for PDF rendering.
- **Anthropic Claude** API — user-supplied key (Keychain), model selectable
  in Settings (Sonnet 4.6 / Opus 4.7 / Haiku 4.5).
  - **tool_use with `input_schema`** for extract + recommend (structured
    output, no prose parsing).
  - **Streaming + multi-turn + tool-using Ask tab.** The AI can call a
    `query_transactions` tool we expose locally, so answers are based on
    actual records (the model fetches what it needs on demand instead of
    being dumped a fixed 150-row window).
  - **Prompt caching** (`cache_control: ephemeral`) on system + tool blocks.
  - Exponential-backoff retries on 429 / 5xx / transient `URLError`s,
    exercised end-to-end by HTTP-path tests via `URLProtocol` stub.
  - Per-request timeout, cancellable via `Task.checkCancellation`.
  - Key is validated against `/v1/models` before saving.
- **ECB FX feed** for multi-currency conversion, with **per-transaction
  FX snapshots** taken at commit time so historical Net Worth doesn't
  rewrite itself as rates drift. All Net Worth and Analytics roll up in
  the user's chosen base currency.
- **Swift Charts** for analytics.
- **XCTest** suite: **88 unit tests + 6 XCUITest** (~75s total) covering
  AI tool decoding, AI HTTP retry / 4xx / 5xx via `URLProtocol` stub,
  SSE streaming, transaction-query tool, FX conversion + ECB XML parsing
  + per-tx snapshot, duplicate detection, category & account fuzzy
  matching, persistence + cascade deletes, pending-capture store, and
  end-to-end UI smoke tests (tab structure, capture screen, settings
  reachability, add-account flow).

## What ships

- Capture: scan / camera / photos / PDFs / text / Share-sheet → AI → Review
  with **duplicate detection** and AI-suggested **account hints** → save.
- Activity list, grouped by day, with filters and PDF/image attachment preview.
- Accounts: bank, savings, cash, credit, other — balances and Net Worth
  converted to base currency.
- Analytics: in/out/net, daily flow, category donut + legend, AI
  recommendations on silly spend and savings.
- **Ask**: free-form Q&A. AI sees a compact summary of recent transactions
  and balances — never your full export.
- Settings (reachable from Accounts → ⚙): profile, default and base
  currency, FX refresh button, monthly budget, AI model picker, API key
  replace/remove with validation, privacy links, **delete account & all
  data** (preview screen with live counts and `DELETE` confirmation).
- Ask now **streams responses, remembers the conversation, and can call
  `query_transactions`** to fetch precise data while answering.

## Setup

You need Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
cd BudgetBot
xcodegen generate
open BudgetBot.xcodeproj
```

In Xcode, set your team under **Signing & Capabilities** for both
`BudgetBot` and `ShareExtension` targets (the App Group `group.dev.toma5od.BudgetBot`
needs to be registered with the team). Run on a device or the iOS 17+
simulator. Sign in with Apple and the document scanner require a real device
for the full flow.

On first launch you'll Sign in with Apple, then paste an Anthropic API key
(get one at <https://console.anthropic.com>). The key is validated against
`api.anthropic.com` before being stored in the iOS Keychain.

## Project context — one person, one phone

BudgetBot is built and maintained by a **single developer**. That shapes
the engineering choices throughout: no backend to operate, no team
roles to coordinate, no team CI plan to pay for. The goal is "a real
production-quality iOS app that one human can keep running for years".

The codebase reflects that:
- **Zero hosted services we own** — the AI key is the user's, sync is
  CloudKit (Apple's infra), FX rates come from the ECB feed. There is
  nothing to deploy, monitor, or get paged for.
- **SwiftData over Core Data** — less ceremony, less typing, fewer
  places to make a mistake.
- **Tests favour breadth over depth** — fast unit tests on every
  decision-point (categorisation, FX, duplicate detection, subscription
  inference) instead of brittle integration suites.

If you're a future contributor or future-me coming back to this:
read `SOLID.md` for the rules of the codebase, `PRIVACY.md` for the
data-flow story, `TODO.md` for what was deliberately deferred.

## Tests & CI

Local:
```bash
make test          # unit + UI (~75s simulator boot dominates)
make test-unit     # unit only, ~0.5s
make test-ui       # UI only
make build         # build without running tests
make clean         # remove generated project + DerivedData
```

Override the simulator name if `iPhone 17` isn't on your machine:
```bash
make test SIM='iPhone 16 Pro'
```

### CI on the GitHub free plan — what we ran into and why we're fine

GitHub Free gives you **2,000 Actions minutes per month** on the
default runners. iOS work needs **macOS runners**, and every macOS
minute is billed at **10×** the rate of a Linux minute — so the
practical budget is **200 macOS minutes/month**. Our previous CI
pipeline (build + unit + UI tests) was ~10 minutes per push; about
20 pushes burned the whole quota.

After we hit the wall the workflow was trimmed to **unit tests only**,
which cuts each run to ~3–4 minutes. At that rate the free quota
comfortably covers ~50 pushes a month, which is more than enough for
a solo cadence. UI tests still run locally on demand via
`make test-ui` and are expected to be green before pushing anything
UI-shaped.

A **$0 Actions budget** is set on the GitHub account as a safety
catch: if usage ever exceeds the free 200 macOS-minute envelope,
Actions pauses for the rest of the cycle instead of running up a
bill. The catch is that pushes during a paused cycle don't trigger
CI — code still lands on `main`, you just verify locally.

**Why this doesn't really affect us:**
- We're solo. There's no team waiting on the CI signal to merge.
- Local `make test-unit` runs in under a second. Tight loop on logic
  changes is faster than a CI roundtrip anyway.
- `make test-ui` covers what CI can't. For UI-affecting commits, run
  it before pushing — that's the discipline.
- Quota resets on the 1st of each month. If we ever pause, the worst
  case is "no CI status badge for a few weeks" — not a real outage.

**Avoiding future trips into the wall:**
- Don't push CI-triggering churn for docs-only commits if you can
  group them with code changes. (We don't have a `paths-ignore` rule
  yet because it doesn't matter at our cadence; add one if it
  starts to.)
- The `concurrency: cancel-in-progress: true` in `ci.yml` already
  kills superseded runs to save minutes on rapid pushes.
- If a particular sprint is going to be UI-heavy, expect to bump the
  local `make test-ui` cadence and skip pushing until tests pass —
  no point burning minutes on a known-broken state.
- The unit-tests-only CI is in `.github/workflows/ci.yml` line that
  says `-only-testing:BudgetBotTests`. If you ever want UI tests in
  CI for a real PR review, remove that line for one run; don't
  permanently re-enable.

131 unit tests + 8 UI tests. All green locally.

## Project structure

```
BudgetBot/
  App/            composition root, scenePhase, tab routing
  Models/         SwiftData @Model types, schema/migrations, DTOs
  Services/       AI, FX, Auth, Keychain, DuplicateDetector
  ViewModels/     CaptureViewModel
  Views/          SwiftUI, grouped by feature
  Shared/         compiled into BOTH BudgetBot and ShareExtension
  Resources/      Assets.xcassets, Info.plist
ShareExtension/   system Share-sheet target
BudgetBotTests/   XCTest
tools/            scripts (e.g. make_icon.swift)
SOLID.md          architecture & conventions
TODO.md           deferred work (bank aggregator, CI, iCloud sync, …)
```

See `SOLID.md` for the architecture rules code is expected to obey,
`PRIVACY.md` for the data-flow + Apple-Review evidence document, and
`TODO.md` for what we deliberately punted on — most notably bank aggregator
integration (Plaid / TrueLayer / GoCardless / Revolut), which needs a
backend and was scoped out in favour of the Share-extension pipeline that
covers ~80% of the value with zero backend.
