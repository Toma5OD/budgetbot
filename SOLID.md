# SOLID.md — architecture & conventions

This file describes how BudgetBot is *meant* to be built. If you find code that
disagrees with this document, **the code is wrong unless this document is
explicitly updated in the same commit**.

## Targets

- **BudgetBot** — the iOS app. SwiftUI + SwiftData, iOS 17+.
- **ShareExtension** — system Share-sheet target. Accepts images, PDFs, text;
  drops them in the App Group container; main app ingests on `scenePhase ==
  .active`. Has no API key access of its own and never calls the network.
- **BudgetBotTests** — XCTest unit tests. Uses an in-memory `ModelContainer`.

App Group: `group.dev.toma5od.BudgetBot` (shared between BudgetBot and
ShareExtension).

## Layer responsibilities

```
App/        — composition root: @main, scenePhase, tab routing, container
Models/     — SwiftData @Model types, ExtractedDraft wire types, schema/migrations
Services/   — pure or stateless logic that talks to Keychain, Anthropic, ECB,
              the file system, etc. No SwiftUI.
ViewModels/ — @Observable types that wrap Services for the views. No views.
Views/      — SwiftUI only. May read Services from the environment but not
              construct them.
Shared/     — code compiled into BOTH BudgetBot and ShareExtension targets
              (App Group config, PendingCaptureStore).
Resources/  — Assets.xcassets, Info.plist.
```

Dependency rule: **Views → ViewModels → Services → Models**. No edges
backwards. Services never import SwiftUI.

## Single Responsibility, in practice

| File                       | One job                                                          |
| -------------------------- | ---------------------------------------------------------------- |
| `AIService.swift`          | Anthropic Messages API: extract, recommend, answer, validate-key |
| `FXService.swift`          | ECB rates: fetch, cache, convert                                 |
| `KeychainService.swift`    | Read/write API key + Apple user ID, nothing else                 |
| `AuthService.swift`        | Sign in with Apple + UserProfile upsert                          |
| `PendingCaptureStore.swift`| Persist + read the share-extension queue, both processes         |
| `DuplicateDetector.swift`  | Hash + window logic, no I/O, fully tested                        |

Anything that grows a second responsibility gets split.

## Open / Closed

- AI provider is one file (`AIService`). A future Gemini / OpenAI provider
  goes in its own service implementing the same shape; pick at runtime from
  `UserProfile.aiProvider`. Don't fork `AIService` with `if openai ...`.
- New SwiftData schema versions append to `BudgetBotMigrationPlan` rather
  than editing `SchemaV1`.

## Liskov

Concrete types only. No protocols-with-one-implementation in the app code.
Add a protocol the second moment a real test or feature requires substitution
(e.g. `URLProtocol` stub for AIService HTTP tests).

## Interface Segregation

Views receive only what they read. Pass `[Account]` not `ModelContext` when a
view only needs to render. SwiftData `@Query` does the read; the view never
fetches imperatively.

## Dependency Inversion

- `BudgetBotApp` builds the `ModelContainer` and injects via
  `.modelContainer(...)`.
- `AuthService`, `FXService` injected through `.environment(...)`.
- `AIService(model:)` is constructed at the call site so tests can pass a
  custom `URLSession` config in the future. No singletons.

## SwiftData rules

- `@Model` types live in `Models/`. They expose value-typed init params, never
  reference `ModelContext` themselves.
- Relationships always specify `deleteRule` explicitly.
- `@Attribute(.externalStorage)` for any blob > 1KB.
- Use `VersionedSchema` and `BudgetBotMigrationPlan` for every model change.
  Never edit a shipped `SchemaV1` member in place.

## AI integration rules

- **Always use `tool_use`** with a JSON `input_schema` for structured output.
  Never parse prose JSON from `content[].text`.
- **Always set `cache_control: ephemeral`** on the system block and any large
  tool definitions — the same prompt gets reused across hundreds of captures.
- **Retry on 429 / 5xx / transient URLError only**; never on 4xx that aren't
  429. Backoff is exponential with jitter (`AIService.backoffSeconds`).
- **Per-request timeout** via the service's own `URLSession`, not
  `URLSession.shared`.
- **Honour `Task.checkCancellation()`** between retries so UI cancels release
  the connection.
- The user's API key never appears in logs, error strings, or any UI string.

## Security & privacy rules

- API key lives in Keychain only (`KeychainService.set`). Never in
  `UserDefaults`, never in a SwiftData model, never logged.
- The ShareExtension cannot read the API key. It just enqueues; the main app
  does the AI call. (If we ever want extraction inside the extension, the
  keychain access group is shared — but we keep that off by default to limit
  attack surface.)
- All network calls go to `api.anthropic.com` or
  `www.ecb.europa.eu`. Anything else is a bug.
- "Delete account" wipes SwiftData + Keychain. We document Apple Sign-In
  revocation steps because we have no backend to call Apple's revoke endpoint
  (see [TODO.md](TODO.md)).

## Testing conventions

- New non-trivial logic → one test class, in `BudgetBotTests/`.
- Pure functions are `static` + `nonisolated` so tests don't need MainActor.
- Persistence tests use `PersistenceController.makeInMemory()`.
- No network in tests. AI HTTP path is exercised by mocking via the static
  `AIService.toolUseInput(in:expectedName:)` and retry classifiers.
- Run with: `xcodebuild -scheme BudgetBot test`.

## Coding style

- Two-space indents are wrong, use four. (XcodeGen default; SwiftFormat config
  pending — see [TODO.md](TODO.md).)
- No comments that paraphrase the code. Comments explain *why*: a constraint,
  a workaround, a hidden invariant.
- View files stay under ~200 lines; if they grow, extract a subview file.
- One `@Model` per file. Wire-format DTOs (`ExtractedDraftWire`,
  `RecommendationWire`) sit beside `ExtractedDraft.swift`.

## When in doubt

Read the recent PRs. If the answer isn't clear from existing code or this
file, write up the decision in this file in the same PR that introduces it.
