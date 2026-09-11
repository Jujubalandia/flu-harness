# 02 — Dev plan (D1 → D20)

> The day-by-day plan. Milestones have definitions of done. **You do not advance
> past a milestone until its DoD passes.**

---

## Shape of the 20 days

| Phase | Days | Focus | Gate to leave the phase |
|-------|------|-------|-------------------------|
| Spec + setup | D1-D3 | Decide, then stand up a running app | M1 |
| Core build | D4-D10 | One MVP feature per day | M2, M3 |
| Polish | D11-D13 | i18n, a11y, states, performance | M4 |
| QA + store prep | D14-D15 | Release build, assets, metadata | M5 |
| Submission | D16-D17 | Upload, review, compliance | M6 |
| Launch | D18-D20 | Landing page, posts, metrics | M7 |

---

## Milestones

### M0 — D0-D1: start the clocks that cannot be rushed

- [ ] Play Console app entry created; **placeholder build pushed to closed
      testing** (starts a 14-day, 12-tester requirement on personal accounts,
      see `05-store-launch.md`)
- [ ] 12 closed-test testers recruited and opted in, as a group **disjoint** from
      your internal testers. Internal testers are not eligible for closed tests,
      so the same people on both tracks means the clock never starts.
- [ ] App category checked: health, financial services, VPN and government apps
      need an organisation account, which needs a D-U-N-S number (up to 30 days)
- [ ] Apple Developer account active (approval can take days)
- [ ] iPhone borrow for D17-D18 scheduled
- [ ] Repo created, `flutter-doctor` at zero FAILs

Everything here is waiting time rather than work time. Starting it late is the
single most common reason a 20-day plan runs to 30.

### M1 — D3: it runs

- [ ] The app opens on a **physical Android device** (not just the emulator)
- [ ] Login works end to end
- [ ] Two screens navigate, with state surviving the transition
- [ ] `flutter analyze` clean, pre-commit hook fires on `git commit`

### M2 — D7: the main flow is functionally complete

- [ ] Core features 1-4 implemented
- [ ] A user can complete the main flow start to finish
- [ ] No crashes on the happy path

### M3 — D10: it survives real use

- [ ] Core features 5-6 implemented
- [ ] Main flow completes with no crash on a physical device
- [ ] The app has been used by someone who is not you

### M4 — D13: it is presentable

- [ ] i18n complete — zero hardcoded user-facing strings
- [ ] Loading, empty and error states on every fetching screen
- [ ] Semantics labels on every interactive element
- [ ] Full gate plan green

### M5 — D15: release candidate

- [ ] Release build installed on a physical device, no crash on Golden Paths
- [ ] Store assets and metadata complete
- [ ] `flutter-doctor` with zero FAILs

### M6 — D17: submitted

- [ ] AAB uploaded to the Play Console internal track, then promoted
- [ ] iOS build uploaded to TestFlight, then submitted
- [ ] Build number and status logged in `DECISIONS.md`

### M7 — D20: launched

- [ ] Approved on both stores (or feedback answered)
- [ ] Landing page live
- [ ] At least one marketing channel active
- [ ] D+7 metrics logged in `DECISIONS.md`

---

## Daily rhythm

| Slot | Task |
|------|------|
| Start of day | `flutter-doctor` (expect 0 FAIL), check `TODO.md` blockers |
| Build | One feature. Commit when it compiles and the gate plan passes. |
| Midday | Test the feature on a physical device |
| End of day | `flutter analyze` clean, `TODO.md` updated, one commit |
| Every day from D13 | Walk the Golden Paths on a real device |

**Stuck for more than 4 hours?** Log the blocker in `TODO.md`, move to the next
feature, come back with fresh eyes. Spiral is the schedule killer.

---

## D4-D10: the feature queue

| Day | Feature | DoD |
|-----|---------|-----|
| D4 | | |
| D5 | | |
| D6 | | |
| D7 | | |
| D8 | | |
| D9 | | |
| D10 | Buffer / catch-up | |

Estimate each at one day. If a feature needs three, it is three features and the
cut/keep list is wrong — go back to `01-spec.md`.

---

## Common blockers and their actual causes

| Symptom | Usually is |
|---------|-----------|
| "It works in debug, breaks in release" | Missing ProGuard/R8 rules for a plugin, or `--obfuscate` without `--split-debug-info`. Test a release build on D14, not D16. |
| Gradle build fails after adding a plugin | `minSdkVersion` too low for that plugin, or the Android Gradle Plugin and the plugin's Kotlin version disagree. Read the *first* error, not the last. |
| iOS build fails only on CI | CocoaPods cache, or a plugin without a Swift Package Manager manifest. `cd ios && pod install --repo-update`. |
| "Hot reload does nothing" | You changed `main()`, a global, a `const`, an enum, or a generic type signature. Hot restart (`R`), not `r`. |
| Works on emulator, not on device | Network permissions, cleartext HTTP blocked on Android 9+, or `localhost` pointing at the device instead of your machine. |
| Hook does not run at all | `core.hooksPath` is not set in *this* clone — it is a local git config, not a committed one. Or the hook has CRLF. `flutter-doctor` checks 22 and 23. |
| Hook runs in Git Bash but not PowerShell | It should not matter — git runs hooks with its own sh. If it does, check `.githooks/lib/quality.sh` for CRLF. See `docs/WINDOWS.md`. |

---

## Scope discipline

At D10 the app is whatever it is. From D11 onward you polish, you do not add.

Any feature not in the D4-D10 table is a **v1.1 feature**. Write it in `TODO.md`
under a `## v1.1` heading and close the file.
