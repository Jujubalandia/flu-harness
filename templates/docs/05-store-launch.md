# 05 — Store launch

> Phase D15-D17. Everything here is irreversible once submitted. Read it twice.

---

## Read this on D0, not D15

**Google Play requires a closed test with 12 testers opted in continuously for 14
days before a personal developer account can publish to production.** Add review
time and the real lead time is up to three weeks: longer than this entire plan.

What that means in practice:

- A **personal** developer account created after 13 November 2023 is subject to it.
  Organisation accounts are not.
- The 12 testers must be **opted in continuously**. If one drops out on day 9, the
  clock is not what you think it is.
- **Publish any valid build to closed testing on D0**, before the app is good. A
  placeholder that launches satisfies the requirement, and the 14 days then run in
  the background while you build.

### The trap that silently costs you the whole plan

Play requires that internal testers and closed testers be **disjoint groups**:

> A user who opts into your app's internal test is no longer eligible to receive
> an open or closed test. To access an open or closed test, the user must first
> opt out of the internal test and then opt in.

So seeding both tracks with the same friends, which is the obvious move,
means **the 14-day clock never starts**. You find out when you apply for
production access, after the budget is gone.

**Plan for two separate groups:** 12 people on closed testing doing nothing else,
and a different set on internal testing for the fast iteration loop.

### Two more gates that can invalidate the plan before you write code

| Check | Why it matters |
|-------|----------------|
| **App category** | Health, financial services, VPN and government apps **require an organisation account**, which needs a D-U-N-S number that can take up to 30 days. |
| **Device verification** | Personal accounts must verify a real Android device through the Play Console mobile app. An emulator does not count. |

Verify the current requirements in the Play Console before planning around them.
Google has changed these thresholds before.

> **D0 actions:** create the Play Console app entry, push a placeholder to closed
> testing, and start recruiting. Log the 14-day deadline in `TODO.md` as a blocker.

---

## Build identifiers — decide once

| | Value |
|---|---|
| Android `applicationId` | |
| iOS bundle identifier | |
| Version name | |
| First version code / build number | 1 |

`applicationId` and the bundle identifier are **permanent**. Changing either
after publication means a new app listing, a new package name, and losing every
install and review. Decide before the first upload.

Where they live:

```kotlin
// android/app/build.gradle.kts
android {
    defaultConfig {
        applicationId = "com.yourorg.yourapp"
        minSdk = 24
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
}
```

```yaml
# pubspec.yaml — the single source for the version
version: 1.0.0+1     # <version name>+<build number>
```

The iOS side is `PRODUCT_BUNDLE_IDENTIFIER` in `ios/Runner.xcodeproj`, or via
`flutter create --org`.

---

## Signing

### Android

Create an upload keystore **once**, then never lose it:

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

`android/key.properties` (gitignored — verify it is):

```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=/absolute/path/to/upload-keystore.jks
```

Back the keystore and its passwords up somewhere that is not this repo and not
this laptop. Losing the upload key means a support ticket to Google and a delay
measured in days. Losing the **app signing** key (if you opted out of Play App
Signing) means you can never update that listing.

### iOS

Xcode manages signing; for CI you need an App Store Connect API key, a
distribution certificate and a provisioning profile. Do this on D1.

---

## Release build

```bash
# Android App Bundle, for the Play Store
flutter build appbundle --release \
  --obfuscate --split-debug-info=build/symbols

# Android APK, for sideloading and testing
flutter build apk --release --split-per-abi

# iOS archive
flutter build ipa --release --obfuscate --split-debug-info=build/symbols
```

`--obfuscate` without `--split-debug-info` throws the symbol map away and makes
every future crash report unreadable. Always pass both, and keep the `symbols/`
directory.

### The symbols are not reproducible. Back them up.

This is the part that loses data. `--split-debug-info` embeds absolute source
paths in the DWARF data, so **building the same commit from a different directory
produces different symbol files and a different `app.so`**. You cannot regenerate
symbols later from the commit. If you lose them, every crash report from that
release is a wall of addresses, permanently.

Two more things that follow from it:

- `--split-debug-info` **by itself** already strips the shipped binary. `--obfuscate`
  is a separate concern (identifier renaming), not what makes traces unreadable.
  Adding it does not make symbol loss worse, and skipping it does not make traces
  readable.
- Deleting the symbols directory and rebuilding **silently produces no symbols at
  all** in some Flutter versions. Put `flutter clean` in the release script rather
  than deleting directories by hand.

So the release script must archive `build/symbols/` somewhere durable, keyed by
version code, before the build leaves the machine.

`flutter symbolize -d` takes a **file**, not a directory, and only one. Multiple
compilation units need `-u <unitId>:<path>`.

### Two build flags that cannot be combined

- `--analyze-size` **cannot** be combined with `--split-debug-info`.
- `--analyze-size` requires `--release` and, for Android, one ABI at a time.

So a size analysis is a separate build from a release build:

```bash
# size analysis - its own build
flutter build apk --analyze-size --target-platform=android-arm64

# release build with symbol recovery
flutter build appbundle --release \
  --split-debug-info=build/symbols --obfuscate
```

Decode a crash later with:

```bash
flutter symbolize -i stack_trace.txt -d build/symbols/app.android-arm64.symbols
```

Play Store now requires an **AAB**, not an APK, for new apps. And **staged
rollouts cannot be used for a first release**: v1.0 must go to 100%.

### Configuration, not secrets

`--dart-define-from-file` needs an `=` sign, accepts `.json` or `.env`, and is not
supported on desktop builds:

```bash
flutter build appbundle --dart-define-from-file=env.json
```

These values are compiled into the binary. They are configuration, not a secret
store. Anything that must stay secret belongs on your backend.

> `flutter doctor` exits **0** even when it prints `[!]` issues and
> "Doctor found issues in N categories." Do not wire it into CI as a gate; its
> exit code does not mean what you would assume. And `flutter doctor --machine`
> no longer exists; for machine-readable version info use `flutter --version --machine`.

---

## Store assets

### Play Store

| Asset | Requirement |
|-------|-------------|
| App icon | 512×512 PNG, 32-bit, no transparency |
| Feature graphic | 1024×500 PNG/JPEG |
| Phone screenshots | 2-8, min 320px, max 3840px, 16:9 or 9:16 |
| Short description | ≤ 80 characters |
| Full description | ≤ 4000 characters |
| Privacy policy URL | required if you collect anything |
| Data safety form | every data type, declared |

### App Store

| Asset | Requirement |
|-------|-------------|
| App icon | 1024×1024 PNG, no alpha, no rounded corners |
| iPhone screenshots | 6.7" and 6.1" required |
| iPad screenshots | required if the app supports iPad |
| Subtitle | ≤ 30 characters |
| Promotional text | ≤ 170 characters |
| Keywords | ≤ 100 characters, comma-separated |
| Privacy nutrition labels | every data type, declared |
| Age rating | questionnaire |

Taking screenshots: run the release build on a device, not the emulator, and
capture with real data. Screenshots with `lorem ipsum` and `test@test.com` are
the most visible sign of an unlaunched app.

---

## Store listing copy

Draft here, then paste.

**Short description (≤80)**

>

**Full description**

>

**What's new (v1.0.0)**

>

**Keywords / search terms**

>

---

## Submission checklist

### Before you upload
- [ ] A release build installed on a physical device and used for 10 minutes
- [ ] Golden Paths GP-1 … GP-5 validated on that release build
- [ ] `flutter-doctor` — zero FAILs
- [ ] Version bumped in `pubspec.yaml`, `+buildNumber` incremented
- [ ] Privacy policy live at a public URL
- [ ] Account deletion available in-app if the app creates accounts (Play and
      App Store both require this now, and both reject apps without it)
- [ ] No placeholder text, no debug banners, no `flutter: ` log spam in release

### Google Play
- [ ] AAB uploaded to the **internal testing** track first
- [ ] Data safety form completed and consistent with the privacy policy
- [ ] Content rating questionnaire completed
- [ ] Target API level meets the current Play requirement
- [ ] Internal test installed from the Play link on a clean device
- [ ] Promoted to production

### App Store
- [ ] Archive uploaded; the build appears in TestFlight
- [ ] TestFlight build installed and used
- [ ] App Privacy answers completed
- [ ] Export compliance answered
- [ ] Demo account supplied if the app has login
- [ ] Submitted for review

### After submitting
- [ ] Build number and submission date logged in `DECISIONS.md`
- [ ] Rejection feedback answered within 24h — reviewers move fast if you do
- [ ] Store links tested from a device that has never installed the app

---

## The rejection reasons that actually happen

| Reason | Prevention |
|--------|-----------|
| Guideline 4.2 "minimum functionality" | A wrapped website or a single-screen app. Add native value. |
| Broken links / placeholder content | Click every link in the listing. Yes, all of them. |
| Login required to see anything | Offer a guest path, or a demo account in the review notes. |
| Missing account deletion | Build it before D14. |
| Privacy policy missing or mismatched | The policy must name every data type you declared. |
| Screenshots showing a different app | Recapture after any UI change. |
| Play: target API too old | Check the current requirement the week you submit. |
| Play: upload key lost | Do not lose it. See Signing above. |

---

## DoD for D15-D17

- [ ] Release build installed and validated on a physical device
- [ ] All store assets produced at the right dimensions
- [ ] Metadata written and pasted into both consoles
- [ ] Both submissions confirmed
- [ ] Build number logged in `DECISIONS.md`
