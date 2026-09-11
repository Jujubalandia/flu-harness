# 04 — Testing

> Phase D13-D15. Targets a solo developer who does **not** own a Mac.

---

## Test tiers

| Tier | Tool | What it covers | When it runs | Target |
|------|------|----------------|--------------|--------|
| Unit | `flutter test` | pure Dart: models, parsers, formatters, reducers | every commit | fast, hundreds |
| Widget | `flutter test` + `WidgetTester` | one widget's render + interaction, with fakes | every commit | the 10-15 screens that matter |
| Golden | `flutter test --update-goldens` | pixel regressions on a fixed surface size | on demand, reviewed in the diff | the design-system components |
| Integration | `integration_test` | real app, real routing, real plugin channels | before a release build | 5 Golden Paths |
| Manual | your thumbs | haptics, share sheets, deep links, permissions | daily from D13 | 5 minutes |

The pyramid is a cost ordering, not a religion. Widget tests catch more than unit
tests in Flutter and cost about the same — write them first.

---

## Commands

```bash
flutter test                                  # everything in test/
flutter test test/features/paywall_test.dart  # one file
flutter test --name "shows the price"         # one test
flutter test --coverage                       # writes coverage/lcov.info
flutter test --coverage --branch-coverage     # also records branch coverage
flutter test --reporter=expanded              # compact | expanded | failures-only | github | json
flutter test --update-goldens                 # rewrite golden files (review the diff!)
```

Coverage, when you want a number:

```bash
flutter test --coverage
lcov --summary coverage/lcov.info
genhtml coverage/lcov.info -o coverage/html    # needs the lcov toolchain
```

The Dart team's own path, if you want coverage without Flutter's wrapper:

```bash
dart pub add dev:coverage
dart run coverage:test_with_coverage
```

Ignore directives when a line genuinely cannot be tested:
`// coverage:ignore-line`, `// coverage:ignore-start` … `// coverage:ignore-end`,
`// coverage:ignore-file`.

> **Windows trap:** in `coverage/lcov.info` the `SF:` source-file lines use
> **backslashes** on Windows (`SF:lib\main.dart`). Any script that filters or
> globs those paths must normalise separators first, or it will silently exclude
> nothing and report 100%.

Do not chase a coverage percentage. Chase the paths that break the app: auth,
payment, data loss, and anything with an `await` in a loop.

### Integration tests

```bash
flutter test integration_test/app_test.dart -d <device-id>
flutter devices        # list device ids
```

---

## Golden Paths — 5 minutes a day from D13

Define five critical flows **before** D13 and walk them on a physical device
every day. Fill in the real ones:

| # | Flow | Passes when |
|---|------|-------------|
| GP-1 | First run: install → onboarding → main feature | a new user reaches value without help |
| GP-2 | Returning user: open → authenticate → main feature → result | state restored, no re-login |
| GP-3 | Share: produce something → share → open the link on another device | the link opens the right screen |
| GP-4 | Hostile conditions: airplane mode → act → reconnect | a message the user understands, no crash, no data loss |
| GP-5 | Accessibility: complete the main flow with TalkBack/VoiceOver on | everything reachable and labelled |

GP-5 finds more real bugs than the other four combined, and it is the one
everybody skips.

---

## Device matrix

| Device | Platform | Use |
|--------|----------|-----|
| Your own Android phone | Android | main loop: real haptics, share sheet, deep links |
| Android emulator | Android | fast iteration, multi-user, screen sizes |
| Appetize.io (free tier) | iOS | weekly smoke: layout, navigation, i18n |
| Borrowed iPhone | iOS | TestFlight from D17, 1-2 hours |
| Chrome (`flutter run -d chrome`) | Web | fastest layout check, and it is not a phone |

**No Mac?** Two workable routes: a cloud Mac by the hour for the archive step, or
a CI runner that archives for you and uploads to TestFlight. Both need an Apple
Developer account and an App Store Connect API key. Set this up on **D1**, not
D16 — it is the single most common reason a 20-day plan becomes a 30-day plan.

> **D1 action:** schedule the iPhone borrow for D17-D18. Log it in `TODO.md`.

---

## Testing rules

**Do**
- Inject dependencies. A widget that constructs its own repository cannot be tested.
- Fake at the boundary (repository / client), not deep inside.
- Test behaviour, not implementation: find widgets by text or key, not by type.
- Use `pumpAndSettle()` after an action that triggers async work; use `pump()`
  when you deliberately want to observe an intermediate frame.

**Do not**
- Assert on exact pixel values outside golden tests.
- Call `DateTime.now()` inside a widget under test — inject a clock.
- Leave `await tester.pumpAndSettle()` on an infinite animation, it hangs forever.
- Mock the thing you are actually testing.

---

## What is not worth testing here

- Generated code (`*.g.dart`, `*.freezed.dart`) — it is the generator's job
- Third-party plugin internals
- Trivial getters and one-line `copyWith`s
- The theme

---

## DoD for D13-D15

- [ ] `flutter test` green, and it runs on every push
- [ ] GP-1 … GP-5 defined and walked at least once on a physical device
- [ ] A release build installed on a physical device and used for 10 minutes
- [ ] `flutter-doctor` shows zero FAILs
