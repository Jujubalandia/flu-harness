---
name: new-flutter-project
description: Interactive wizard that initializes a Flutter/Dart project with flu-harness. Auto-detects the stack from pubspec.yaml, then creates CLAUDE.md, docs/, DECISIONS.md, TODO.md, git hooks (PowerShell + CMD + Git Bash), and selective .claude/rules/. Never overwrites an existing file. Run from the project root.
---

# new-flutter-project — wizard

> Skill of the `flu-harness` plugin — install with
> `/plugin marketplace add Jujubalandia/flu-harness` then
> `/plugin install flu-harness@flu-harness`.

## When to invoke

The user is in a Flutter project directory (new, or existing but without a
`CLAUDE.md`) and wants to start with flu-harness.

## Sequence — run these steps in order

### Step 1: Confirm the working directory

Confirm the current directory is the project root, not a subdirectory. The tell
is `pubspec.yaml` sitting next to `lib/`.

If `CLAUDE.md` already exists, warn and ask whether to continue. If
`.githooks/` already exists, note that the hooks will be refreshed.

---

### Step 1b: Auto-detect the stack from pubspec.yaml

**If `pubspec.yaml` exists**, read it and detect every dimension below. Match on
the dependency name anywhere in `dependencies:`, `dev_dependencies:`, or
`dependency_overrides:`.

```
STATE MANAGEMENT
  flutter_riverpod / hooks_riverpod / riverpod_annotation  -> Riverpod
  flutter_bloc / bloc                                      -> Bloc
  provider                                                 -> Provider
  get / getx                                               -> GetX
  signals_flutter                                          -> Signals
  (none)                                                   -> Riverpod (default)

NAVIGATION / ROUTING
  go_router              -> go_router (Flutter-team recommended)
  auto_route             -> auto_route
  beamer                 -> Beamer
  (none)                 -> go_router (default)

BACKEND
  supabase_flutter       -> Supabase
  firebase_core          -> Firebase
  appwrite               -> Appwrite
  amplify_flutter        -> AWS Amplify
  (none)                 -> "(none)"

LOCAL DATABASE
  drift                  -> Drift (SQLite, type-safe)
  isar / isar_community  -> Isar
  sqflite                -> sqflite
  hive_ce / hive         -> Hive
  (none)                 -> "(none)"

HTTP CLIENT
  dio                    -> Dio
  http                   -> http
  chopper                -> Chopper
  (none)                 -> Dio (default)

SERIALIZATION
  json_serializable      -> json_serializable + build_runner
  freezed                -> Freezed
  built_value            -> built_value
  (none)                 -> json_serializable (default)

SECURE STORAGE
  flutter_secure_storage -> flutter_secure_storage (OK)
  shared_preferences     -> shared_preferences
  BOTH                   -> flutter_secure_storage for secrets, shared_preferences
                            for preferences (OK if used that way)
  shared_preferences ONLY while the app has auth -> WARNING:
    "tokens in shared_preferences are plain text on disk"
  (none)                 -> "(none)"

INTERNATIONALIZATION
  flutter_localizations + intl  -> official gen-l10n
  easy_localization             -> easy_localization
  slang                         -> slang
  (none)                        -> "(none)"

ANIMATION
  flutter_animate        -> flutter_animate
  rive                   -> Rive
  lottie                 -> Lottie
  (none)                 -> "(none)"

MONETIZATION
  purchases_flutter      -> RevenueCat
  in_app_purchase        -> in_app_purchase (official)
  google_mobile_ads      -> AdMob
  (none)                 -> "(none)"

NOTIFICATIONS
  firebase_messaging            -> FCM
  flutter_local_notifications   -> local notifications
  BOTH                          -> FCM + local
  (none)                        -> "(none)"

TESTING
  mocktail               -> mocktail
  mockito                -> mockito
  patrol                 -> Patrol
  integration_test       -> integration_test
  alchemist              -> Alchemist (golden tests)
  (none)                 -> flutter_test only

LINTING
  very_good_analysis     -> very_good_analysis (strict)
  flutter_lints          -> flutter_lints
  custom_lint            -> custom_lint enabled
  dart_code_linter       -> dart_code_linter metrics
  (none)                 -> flutter_lints (default)

RELEASE TOOLING
  shorebird_code_push    -> Shorebird
  (fastlane/ directory)  -> Fastlane
  (none)                 -> "(none)"

DESIGN SYSTEM  (Flutter 3.47+ decoupled Material and Cupertino out of the SDK)
  material_ui / cupertino_ui in deps -> standalone packages (migrated)
  imports of package:flutter/material.dart -> in-framework (not migrated)
  both                                 -> WARNING: mixed - two distinct ThemeData
                                          types, assignment errors are guaranteed
  (no lib/ yet)                        -> "(not decided)"
  The in-framework libraries were frozen in Flutter 3.44 and are scheduled for
  deprecation. This is a real fork in the road: report which side the project is
  on, because the two are not interchangeable. See rules/material-ui.md.

EXTRAS (for LIBS_ADICIONAIS)
  camera, geolocator, url_launcher, share_plus, path_provider,
  image_picker, permission_handler, flutter_local_notifications,
  sqflite, google_fonts, flutter_svg, cached_network_image
```

**Print the detection table before asking anything:**

```
Stack detected in pubspec.yaml:
---------------------------------------------
State management : Riverpod              (detected)
Navigation       : go_router             (detected)
Backend          : Supabase              (detected)
Local database   : Drift                 (detected)
HTTP client      : Dio                   (detected)
Serialization    : Freezed + json_serializable (detected)
Secure storage   : flutter_secure_storage (detected)
i18n             : official gen-l10n     (detected)
Animation        : flutter_animate       (detected)
Monetization     : RevenueCat            (detected)
Notifications    : FCM                   (detected)
Testing          : mocktail              (detected)
Linting          : very_good_analysis    (detected)
Release tooling  : Fastlane              (detected)
Extras           : camera, share_plus, url_launcher
---------------------------------------------
Press Enter to confirm, or tell me what to correct:
```

Wait for confirmation. Use any corrections the user gives.

**Automatic warnings:**
- `shared_preferences` holding auth tokens -> `WARNING: tokens in shared_preferences are stored in plain text. Move them to flutter_secure_storage.`
- Firebase detected -> `NOTE: the supabase.md rule does not apply (Firebase detected).`
- Both Riverpod and Bloc present -> `WARNING: two state managers detected. Pick one before adding rules.`
- `hive` (not `hive_ce`) -> `WARNING: hive itself is unmaintained; hive_ce is the maintained fork.`

---

### Step 2: Detect the shell environment

The harness ships gates for three shells. Find out which ones this machine can
actually run, and record the answer in `CLAUDE.md`:

```bash
# what is available?
git --version                 # required
sh --version 2>/dev/null      # Git Bash / MSYS
powershell -Command '$PSVersionTable.PSVersion' 2>/dev/null
pwsh -Command '$PSVersionTable.PSVersion' 2>/dev/null
cmd /c ver 2>/dev/null
flutter --version
dart --version
```

Show the result as a table:

```
Shell support on this machine:
---------------------------------------------
Git Bash (sh)     : available          <- git hooks run here
PowerShell 5.1    : available
PowerShell 7      : not found (optional)
cmd.exe           : available
Flutter SDK       : 3.41.6 stable at C:\flutter\flutter
Dart SDK          : 3.11.4
---------------------------------------------
```

**Critical check — the broken Flutter sh wrapper.** On Windows the SDK's
`bin/flutter` bash wrapper sources `bin/internal/shared.sh`, which ships with
CRLF line endings in the Windows distribution. Under Git Bash it dies with:

```
internal/shared.sh: line 5: $'\r': command not found
```

Test for it and report it now, before the user wastes an afternoon on it:

```bash
# Git Bash / WSL
head -c 200 "$(dirname "$(command -v flutter)")/internal/shared.sh" | od -c | grep -q '\\r' \
  && echo "WARNING: Flutter sh wrapper has CRLF -> use flutter.bat, or repair the SDK"
```

If detected, offer the repair:

```bash
find "$FLUTTER_ROOT/bin" -name '*.sh' -exec sed -i 's/\r$//' {} +
```

Do not run the repair without asking — it edits the user's SDK.

---

### Step 3: Collect what could not be detected

Ask **only** what cannot be inferred from `pubspec.yaml`:

- **APP_NAME** — display name (e.g. `BracketBall`, `FitTracker`)
- **APP_SLUG** — snake_case, must be a valid Dart package name (e.g. `bracketball`)
- **ORG** — reverse-domain org for the bundle id (e.g. `com.jujubalandia`)
- **DESCRIPTION** — one line: problem + solution
- **MAIN_FOCUS** — the differentiator or viral hook
- **LANGUAGES** — e.g. `PT-BR / EN-US` (pick at least one)
- **MONETIZATION** — freemium / IAP / ads / subscription / none
- **HOOK_PROFILE** — read `${CLAUDE_PLUGIN_DATA}/.profile` if it exists and offer
  to keep it; default `strict` otherwise.
  - `minimal` — `flutter analyze` only. Fast inner loop, D1-D5.
  - `standard` — format + analyze on commit; + lint + tests on push.
  - `strict` — *default*: format + analyze + lint on commit; + tests + a real
    debug APK build on push. The build gate is what catches "compiles in the
    analyzer, explodes in Gradle".
  At the end of Step 5, write the choice back to
  `${CLAUDE_PLUGIN_DATA}/.profile` so the next project remembers it.
- **EDITOR** — Zed / VS Code / Android Studio / other
- **PRIMARY_SHELL** — PowerShell / cmd / Git Bash. Offer the detected value from
  Step 2 as the default.

Derive automatically:
- `BUNDLE_ID` = `<ORG>.<APP_SLUG>`
- `START_DATE` = today, ISO
- `LIBS_ADICIONAIS` = the detected EXTRAS plus backend, db, http, i18n, animation
- `DOMAIN` = the domain noun derived from APP_NAME (used for hook and type names)

---

### Step 4: Create the structure — never overwrite

For every file: check for existence first. If it exists, print
`WARNING: <file> already exists — skipping` and continue with the rest.

**A. `CLAUDE.md`** — from `${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE.md.tmpl`

Replace every `{{PLACEHOLDER}}`. The template must end up with **zero**
`{{` occurrences — if any remain it is a bug, finish them by hand.

| Placeholder | Value |
|-------------|-------|
| `{{APP_NAME}}` | collected |
| `{{APP_SLUG}}` | collected |
| `{{DESCRIPTION}}` | collected |
| `{{MAIN_FOCUS}}` | collected |
| `{{LANGUAGES}}` | collected |
| `{{STATE_MGMT}}` | detected |
| `{{NAVIGATION}}` | detected |
| `{{BACKEND}}` | detected |
| `{{LOCAL_DB}}` | detected |
| `{{HTTP_CLIENT}}` | detected |
| `{{SERIALIZATION}}` | detected |
| `{{SECURE_STORAGE}}` | detected |
| `{{I18N}}` | detected |
| `{{MONETIZATION}}` | detected |
| `{{NOTIFICATIONS}}` | detected |
| `{{TESTING}}` | detected |
| `{{LINTING}}` | detected |
| `{{LIBS_ADICIONAIS}}` | extras, or drop the line |
| `{{DOMAIN}}` | derived |
| `{{DOMAIN_TYPES}}` | `// TODO: define the domain types on D3` |
| `{{DOMAIN_RULES}}` | the project's own non-negotiables, or drop the line |
| `{{PRIMARY_SHELL}}` | collected |
| `{{EDITOR}}` | collected |

**B. `DECISIONS.md`** — from `templates/DECISIONS.md.stub`. Replace
`{{APP_NAME}}`, `{{START_DATE}}`, `{{STATE_MGMT}}`, `{{NAVIGATION}}`,
`{{BACKEND}}`.

**C. `TODO.md`** — from `templates/TODO.md.stub`. Replace `{{APP_NAME}}`,
`{{START_DATE}}`. Leave `{{FEATURE_1}}`, `{{FEATURE_2}}` and `{{FEATURE_3}}` for the user to fill
in on D3 — they are the D4-D10 feature queue.

**D. `docs/` (6 files)** — copy `templates/docs/` unchanged, creating `docs/` if
needed. On Windows, keep LF line endings.

**E. `.claude/rules/`** — copy **selectively** from `templates/rules/`:

| Rule | Copy when |
|------|-----------|
| `patterns.md` | **always** |
| `performance.md` | **always** |
| `security.md` | **always** |
| `accessibility.md` | **always** |
| `forbidden.md` | **always** |
| `testing.md` | **always** |
| `riverpod.md` | STATE = Riverpod |
| `bloc.md` | STATE = Bloc |
| `go-router.md` | NAVIGATION = go_router |
| `supabase.md` | BACKEND = Supabase |
| `firebase.md` | BACKEND = Firebase |
| `drift.md` | LOCAL_DB = Drift |
| `dio.md` | HTTP = Dio |
| `freezed.md` | SERIALIZATION = Freezed or json_serializable |
| `i18n.md` | I18N is configured |
| `revenue-cat.md` | MONETIZATION = RevenueCat or in_app_purchase |
| `notifications.md` | NOTIFICATIONS != "(none)" |
| `animation.md` | ANIMATION != "(none)" |
| `material-ui.md` | Flutter 3.47+, or the project imports `material_ui`/`cupertino_ui`. Always worth having on a recent SDK — the two design-system worlds are not interchangeable. |
| `windows-dev.md` | **always on Windows** — the multi-shell rules |

For a brand-new project with no `pubspec.yaml`: copy **all** rules as a starting
set, then prune once the stack is decided.

**F. `.githooks/`** — copy from `${CLAUDE_PLUGIN_ROOT}/git-hooks/`:

```
.githooks/pre-commit          <- git-hooks/pre-commit        (POSIX sh, LF)
.githooks/pre-push            <- git-hooks/pre-push          (POSIX sh, LF)
.githooks/pre-commit.ps1      <- git-hooks/pre-commit.ps1
.githooks/pre-commit.cmd      <- git-hooks/pre-commit.cmd
.githooks/pre-push.ps1        <- git-hooks/pre-push.ps1
.githooks/pre-push.cmd        <- git-hooks/pre-push.cmd
.githooks/lib/quality.sh      <- scripts/quality.sh
.githooks/lib/quality.ps1     <- scripts/quality.ps1
.githooks/lib/quality.cmd     <- scripts/quality.cmd
.githooks/lib/gates.def       <- git-hooks/profiles/<HOOK_PROFILE>/gates.def
.githooks/.profile            <- containing exactly "<HOOK_PROFILE>"
```

**Write LF line endings for every file under `.githooks/`.** On Windows that
means using a writer that does not translate: in PowerShell,
`[System.IO.File]::WriteAllText($path, $text)` with `"`n"` joins — *not*
`Set-Content` or `Out-File`, which append CRLF and produce a hook git refuses to
run. This is the single most common way a Windows install breaks.

Then:

```bash
mkdir -p .githooks/lib
git config core.hooksPath .githooks
chmod +x .githooks/pre-commit .githooks/pre-push .githooks/lib/quality.sh 2>/dev/null || true
```

If `.git/` does not exist yet, run `git init` first.

**G. `.claude/settings.json`** — from `templates/claude/settings.json` (only if absent).

**H. `.claude/hooks/`** — from `templates/claude/hooks/`:

```
.claude/hooks/pre-tool-use.sh     <- POSIX sh, no python3 dependency
.claude/hooks/pre-tool-use.ps1    <- PowerShell twin
.claude/hooks/pre-tool-use.cmd    <- cmd.exe entry point
```

**I. `.gitattributes`** — from the plugin root. This is not optional on Windows:
without it a clone with `core.autocrlf=true` checks the hooks out with CRLF and
git refuses to run them. Verify it afterwards:

```bash
git check-attr eol -- .githooks/pre-commit   # -> eol: lf
```

**J. `.gitignore`** — merge, do not replace. Flutter needs at minimum:

```
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
*.g.dart
*.freezed.dart
```

Only append the `*.g.dart` / `*.freezed.dart` lines if the project actually uses
code generation — otherwise they hide files someone meant to commit.

---

### Step 5: Configure the hooks

Already handled in Step 4F. Print the outcome:

```
Hooks installed with profile: strict
  .githooks/pre-commit      (POSIX sh — git runs this from PowerShell, cmd and Git Bash)
  .githooks/pre-commit.ps1  (run by hand in PowerShell)
  .githooks/pre-commit.cmd  (run by hand in cmd.exe)
  git core.hooksPath = .githooks
```

Then prove the three shells agree, which is the whole point of shipping three:

```bash
sh   .githooks/lib/quality.sh  --dry-run
powershell -NoProfile -ExecutionPolicy Bypass -File .githooks/lib/quality.ps1 -DryRun
cmd /c .githooks\lib\quality.cmd /dry-run
```

All three must print the same `gate=` lines. If they do not, the install is
broken — report it rather than papering over it.

Finally, remember the profile:

```bash
mkdir -p "${CLAUDE_PLUGIN_DATA}"
printf '%s' "$HOOK_PROFILE" > "${CLAUDE_PLUGIN_DATA}/.profile"
```

(On Windows PowerShell:
`New-Item -ItemType Directory -Force $env:CLAUDE_PLUGIN_DATA | Out-Null;`
`[System.IO.File]::WriteAllText("$env:CLAUDE_PLUGIN_DATA\.profile", $HookProfile)`)

---

### Step 6: Print a next-steps checklist

Tailor it to the detected stack. Print it in the chat — do not write a file.

```
Project initialized: {{APP_NAME}}
Stack: {{STATE_MGMT}} + {{NAVIGATION}} + {{BACKEND}} + {{I18N}}
Primary shell: {{PRIMARY_SHELL}}   Hook profile: {{HOOK_PROFILE}}

## Next steps (D1)
```

If there is no `pubspec.yaml` yet:

```
- [ ] flutter create . --org com.{{ORG}} --project-name {{APP_SLUG}} --platforms=android,ios
```

Build the `flutter pub add` line from **only what was not detected**:

```
flutter pub add flutter_riverpod go_router flutter_secure_storage
flutter pub add dev:flutter_lints build_runner json_serializable
```

Always end dependency installation with:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # only if codegen is used
```

Always include:

```
### Verify the install
- [ ] sh .githooks/lib/quality.sh --dry-run          (Git Bash)
- [ ] powershell -ExecutionPolicy Bypass -File .githooks\lib\quality.ps1 -DryRun
- [ ] cmd /c .githooks\lib\quality.cmd /dry-run
      -> all three must list the same gates
- [ ] /flu-harness:flutter-doctor                    (expect 0 FAIL)

### If Supabase is the backend
supabase init
supabase link --project-ref <YOUR_PROJECT_REF>

### If Fastlane is in play
cd android && bundle exec fastlane init

### Useful skills right now
- /firecrawl-search — competitor research (D1-D2)
- /code-review — before every commit
- flutter-doctor — before any release build
```

---

## Existing files

If any target file already exists:
- print `WARNING: <file> already exists — skipping (delete it and re-run to overwrite)`
- continue with the remaining files
- the final summary lists created vs skipped

## Template reference

All templates live in `${CLAUDE_PLUGIN_ROOT}/templates/`, inside the plugin — no
separate install step.

If `${CLAUDE_PLUGIN_ROOT}` is empty or the templates are missing:

```
ERROR: the flu-harness plugin was not found.
   Install it first:
   /plugin marketplace add Jujubalandia/flu-harness
   /plugin install flu-harness@flu-harness
```
