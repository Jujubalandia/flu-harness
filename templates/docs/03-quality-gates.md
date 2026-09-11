# 03 — Quality gates

> The gate plan is mandatory and ordered. Nothing gets committed that breaks the
> chain. This document is the policy; `.githooks/lib/gates.def` is the machine
> readable version of it.

---

## The pyramid

```
            [Manual: Golden Paths]        <- 5 min/day from D13
          [flutter build apk --debug]     <- pre-push, strict profile
        [flutter test]                    <- pre-commit (strict) / pre-push
      [custom_lint / dart_code_linter]    <- pre-commit, strict profile
     [dart format --set-exit-if-changed]  <- pre-commit
    [flutter analyze --fatal-infos]       <- every save in the IDE + pre-commit
```

Cheapest first, most often. Do not skip layers — a formatting diff hides a type
error, and a type error hides a logic error.

---

## Gates

| Gate id | Command | Fails when |
|---------|---------|-----------|
| `format` | `dart format --output=none --set-exit-if-changed .` | any file is unformatted (exit 1) |
| `analyze` | `flutter analyze --fatal-infos --fatal-warnings` | any analyzer issue, including infos |
| `lint` | `dart run dart_code_linter:metrics analyze lib --set-exit-on-violation-level=warning` | any metric or anti-pattern violation (exit 2). Self-skips when `analysis_options.yaml` configures neither `dart_code_linter:` nor `custom_lint:`. |
| `test` | `flutter test` | any test fails. Self-skips if there is no `test/` directory. |
| `build` | `flutter build apk --debug` | the app does not compile for a real target |

### Two things that surprise people

**`flutter analyze` is stricter than `dart analyze`.** Its `--fatal-infos` and
`--fatal-warnings` both default to **on**, unlike `dart analyze` where
`--fatal-infos` is opt-in. Two info-level lints are enough to exit 1. That is the
behaviour you want in a gate, but it means `flutter analyze` "failing" on a fresh
`flutter create` project is expected until you format and fix.

The harness passes both flags explicitly anyway. They are a no-op on current
Flutter, and stating them keeps the intent visible to anyone who later wonders why
an info-level lint is blocking a commit. To relax the gate deliberately, pass
`--no-fatal-infos`; do not delete the flags and hope.

**`dart_code_linter` exits 0 even when it finds violations.** The exit-2
behaviour only happens with `--set-exit-on-violation-level=warning`. Omit that
flag and you have built a gate that always passes — which is worse than no gate,
because it looks like one.

---

## Profiles

Set by `/flu-harness:new-flutter-project`, stored in `.githooks/.profile`.

| Profile | pre-commit | pre-push |
|---------|-----------|----------|
| `minimal` | `analyze` | `analyze`, `test` |
| `standard` | `format`, `analyze` | `format`, `analyze`, `lint`, `test` |
| `strict` *(default)* | `format`, `analyze`, `lint` | `format`, `analyze`, `lint`, `test`, `build` |

`strict` is the default because of `build`. The analyzer passing does not mean
Gradle will accept your manifest, and finding that out at D16 instead of D5 is
the difference between shipping and not.

### Switching profile

```bash
# write the new plan's gates.def and the remembered profile
cp .githooks/lib/../../path/to/gates.def ...   # or copy from the plugin
echo minimal > .githooks/.profile
```

Or re-run `/flu-harness:new-flutter-project` and pick a different profile.

Exit codes: `0` = all gates passed or were skipped, `1` = at least one failed,
`2` = bad usage.

---

## The same plan, in three shells

This is the part flu-harness adds over a single-shell setup.

`.githooks/lib/gates.def` is the single source of truth:

```
pre-commit=format,analyze,lint
pre-push=format,analyze,lint,test,build
```

Three runners parse it:

| Shell | Runner | Invoke |
|-------|--------|--------|
| Git Bash / POSIX | `quality.sh` | `sh .githooks/lib/quality.sh --stage pre-commit` |
| PowerShell 5.1 / 7 | `quality.ps1` | `powershell -ExecutionPolicy Bypass -File .githooks\lib\quality.ps1 -Stage pre-commit` |
| cmd.exe | `quality.cmd` | `.githooks\lib\quality.cmd /stage:pre-commit` |

Because the plan is data rather than three copies of code, they cannot drift.
Prove it any time:

```bash
sh  .githooks/lib/quality.sh  --dry-run
# profile=strict
# stage=pre-commit
# def=...
# gate=format
# gate=analyze
# gate=lint
```

`--dry-run` / `-DryRun` / `/dry-run` prints the plan instead of running it. All
three must print identical `gate=` lines.

### Hook entry points

`git commit` always runs `.githooks/pre-commit`, a POSIX sh script, because git
executes hooks itself through the sh that ships with Git for Windows — not
through whichever shell you typed the command in. The `.ps1` and `.cmd` files next
to it are for running the same gates by hand, early. See `docs/WINDOWS.md`.

---

## Thresholds

| Gate | Threshold | When |
|------|-----------|------|
| `dart format` | zero diffs | pre-commit |
| `flutter analyze` | zero issues | every save + pre-commit |
| complexity | see below | pre-commit (`strict`), via `dart_code_linter` |
| tests | 100% pass | pre-push |
| debug build | compiles | pre-push (`strict`) |
| release build size | Android AAB, watch it | before submission |
| crash-free sessions | > 99.5% | after launch |

---

## Complexity

Dart has no `fta` equivalent, and `dart analyze` computes no metrics at all. The
maintained option is **`dart_code_linter`** (the community successor to the
discontinued `dart_code_metrics`), configured in `analysis_options.yaml` under a
`dart_code_linter:` key:

```yaml
# analysis_options.yaml
dart_code_linter:
  metrics:
    cyclomatic-complexity: 20      # default 20
    maintainability-index: 50      # default 50 - INVERTED: lower is worse
    number-of-parameters: 4
    maximum-nesting-level: 5
    source-lines-of-code: 50
  metrics-exclude:
    - test/**
    - "**.g.dart"
    - "**.freezed.dart"
  anti-patterns:
    - long-method
    - long-parameter-list
  rules:
    - avoid-dynamic
    - no-empty-block
```

```bash
dart run dart_code_linter:metrics analyze lib
dart run dart_code_linter:metrics analyze lib --reporter=json
# the form that actually gates:
dart run dart_code_linter:metrics analyze lib --set-exit-on-violation-level=warning
```

The metrics most worth setting: `cyclomatic-complexity` and
`maintainability-index` (a function of cyclomatic complexity, Halstead volume and
source lines). `maintainability-index` is inverted — 0 is worst, 100 is best — so
a threshold of 50 means "fail below 50".

Whole-program analysis, so it is slow: expect tens of seconds, not one. That is
why it sits in `pre-commit` for `strict` and in `pre-push` for `standard`.

**When a complexity check fires, refactor. Never raise the threshold to make it
pass.** In Flutter the refactor is almost always one of:

1. Extract sub-widgets — a `build()` over ~80 lines is a widget tree that wants
   to be three widgets.
2. Extract a state notifier — async logic tangled into a widget becomes a
   `Notifier` / `Bloc` with its own tests.
3. Replace a `switch`/`if` chain over 5 cases with a lookup map or a `sealed`
   class and a `switch` expression.
4. Extract a pure function — anything that does not touch `context` does not
   belong in a widget.

---

## Analyzer rules worth turning on

`flutter_lints` is the floor. Note the include path carefully:

```yaml
# analysis_options.yaml
include: package:flutter_lints/flutter.yaml   # NOT .../recommended.yaml - that file does not exist
```

`dart.dev` shows `package:flutter_lints/recommended.yaml` in one example. That
path does not resolve; you get `include_file_not_found`. Use `flutter.yaml`.

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  errors:
    invalid_annotation_target: ignore   # false positive with freezed + json_serializable
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true

linter:
  rules:
    always_declare_return_types: true
    avoid_print: true
    prefer_const_constructors: true
    prefer_const_constructors_in_immutables: true
    prefer_const_declarations: true
    prefer_final_locals: true
    prefer_single_quotes: true
    unawaited_futures: true
    use_build_context_synchronously: true
    avoid_dynamic_calls: true
    cancel_subscriptions: true
    close_sinks: true
```

`use_build_context_synchronously` and `cancel_subscriptions` are the two that
prevent the most common Flutter crashes. Do not silence either.

> **Dart 3.13 note:** `no_raw_types` and `no_dynamic_casts` are being introduced
> as lint rules to replace the `strict-raw-types` and `strict-casts` analyzer
> options. If your SDK is 3.13+, prefer the lint rules and drop the options.

For a stricter house style, swap the include for `very_good_analysis`:
```yaml
include: package:very_good_analysis/analysis_options.yaml
```

---

## Formatter

Since Dart 3.7 the formatter uses the "tall style", and it is **language
versioned**: your `environment.sdk` lower bound decides which style each file
gets. Raise it to use the new one.

```yaml
# analysis_options.yaml
formatter:
  page_width: 100           # default 80; needs language version >= 3.7
  trailing_commas: preserve # automate (default) | preserve; needs >= 3.8
```

```bash
dart format .                                  # write
dart format --output=none --set-exit-if-changed .   # CI check, exit 1 on diff
dart format --show=none --output=none --set-exit-if-changed .   # quiet
```

Two traps:

- `dart format` needs a `package_config.json` to know each file's language
  version, so **run `dart pub get` before a format check in CI**. Without it the
  formatter guesses the wrong style and reports diffs that are not real.
- `automate` trailing commas means the formatter adds and removes them itself.
  If you are used to using a trailing comma to force a line break, set
  `preserve`.

---

## Golden Paths — 5 min/day from D13

Define five critical flows before D13 and walk them on a physical device daily.
Fill in yours in `04-testing.md`:

| # | Flow |
|---|------|
| GP-1 | First run → onboarding → main feature |
| GP-2 | Returning user → authenticate → main feature → result |
| GP-3 | Share → open the link on another device |
| GP-4 | Airplane mode → act → reconnect |
| GP-5 | Screen reader on → complete the main flow |

D13 requires: the full plan green, `flutter build apk --debug` succeeding, and
GP-1 … GP-5 validated on a physical device.

---

## Pre-commit hook, by profile

```sh
# strict — .githooks/pre-commit delegates to the gate runner
sh .githooks/lib/quality.sh --stage pre-commit
```

Which expands to, for `strict`:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos --fatal-warnings
dart run custom_lint            # skipped when not configured
```

Nothing here is exotic. The value is that it runs the same way in PowerShell,
cmd.exe and Git Bash, and that the plan lives in one file.
