# Deferred Work

A register of work we *consciously chose not to do yet* — with the
reasoning and the trigger that should make us revisit. This is not a
bug list (those get fixed) and not a backlog of features (those get
prioritised). It's the set of things that are *fine for now* and would
be a mistake to do early.

Each entry says **what**, **why deferred**, **when it bites**, and
**the fix when it's time**. When an item is actioned, move it to the
"Resolved" section at the bottom with the commit that closed it.

---

## 1. Analytics aggregations recompute on every render

**Status:** deferred · logged 2026-05-16

### What

`AnalyticsView`'s aggregation properties — `byDay`, `byCategory`,
`topPayees`, `byDow`, and the inputs to every behavioural card
(`drinkStats`, `coffeeStats`, `brandTax`, `viceComparisons`,
`anomalies`, `hindsightBreakdown`, etc.) — are plain computed
properties. SwiftUI re-evaluates a view's `body` often: on any state
change, on scroll, on every animation tick. Each evaluation re-runs
the full aggregation: iterate every confirmed transaction, expand its
`categorisedSlices`, and call `amountInBase` (an FX conversion) per
slice. Nothing is memoised.

There is no remote query here — SwiftData is on-device — so this is a
**compute** cost, not an I/O cost. The fetch is cheap; the per-render
arithmetic over the full transaction set is the smell.

### Why deferred

1. **Premature at current scale.** A new user has tens to low-hundreds
   of transactions for the first several months. At that size each
   recompute is sub-millisecond — imperceptible, nowhere near the
   16ms (60Hz) / 8ms (120Hz) frame budget.
2. **Bad memoisation is worse than no memoisation.** A correct cache
   has to invalidate on: transaction inserts/edits/deletes, the range
   picker, the lens picker, the base-currency setting, *and* an FX-rate
   refresh. Get any one wrong and the screen shows stale numbers —
   a wrong-data bug, which is far worse than a few wasted microseconds.
   Doing it properly is a real refactor; doing it hastily is a
   regression.
3. **The lens split already bought headroom.** Since the Overview /
   Habits / Insights refactor (commit 2244e87), only the *active*
   lens's sections render, so a given frame recomputes ~⅓ of what it
   used to.

### When it bites

Watch for **scroll jank on the Analytics screen** — sections hitching
as you flick through a lens. Concretely:

- **~2,000–5,000 confirmed transactions** is the rough zone where the
  per-render passes start eating into the frame budget on a mid-range
  device. Below that, fine.
- **Timeline:** a heavy bank-sync user pulls ~30–50 transactions/month,
  so ~400–600/year. That's **roughly 4–8 years** of history before a
  single-account user hits the zone — but a user with several linked
  accounts, or one who imports a long back-catalogue, gets there much
  sooner. Loading the demo seeder repeatedly also inflates the count.
- First observable symptom will be the **behavioural cards / vice
  tracker** (Habits lens) and the **counterfactual + anomaly** cards
  (Insights lens), since those do the most per-transaction work.

If a user reports "Analytics feels laggy" — this is the first suspect.

### The fix when it's time

Memoise the aggregations behind a cache keyed by a cheap signature:
`(transactionCount + lastModifiedDate, range, baseCurrency, fxFetchedAt)`.
Recompute only when the signature changes. Options, simplest first:

1. A `@State`-held struct of precomputed results, rebuilt in an
   `.onChange`/`.task` on the signature rather than in `body`.
2. An `@Observable` `AnalyticsCache` service that owns the derived
   data and recomputes off the main actor.
3. If SwiftData's aggregate-fetch support has matured by then, push
   the sums into the store.

Keep `AnalyticsMetrics` / `CounterfactualEngine` pure — they're
already the right shape; only the *call site* needs the cache.

---

## Also tracked (pre-1.0 cleanups)

Smaller deferrals already flagged in code comments — listed here so
they live in one register:

- **`PersistenceController` schema-drift wipe.** `live` wipes and
  rebuilds the store on a `ModelContainer` load failure. That's a
  pre-1.0 convenience while the schema is still moving. Before 1.0 it
  must be replaced with a real `MigrationStage` — a shipped app may
  never silently destroy user data. (Comment is in
  `PersistenceController.swift`.)
- **`DemoDataSeeder`.** Whole file + the Settings → Developer entry
  are dev-only. Delete before App Store submission. (Header comment
  in `DemoDataSeeder.swift`.)
- **Privacy manifests for extensions.** `BudgetBot/Resources/PrivacyInfo.xcprivacy`
  covers the main app. The ShareExtension and BudgetBotWidget targets
  need their own trimmed manifests if they ever touch a required-reason
  API. (See `docs/PERMISSIONS_AND_PRIVACY.md` §4.)
- **Bank-sync providers Tink / TrueLayer / Plaid** remain stubs —
  GoCardless is the only live provider. This is a *procurement*
  decision, not a tech deferral; tracked in `docs/BANK_SYNC.md`.

---

## Resolved

_(none yet — when a deferred item is actioned, move it here with the
closing commit hash and date.)_
