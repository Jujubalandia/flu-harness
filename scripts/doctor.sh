#!/bin/sh
# flu-harness doctor — health checks for a Flutter project (POSIX sh).
#
# Runs on Git Bash on Windows, and on any Unix shell (Linux, macOS, WSL).
# The PowerShell twin (doctor.ps1) implements the identical check list;
# doctor.cmd delegates to it. tests/test.sh cross-checks that the three agree
# on the check count, so the list cannot silently drift.
#
# Usage:
#   doctor.sh [--json] [--quiet] [PROJECT_DIR]
#
# Exit: 0 = no FAIL (OK and WARN pass), 1 = at least one FAIL.

set -u

JSON_MODE=""
QUIET=""
PROJECT_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --json)  JSON_MODE=1; shift ;;
    --quiet) QUIET=1; shift ;;
    -h|--help)
      sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*) printf 'doctor.sh: unknown option: %s\n' "$1" >&2; exit 2 ;;
    *)  PROJECT_DIR="$1"; shift ;;
  esac
done

[ -z "$PROJECT_DIR" ] && PROJECT_DIR="."
[ -d "$PROJECT_DIR" ] || { printf 'doctor.sh: not a directory: %s\n' "$PROJECT_DIR" >&2; exit 2; }
PROJECT_DIR=$(CDPATH= cd -- "$PROJECT_DIR" && pwd)

TOTAL_CHECKS=26
OK=0; WARN=0; FAIL=0
RESULTS=""

# JSON-safe text: drop control chars and escape the two JSON metacharacters.
json_escape() {
  printf '%s' "$1" | tr -d '\r\n\t' | sed 's/\\/\\\\/g; s/"/\\"/g'
}

_out() {
  # _out LEVEL NUMBER MESSAGE [FIX]
  level="$1"; num="$2"; msg="$3"; fix="${4:-}"
  case "$level" in
    OK)   OK=$((OK + 1)) ;;
    WARN) WARN=$((WARN + 1)) ;;
    FAIL) FAIL=$((FAIL + 1)) ;;
  esac
  if [ -n "$JSON_MODE" ]; then
    RESULTS="${RESULTS}{\"n\":$num,\"level\":\"$level\",\"msg\":\"$(json_escape "$msg")\",\"fix\":\"$(json_escape "$fix")\"},"
  else
    [ -n "$QUIET" ] && [ "$level" != "FAIL" ] && return 0
    case "$level" in
      OK)   printf '  [OK]   %s\n' "$msg" ;;
      WARN) printf '  [WARN] %s\n' "$msg" ;;
      FAIL) printf '  [FAIL] %s\n         fix: %s\n' "$msg" "$fix" ;;
    esac
  fi
}

_section() { [ -z "$JSON_MODE" ] && [ -z "$QUIET" ] && printf '\n  -- %s --\n' "$1"; return 0; }

if [ -z "$JSON_MODE" ] && [ -z "$QUIET" ]; then
  printf '\nflu-harness doctor  (%d checks)\n' "$TOTAL_CHECKS"
  printf '========================================\n'
fi

# ── Environment ──────────────────────────────────────────────────────────────
_section "Environment"

FLUTTER=""
for c in flutter flutter.bat flutter.ps1; do
  if command -v "$c" >/dev/null 2>&1; then FLUTTER="$c"; break; fi
done

FLUTTER_VERSION=""
if [ -n "$FLUTTER" ]; then
  FLUTTER_VERSION=$("$FLUTTER" --version 2>/dev/null | head -n 1 | tr -d '\r')
  # "Flutter 3.41.6 • channel stable • https://..."
  FLUTTER_VER_NUM=$(printf '%s' "$FLUTTER_VERSION" | sed -n 's/.*Flutter[^0-9]*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')
  FLUTTER_CHANNEL=$(printf '%s' "$FLUTTER_VERSION" | sed -n 's/.*channel \([a-z]*\).*/\1/p')
  if [ -n "$FLUTTER_VER_NUM" ]; then
    _out OK 1 "flutter $FLUTTER_VER_NUM on PATH (channel: ${FLUTTER_CHANNEL:-unknown})"
  else
    _out WARN 1 "'$FLUTTER' found but did not report a version — the wrapper may be broken" \
      "Try: flutter --version — if it prints \"\$'\\r': command not found\", see check 26"
  fi
else
  _out FAIL 1 "flutter not found on PATH" \
    "Install the SDK: https://docs.flutter.dev/install — then reopen your shell"
fi

if [ -n "$FLUTTER_VER_NUM" ]; then
  MAJ=$(printf '%s' "$FLUTTER_VER_NUM" | cut -d. -f1)
  MIN=$(printf '%s' "$FLUTTER_VER_NUM" | cut -d. -f2)
  if [ "$MAJ" -gt 3 ] 2>/dev/null; then
    _out OK 2 "Flutter $FLUTTER_VER_NUM is newer than the 3.35 baseline"
  elif [ "$MAJ" -eq 3 ] 2>/dev/null && [ "$MIN" -ge 35 ] 2>/dev/null; then
    _out OK 2 "Flutter $FLUTTER_VER_NUM meets the 3.35 baseline"
  else
    _out WARN 2 "Flutter $FLUTTER_VER_NUM is older than the 3.35 baseline" \
      "flutter upgrade"
  fi
else
  _out WARN 2 "Flutter version undetermined" "flutter --version"
fi

DART=""
for c in dart dart.bat dart.ps1; do
  if command -v "$c" >/dev/null 2>&1; then DART="$c"; break; fi
done
if [ -n "$DART" ]; then
  DART_VERSION=$("$DART" --version 2>/dev/null | grep -i 'Dart SDK' | head -n 1 | tr -d '\r')
  [ -z "$DART_VERSION" ] && DART_VERSION=$("$DART" --version 2>&1 | head -n 1 | tr -d '\r')
  _out OK 3 "$DART_VERSION"
else
  _out FAIL 3 "dart not found on PATH (ships with the Flutter SDK)" \
    "Add <flutter-sdk>/bin to PATH"
fi

if command -v git >/dev/null 2>&1; then
  _out OK 4 "git $(git --version 2>/dev/null | tr -d '\r' | awk '{print $3}') installed"
else
  _out FAIL 4 "git not found" "https://git-scm.com/downloads"
fi

# Android toolchain: cheap probe of the usual install locations.
ANDROID_SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -z "$ANDROID_SDK" ]; then
  for c in "$HOME/AppData/Local/Android/Sdk" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk" "/usr/lib/android-sdk"; do
    [ -d "$c" ] && { ANDROID_SDK="$c"; break; }
  done
fi
if [ -n "$ANDROID_SDK" ] && [ -d "$ANDROID_SDK" ]; then
  _out OK 5 "Android SDK found: $ANDROID_SDK"
else
  _out WARN 5 "Android SDK not found in the usual locations" \
    "Install Android Studio, or set ANDROID_HOME — then run: flutter doctor"
fi

# Java is needed for Gradle. `java -version` writes to stderr on the JRE.
if command -v java >/dev/null 2>&1; then
  JAVA_VER=$(java -version 2>&1 | head -n 1 | tr -d '\r')
  _out OK 6 "java present: $JAVA_VER"
else
  _out WARN 6 "java/JDK not found — Gradle builds will fail" \
    "Install a JDK 17+ (Android Studio bundles one)"
fi

# ── Project structure ────────────────────────────────────────────────────────
_section "Project structure"

PUBSPEC="$PROJECT_DIR/pubspec.yaml"
if [ -f "$PUBSPEC" ]; then
  APP_NAME=$(sed -n 's/^name:[[:space:]]*//p' "$PUBSPEC" | head -n 1 | tr -d '\r')
  _out OK 7 "pubspec.yaml present (name: ${APP_NAME:-unknown})"
else
  _out FAIL 7 "pubspec.yaml not found — not a Flutter project root?" \
    "flutter create . — or cd into the directory that holds pubspec.yaml"
fi

if [ -f "$PROJECT_DIR/CLAUDE.md" ]; then
  _out OK 8 "CLAUDE.md present"
else
  _out WARN 8 "CLAUDE.md missing (flu-harness not initialized)" \
    "Run /flu-harness:new-flutter-project in Claude Code"
fi

if [ -d "$PROJECT_DIR/.claude/rules" ]; then
  RULE_COUNT=$(find "$PROJECT_DIR/.claude/rules" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  if [ "${RULE_COUNT:-0}" -gt 0 ]; then
    _out OK 9 ".claude/rules/ present ($RULE_COUNT rules)"
  else
    _out WARN 9 ".claude/rules/ is empty" "Re-run /flu-harness:new-flutter-project"
  fi
else
  _out WARN 9 ".claude/rules/ missing (knowledge rules not installed)" \
    "Re-run /flu-harness:new-flutter-project"
fi

if [ -d "$PROJECT_DIR/lib" ]; then
  DART_FILES=$(find "$PROJECT_DIR/lib" -name '*.dart' 2>/dev/null | wc -l | tr -d ' ')
  _out OK 10 "lib/ present ($DART_FILES .dart files)"
else
  _out FAIL 10 "lib/ missing" "flutter create . to scaffold the app"
fi

if [ -d "$PROJECT_DIR/test" ] || [ -d "$PROJECT_DIR/integration_test" ]; then
  TEST_FILES=$(find "$PROJECT_DIR/test" "$PROJECT_DIR/integration_test" -name '*_test.dart' 2>/dev/null | wc -l | tr -d ' ')
  if [ "${TEST_FILES:-0}" -gt 0 ]; then
    _out OK 11 "test suite present ($TEST_FILES _test.dart files)"
  else
    _out WARN 11 "test/ exists but holds no *_test.dart" \
      "Add a widget test — the pre-push gate runs: flutter test"
  fi
else
  _out WARN 11 "no test/ directory" "flutter test needs one; add test/widget_test.dart"
fi

if [ -f "$PROJECT_DIR/analysis_options.yaml" ]; then
  if grep -qE 'flutter_lints|very_good_analysis|lints:' "$PROJECT_DIR/analysis_options.yaml" 2>/dev/null; then
    _out OK 12 "analysis_options.yaml includes a lint rule set"
  else
    _out WARN 12 "analysis_options.yaml has no lint rule set include" \
      "Add: include: package:flutter_lints/flutter.yaml"
  fi
else
  _out FAIL 12 "analysis_options.yaml missing — analyzer runs with defaults only" \
    "Create it with: include: package:flutter_lints/flutter.yaml"
fi

# ── Dependencies & config ────────────────────────────────────────────────────
_section "Dependencies & config"

if [ -f "$PUBSPEC" ]; then
  if grep -qE '^environment:' "$PUBSPEC" 2>/dev/null && grep -qE '^[[:space:]]+sdk:' "$PUBSPEC" 2>/dev/null; then
    SDK_CONSTRAINT=$(sed -n 's/^[[:space:]]*sdk:[[:space:]]*//p' "$PUBSPEC" | head -n 1 | tr -d '\r')
    _out OK 13 "pubspec.yaml pins an SDK constraint ($SDK_CONSTRAINT)"
  else
    _out FAIL 13 "pubspec.yaml has no environment.sdk constraint" \
      "Add: environment: { sdk: ^3.11.0 } (match your Dart version)"
  fi
else
  _out WARN 13 "SDK constraint not checkable (no pubspec.yaml)" ""
fi

if [ -f "$PROJECT_DIR/pubspec.lock" ]; then
  _out OK 14 "pubspec.lock present — builds are reproducible"
else
  _out WARN 14 "pubspec.lock missing" "flutter pub get, then commit pubspec.lock"
fi

# Packages that are discontinued or superseded. Each entry is "package|reason".
DISCONTINUED="dart_code_metrics|discontinued — migrate to dart_code_linter
flutter_appauth_web|discontinued
flutter_tindercard|unmaintained since 2020
hive|superseded by hive_ce (community edition, still maintained)
flutter_launcher_icons_plus|unmaintained fork
path_provider_ios|merged into path_provider"
if [ -f "$PUBSPEC" ]; then
  HITS=""
  OLD_IFS="$IFS"; IFS='
'
  for entry in $DISCONTINUED; do
    pkg=${entry%%|*}
    why=${entry#*|}
    if grep -qE "^[[:space:]]+$pkg:" "$PUBSPEC" 2>/dev/null; then
      HITS="${HITS}${pkg} (${why}); "
    fi
  done
  IFS="$OLD_IFS"
  if [ -n "$HITS" ]; then
    _out FAIL 15 "discontinued/superseded packages in pubspec: $HITS" \
      "flutter pub remove <package> and pick the maintained alternative"
  else
    _out OK 15 "no discontinued packages in direct dependencies"
  fi
else
  _out WARN 15 "dependency health not checkable (no pubspec.yaml)" ""
fi

if [ -f "$PROJECT_DIR/l10n.yaml" ]; then
  _out OK 16 "l10n.yaml present (gen-l10n configured)"
else
  if [ -d "$PROJECT_DIR/lib/l10n" ] || [ -f "$PROJECT_DIR/lib/l10n/app_en.arb" ]; then
    _out WARN 16 "ARB files exist but l10n.yaml is missing" \
      "Add l10n.yaml with: arb-dir: lib/l10n, template-arb-file: app_en.arb"
  else
    _out WARN 16 "no l10n.yaml — no localization pipeline configured" \
      "Add flutter_localizations + intl and an l10n.yaml (see .claude/rules/i18n.md)"
  fi
fi

# Android applicationId / iOS bundle identifier.
ANDROID_ID=""
for f in "$PROJECT_DIR/android/app/build.gradle" "$PROJECT_DIR/android/app/build.gradle.kts"; do
  [ -f "$f" ] && ANDROID_ID=$(sed -n 's/.*applicationId[[:space:]]*[= ][[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -n 1 | tr -d '\r')
done
IOS_ID=""
if [ -f "$PROJECT_DIR/ios/Runner.xcodeproj/project.pbxproj" ]; then
  IOS_ID=$(sed -n 's/.*PRODUCT_BUNDLE_IDENTIFIER = \([^;]*\);.*/\1/p' "$PROJECT_DIR/ios/Runner.xcodeproj/project.pbxproj" | head -n 1 | tr -d '\r')
fi
if [ -n "$ANDROID_ID" ] && [ -n "$IOS_ID" ]; then
  _out OK 17 "store identifiers set (android: $ANDROID_ID, ios: $IOS_ID)"
elif [ -n "$ANDROID_ID" ]; then
  _out WARN 17 "android applicationId set ($ANDROID_ID) but iOS bundle id not found" \
    "Set PRODUCT_BUNDLE_IDENTIFIER in ios/Runner.xcodeproj — required for App Store"
else
  _out WARN 17 "android applicationId not set (still com.example.*?)" \
    "Set applicationId in android/app/build.gradle — it must be unique and permanent"
fi

# ── Security & git hygiene ───────────────────────────────────────────────────
_section "Security & git hygiene"

if [ -d "$PROJECT_DIR/.git" ]; then
  _out OK 18 "git repository initialized"
else
  _out FAIL 18 "no .git/ directory" "git init && git add . && git commit -m 'chore: init'"
fi

GI="$PROJECT_DIR/.gitignore"
if [ -f "$GI" ]; then
  MISSING=""
  for pat in '.dart_tool' 'build/' '.env' 'key.properties' '*.keystore' '*.jks' 'google-services.json' 'GoogleService-Info.plist'; do
    grep -qF "$pat" "$GI" 2>/dev/null || MISSING="$MISSING $pat"
  done
  if [ -z "$MISSING" ]; then
    _out OK 19 ".gitignore covers Flutter + secret paths"
  else
    _out FAIL 19 ".gitignore does not cover:$MISSING" \
      "Append the missing patterns — *.keystore and key.properties leaking is a release-key compromise"
  fi
else
  _out FAIL 19 ".gitignore missing" "flutter create generates one; restore it"
fi

# Anything secret already in the index?
if [ -d "$PROJECT_DIR/.git" ]; then
  LEAKED=$(git -C "$PROJECT_DIR" ls-files 2>/dev/null \
    | grep -E '(^|/)\.env|key\.properties$|\.keystore$|\.jks$|google-services\.json$|GoogleService-Info\.plist$' \
    | head -n 3)
  if [ -z "$LEAKED" ]; then
    _out OK 20 "no secrets tracked by git"
  else
    _out FAIL 20 "secret files tracked by git: $(printf '%s' "$LEAKED" | tr '\n' ' ')" \
      "git rm --cached <file>, add it to .gitignore, and rotate the credential"
  fi
else
  _out WARN 20 "git index not readable (no .git/)" "git init"
fi

# Hardcoded credentials in Dart source.
if [ -d "$PROJECT_DIR/lib" ]; then
  HARD=$(find "$PROJECT_DIR/lib" -name '*.dart' 2>/dev/null | head -n 400 \
    | xargs grep -lnE "(apiKey|api_key|secret|clientSecret|password)[[:space:]]*[:=][[:space:]]*['\"][A-Za-z0-9_\-]{12,}" 2>/dev/null \
    | head -n 3)
  if [ -z "$HARD" ]; then
    _out OK 21 "no hardcoded credentials found in lib/"
  else
    _out FAIL 21 "possible hardcoded credential in: $(printf '%s' "$HARD" | tr '\n' ' ')" \
      "Move to --dart-define / --dart-define-from-file, or a secret manager. Never commit keys."
  fi
else
  _out WARN 21 "lib/ scan skipped" ""
fi

# ── Quality gates & hooks ────────────────────────────────────────────────────
_section "Quality gates & hooks"

if [ -d "$PROJECT_DIR/.githooks" ]; then
  HOOKS_PATH=$(git -C "$PROJECT_DIR" config core.hooksPath 2>/dev/null | tr -d '\r' || echo "")
  if [ "$HOOKS_PATH" = ".githooks" ]; then
    _out OK 22 "git core.hooksPath = .githooks"
  elif [ -n "$HOOKS_PATH" ]; then
    _out WARN 22 "core.hooksPath is '$HOOKS_PATH', expected .githooks" "git config core.hooksPath .githooks"
  else
    _out FAIL 22 ".githooks/ exists but core.hooksPath is unset — hooks never run" \
      "git config core.hooksPath .githooks"
  fi
else
  _out FAIL 22 ".githooks/ missing — no quality gates installed" "Re-run /flu-harness:new-flutter-project"
  HOOKS_PATH=""
fi

# The Windows check that matters most.
if [ -f "$PROJECT_DIR/.githooks/pre-commit" ]; then
  CR_HOOKS=""
  for f in "$PROJECT_DIR"/.githooks/pre-commit "$PROJECT_DIR"/.githooks/pre-push; do
    [ -f "$f" ] || continue
    # A CR in the first line breaks the shebang: git reports "cannot exec /bin/sh^M".
    FIRST=$(head -c 200 "$f" 2>/dev/null | head -n 1)
    case "$FIRST" in
      *"$(printf '\r')"*) CR_HOOKS="$CR_HOOKS $(basename "$f")" ;;
    esac
  done
  if [ -n "$CR_HOOKS" ]; then
    _out FAIL 23 "CRLF line endings in hook script(s):$CR_HOOKS — git will refuse to run them" \
      "sed -i 's/\\r\$//' .githooks/<file> ; and add '* text eol=lf' + '.githooks/* text eol=lf' to .gitattributes"
  else
    _out OK 23 "hook scripts use LF line endings (git-executable on Windows)"
  fi
else
  _out FAIL 23 ".githooks/pre-commit missing" "Re-run /flu-harness:new-flutter-project"
fi

if [ -f "$PROJECT_DIR/.githooks/lib/quality.sh" ] || [ -f "$PROJECT_DIR/.githooks/lib/quality.ps1" ]; then
  LIB_OK=1
  for f in quality.sh quality.ps1 quality.cmd gates.def; do
    [ -f "$PROJECT_DIR/.githooks/lib/$f" ] || LIB_OK=0
  done
  if [ "$LIB_OK" -eq 1 ]; then
    _out OK 24 "gate library complete (quality.sh/.ps1/.cmd + gates.def)"
  else
    _out WARN 24 "gate library incomplete in .githooks/lib/ — some shells cannot run the gates" \
      "Re-run /flu-harness:new-flutter-project to restore all three shells"
  fi
else
  _out FAIL 24 ".githooks/lib/ gate library missing" "Re-run /flu-harness:new-flutter-project"
fi

if [ -f "$PROJECT_DIR/.gitattributes" ]; then
  if grep -qE '^\*?[[:space:]]*text[[:space:]]*=[[:space:]]*auto[[:space:]]+eol[[:space:]]*=[[:space:]]*lf|\.githooks/\*' "$PROJECT_DIR/.gitattributes" 2>/dev/null; then
    _out OK 25 ".gitattributes pins LF for hooks"
  else
    _out WARN 25 ".gitattributes exists but does not pin LF for .githooks/" \
      "Add: * text=auto eol=lf  and  .githooks/* text eol=lf"
  fi
else
  _out WARN 25 ".gitattributes missing — a Windows clone may convert hooks to CRLF" \
    "Add .gitattributes with '* text=auto eol=lf'"
fi

# ── Windows shell health ─────────────────────────────────────────────────────

# MSYS bash, as used by Git for Windows. It runs the Flutter SDK's bash wrapper
# happily even when that wrapper's shared.sh carries CRLF, which matters for the
# check below and was verified by running both.
is_msys_shell() {
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
  esac
  return 1
}
_section "Windows shell health"

if [ -n "$FLUTTER" ]; then
  case "$FLUTTER" in
    *.bat|*.ps1)
      _out OK 26 "flutter resolves to $FLUTTER (the Windows entry point)"
      ;;
    *)
      FP=$(command -v "$FLUTTER" 2>/dev/null)
      FD=$(dirname "$FP" 2>/dev/null)
      SHARED_CR=0
      if [ -f "$FD/internal/shared.sh" ]; then
        n=$(tr -dc '\r' < "$FD/internal/shared.sh" 2>/dev/null | wc -c | tr -d ' ')
        [ "${n:-0}" != "0" ] && SHARED_CR=1
      fi

      # Whether a CRLF shared.sh matters depends on which sh you are, and this
      # was measured rather than assumed:
      #   Git for Windows (MSYS/MinGW) runs the SDK's bash wrapper fine.
      #   WSL / Linux bash dies with "$'\r': command not found" on line 5.
      # Reporting a FAIL under Git Bash would be a false alarm in the shell most
      # Windows users are actually in, so the check is scoped to where it is true.
      if is_msys_shell; then
        if [ "$SHARED_CR" -eq 1 ]; then
          _out OK 26 "flutter sh wrapper works under Git for Windows (SDK ships CRLF in shared.sh, which MSYS tolerates)"
        else
          _out OK 26 "flutter sh wrapper is intact and runs under Git for Windows"
        fi
      elif [ "$SHARED_CR" -eq 1 ]; then
        _out FAIL 26 "this POSIX shell cannot run the Flutter bash wrapper: bin/internal/shared.sh has CRLF" \
          "Repair the SDK: find \"$FD\" -name '*.sh' -exec sed -i 's/\\r\$//' {} +  -- or run the gates from PowerShell or cmd, which use flutter.bat"
      else
        _out OK 26 "flutter sh wrapper is intact (no CR in internal/shared.sh)"
      fi
      ;;
  esac
else
  _out FAIL 26 "shell health not checkable — flutter not on PATH" "Install the Flutter SDK"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
TOTAL=$((OK + WARN + FAIL))

if [ -n "$JSON_MODE" ]; then
  RESULTS="${RESULTS%,}"
  printf '{"ok":%d,"warn":%d,"fail":%d,"total":%d,"expected":%d,"results":[%s]}\n' \
    "$OK" "$WARN" "$FAIL" "$TOTAL" "$TOTAL_CHECKS" "$RESULTS"
else
  printf '\n  ----------------------------------------\n'
  printf '  OK: %d  WARN: %d  FAIL: %d  / %d total\n' "$OK" "$WARN" "$FAIL" "$TOTAL"
  printf '  ----------------------------------------\n\n'
fi

[ "$FAIL" -eq 0 ]
