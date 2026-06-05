# Shipping BudgetBot to the App Store

End-to-end guide for going from "builds on my machine" to "live on the App Store".
Treat this as a checklist — work top to bottom. Anything marked **one-time** is
done once per project; everything else is per-release.

Project facts:
- Bundle ID: `dev.toma5od.BudgetBot`
- Team ID: `NS4MWJH5LR`
- App Group: `group.dev.toma5od.BudgetBot`
- iCloud container: `iCloud.dev.toma5od.BudgetBot`
- Min iOS: 17.0 (see `project.yml`)
- Solo dev — GitHub Actions free plan, $0/month spend cap

## 0. Current readiness (v0.1.0)

Snapshot of what's already done in code vs. what still needs a human
before the first App Store upload.

**Done in code:**

- Demo data + the Settings → Developer entry are wrapped in `#if DEBUG`
  — release builds ship clean.
- Brand logos resolve via Google's free favicon endpoint. No API token,
  no per-user setup, no recurring cost.
- Daily Roast lives in the Fun hub and repeats at 19:00 local via a
  `UNCalendarNotificationTrigger`.
- Goal rewards: pick a package at goal creation; claim stub on
  completion. Partner ordering is the future change at the claim
  handler.
- `PrivacyInfo.xcprivacy` covers email, name, financial info, with
  tracking explicitly `false`.
- `Info.plist` purpose strings present for camera and photo library.
- Sign in with Apple wired as primary auth.
- No hardcoded secrets — Anthropic + GoCardless keys are user-supplied
  (Settings → AI; Settings → Bank sync).
- `print()` calls in service paths are wrapped in `#if DEBUG`.

**Outstanding (your actions before submission):**

- [ ] Enrol in Apple Developer Program ($99/yr) — §1.
- [ ] Register App ID, App Group, iCloud container — §2.
- [ ] Set up App Store Connect listing: name, description, keywords,
      screenshots, privacy URL, support URL — §4, §9.
- [ ] Take screenshots after loading demo data: Activity (with logos),
      Goal detail (with reward card), Daily Roast, Analytics, Capture
      review.
- [ ] Bump `MARKETING_VERSION` to `1.0.0` and `CURRENT_PROJECT_VERSION`
      — §5.
- [ ] Remove the pre-1.0 wipe-on-drift fallback in
      `PersistenceController.swift:75` and add a real `MigrationStage`
      if `SchemaV1` ever changes post-launch.
- [ ] Deploy CloudKit schema to Production — §11.
- [ ] Host a privacy-policy page + a support page; paste URLs into
      App Store Connect.
- [ ] Mint a time-limited reviewer Anthropic key and drop it into the
      review notes — §10.
- [ ] Pick an age rating. Daily Roast copy leans edgy (e.g. "your
      caffeine receipts are basically a CV now") so 12+ is the
      conservative default.

## 1. Apple Developer Program (one-time)

1. Enrol at <https://developer.apple.com/programs/> ($99/year). Required for
   App Store distribution — you can build to a device with a free account
   but you can't ship.
2. Verify the Team ID matches `NS4MWJH5LR` in `project.yml`. If you ever
   create a new team (e.g. a company entity), update `DEVELOPMENT_TEAM` in
   `project.yml`, regenerate, and reset all certificates.

## 2. Identifiers, capabilities & containers (one-time per ID)

In the [Apple Developer portal](https://developer.apple.com/account):

### App ID

- **Identifiers → App IDs → New** → "App"
- Bundle ID: `dev.toma5od.BudgetBot` (explicit)
- Enable capabilities — these MUST match the `BudgetBot.entitlements` file:
  - Sign in with Apple
  - iCloud (CloudKit)
  - App Groups
  - Push Notifications  *(required even though we only fire local notifications
    today — the `remote-notification` background mode in Info.plist registers
    the entitlement)*

Repeat for the extensions:
- `dev.toma5od.BudgetBot.ShareExtension` — capability: App Groups
- `dev.toma5od.BudgetBot.Widget` — capability: App Groups

### App Group

- **Identifiers → App Groups → New**
- Identifier: `group.dev.toma5od.BudgetBot`
- Description: "BudgetBot shared container"
- Attach this group to all three App IDs above.

### iCloud container

- **Identifiers → iCloud Containers → New**
- Identifier: `iCloud.dev.toma5od.BudgetBot`
- Attach to the main BudgetBot App ID.

### CloudKit Dashboard

- <https://icloud.developer.apple.com/dashboard/>
- Select the `iCloud.dev.toma5od.BudgetBot` container.
- After running the app once in **Development** environment, the schema
  (record types from `SchemaV1`) auto-creates on the server.
- Before App Store submission: **Deploy schema to Production**. Without
  this, production users' iCloud sync will fail because the container's
  Production environment has no record types defined.

## 3. Code signing

We use Automatic signing (`CODE_SIGN_STYLE: Automatic` in `project.yml`).
Xcode manages certificates and provisioning profiles in the background.

If you hit "no profiles found":
1. Xcode → Settings → Accounts → add your Apple ID → Download Manual Profiles
2. Target → Signing & Capabilities → confirm Team and check
   "Automatically manage signing"
3. Run `make gen` to ensure `project.yml` and the project agree on bundle IDs.

## 4. App Store Connect setup (one-time)

<https://appstoreconnect.apple.com>

1. **My Apps → +** → New App.
2. Platform: iOS. Name: "BudgetBot" (must be unique across the store; if
   taken, add a tagline like "BudgetBot — AI Budget Tracker").
3. Primary language: English (Ireland).
4. Bundle ID: pick `dev.toma5od.BudgetBot` from the dropdown (it appears
   once the App ID is registered).
5. SKU: any unique string, e.g. `budgetbot-ie-2026`.
6. User access: Full Access.

Once created, fill in:
- **App Information** → Subtitle (max 30 chars), Category (Primary: Finance;
  Secondary: Lifestyle), Content Rights, Age Rating.
- **Pricing and Availability** → Free or paid tier; if free, pick which
  countries (default: All). If paid, choose a price tier.
- **App Privacy** → see [`PERMISSIONS_AND_PRIVACY.md`](./PERMISSIONS_AND_PRIVACY.md).

## 5. Version & build numbers

Bumped per release in `project.yml`:

```yaml
settings:
  base:
    MARKETING_VERSION: "1.0.0"     # user-visible — bump on real releases
    CURRENT_PROJECT_VERSION: "1"   # build number — increment every upload
```

Rules:
- Marketing version follows semver. `1.0.0` for the first store release.
- Build number must increase monotonically. Even a re-upload to the same
  marketing version needs a higher build number.
- After editing, run `make gen` to regenerate the Xcode project.

## 6. Pre-release sanity checks

Before every archive, run through:

- `make test-unit` — all unit tests pass.
- Manual smoke: capture a receipt, view analytics, open the widget after
  install, toggle a notification setting.
- Confirm `Info.plist` purpose strings are present and accurate
  (`NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`). See
  the permissions doc.
- Confirm `UIBackgroundModes` includes `remote-notification` (needed
  for CloudKit push wakes).
- If you changed any `@Model` schema, confirm `SchemaV1.models` lists the
  new types and migration is sorted (see `PersistenceController.swift`
  comment about the pre-1.0 wipe-on-drift behaviour — **remove that
  fallback before 1.0**).
- CloudKit schema is deployed to Production in CloudKit Dashboard.

## 7. Archive & upload

In Xcode (no Fastlane wired up yet — solo dev, manual is fine):

1. **Product → Scheme → Edit Scheme** → Run → Build Configuration: Release.
2. Select **Any iOS Device (arm64)** as the destination (not a simulator).
3. **Product → Archive**. Takes 2-5 min.
4. When Organizer opens, select the new archive → **Distribute App** →
   App Store Connect → Upload.
5. After ~10-30 min, the build appears in App Store Connect → TestFlight.

If the upload is rejected for missing entitlements or capability mismatches,
re-check that the dev portal App ID has every capability the entitlements
file declares.

## 8. TestFlight (recommended before App Store)

1. App Store Connect → TestFlight tab → your build.
2. Internal Testing: add your own Apple ID (up to 100 internal testers).
   Live in ~10 min after build processing.
3. External Testing: up to 10,000 testers. First external build needs an
   Apple review (24-48h, lighter than App Store review).
4. Add a beta description, feedback email, marketing URL if you have one.
5. Set a build expiry (default 90 days).

## 9. App Store submission

1. App Store Connect → your app → **+ Version or Platform** if not already
   on a draft version.
2. Fill in:
   - **What's New in This Version** (release notes, max 4,000 chars).
   - **Build** — pick the uploaded build.
   - **Promotional Text** (optional, 170 chars, editable without resubmit).
   - **Description** (up to 4,000 chars).
   - **Keywords** (100 chars total, comma-separated — used for search).
     Example: `budget,receipt,ai,expense,finance,savings,money,track`
   - **Support URL** — required. Even a simple GitHub Pages page works.
   - **Marketing URL** — optional.
   - **Screenshots** — 6.7" (iPhone 17 Pro Max) required. iPad if you ship
     iPad. Take from a real run with the demo data loaded so charts have
     content.
   - **App Review Information** — see next section. Critical.
3. **Save** then **Add for Review** then **Submit for Review**.
4. Review typically takes 24-48 hours. Bigger rewrites may take longer.

## 10. App Review notes (write these — they prevent rejection)

A non-standard pattern in BudgetBot is the **user-supplied Anthropic API
key**: there's no server, and the AI features require the user to paste
their own key. Apple reviewers will see "AI extraction" mentioned and
want to test it. If they can't, they reject for incomplete functionality.

Put this in the **App Review Information → Notes** field:

> BudgetBot's AI features (receipt extraction, conversational Ask)
> require the user to supply their own Anthropic API key, configured in
> Settings → AI → API key. The app does not include a built-in key and
> does not call any server we operate.
>
> Test instructions:
>
>   1. Launch the app, complete the brief welcome flow.
>   2. Sign in with Apple (any test Apple ID works).
>   3. Settings → AI → API key → paste a valid Anthropic key
>      (we recommend the reviewer-provided one below) → Validate & save.
>   4. Capture tab → take a photo of any receipt or paste sample text →
>      tap Process.
>
> For convenience, here is a temporary reviewer Anthropic API key valid
> until <DATE>: `sk-ant-…`
>
> (Other features — analytics, savings goals, widget, Hall of Shame, the
> rate-in-hindsight game — work without any AI key. Settings → Developer
> → "Load demo data" populates the app instantly for visual review.)

Tips:
- Generate a *time-limited* Anthropic key for the reviewer; revoke it
  after approval.
- Mention "Load demo data" — it lets the reviewer see the analytics
  surface in seconds without burning AI quota.

## 11. CloudKit production deploy (one-time per schema change)

CloudKit has separate Development and Production environments. Locally
the app talks to Development; App Store users talk to Production.

Before any App Store release that includes a new `@Model`:

1. CloudKit Dashboard → container `iCloud.dev.toma5od.BudgetBot`.
2. Schema → confirm Development reflects all `SchemaV1.models` entries.
3. **Deploy Schema to Production**. Click through the confirmation.
4. Wait ~1 min. Production now has every record type and index.

If you skip this, App Store users will see CloudKit sync silently fail
(`CKError 15/2000`) on the first launch with a new schema.

## 12. Post-release

- Watch crashes in Xcode → Organizer → Crashes. Most show up within 24h
  of release.
- Watch reviews in App Store Connect → Ratings and Reviews. Respond to
  critical ones — public replies count toward conversion.
- Watch usage: Analytics tab in App Store Connect. Pay attention to
  "Active devices", "Crash-free users", "Sessions per active device".
- Monitor Anthropic API: BudgetBot users pay their own API costs, but if
  the API has an outage your app looks broken. We don't have a status
  page wired up; consider adding one later.

## 13. Solo-dev / free-plan considerations

- GitHub Actions free tier: 2,000 macOS minutes/month, at 10× multiplier
  (so effectively 200 min/month of real Mac time). Our CI runs unit tests
  only — see `.github/workflows/`. Don't add UI tests to CI unless you
  upgrade the plan.
- No paid tier on Anthropic for us — every user supplies their own key.
  That's the deliberate cost model.
- No StoreKit/in-app purchase yet. If/when monetised, add the
  `com.apple.developer.in-app-payments` capability and a StoreKit
  configuration. App Store Connect needs an agreement for paid apps
  (Paid Apps Agreement under Agreements, Tax, and Banking).

## 14. Common rejection reasons (preempt these)

| Reason | How we preempt |
|---|---|
| **Incomplete metadata** | Use this checklist. Don't leave URL fields blank. |
| **Crash on launch** | TestFlight first, on iPhone + iPad if both supported. |
| **Missing privacy policy** | Add a hosted policy URL — link it in App Privacy. |
| **API key flow looks broken** | Reviewer note + temporary key (see §10). |
| **Health / Financial / Kids content** | We're Finance; no special claims. |
| **Permissions without purpose** | Every `NS*UsageDescription` set in `Info.plist`. |
| **Background modes without justification** | Document `remote-notification` is for CloudKit. |
| **Sign in with Apple required** | We already offer it as the primary auth. |
| **Privacy manifest missing** | Ship `PrivacyInfo.xcprivacy` — see permissions doc. |

## 15. Useful commands

```bash
make gen          # regenerate BudgetBot.xcodeproj from project.yml
make test-unit    # run unit tests
make build        # debug build for simulator
```

Manual Xcode flow:
- ⌘B build, ⌘U test, ⌘R run
- Product → Archive (for App Store)
- Window → Organizer → Crashes (for post-release diagnostics)
