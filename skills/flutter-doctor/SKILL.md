---
name: flutter-doctor
description: Health check for a Flutter project. Runs 26 checks (environment, structure, dependencies, security, quality gates, Windows shell health) across PowerShell, CMD and Git Bash, and explains every failure with the exact fix. Invoke when a project will not commit, a build fails, hooks seem not to run, or at the start of a dev day.
---

# flutter-doctor — health check (26 checks)

> Skill of the `flu-harness` plugin — install with
> `/plugin marketplace add Jujubalandia/flu-harness` then
> `/plugin install flu-harness@flu-harness`.

## When to invoke

- Before D1, and after cloning on a new machine
- When a pre-commit hook fails without a clear reason, or seems not to run at all
- Before any release build
- After upgrading Flutter or dependencies
- When something works in Git Bash but not PowerShell (or the reverse)

## Running it

Pick the entry point for the shell you are in. All three produce the same 26
checks — pick by availability, not by preference.

**Git Bash / WSL / macOS / Linux**
```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh"
```

**PowerShell (Windows PowerShell 5.1 or PowerShell 7)**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:CLAUDE_PLUGIN_ROOT\scripts\doctor.ps1"
```

**cmd.exe**
```bat
"%CLAUDE_PLUGIN_ROOT%\scripts\doctor.cmd"
```

**Structured output for CI**
```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh" --json
```
```powershell
... -File doctor.ps1 -Json
```
```bat
doctor.cmd /json
```

Point it at a project with a path argument (`doctor.sh /path/to/app`,
`-ProjectDir C:\path\to\app`, `/project:C:\path\to\app`). It defaults to the
current directory.

### Interpreting the output

```
  [OK]   description
  [WARN] description
  [FAIL] description
         fix: the exact command or edit
```

Exit codes: `0` = no FAIL (OK and WARN pass), `1` = at least one FAIL,
`2` = bad usage or PowerShell not found.

### Then: explain and fix

For every `[FAIL]`, explain the root cause and run the suggested fix **after
confirming with the user**. The doctor itself only ever reads — it never edits a
project.

For every `[WARN]`, weigh the phase. Before D5, warns about store identifiers and
`l10n.yaml` are noise. Before a release build, they are not.

---

## The 26 checks

| # | Category | Check | Level on failure |
|---|----------|-------|------------------|
| 1 | Environment | `flutter` on PATH and reporting a version | FAIL |
| 2 | Environment | Flutter >= 3.35 baseline | WARN |
| 3 | Environment | `dart` on PATH | FAIL |
| 4 | Environment | `git` installed | FAIL |
| 5 | Environment | Android SDK findable | WARN |
| 6 | Environment | JDK present (Gradle needs it) | WARN |
| 7 | Structure | `pubspec.yaml` at the project root | FAIL |
| 8 | Structure | `CLAUDE.md` present | WARN |
| 9 | Structure | `.claude/rules/` populated | WARN |
| 10 | Structure | `lib/` with Dart sources | FAIL |
| 11 | Structure | `test/` with at least one `*_test.dart` | WARN |
| 12 | Structure | `analysis_options.yaml` includes a lint set | FAIL if missing |
| 13 | Dependencies | `environment.sdk` constraint pinned | FAIL |
| 14 | Dependencies | `pubspec.lock` committed | WARN |
| 15 | Dependencies | no discontinued packages in direct deps | FAIL |
| 16 | Dependencies | `l10n.yaml` present when localizing | WARN |
| 17 | Dependencies | Android `applicationId` + iOS bundle id set | WARN |
| 18 | Security | `.git/` initialized | FAIL |
| 19 | Security | `.gitignore` covers Flutter + secret paths | FAIL |
| 20 | Security | no secrets tracked by git | FAIL |
| 21 | Security | no hardcoded credentials in `lib/` | FAIL |
| 22 | Gates | `core.hooksPath` = `.githooks` | FAIL |
| 23 | Gates | **hook scripts are LF, not CRLF** | FAIL |
| 24 | Gates | gate library present for all three shells | FAIL |
| 25 | Gates | `.gitattributes` pins LF for `.githooks/` | WARN |
| 26 | Windows | This shell can run the Flutter entry point (MSYS tolerates the SDK's CRLF wrapper; WSL does not) | FAIL |

Checks 22–26 are the ones a generic Flutter linter will never tell you about,
and they are the ones that make hooks "mysteriously not run" on Windows.

---

## Frequent fixes

### FAIL 12: no analysis_options.yaml

```yaml
# analysis_options.yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  errors:
    invalid_annotation_target: ignore   # false positive with freezed + json_serializable

linter:
  rules:
    prefer_const_constructors: true
    prefer_const_declarations: true
    avoid_print: true
```

For a stricter house style, swap in `very_good_analysis`:
```yaml
include: package:very_good_analysis/analysis_options.yaml
```

### FAIL 13: no SDK constraint

```yaml
# pubspec.yaml
environment:
  sdk: ^3.11.0        # match the Dart that ships with your Flutter
```
Find the right number with `dart --version`.

### FAIL 15: discontinued packages

The doctor reports the package and why. The usual migrations:

| Replace | With | Why |
|---------|------|-----|
| `dart_code_metrics` | `dart_code_linter` | discontinued |
| `hive` | `hive_ce` | original is unmaintained |
| `path_provider_ios` | `path_provider` | merged upstream |

### FAIL 19: .gitignore gaps

```bash
cat >> .gitignore <<'EOF'
.dart_tool/
build/
.flutter-plugins
.flutter-plugins-dependencies
.env*
!.env.example
android/key.properties
*.keystore
*.jks
android/app/google-services.json
ios/Runner/GoogleService-Info.plist
ios/Pods/
EOF
```

A committed `key.properties` or `*.keystore` is a release-key compromise, not a
style problem: the key cannot be un-published, and you cannot re-key an app on
the Play Store without losing your install base. Rotate, and expect to publish
under a new package name.

### FAIL 21: hardcoded credentials

```dart
// BEFORE - in the repository, forever, in every clone
const apiKey = 'sk_live_51H8xQ2eZvKYlo2C';

// AFTER - injected at build time, never committed
const apiKey = String.fromEnvironment('API_KEY');
// flutter run --dart-define=API_KEY=... 
// flutter build apk --dart-define-from-file=env.json
```

`--dart-define` values still end up in the binary — they are not a secret store.
For anything that must stay secret, put it behind your backend.

### FAIL 22: hooks never run

```bash
git config core.hooksPath .githooks
git config --get core.hooksPath       # verify
```

Common causes: the repo was cloned and the config was never set (it is local, not
committed — the wizard sets it per clone); or a global `core.hooksPath` is
overriding it; or `.githooks/` was added but nothing re-ran `git config`.

### FAIL 23: CRLF in a hook

Git for Windows reports something unrelated when this happens:

```
error: cannot spawn .githooks/pre-commit: No such file or directory
```

or, from sh itself, `: not found` on line 2. The real cause is that the shebang
line is `#!/bin/sh\r`.

**PowerShell**
```powershell
foreach ($p in @('.githooks\pre-commit', '.githooks\pre-push')) {
    if (Test-Path $p) {
        $t = (Get-Content $p -Raw) -replace "`r`n", "`n"
        [System.IO.File]::WriteAllText((Resolve-Path $p), $t)
    }
}
```

**Git Bash**
```bash
sed -i 's/\r$//' .githooks/pre-commit .githooks/pre-push
```

Then stop it recurring — `.gitattributes` at the repo root:
```
* text=auto eol=lf
.githooks/*  text eol=lf
scripts/**   text eol=lf
```

Verify with `git check-attr eol -- .githooks/pre-commit`, which must print `lf`.

### FAIL 24: gate library incomplete

```bash
ls .githooks/lib/
# expected: quality.sh  quality.ps1  quality.cmd  gates.def
```

Missing files mean one of the three shells cannot run the gates. Re-run
`/flu-harness:new-flutter-project`, or copy the file from the plugin's
`scripts/` directory.

### FAIL 26: this shell cannot run the Flutter bash wrapper

Not your project: the SDK. And it is more specific than it first looks.

`bin/flutter` is a bash wrapper around `bin/internal/shared.sh`, and in the Windows
distribution of the SDK that file carries CRLF line endings. Whether that matters
depends entirely on which `sh` you are:

| Shell | Result |
|-------|--------|
| Git for Windows (Git Bash, MSYS, MinGW) | **Works.** MSYS bash tolerates the CR. Check 26 reports OK. |
| WSL, or Linux/macOS bash reaching a Windows SDK | **Broken:** |

```
$ flutter --version
<flutter-sdk>/bin/internal/shared.sh: line 5: $'\r': command not found
```

So this FAIL means you are in a POSIX shell that is not MSYS. It does **not** mean
Git Bash is broken, and it is not a reason to "repair" an SDK you only ever use
from PowerShell.

Two ways out. Run the gates from PowerShell or cmd, which use `flutter.bat`:

```bat
.githooks\pre-commit.cmd
```

Or repair the SDK once (ask the user first, this edits their SDK):

**Git Bash / WSL**
```bash
find "$(dirname "$(dirname "$(command -v flutter)")")/bin" -name '*.sh' \
  -exec sed -i 's/\r$//' {} +
```

**PowerShell**
```powershell
$sdkBin = Split-Path (Get-Command flutter.bat).Source -Parent
Get-ChildItem $sdkBin -Recurse -Filter *.sh | ForEach-Object {
    $t = (Get-Content $_.FullName -Raw) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($_.FullName, $t)
}
```

A `flutter upgrade` can restore the CRLF, so re-check after upgrading.

One detection note, because it trips up scripts: under MSYS, `command -v flutter`
returns the extensionless wrapper and `command -v flutter.bat` returns nothing,
even though `flutter.bat` is in the same directory. MSYS does not apply `PATHEXT`
to `command -v`. Branch on `uname -s` rather than probing for the `.bat`.

---

## Expected results by phase

| Phase | Acceptable FAILs | Normal WARNs |
|-------|------------------|--------------|
| D1 (setup) | none | 8 (CLAUDE.md), 9 (rules), 16 (l10n), 17 (store ids) |
| D3+ (dev) | none | 16, 17 if store config is not done yet |
| D14+ (release prep) | none | none — everything should be OK |

## Script reference

```
${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh    POSIX sh  — Git Bash, WSL, macOS, Linux
${CLAUDE_PLUGIN_ROOT}/scripts/doctor.ps1   PowerShell — Windows PowerShell 5.1+ and 7+
${CLAUDE_PLUGIN_ROOT}/scripts/doctor.cmd   cmd.exe   — delegates to doctor.ps1
```

`doctor.cmd` does not reimplement the checks. Writing the list a third time in
batch is how three implementations drift apart; the wrapper finds PowerShell and
runs `doctor.ps1`.
