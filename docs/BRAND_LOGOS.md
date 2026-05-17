# Brand Logos

How subscription rows get real brand logos — free, light on data,
clean on licensing.

## Two tiers

`BrandLogoView` resolves a subscription's icon through two tiers:

1. **Real logo** — the brand's own icon, fetched once by domain and
   cached on disk. Instant and offline on every later view.
2. **SF Symbol** — `SubscriptionStyle`'s category glyph. The fallback
   while a logo is still loading, when offline on first sight, or when
   the brand isn't in `BrandCatalog`.

## Where the logos come from

Every brand publishes an icon on its own website — its favicon.
`BrandLogoStore` fetches that icon by domain from a free public
favicon endpoint (Google's `s2/favicons`):

```
https://www.google.com/s2/favicons?domain=netflix.com&sz=128
```

- **Free.** No token, no account, no API plan, no quota a budgeting
  app would ever reach. Nothing to pay for, now or at scale.
- **Real.** A favicon *is* the brand's own published mark — the real
  Netflix / Spotify / Three icon, not a redrawn stand-in.
- **Right shape.** Favicons are square icons, which is exactly what a
  circular badge needs (a wide wordmark wouldn't fit anyway).

DuckDuckGo's `https://icons.duckduckgo.com/ip3/<domain>.ico` is a
drop-in alternative — swap the host in `BrandLogoStore.makeRequest`.

## Why this is fine

We don't bundle, host, scrape, or redistribute anything. Each icon is
fetched at runtime from a public endpoint and shown to label a
subscription the user actually pays for — identifying (nominative)
use, the same basis every subscription tracker relies on. Brand names
and logos remain trademarks of their owners.

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

## Adding a brand

Add a `Brand` entry to `BrandCatalog.swift` — match keys, display
name, and the brand's web domain. The domain is all that's needed:
the logo is fetched and cached from it on first sight.
