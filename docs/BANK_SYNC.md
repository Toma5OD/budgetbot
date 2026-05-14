# Bank Sync — Procurement & Integration

This is the *commercial* track for bank sync. Code-wise the
abstraction is already shipped (`BankSyncProvider` + the active-stub
pattern). What's missing is a real provider with production
credentials, and that needs a procurement conversation you can't do
in code.

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

## Decision points (you need to make these before I can ship a real provider)

1. **Provider** — GoCardless for v1, Tink later? Or Tink from day one?
2. **Region rollout** — IE only first, or IE+UK simultaneously?
3. **Pricing model** — does the app charge users? If yes, how much,
   what tier (free Foundation Models + paid bank sync? Bundle
   everything?).
4. **Aggregator hosted vs custom consent** — Tink Link is faster
   to ship; a custom flow is more on-brand but takes weeks longer.

When you've made these calls, ping me and we wire up the real provider
behind the existing protocol.
