# Brand Logos

How subscription icons resolve to real brand marks — and how to keep
it light on data and clean on licensing.

## The four-tier resolver

`BrandLogoView` resolves a subscription's icon through four tiers,
each degrading cleanly into the next:

1. **Bundled mark** — a CC0 simple-icons glyph in `Brands.xcassets`,
   rendered white on the brand's official colour. Instant, offline,
   no network. Covers the big global brands (Netflix, Spotify,
   Disney+, …).
2. **Disk-cached logo** — a full-colour logo fetched earlier by the
   logo-API tier and kept in the App Group container. Instant,
   offline.
3. **Freshly-fetched logo** — for a brand seen for the first time and
   not in the bundled set, fetched once from the logo API (if a token
   is configured), then written to the disk cache so tier 2 covers it
   forever after.
4. **SF Symbol** — `SubscriptionStyle`'s category glyph. The universal
   fallback: offline + uncached + unknown brand.

The app builds and runs correctly at every stage — with an empty
`Brands.xcassets` and no API token it simply lives on tier 4.

## Why a disk cache, not the database

A brand logo is **re-derivable cache data**, not user data. It must
not go in the SwiftData store:

- The store is CloudKit-mirrored — logos would be pushed into every
  user's iCloud, burning their quota to sync data that's freely
  re-fetchable.
- It bloats the system-of-record with disposable content.

So fetched logos live in `BrandLogos/` inside the App Group container
(`BrandLogoStore`). That survives launches, isn't auto-purged like
`Caches/`, and the widget extension can read it. Fetched once, then
zero network — and if it's ever lost, it just re-fetches. ~10 KB per
logo; a user's long-tail set is well under 1 MB.

## Bundled marks — the fetch script

`Scripts/fetch_brand_logos.sh` populates `Brands.xcassets` from
[simple-icons](https://github.com/simple-icons/simple-icons).

- The script is **not** part of the build. Run it manually to add or
  refresh marks: `./Scripts/fetch_brand_logos.sh`
- It downloads each brand's SVG and writes an asset-catalog imageset
  with vector data preserved and template rendering enabled (so the
  monochrome mark tints to the brand colour).
- The committed `Brands.xcassets` holds only an empty catalogue — a
  valid state. Bundled marks are a local enhancement; CI and a fresh
  clone build fine without running the script.
- Keep the script's `id slug` list in sync with `BrandCatalog.swift`.

### Licensing

simple-icons **icon files are released under CC0 1.0** (public
domain) — free to bundle. Brand names and logos remain trademarks of
their owners; using a mark to label a service the user actually
subscribes to is identifying (nominative) use, the same basis every
subscription-tracker app relies on. We deliberately do **not** scrape
or hand-draw logos.

## Logo-API tier (the long tail)

Brands simple-icons doesn't stock — Irish regionals like GoMo, Eir,
Electric Ireland, Bord Gáis, FlyeFit — are served by a logo API
keyed on domain (`BrandCatalog` carries the domain for every brand).

- `BrandLogoStore` targets a Logo.dev-style endpoint
  (`https://img.logo.dev/<domain>?token=…`). Brandfetch's CDN has a
  similar domain-keyed shape — swap the host in `makeRequest` if the
  provider changes.
- The token is a **publishable** logo-API token (not a secret), read
  from the `BudgetBot.logoAPIToken` UserDefaults key. With no token
  the fetch tier is simply inert — tiers 1, 2 and 4 still work.
- Logo APIs license logo *delivery* for exactly this purpose, which
  keeps the legal posture clean: the provider has handled sourcing.

To enable it, set a free publishable token from your chosen provider
into `BudgetBot.logoAPIToken` (`BrandLogoStore.logoAPIToken = "…"`).

## Adding a brand

1. Add a `Brand` entry to `BrandCatalog.swift` — match keys, official
   hex colour, domain.
2. If simple-icons stocks it, add the `id slug` line to
   `Scripts/fetch_brand_logos.sh` and re-run the script.
3. If it doesn't, the domain alone is enough — the logo-API tier
   handles it.
