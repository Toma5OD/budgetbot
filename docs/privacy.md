---
layout: page
title: Privacy Policy
permalink: /privacy/
---

# BudgetBot — Privacy Policy

**Last updated: 8 June 2026**

BudgetBot is a personal finance app that runs on your iPhone. This
policy explains what data we handle, where it lives, and who else can
see it.

## In short

- **All your financial data stays on your device** and, if you turn
  iCloud sync on, in your own iCloud account. We do not run any servers
  that store your data.
- We do not sell, share, or use your data for advertising. We don't
  collect analytics or build any user profile.
- AI features (receipt capture, the "Ask" chat) only contact a
  third-party (Anthropic) when *you* trigger them, and only with the
  specific content you submitted (the receipt photo, the question
  text). They use *your own* Anthropic API key.

## What we collect

| Type | Source | Where it lives |
|---|---|---|
| **Email address** | Sign in with Apple (relay or real, your choice) or typed into your profile | Local database; iCloud (if sync is on) |
| **Display name** | Sign in with Apple or typed into your profile | Local database; iCloud (if sync is on) |
| **Apple user identifier** | Sign in with Apple | iOS Keychain on this device |
| **Financial information** — transaction amounts, payee names, categories, savings goals, account balances | Entered by you, imported by you (bank sync), or extracted by AI from a receipt you captured | Local database; iCloud (if sync is on) |
| **Receipt photos and notes** | Captured or attached by you | Local database |
| **Hindsight ratings, regrets, free-text notes** | Entered by you | Local database; iCloud (if sync is on) |
| **Anthropic API key** *(if you set one)* | You paste it into Settings → AI | iOS Keychain on this device |
| **GoCardless credentials** *(if you set them up for bank sync)* | You paste them into Settings | iOS Keychain on this device |

We do **not** collect:

- Location.
- Health or fitness data.
- Advertising or tracking identifiers (IDFA).
- Contacts, calendar, or microphone data.
- Any usage analytics or telemetry.

## Where your data lives

- **On your device.** The primary database is on this iPhone, inside
  the app's sandboxed storage. If you delete the app, it's gone.
- **In your iCloud account, if you opt in.** When iCloud sync is on
  (Settings → Storage), iOS mirrors the database to the
  `iCloud.dev.toma5od.BudgetBot` container in your own Apple ID's
  iCloud. Apple stores this on Apple-operated servers; the residency
  region follows your Apple ID region. We have no access to it.
- **Nowhere else.** We do not operate any back-end servers. There is
  no BudgetBot account on a BudgetBot database.

## When we contact a third party

There are two places the app may send data outside your device, and
both are triggered by an explicit action you take:

### Anthropic (Claude API) — only on your action

When you ask the AI to extract a receipt, scan a PDF, or you send a
message in the Ask tab, the relevant content (image, document, or text
of your message) is sent to Anthropic's API at `api.anthropic.com`.
The request uses **your own Anthropic API key**, which you supply in
Settings. BudgetBot does not ship a built-in API key and does not
proxy or store your AI requests on any server we operate.

Anthropic's own policies govern what they do with that data. See
<https://www.anthropic.com/privacy>.

### Brand logos — domain-only lookup

For subscription and merchant rows, the app fetches each brand's
favicon from a public favicon endpoint
(`https://www.google.com/s2/favicons`) using only the brand's domain
(e.g. `netflix.com`). No personal information, transaction details, or
account identifier is transmitted. Logos are cached on your device
after first fetch.

### GoCardless (optional, only if you set up bank sync)

If you opt in to bank sync (Settings → Bank sync) and paste your own
GoCardless secret, the app contacts GoCardless directly using your
credentials. We do not proxy or see those credentials.

## Apple Sign in with Apple

We use Sign in with Apple as the primary authentication. By default,
Sign in with Apple gives us a private Apple relay email address, not
your real one. You can choose to share your real email instead. Either
way the data lives in your local database (and your own iCloud, if
sync is on).

## Your rights and choices

- **Read your data.** Everything BudgetBot stores about you is visible
  in the app — every transaction, goal, and note is editable.
- **Export your data.** Settings → Export → CSV.
- **Delete your account and all data.** Settings → Delete account.
  This wipes the local database and your iCloud copy. Reinstalling the
  app gives you a fresh, empty database.
- **Stop iCloud sync.** Settings → Storage → iCloud sync (toggle off).
  Local data remains on the device; new changes stop being mirrored.
- **Revoke Sign in with Apple.** Settings (iOS) → your name → Sign in
  with Apple → BudgetBot → Stop using.

## Children

BudgetBot is not directed at children under 13. We do not knowingly
collect data from children under 13. If you believe a child has
provided data, contact us and we will delete it.

## Changes to this policy

We will update the "Last updated" date at the top of this page whenever
this policy changes. Material changes will be highlighted in the app
on next launch.

## Contact

Privacy questions: **tom1996.18@gmail.com**.

For account deletion requests by email (in addition to the in-app
"Delete account" flow), email the same address with the subject
"Delete my BudgetBot data" and the Apple ID email associated with
your account.
