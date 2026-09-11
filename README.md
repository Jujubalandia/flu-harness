# flu-harness

[🇧🇷 Português](README.pt-BR.md) | **🇺🇸 English**

Development framework to ship Flutter apps to the App Store + Play Store in ≤20 days.

Built for Claude Code, with a project wizard, a 26-check health check, and quality
gates that run natively in **PowerShell, CMD and Git Bash** on Windows.

New here? [`docs/GETTING_STARTED.md`](docs/GETTING_STARTED.md) is the condensed
empty-folder → shipped-app walkthrough. [`docs/WINDOWS.md`](docs/WINDOWS.md) is
the shell reference, including four Windows bugs this harness exists to prevent.

---

## What it is

A set of templates, skills and hooks that standardize the full flow:

```
Spec → UX → Dev → QA → Store → Marketing
```

The core is `/flu-harness:new-flutter-project`: open a directory (new or
existing), type the command, and it detects your stack from `pubspec.yaml`,
configures the project, and creates the full structure — a filled `CLAUDE.md`,
`docs/`, git hooks from the selected quality profile, and selective knowledge
rules.

---

## Prerequisites

| Tool | Min version | Install |
|------|-------------|---------|
| Flutter | 3.35 stable | <https://docs.flutter.dev/install> |
| Dart | ships with Flutter | — |
| Git | any | <https://git-scm.com/downloads> |
| Claude Code | latest | `npm i -g @anthropic-ai/claude-code` |
| JDK | 17+ | Android Studio bundles one |

On Windows, also enable **Developer Mode** (Flutter needs symlink support) and
install **Git for Windows** — its bundled `sh.exe` is what runs the git hooks:

```powershell
start ms-settings:developers
```

---

## Installation

Installed as a Claude Code plugin — the same commands on every OS, no clone, no
shell script.

```
/plugin marketplace add Jujubalandia/flu-harness
/plugin install flu-harness@flu-harness
```

Skills, templates, doctor scripts and hook profiles ship inside the plugin;
nothing to place manually.

Update with `/plugin update flu-harness`, remove with
`/plugin uninstall flu-harness`.

### Standalone (optional)

If you want the doctor and gate runners without Claude Code, there is an
installer for each shell. They produce an identical layout in `~/.flu-harness`.

From a clone:

```bash
./scripts/install.sh                       # Git Bash, macOS, Linux
```

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install.ps1
```

```bat
scripts\install.cmd
```

Without cloning, straight from the repository:

```bash
# Git Bash, macOS, Linux
curl -fsSL https://raw.githubusercontent.com/Jujubalandia/flu-harness/main/scripts/install.sh | sh
```

```powershell
# PowerShell
irm https://raw.githubusercontent.com/Jujubalandia/flu-harness/main/scripts/install.ps1 | iex
```

The piped form downloads a tarball of the repository to a temporary directory,
installs from it, and removes it. `HARNESS_REF` picks a branch or tag;
`HARNESS_TARBALL_URL` overrides the download for a fork or a mirror.

| Flag / variable | Effect |
|-----------------|--------|
| `--prefix DIR` / `-Prefix DIR` | install somewhere other than `~/.flu-harness` |
| `--from DIR` / `-From DIR` | install from a specific checkout |
| `--force` / `-Force` | overwrite an existing install |
| `--uninstall` / `-Uninstall` | remove the install |
| `HARNESS_REF` | branch or tag to download (default `main`) |
| `HARNESS_TARBALL_URL` | full download URL; must be a `.zip` for PowerShell |

---

## Usage — new project

```bash
mkdir ~/projects/my-app && cd ~/projects/my-app
claude
```

In Claude Code:

```
/flu-harness:new-flutter-project
```

### What the wizard does

**1. Auto-detects the stack from `pubspec.yaml`** across 16 dimensions:

| Dimension | What it detects |
|-----------|----------------|
| State management | Riverpod · Bloc · Provider · GetX · Signals |
| Routing | go_router · auto_route · Beamer |
| Backend | Supabase · Firebase · Appwrite · Amplify |
| Local database | Drift · Isar · sqflite · Hive |
| HTTP client | Dio · http · Chopper |
| Serialization | Freezed · json_serializable · built_value |
| Secure storage | flutter_secure_storage · shared_preferences (WARN if it holds tokens) |
| i18n | official gen-l10n · easy_localization · slang |
| Animation | flutter_animate · Rive · Lottie |
| Monetization | RevenueCat · in_app_purchase · AdMob |
| Notifications | FCM · flutter_local_notifications |
| Testing | mocktail · mockito · Patrol · Alchemist |
| Linting | very_good_analysis · flutter_lints · dart_code_linter |
| Release tooling | Shorebird · Fastlane |
| **Design system** | **`material_ui`/`cupertino_ui` vs in-framework — not interchangeable** |
| Extras | camera · geolocator · share_plus · url_launcher · … |

It shows the table and asks you to confirm before writing anything.

**2. Detects your shell environment** — which of the three shells this machine can
run — and reports the state of your Flutter SDK, including the CRLF-corrupted `sh`
wrapper that ships in the Windows distribution (see below).

**3. Only asks what it cannot detect:** name, org, description, languages,
monetization, hook profile, editor, primary shell.

**4. Creates the structure:**
- `CLAUDE.md` filled in (no placeholders left)
- `DECISIONS.md` + `TODO.md` initialized
- `docs/` with the 6 phase templates
- `.githooks/` with hooks **and a gate runner for all three shells**
- `.claude/rules/` with **selective** knowledge rules, only for your detected stack
- `.claude/settings.json` + hooks — the destructive-operation guard
- `.gitattributes` pinning LF for the hooks (not cosmetic on Windows)

**5. Proves the three shells agree** by dry-running the gate plan in each, then
prints a next-steps checklist tailored to your stack.

---

## The Windows story

This is the part that differs most from a typical harness, and it is not
decoration. Each of these was found by running the thing.

### Git runs hooks itself

On Windows, Git for Windows executes hooks through its bundled `sh.exe` — **not**
through whichever shell you typed `git commit` in. So `.githooks/pre-commit` is one
POSIX shell script, and it fires identically from PowerShell, `cmd.exe` and Git
Bash. Git cannot execute a `.ps1` or a `.cmd` as a hook, which is why the Windows
variants next to it are for running the same gates by hand.

```
                        you type: git commit
                               │
              ┌────────────────┼────────────────┐
              ▼                ▼                ▼
         PowerShell         cmd.exe          Git Bash
              └────────────────┼────────────────┘
                               ▼
                    .githooks/pre-commit
                    run by Git for Windows' own sh.exe
                               │
                               ▼
                    .githooks/lib/quality.sh
                    (reads gates.def — one plan)
```

### One gate plan, three runners

Three shells means three chances to drift: someone adds a gate to the PowerShell
runner, forgets the batch one, and a Windows user ships without it.

So the plan is data, not three copies of code:

```
# .githooks/lib/gates.def
pre-commit=format,analyze,lint
pre-push=format,analyze,lint,test,build
```

`quality.sh`, `quality.ps1` and `quality.cmd` all parse that same file.
`--dry-run` prints the resolved plan, and the test suite asserts all three produce
**identical** output for every profile — so they cannot drift silently.

### Four bugs it prevents

| # | Bug | Symptom | What flu-harness does |
|---|-----|---------|-----------------------|
| 1 | `cmd.exe`: `shift` also moves `%1` into `%0` | `%~dp0` stops meaning "this script's directory" and expands to `C:\project:C:\src\` | Captures `%~dp0` into a variable on the first line, before any parsing |
| 2 | `cmd.exe`: `set "VAR=value"` strips only the outer quotes | A nested `""` survives as two literal quote characters and the argument arrives mangled | Uses the plain `set VAR=value` form so inner quotes survive verbatim |
| 3 | The Flutter SDK ships `bin/internal/shared.sh` with CRLF | `internal/shared.sh: line 5: $'\r': command not found`, but **only** from WSL or Linux bash. Git Bash runs the same SDK fine. | Branches on `uname -s`: trusts the wrapper under MSYS, FAILs it on a POSIX shell where it genuinely cannot run, and prints the repair command |
| 4 | A hook checked out with CRLF | Git looks for an interpreter named `/bin/sh\r` and reports something unrelated | `.gitattributes` pins `eol=lf`, the installer rewrites on the way in, and doctor FAIL 23 detects it |

Full write-up, with the evidence and the repairs: [`docs/WINDOWS.md`](docs/WINDOWS.md).

---

## flutter-doctor — health check

26 checks on any Flutter project. Read-only: it never edits your files.

```
/flu-harness:flutter-doctor
```

Or run it directly. Pick your shell:

```bash
sh ~/.flu-harness/scripts/doctor.sh                     # Git Bash, WSL, macOS, Linux
```

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.flu-harness\scripts\doctor.ps1"
```

```bat
%USERPROFILE%\.flu-harness\scripts\doctor.cmd
```

Add `--json` / `-Json` / `/json` for structured output — the shape is verified by
the test suite, including that every FAIL carries a `fix`.

### What it checks

| Category | Checks |
|----------|--------|
| Environment | flutter on PATH and reporting a version, ≥3.35, dart, git, Android SDK, JDK |
| Structure | `pubspec.yaml`, `CLAUDE.md`, `.claude/rules/`, `lib/`, `test/`, `analysis_options.yaml` |
| Dependencies | `environment.sdk` pinned, `pubspec.lock` committed, no discontinued packages, `l10n.yaml`, store identifiers |
| Security | `.git/`, `.gitignore` covers Flutter + secret paths, no secrets tracked, no hardcoded credentials |
| Gates | `core.hooksPath`, **hook line endings**, gate library complete for all three shells, `.gitattributes` |
| Windows | the Flutter SDK's CRLF-corrupted sh wrapper |

### Output

```
  [OK]   flutter 3.41.6 on PATH (channel: stable)
  [OK]   Dart SDK version: 3.11.4 (stable) on "windows_x64"
  [OK]   flutter resolves to flutter.bat (the Windows entry point)
  [WARN] CLAUDE.md missing (flu-harness not initialized)
  [FAIL] CRLF line endings in hook script(s): pre-commit - git will refuse to run them
         fix: sed -i 's/\r$//' .githooks/pre-commit ; and add '.githooks/* text eol=lf' to .gitattributes
  ...
  OK: 19  WARN: 4  FAIL: 3  / 26 total
```

Exit `0` = no FAIL. Exit `1` = at least one FAIL. Exit `2` = bad usage.

### When to run it

- D1, right after the wizard
- After cloning on a new machine
- When a hook fails without a clear reason, or seems not to run at all
- When something works in Git Bash but not PowerShell
- Before any release build

---

## Quality gates

Pre-commit blocks based on the **active profile**:

| Profile | pre-commit | pre-push |
|---------|-----------|----------|
| `minimal` | `flutter analyze` | + `flutter test` |
| `standard` | `dart format` + `analyze` | + `lint` + `test` |
| `strict` *(default)* | `format` + `analyze` + `lint` | + `test` + `flutter build apk --debug` |

Gates:

| Gate | Command |
|------|---------|
| `format` | `dart format --output=none --set-exit-if-changed .` |
| `analyze` | `flutter analyze --fatal-infos --fatal-warnings` |
| `lint` | `dart_code_linter` metrics with `--set-exit-on-violation-level=warning` (or `custom_lint`), self-skips when unconfigured |
| `test` | `flutter test`, self-skips when there is no `test/` |
| `build` | `flutter build apk --debug` — the only gate that catches a Gradle failure |

`strict` is the default because of `build`. The analyzer passing does not mean the
app compiles for a real target, and discovering that at D16 instead of D5 is the
difference between shipping and not.

**Never weaken a gate to make it pass.** If the check is wrong, fix the check in
the same commit and say why.

Prove your three shells agree, any time:

```bash
sh  .githooks/lib/quality.sh  --dry-run
powershell -ExecutionPolicy Bypass -File .githooks\lib\quality.ps1 -DryRun
cmd /c .githooks\lib\quality.cmd /dry-run
```

---

## Environment variables

| Variable | Effect |
|----------|--------|
| `HARNESS_PROFILE` | `minimal` / `standard` / `strict` when `.githooks/.profile` is absent |
| `HARNESS_DEVICE_OK` | `1` pre-answers the pre-push "tested on a real device?" prompt |
| `HARNESS_SKIP_BUILD` | `1` skips the `build` gate and prints a loud warning that it did |
| `HARNESS_FLUTTER` / `HARNESS_DART` | point at a specific SDK binary |

---

## Destructive-operation guard

Two mechanisms block irreversible operations before they run.

### `.claude/settings.json` — declarative denylist

```json
{ "permissions": { "deny": [
  "Bash(flutter pub publish*)",
  "Bash(fastlane deliver*)",
  "Bash(git push --force*)",
  "Bash(keytool -genkey*)",
  "Read(./android/key.properties)"
]}}
```

### `.claude/hooks/pre-tool-use.*` — runtime blocking

Blocked: `flutter pub publish`, `dart pub publish`, `fastlane deliver|supply`,
`firebase appdistribution:distribute`, `firebase firestore:delete`,
`flutter build ipa`, `git push --force`, `git commit --no-verify`,
`git reset --hard`, `git clean -f`, `git filter-branch|filter-repo`,
`git rebase -i`, `rm -rf /` and `~`, `supabase db reset`, `DROP TABLE`,
`TRUNCATE TABLE`, `DELETE` with no `WHERE`, `keytool -genkey`.

Shipped for all three shells — `.sh` (no Python dependency), `.ps1`, `.cmd`.
The `.sh` version deliberately avoids `python3`, which is the reason most hooks
silently do nothing on a Windows box.

---

## Knowledge rules

20 `.md` files that Claude loads automatically based on the files you are editing.
The wizard copies **only those relevant to your detected stack**.

| Rule | Copied when | Covers |
|------|-------------|--------|
| `patterns.md` | always | folder structure, widget decomposition, async state, streams |
| `performance.md` | always | `const`, rebuild scoping, lists, images, isolates, app size |
| `security.md` | always | what is safe to embed, secure storage, signing, RLS |
| `accessibility.md` | always | semantics, 48dp targets, text scaling, contrast, a11y tests |
| `forbidden.md` | always | deprecated and removed APIs, plus the 13 patterns that cause silent bugs |
| `testing.md` | always | fakes vs mocks, widget tests, goldens, what not to test |
| `riverpod.md` | State = Riverpod | providers, `watch`/`read`/`listen`, `AsyncValue`, testing |
| `bloc.md` | State = Bloc | events, `emit` safety, builder/listener/consumer, ownership |
| `go-router.md` | Routing = go_router | shell routes, auth redirects, deep links, typed routes |
| `dio.md` | HTTP = Dio | interceptors, token refresh, cancellation, typed failures |
| `supabase.md` | Backend = Supabase | session persistence in secure storage, RLS, `.single()` traps |
| `firebase.md` | Backend = Firebase | auth streams, Firestore cost, converters, rules |
| `drift.md` | DB = Drift | tables, migrations, background isolate, reactive queries |
| `freezed.md` | Codegen | unions, JSON, the `copyWith(null)` trap, unknown enum values |
| `i18n.md` | i18n configured | ARB, ICU plurals, `Intl` locale traps, detecting hardcoded strings |
| `revenue-cat.md` | Monetization | entitlements, restore, user identity, sandbox vs production |
| `notifications.md` | Notifications | FCM states, the `vm:entry-point` trap, channels, scheduling |
| `animation.md` | Animation | implicit vs explicit, controller lifecycle, jank diagnosis |
| `material-ui.md` | Flutter 3.47+ | the `material_ui`/`cupertino_ui` split and its compatibility bridge |

---

## 20-day timeline

| Phase | Days | Focus | Main doc |
|-------|------|-------|----------|
| Spec + setup | D1-D3 | Specification + running environment | `01-spec.md` |
| Core dev | D4-D10 | MVP features (1/day) | `02-dev-plan.md` |
| Polish | D11-D13 | i18n, a11y, loading states, performance | `03-quality-gates.md` |
| QA + store prep | D14-D15 | Release build + assets | `04-testing.md`, `05-store-launch.md` |
| Submission | D16-D17 | AAB/IPA upload + review | `05-store-launch.md` |
| Marketing | D18-D20 | Landing page + launch posts | `06-marketing.md` |

> **Start the clocks that cannot be rushed on D0.** Apple Developer approval takes
> days, and a **Google Play personal account needs 12 testers opted in for 14
> continuous days** before it can publish to production. That is three weeks of
> lead time — longer than this entire plan. Push a placeholder to closed testing
> on D0. See `05-store-launch.md`.

---

## Device matrix

| Device | Platform | Use |
|--------|----------|-----|
| Your own Android phone | Android | main loop: haptics, share sheet, deep links |
| Android emulator | Android | fast iteration, multi-user, screen sizes |
| Appetize.io / Chrome | iOS / web | weekly smoke: layout, navigation, i18n |
| Borrowed iPhone | iOS | TestFlight from D17, 1-2 hours |

**No Mac?** A cloud Mac by the hour for the archive step, or a CI runner that
archives and uploads to TestFlight. Both need an Apple Developer account and an
App Store Connect API key. Set this up on **D1**, not D16.

> **D1 action:** schedule the iPhone borrow for D17-D18. Log it in `TODO.md`.

---

## Repo structure

```
flu-harness/
├── .claude-plugin/           plugin + marketplace manifests
├── .gitattributes            LF policy — load-bearing on Windows
├── docs/
│   ├── GETTING_STARTED.md
│   └── WINDOWS.md            the shell reference
├── scripts/
│   ├── quality.sh|ps1|cmd    gate runner, one per shell
│   ├── doctor.sh|ps1|cmd     26 checks
│   └── install.sh|ps1|cmd    standalone installer
├── git-hooks/
│   ├── pre-commit            POSIX sh — git runs this from any shell
│   ├── pre-push
│   ├── pre-commit.ps1|cmd    manual runners
│   ├── pre-push.ps1|cmd
│   └── profiles/<name>/gates.def
├── skills/
│   ├── new-flutter-project/
│   └── flutter-doctor/
├── templates/
│   ├── CLAUDE.md.tmpl
│   ├── DECISIONS.md.stub
│   ├── TODO.md.stub
│   ├── docs/                 6 phase templates
│   ├── rules/                20 knowledge rules
│   └── claude/               settings.json + pre-tool-use.*
└── tests/
    ├── test.sh                 suite: structure, shells, gates, guard, doctor
    ├── test.ps1                Windows suite, including real hook execution
    └── check_links.py          every relative doc link must resolve
```

---

## Contributing

1. Clone the repo and edit files locally
2. Run `bash tests/test.sh` — it must finish with 0 failures. On Windows also run
   `powershell -ExecutionPolicy Bypass -File tests\test.ps1`
3. Test the skills against your local clone:
   `/plugin marketplace add /path/to/local/flu-harness`
4. Commit and push

The test suite asserts the three shells agree on the gate plan, that the guard
blocks and allows the right things, that the doctor's 26 checks are present and
identical in both native implementations, and that hooks are LF. If you change a
gate or a check, those assertions are what catch the drift.

Template and rule changes take effect in projects created **after** the change.
Existing projects are not affected.

---

## FAQ

**Does it work on Windows?**
That is most of what it is designed for. See [`docs/WINDOWS.md`](docs/WINDOWS.md).

**Do I need Git Bash installed if I use PowerShell?**
You need **Git for Windows**, which ships `sh.exe` — that is the interpreter git
uses to run hooks. You never have to open it. If you use Git Bash as your shell,
it is already there.

**Why is the hook a `.sh` file if I work in PowerShell?**
Because git runs hooks itself, through its bundled `sh.exe`, regardless of your
shell. A `.ps1` cannot be a git hook. There are `.ps1` and `.cmd` twins for
running the same gates manually.

**The three runners disagree. What now?**
They cannot, by construction — they parse the same `gates.def`. If `--dry-run`
output differs, the file is corrupt or one runner is a stale copy. Re-run the
wizard.

**`flutter` fails with `$'\r': command not found`. Why?**
Your SDK's `bin/internal/shared.sh` has CRLF line endings, a defect in the Windows
distribution of the SDK. But it only breaks some shells: Git Bash (MSYS) runs it
anyway, WSL and Linux bash do not. So `flutter` failing that way means you are in
WSL, not Git Bash. Run the gates from PowerShell or cmd, or use doctor check 26's
repair command. See [`docs/WINDOWS.md`](docs/WINDOWS.md).

**How do I start without overwriting existing files?**
The wizard checks each file before creating. Existing ones are skipped with a
warning.

**Are all 19 rules always copied?**
No — they are selective. A project without Supabase never sees `supabase.md`. To
get all of them, run the wizard in a directory with no `pubspec.yaml`.

**How do I change the hook profile?**
Re-run `/flu-harness:new-flutter-project` and pick a different one, or replace
`.githooks/lib/gates.def` and `.githooks/.profile` by hand.

**Does the doctor modify files?**
No. It reads and reports. Fixes are suggested, and applied only when you confirm.

**Is `--json` output safe for CI?**
Yes. `tests/test.sh` asserts it parses, that check numbers are exactly `1..26`
with no gaps or duplicates, and that every `FAIL` has a non-empty `fix`.

---

## Uninstall

```
/plugin uninstall flu-harness
```

Removes the plugin. Projects you already generated keep their files — templates
and rules only apply to projects created after a change.
