# Permissions, Entitlements & Privacy

What BudgetBot asks the user for, why, and what to disclose in App Store
Connect. Pair with [`SHIPPING.md`](./SHIPPING.md).

## 1. Info.plist usage descriptions

These are the *purpose strings* iOS shows in the permission dialog. App
Store will reject builds that use a capability without a matching string,
or whose string is vague ("Allow access").

Current strings (in `project.yml` under `targets.BudgetBot.info.properties`,
written to `BudgetBot/Resources/Info.plist`):

| Key | Why we ask | When the prompt fires |
|---|---|---|
| `NSCameraUsageDescription` | Capture receipts/invoices from the camera so the AI can extract data. | First time the user taps Camera from Capture. |
| `NSPhotoLibraryUsageDescription` | Read photos the user picks so the AI can extract transaction data. | First time the user picks from the photo library. |
| `ITSAppUsesNonExemptEncryption` (= `false`) | We use only iOS-provided TLS, no custom crypto. Skips the encryption export-compliance prompt at App Store upload. | n/a (build-time declaration). |
| `UIBackgroundModes: [remote-notification]` | CloudKit registers a silent-push handler to notify the device when iCloud data changes. Required even though we don't show server-side push notifications. | n/a (entitlement-level). |

If a future feature needs a new permission, add the matching key in
`project.yml` *first* — without it, the system fails the call silently
on iOS 14+ and the App Store will reject.

Likely future strings:

| Key | Trigger |
|---|---|
| `NSFaceIDUsageDescription` | If we ever gate the app behind Face ID. |
| `NSLocationWhenInUseUsageDescription` | If we ever auto-attach the location of a capture (currently we don't). |
| `NSContactsUsageDescription` | If we add a couples/family mode that lets users invite by contact. |
| `NSCalendarsUsageDescription` | If we add the "recurring expenses on Calendar" feature. |

## 2. Entitlements

`BudgetBot/BudgetBot.entitlements`:

| Entitlement | Purpose |
|---|---|
| `com.apple.developer.applesignin` | Sign in with Apple — the primary auth path. |
| `com.apple.developer.icloud-container-identifiers` = `iCloud.dev.toma5od.BudgetBot` | Names the CloudKit container the app reads/writes when sync is enabled. |
| `com.apple.developer.icloud-services` = `CloudKit` | Permits CloudKit (private database) access. |
| `com.apple.developer.ubiquity-kvstore-identifier` | Reserved for `NSUbiquitousKeyValueStore` — not used today but registered so we can flip it on later without an entitlement migration. |
| `com.apple.security.application-groups` = `group.dev.toma5od.BudgetBot` | Shared container used by ShareExtension and the Widget to hand data to the main app. |
| `keychain-access-groups` = `$(AppIdentifierPrefix)dev.toma5od.BudgetBot` | Lets the main app and extensions share Keychain items (notably the Anthropic API key). |

`ShareExtension/ShareExtension.entitlements`: App Group only (no
Keychain — the share extension just writes pending captures to the
shared container for the main app to pick up).

`BudgetBotWidget/BudgetBotWidget.entitlements`: App Group only (the
widget reads a JSON snapshot file the main app writes).

### Important: entitlements ≠ capabilities

The entitlement file declares what the binary requests. The Apple Dev
portal must also have these capabilities ENABLED on the App ID for that
bundle ID. Mismatches show up as opaque code-signing errors at archive
time. If you hit one:

1. Open the Dev portal → Identifiers → the App ID.
2. Confirm every capability listed in the entitlements file is also
   checked there.
3. If it isn't, check the box and re-archive.

## 3. Data we collect (App Privacy disclosure)

For **App Store Connect → App Privacy**:

### Data types

| Data Type | Collected? | Linked to user? | Used for tracking? | Where it lives |
|---|---|---|---|---|
| **Contact Info → Email** | Yes (only if user provides; Sign in with Apple gives us a relay email by default). | Yes. | No. | SwiftData + CloudKit. |
| **Contact Info → Name** | Yes (user-provided in profile, or from Sign in with Apple). | Yes. | No. | SwiftData + CloudKit. |
| **Financial Info → Other Financial Info** | Yes (transaction amounts, payee names, categories the user records). | Yes. | No. | SwiftData + CloudKit. |
| **User Content → Photos or Videos** | Yes (receipt photos the user attaches). | Yes. | No. | SwiftData. The image data is also sent to the Anthropic API *only* when the user chooses to process it. |
| **User Content → Other User Content** | Yes (notes, regret reasons, ratings). | Yes. | No. | SwiftData + CloudKit. |
| **Identifiers → User ID** | Yes (Sign in with Apple user identifier). | Yes. | No. | Keychain (id only) + SwiftData (profile). |
| **Diagnostics** | No. We don't ship a crash-reporting SDK; Apple's own crash logs go to App Store Connect if the user opted in. | n/a | No. | n/a |
| **Identifiers → Advertising ID (IDFA)** | No. | n/a | No. | n/a |
| **Location** | No. | n/a | No. | n/a |
| **Health & Fitness** | No. | n/a | No. | n/a |

### Purposes

For every "Yes" above, select these purposes when prompted in App
Privacy:

- **App Functionality** — primary purpose for everything we collect.
- Do *not* tick "Analytics", "Product Personalization", "Advertising",
  "Third-Party Advertising", or "Other Purposes". We don't do those.

### Third-party processors

Anthropic's API is a third-party processor for the data the user
*explicitly* sends for AI processing — receipt photos, captured PDFs,
free-text descriptions, conversation messages in Ask tab.

Disclosure language for the App Privacy section's free-text field
(or the privacy policy):

> When the user chooses to process a receipt or query, the relevant
> data (the photo, PDF, or message text) is sent to Anthropic
> (api.anthropic.com) for extraction or response generation, using
> the user's own Anthropic API key. The app does not include a built-in
> key, does not retain processed content beyond the local database, and
> does not transmit any data to servers operated by the developer.

## 4. Privacy Manifest (`PrivacyInfo.xcprivacy`)

Required for new App Store submissions since May 2024. Declares which
"required reason" APIs the app uses and what tracking domains it
contacts.

We don't ship one yet — **adding this is a blocker for App Store
submission**. The minimum viable manifest for BudgetBot:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array>
        <!-- Mirror the data types from the table above. Each entry
             names a collected type, whether it's linked to the user,
             whether it's used for tracking, and the purpose. -->
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeEmailAddress</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <true/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
            </array>
        </dict>
        <!-- Repeat for name, financial info, photos, user IDs. -->
    </array>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <!-- CA92.1: app's own preferences. -->
                <string>CA92.1</string>
            </array>
        </dict>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <!-- C617.1: display file timestamps to the user. -->
                <string>C617.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

Put this at `BudgetBot/Resources/PrivacyInfo.xcprivacy` and add it to
the resources list in `project.yml`. Repeat trimmed-down versions for
the ShareExtension and Widget if they use any required-reason APIs.

Apple validates this at upload time. Missing entries → email warning;
unjustified APIs → eventual rejection.

## 5. Privacy Policy (mandatory)

Apple requires a hosted privacy policy URL for any app that collects
data. We collect data, so we need one. Minimum content:

1. What we collect (mirror §3).
2. Why we collect it.
3. Who else sees it (Anthropic, Apple/iCloud).
4. How users can request deletion (Settings → Delete account & all
   data).
5. How to contact the developer (email).
6. Last-updated date.

The simplest place to host this is a static page in a public GitHub repo
served via GitHub Pages. The URL goes into App Store Connect → App
Information → Privacy Policy URL.

## 6. CloudKit & data residency

When iCloud sync is on (Settings → Storage), user data is mirrored to
the user's iCloud account in the private database of the
`iCloud.dev.toma5od.BudgetBot` container. Apple stores this on
Apple-operated servers; the user's iCloud Apple-ID-region determines
data residency. We don't operate servers, so we can't choose a region
ourselves.

When sync is off (default at the moment for dev-build noise reasons),
the data lives only in the device's `Library/Application Support`
directory inside the app sandbox. No external transmission.

## 7. Keychain items

| Item | Purpose | Lifetime |
|---|---|---|
| `anthropicAPIKey` | The user's Anthropic API key, used for receipt extraction + Ask. | Until the user removes it (Settings → API key → Remove). |
| `appleUserID` | The user identifier returned by Sign in with Apple. | Until sign-out or account deletion. |
| `googleUserID` | The user identifier from Google OAuth (if used). | Until sign-out or account deletion. |

All three live in the keychain access group declared in the
entitlements file, scoped to the App ID prefix — so the share
extension and widget can read them if they ever need to (they don't
today, but the access is there).

## 8. Pre-submission checklist

- [ ] Every capability in `BudgetBot.entitlements` is enabled on the App ID
      in the Dev portal.
- [ ] App Group registered and attached to all three App IDs.
- [ ] iCloud container registered.
- [ ] `PrivacyInfo.xcprivacy` shipped under `Resources/`.
- [ ] App Privacy section in Connect fully filled in (§3).
- [ ] Privacy Policy URL set in App Information.
- [ ] Support URL set.
- [ ] Reviewer notes mention the user-supplied Anthropic key (see
      [`SHIPPING.md`](./SHIPPING.md) §10).
- [ ] CloudKit schema deployed to Production.
