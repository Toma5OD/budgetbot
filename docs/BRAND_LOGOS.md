# Brand Logos

How subscription rows get real brand logos — light on data, clean on
licensing.

## Two tiers

`BrandLogoView` resolves a subscription's icon through two tiers:

1. **Real logo** — the brand's full-colour logo, fetched once by
   domain from a logo API and cached on disk. Instant and offline on
   every later view.
2. **SF Symbol** — `SubscriptionStyle`'s category glyph. The fallback
   when there's no API token, no network on first sight, or the brand
   isn't in `BrandCatalog`.

The app builds and runs correctly with no token — it simply lives on
tier 2 until a token is set.

## Enabling real logos — the token

Logos come from a logo API ([Logo.dev](https://logo.dev) by default).
Getting a key is a free, open process: create an account and copy the
**publishable** token. It is not a secret — publishable logo-API
tokens are designed to ship in client apps.

Set it into the `BudgetBot.logoAPIToken` UserDefaults key:

```swift
BrandLogoStore.logoAPIToken = "pk_your_token_here"
```

`BrandLogoStore.makeRequest` targets `https://img.logo.dev/<domain>`.
Brandfetch's CDN has the same domain-keyed shape — swap the host there
if you change providers.

## Why a disk cache, not the database

A brand logo is **re-derivable cache data**, not user data:

- The SwiftData store is CloudKit-mirrored — logos there would be
  pushed into every user's iCloud, burning quota to sync something
  that's freely re-fetchable.
- It would bloat the system-of-record with disposable content.

So fetched logos live in `BrandLogos/` inside the App Group container
(`BrandLogoStore`). That survives launches, isn't auto-purged like
`Caches/`, and the widget extension can read it. Fetched once, then
zero network — and if a logo is ever lost it just re-fetches. ~10 KB
per logo; a user's long-tail set stays well under 1 MB.

## Licensing

Logo APIs license logo *delivery* for exactly this purpose, so the
provider has handled sourcing. Brand names and logos remain trademarks
of their owners; showing a logo to label a service the user actually
subscribes to is identifying (nominative) use — the same basis every
subscription-tracker app relies on. We deliberately do **not** scrape
or hand-draw logos.

## Adding a brand

Add a `Brand` entry to `BrandCatalog.swift` — match keys, display
name, and the brand's web domain. The domain is all that's needed:
the logo is fetched and cached from it on first sight.
