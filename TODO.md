# TODO

Deferred work. Open in priority order. Items get deleted as they ship,
not crossed out; the git history is the audit log.

## Deferred — not in current sprint

### Bank account aggregator (Revolut / others)
Intentionally **out of scope**. Possible via Plaid / TrueLayer / GoCardless Bank
Account Data / Tink — they all cover Revolut UK & EU, Plaid additionally covers
US Revolut. Two blockers:
1. Aggregator API secrets cannot live in the iOS bundle, so this requires a
   small backend (Cloudflare Workers / Supabase / Lambda) to hold OAuth tokens
   and proxy refreshes. The app is currently zero-backend on purpose.
2. PSD2 strong customer authentication forces user re-consent every 90 days.
   Real UX tax for an app that runs on screenshots and PDFs the user
   *already has*.

The Share Extension + AI pipeline gets ~80% of the value with ~5% of the work.
Revisit only if user feedback after launch demands live sync.

### Other deferred

- **CSV / OFX / QIF import** — once Share Extension is in, this is the next
  most-asked feature for migration from other apps.
- **Path-filtered CI** — add `paths-ignore` to skip CI on docs-only PRs
  if the solo cadence ever ramps up enough to matter. Not needed today.
- **Recurring transactions** model & UI (rent, subscriptions auto-posted).
- **Transfers between accounts** as a first-class concept, not two unlinked tx.
- **Per-category budget envelopes** + burndown chart on Analytics.
- **Apple Sign-In token revocation** — needs a backend (Apple requires calling
  their `/auth/revoke` endpoint with a refresh token, which we never obtain
  with the simple client-side flow). Currently we listen for
  `credentialRevokedNotification` (auto-signout if user revokes in iOS
  Settings), the in-app Delete Account does a full local wipe, and we show
  the user step-by-step revocation instructions. PRIVACY.md documents this
  for App Review.
- **Push notifications** for budget alerts / weekly review.
- **iCloud sync** (`CloudKitDatabase` in `ModelConfiguration`) — biggest blocker
  is the `Attachment.data` blob size; would need to chunk or move attachments
  to CloudKit's `CKAsset` separately.
- **SwiftLint + SwiftFormat** configs.
- **UI tests** (XCUITest) — capture-flow happy path, settings round-trip.
- **Snapshot tests** for the chart views.
- **Cost ledger** — record `usage.input_tokens / output_tokens` from each AI
  response so users see what they've spent.
- **Account context-aware FX** — currently FX rates are vs EUR via ECB; for
  non-EUR base users we cross via EUR which is fine but loses precision on
  exotic pairs.
