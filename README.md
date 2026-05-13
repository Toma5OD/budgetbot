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

CI runs the same `xcodebuild test` on every push and PR to `main`
via GitHub Actions (`.github/workflows/ci.yml`). Test results are
uploaded as an `xcresult` artifact on every run; the xcodebuild log
is uploaded on failure.

88 unit tests + 6 UI tests. All green.

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
