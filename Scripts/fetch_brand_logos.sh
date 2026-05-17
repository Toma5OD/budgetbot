#!/usr/bin/env bash
#
# fetch_brand_logos.sh — populate Brands.xcassets with bundled brand
# marks for BudgetBot's subscription icons.
#
# Source: simple-icons (https://github.com/simple-icons/simple-icons).
# The simple-icons icon files are released under CC0 1.0 (public
# domain). Brand trademarks remain with their owners; using a mark to
# label a service a user actually subscribes to is identifying
# (nominative) use. See docs/BRAND_LOGOS.md.
#
# This script is NOT run by the build — run it manually when you want
# to add/refresh the bundled marks. The app builds and runs fine
# without it (BrandLogoView falls back to the logo API and then to SF
# Symbols), so an empty Brands.xcassets is a valid committed state.
#
# Usage:   ./Scripts/fetch_brand_logos.sh
# Needs:   bash, curl
#
# Keep the id↔slug list below in sync with BrandCatalog.swift — the
# `id` is the asset-catalog name suffix; the `slug` is the simple-icons
# identifier. Only global brands simple-icons stocks are listed; the
# Irish regional brands (GoMo, Eir, …) deliberately have no entry —
# they're served by the logo-API tier instead.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="${REPO_ROOT}/BudgetBot/Resources/Brands.xcassets"
BASE_URL="https://raw.githubusercontent.com/simple-icons/simple-icons/master/icons"

# id slug  (one pair per line)
BRANDS="
netflix netflix
disneyplus disneyplus
primevideo primevideo
appletv appletv
paramountplus paramountplus
hulu hulu
crunchyroll crunchyroll
twitch twitch
spotify spotify
applemusic applemusic
youtubemusic youtubemusic
tidal tidal
soundcloud soundcloud
audible audible
youtube youtube
patreon patreon
icloud icloud
dropbox dropbox
googledrive googledrive
notion notion
github github
openai openai
adobe adobe
canva canva
linkedin linkedin
playstation playstation
duolingo duolingo
nordvpn nordvpn
strava strava
vodafone vodafone
"

mkdir -p "${ASSETS_DIR}"
cat > "${ASSETS_DIR}/Contents.json" <<'JSON'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

ok=0
fail=0

while read -r id slug; do
    [ -z "${id}" ] && continue
    imageset="${ASSETS_DIR}/brand.${id}.imageset"
    tmp="$(mktemp)"

    status="$(curl -sL -w '%{http_code}' -o "${tmp}" "${BASE_URL}/${slug}.svg")"
    if [ "${status}" = "200" ] && [ -s "${tmp}" ] && head -c 5 "${tmp}" | grep -q '<svg' ; then
        mkdir -p "${imageset}"
        cp "${tmp}" "${imageset}/${id}.svg"
        cat > "${imageset}/Contents.json" <<JSON
{
  "images" : [
    {
      "filename" : "${id}.svg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "preserves-vector-representation" : true,
    "template-rendering-intent" : "template"
  }
}
JSON
        echo "  ✓ ${id} (simple-icons: ${slug})"
        ok=$((ok + 1))
    else
        echo "  ✗ ${id} — simple-icons slug '${slug}' not found (HTTP ${status}); will use logo API / SF Symbol"
        fail=$((fail + 1))
    fi
    rm -f "${tmp}"
done <<< "${BRANDS}"

echo ""
echo "Bundled ${ok} brand marks into Brands.xcassets (${fail} skipped)."
echo "Run 'make gen' if your project file needs regenerating, then build."
