# Privacy & Data Flow

This document is intended both as user-facing privacy material and as App Store
review evidence for the account-deletion and data-handling requirements
(App Store guideline 5.1.1(v) and 5.1.2).

## What data BudgetBot collects

BudgetBot is a **single-device, no-backend** iOS application. We do not run a
server. We do not have a database that stores your information. We have no
analytics SDK, no crash reporting service, and no advertising frameworks.

The following data lives on your device only:

| Data                                  | Where                                    |
| ------------------------------------- | ---------------------------------------- |
| Your name and email                   | Apple Sign-In → SwiftData (`UserProfile`)|
| Apple user ID token                   | iOS Keychain (key: `appleUserID`)        |
| Your Anthropic API key                | iOS Keychain (key: `anthropicAPIKey`)    |
| Accounts, transactions, categories    | SwiftData on-disk store                  |
| Receipt images / PDFs you upload      | SwiftData `Attachment.data` (encrypted at rest with iOS data protection) |
| AI recommendations                    | SwiftData                                |
| Pending share-sheet items             | App Group container (`group.dev.toma5od.BudgetBot`) |

## What leaves your device

- **Anthropic Claude API** (`api.anthropic.com`). When you tap "Extract with
  AI", "Refresh" on Analytics, or send a question on Ask, the relevant
  payload is sent to `api.anthropic.com` using your own API key.
  Anthropic's data-handling policy applies; per their commercial agreement,
  inputs to the Messages API are not used to train models by default.
- **European Central Bank** (`www.ecb.europa.eu`). We fetch the public daily
  FX rates feed. No identifying information is sent.
- **Apple Sign-In** (`appleid.apple.com`). Standard Apple Sign-In flow,
  managed by the system; we read the user ID and name/email tokens Apple
  provides.

No other hosts are contacted by the application.

## Account deletion

You can delete your account and all associated data at any time from inside
the app: **Accounts tab → ⚙ Settings → Delete account & all data**.

Confirmation requires typing `DELETE` into a text field. Upon confirmation:

1. Every SwiftData entity is removed (`Transaction`, `Account`,
   `TxCategory`, `UserProfile`, `Attachment`, `AIRecommendation`,
   `FXRateSnapshot`).
2. Your Anthropic API key is removed from Keychain.
3. Your Apple user ID is removed from Keychain.
4. The App Group share-extension queue is cleared.
5. You are signed out.

Because BudgetBot has no backend, we cannot call Apple's
`/auth/revoke` endpoint on your behalf. After deletion we display
step-by-step instructions for revoking BudgetBot's Sign in with Apple
access from iOS Settings (Settings → your name → Sign-In & Security →
Sign in with Apple → BudgetBot → Stop Using Apple ID). The app also
listens for `ASAuthorizationAppleIDProvider.credentialRevokedNotification`
and signs you out automatically if you revoke externally.

## Children

BudgetBot is not directed at children and does not knowingly collect
information from children under 13.

## Changes

This document is versioned with the application source. The latest version is
always the one in the released TestFlight or App Store build.
