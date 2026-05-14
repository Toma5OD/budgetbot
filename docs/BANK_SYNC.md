# Bank Sync — Procurement & Integration

> **Status (May 2026):** GoCardless Bank Account Data is **wired and
> shipping**. IE + UK supported on day one. Each user supplies their
> own free-tier credentials — see "User onboarding" below. Tink /
> TrueLayer / Plaid stubs remain in the registry as procurement
> upgrade targets for when volume justifies paying.

## Why we need an aggregator

The PSD2 (EU/UK) and equivalent regimes (US Open Banking via Plaid)
require **regulated Account Information Service Providers** (AISPs)
to connect to a user's bank. We won't be that — too much regulatory
overhead for a solo project. Aggregators (Tink, TrueLayer, Plaid,
Belvo, Nordigen/GoCardless, Salt Edge) are registered AISPs and act
as the middleman. We pay them per call / per connection and they
handle the banks' API peculiarities.

## Provider shortlist by region

| Region | Recommended | Notes |
|---|---|---|
| Ireland / EU | **Tink (Visa)** | Best EU coverage. Owned by Visa. Sandbox is free, production is per-API-call. |
| UK | **TrueLayer** | Strong UK + IE. Cheaper at low volume. |
| US | **Plaid** | The default. Expensive at scale, generous startup tier (~100 active items free). |
| LATAM | **Belvo** | Strong in Mexico/Brazil. |
| Free EU/UK | **Nordigen / GoCardless Bank Account Data** | Free tier for EU PSD2. 100 connections/month. Worth piloting with. |

For a v1 IE+UK launch, **GoCardless free tier** is the no-cost path
to a working product. Tink is the upgrade target once volume justifies
paying.

## What you need to procure

### GoCardless Bank Account Data (free PSD2 path)

1. Sign up at <https://bankaccountdata.gocardless.com>.
2. Create a Secret ID + Secret Key in the dashboard.
3. **Read the rate limit**: 4 requests per day per account.
4. No KYC required — they handle PSD2 compliance themselves under
   their AISP licence.

### Tink (Visa)

1. <https://console.tink.com> → create developer account.
2. Apply for production access. Needs:
   - Company name + registered address (a sole-trader works in IE).
   - Description of the use case.
   - PSD2 AISP scope confirmation. Tink owns the licence so the
     paperwork is light, but they'll ask which countries you intend
     to serve.
   - DPA (Data Processing Agreement) — they send a template, you
     sign and return.
3. Get a Client ID + Client Secret. Store in Keychain (never bundle
   them — see the `ConnectBankView` "Why we don't bundle keys" note).
4. Tink uses an OAuth-style flow via Tink Link (their hosted widget).
   Cleaner than rolling our own consent screen.

### TrueLayer

1. <https://console.truelayer.com> → create developer account.
2. UK + IE focus. Apply for "Data API" production access.
3. Same DPA pattern as Tink.
4. They publish per-call pricing; budget ~£0.01-0.05 per transaction
   pull at low volume.

## What the integration looks like in code

The protocol is already in `BudgetBot/Services/BankSync/BankSyncProvider.swift`.
A new provider implements it:

```swift
public struct TinkBankSyncProvider: BankSyncProvider {
    public let displayName = "Tink"
    public var isConfigured: Bool {
        KeychainService.shared.get(.tinkClientID) != nil
            && KeychainService.shared.get(.tinkClientSecret) != nil
    }

    public func connect(institution: BankInstitution) async throws -> BankConnection {
        // 1. Get a short-lived authorisation code via Tink Link
        //    (ASWebAuthenticationSession in iOS).
        // 2. Exchange for an access token.
        // 3. Fetch accounts, return as a BankConnection.
        ...
    }

    public func transactions(account: BankAccountID, since cursor: String?)
        async throws -> ([BankTransactionRaw], String?) {
        ...
    }
    // etc.
}
```

Then register it:

```swift
BankSyncRegistry.all.append(TinkBankSyncProvider())
```

The settings picker, the import pipeline, and the UI gating all
read from `BankSyncRegistry.active.isConfigured`. Once the provider
returns `true`, the "Coming soon" state in `ConnectBankView`
automatically becomes "Connect a bank".

## Import pipeline (when provider is live)

```
provider.connect(institution)
  → BankConnection (accounts list)
  → store account refs in SwiftData

[nightly, or app foreground] for each account:
  provider.transactions(account, since: cursor)
    → [BankTransactionRaw]
    → run through PayeeNormaliser
    → run through CaptureCategoryResolver
    → dedup against existing Transactions by (provider-id)
    → insert as Transactions, with attachment = nil
    → save cursor for next pull
```

Notes:
- Use Background App Refresh (`BGAppRefreshTask`) for the nightly
  pull. Apple grants ~30s per refresh.
- Dedup is critical — banks will re-issue the same tx with different
  IDs sometimes; consider a fuzzy match on (date ± 2 days, amount,
  merchant slug) as well as the provider-id.

## Privacy implications

If/when bank sync ships, update:

1. **App Privacy** in App Store Connect:
   - Add data type **Financial Info → Payment Info** (account
     numbers, routing data — even if we only store last-4).
   - Add **Diagnostics → Crash data** if the aggregator's SDK
     pulls it in.

2. **`PrivacyInfo.xcprivacy`**:
   - Add the new collected types.
   - If the aggregator's SDK uses `IDFA`, add `NSPrivacyTracking
     = true` and list their tracking domain (unlikely for AISPs but
     check).

3. **Privacy Policy**:
   - Name the aggregator as a third-party processor.
   - Document the OAuth scope (read-only AISP — no payment
     initiation).

## Cost modelling

Rough numbers for budgeting the per-user economics:

| Provider | Cost per active connection / month |
|---|---|
| GoCardless free tier | €0 (rate-limited to ~4 pulls/day/account) |
| Tink | €0.20-€0.40 (volume-dependent) |
| TrueLayer | £0.05-£0.30 |
| Plaid | $0.30-$1.50 (US) |

For a free-app model, GoCardless's free tier is the only viable
default. If we go paid (subscription or one-time), even €1/user/month
covers the worst-case Plaid number.

## User onboarding (BYO GoCardless credentials)

Because the free PSD2 tier is per-integrator (100 requisitions/month),
bundling one shared key in the app would let any user drain everyone
else's quota the moment the binary leaks. Instead, each user creates
their own free-tier account — same pattern as the Anthropic API key.

In the app: Settings → Connections → Connect a bank → if not
configured, the user is shown a `GoCardlessSetupView` walking through:

1. Visit `bankaccountdata.gocardless.com` and sign up (free, no card).
2. Under "User Secrets" create a new key pair.
3. Paste Secret ID + Secret Key into BudgetBot.
4. We immediately attempt a token exchange + institutions query — if
   it succeeds the credentials are stored in Keychain; if it fails we
   wipe both and surface the error so the user isn't stuck in a
   half-configured state.

Once configured, the user picks a country (IE/GB/FR/DE/ES/IT/NL/BE/PT
ship in the picker; adding more is one line), selects their bank from
the list GoCardless returns, and is bounced through
`ASWebAuthenticationSession` to the bank's consent flow. On return,
GoCardless has linked the account(s) and we're free to pull
transactions.

Refreshing happens manually via "Sync now" on the connection card —
background-refresh-on-foreground is the next step but doesn't ship in
the first cut.

## Import path

`BankTransactionImporter` converts `BankTransactionRaw` rows into
SwiftData `Transaction` records:

1. Lookup by `externalID` — bank's tx id. If present, update existing
   row (covers amount corrections / late-posting status changes).
2. Else soft-dedup by `(PayeeNormaliser.key(payee), date, amount)`
   against manual entries the user already captured — prevents a
   receipt photo and a bank pull both creating the same transaction.
3. Else insert a new `Transaction` with `confirmed = true`,
   `aiExtracted = false`, `externalID = raw.id`, account = the local
   `Account` row mirroring the bank account.

Payee strings get `PayeeNormaliser.canonical(...)` so "TESCO STORES
*4242 STRASBOURG" lands as "Tesco". Category hints from the bank are
matched against existing `TxCategory` rows by case-insensitive name —
we deliberately don't auto-create categories from bank hints because
MCC codes are vague.

## Decision points already made

For reference — the four calls that unblocked this work:

1. **Provider** — GoCardless first, Tink as the paid upgrade later.
2. **Region rollout** — IE + UK simultaneously; same PSD2 regime,
   GoCardless covers both.
3. **Pricing model** — Free forever, BYO API keys (Anthropic +
   GoCardless). The "no cut of your AI bill, no paywalled features,
   no server we can sell out of" pitch.
4. **Aggregator hosted vs custom consent** — Hosted (GoCardless's own
   flow, opened via `ASWebAuthenticationSession`).
