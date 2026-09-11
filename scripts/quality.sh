#!/bin/sh
# flu-harness — quality gate runner (POSIX sh)
#
# Runs the gate plan for a profile. Every gate is a plain Flutter/Dart CLI
# call, so this file has no dependencies beyond the Flutter SDK and git.
#
# This is one of three implementations of the same contract:
#   quality.sh    POSIX sh   — Git Bash on Windows, and any Unix shell
#   quality.ps1   PowerShell — Windows PowerShell 5.1+ and PowerShell 7+
#   quality.cmd   CMD        — cmd.exe on Windows
# All three read the same gates.def, so the plan cannot drift between shells.
#
# Usage:
#   quality.sh [--stage pre-commit|pre-push] [--profile NAME] [--def FILE]
#              [--dry-run] [--quiet] [PROJECT_DIR]
#
# Env:
#   HARNESS_PROFILE     default profile when --profile is omitted
#   HARNESS_SKIP_BUILD  =1 to skip the `build` gate and print a loud warning
#   HARNESS_DEVICE_OK   =1 to answer "yes" to the pre-push device prompt
#
# Exit: 0 = every gate passed (or was skipped), 1 = at least one gate failed.

set -u

# ── Locate ourselves without bash-isms ───────────────────────────────────────
SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

STAGE=""
PROFILE="${HARNESS_PROFILE:-}"
DEF_FILE=""
DRY_RUN=""
QUIET=""
PROJECT_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --stage)   STAGE="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --def)     DEF_FILE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --quiet)   QUIET=1; shift ;;
    -h|--help)
      sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*) printf 'quality.sh: unknown option: %s\n' "$1" >&2; exit 2 ;;
    *)  PROJECT_DIR="$1"; shift ;;
  esac
done

# ── Project root ─────────────────────────────────────────────────────────────
if [ -z "$PROJECT_DIR" ]; then
  if PROJECT_DIR=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$PROJECT_DIR" ]; then
    :
  else
    # lib/ -> .githooks/ -> project root
    PROJECT_DIR=$(CDPATH= cd -- "$SELF_DIR/../.." && pwd)
  fi
fi

# ── Resolve the gate plan ────────────────────────────────────────────────────
if [ -z "$DEF_FILE" ]; then
  for candidate in \
    "$PROJECT_DIR/.githooks/lib/gates.def" \
    "$PROJECT_DIR/.githooks/gates.def" \
    "$SELF_DIR/gates.def" \
    "$SELF_DIR/../git-hooks/profiles/$PROFILE/gates.def"
  do
    [ -f "$candidate" ] && { DEF_FILE="$candidate"; break; }
  done
fi

if [ -z "$DEF_FILE" ] || [ ! -f "$DEF_FILE" ]; then
  # Last resort: derive from the plugin layout (scripts/ sits next to git-hooks/).
  if [ -n "$PROFILE" ] && [ -f "$SELF_DIR/../git-hooks/profiles/$PROFILE/gates.def" ]; then
    DEF_FILE="$SELF_DIR/../git-hooks/profiles/$PROFILE/gates.def"
  fi
fi

if [ -z "$PROFILE" ]; then
  # gates.def lives at <profile>/gates.def or .githooks/lib/gates.def; in the
  # latter case the profile is written to .githooks/.profile by the wizard.
  if [ -f "$PROJECT_DIR/.githooks/.profile" ]; then
    PROFILE=$(tr -d ' \t\r\n' < "$PROJECT_DIR/.githooks/.profile")
  fi
  [ -z "$PROFILE" ] && PROFILE=strict
fi

if [ -z "$DEF_FILE" ] || [ ! -f "$DEF_FILE" ]; then
  printf '[FAIL] no gates.def found for profile "%s"\n' "$PROFILE" >&2
  printf '       looked in %s/.githooks/lib/ and %s\n' "$PROJECT_DIR" "$SELF_DIR" >&2
  exit 1
fi

if [ -z "$STAGE" ]; then
  STAGE=pre-commit
fi

# ── Read the gate list for this stage ────────────────────────────────────────
GATES=""
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    ''|\#*) continue ;;
  esac
  line=$(printf '%s' "$line" | tr -d '\r')
  key=${line%%=*}
  val=${line#*=}
  # trim
  key=$(printf '%s' "$key" | tr -d ' \t')
  if [ "$key" = "$STAGE" ]; then
    GATES=$(printf '%s' "$val" | tr ',' ' ')
    break
  fi
done < "$DEF_FILE"

if [ -z "$GATES" ]; then
  printf '[WARN] profile "%s" defines no gates for stage "%s" — nothing to do\n' "$PROFILE" "$STAGE"
  exit 0
fi

# ── Output helpers (ASCII only: survives cmd.exe codepages) ──────────────────
say()  { [ -n "$QUIET" ] || printf '%s\n' "$*"; }
step() { [ -n "$QUIET" ] || printf '\n-> %s\n' "$*"; }

# ── Tool discovery ───────────────────────────────────────────────────────────
#
# Not as trivial as `command -v flutter`, for a reason worth spelling out.
#
#   The Flutter Windows distribution ships bin/flutter (a bash wrapper) AND
#   bin/flutter.bat. The wrapper sources bin/internal/shared.sh, which in the
#   Windows distribution carries CRLF line endings (283 CR bytes in 3.41.6).
#
#   Whether that matters depends entirely on which sh you are:
#
#     Git for Windows (MSYS/MinGW)  -> fine. MSYS bash tolerates the CR. The
#                                      wrapper runs, so use it.
#     WSL or Linux bash             -> broken. Bash 5 on Linux hits
#                                      "internal/shared.sh: line 5: $'\r': command not found"
#                                      and the wrapper dies before doing anything.
#
#   Verified by running both, not by reading documentation. A blanket "CRLF
#   means broken" check is a false alarm on Git Bash, which is the shell most
#   Windows users of this harness are in, so the check is scoped to the shells
#   where it is actually true.
#
# Set HARNESS_FLUTTER / HARNESS_DART to point at a specific binary.

is_windows_shell() {
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*|Windows_NT) return 0 ;;
  esac
  return 1
}

# MSYS bash, as used by Git for Windows. It runs the SDK's bash wrapper happily.
is_msys_shell() {
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
  esac
  return 1
}

# Does this script carry CRLF? (POSIX tr, not the $'\r' bashism.)
has_crlf() {
  f="$1"
  [ -f "$f" ] || return 1
  case "$f" in
    *.sh|*.bash)
      # A shell script is text: a stray CR anywhere breaks execution.
      n=$(tr -dc '\r' < "$f" 2>/dev/null | wc -c | tr -d ' ')
      [ "${n:-0}" != "0" ] && return 0
      return 1
      ;;
    *)
      # Extensionless wrappers are only broken by a CR in the shebang, which is
      # the line the kernel reads.
      first=$(head -c 200 "$f" 2>/dev/null | head -n 1)
      case "$first" in
        *"$(printf '\r')"*) return 0 ;;
      esac
      return 1
      ;;
  esac
}

pick_tool() {
  # pick_tool <env-override> <preferred...>
  override="$1"; shift
  if [ -n "$override" ]; then printf '%s\n' "$override"; return 0; fi

  first=""
  for c in "$@"; do
    if command -v "$c" >/dev/null 2>&1; then
      [ -z "$first" ] && first="$c"
    fi
  done
  printf '%s\n' "$first"
}

if is_windows_shell; then
  # Under MSYS the bash wrapper is the entry point that works, and `command -v`
  # will not find flutter.bat anyway (MSYS does not apply PATHEXT here) even
  # though the file sits right next to it. So prefer the wrapper, as verified.
  FLUTTER=$(pick_tool "${HARNESS_FLUTTER:-}" flutter flutter.bat)
  DART=$(pick_tool "${HARNESS_DART:-}" dart dart.bat)
else
  FLUTTER=$(pick_tool "${HARNESS_FLUTTER:-}" flutter flutter.bat)
  DART=$(pick_tool "${HARNESS_DART:-}" dart dart.bat)
fi

# The one case that genuinely cannot work: a POSIX shell (WSL, Linux, macOS)
# driving a Windows SDK whose bash wrapper is CRLF-corrupted. There is no .bat
# fallback available from there, because a Linux shell cannot execute .bat.
if ! is_msys_shell; then
  if [ -n "$FLUTTER" ]; then
    fp=$(command -v "$FLUTTER" 2>/dev/null)
    fd=$(dirname "$fp" 2>/dev/null)
    if has_crlf "$fd/internal/shared.sh" || has_crlf "$fp"; then
      say "   [WARN] The Flutter SDK at $fd has CRLF line endings in"
      say "          bin/internal/shared.sh, so its bash wrapper cannot run here."
      say "          This shell is POSIX (WSL/Linux/macOS), not Git Bash/MSYS."
      say ""
      say "          Either repair the SDK, once:"
      say "            find \"$fd\" -name '*.sh' -exec sed -i 's/\\r\$//' {} +"
      say "          or run the gates from PowerShell or cmd, which use flutter.bat:"
      say "            .githooks\\pre-commit.cmd"
    fi
  fi
fi

# Analytics off: keeps gate output stable and stops the SDK writing session
# files into a read-only HOME during CI or sandboxed runs.
FLUTTER_OPTS="--suppress-analytics"
DART_OPTS="--suppress-analytics"

# ── Gate implementations ─────────────────────────────────────────────────────
FAILED=0
RAN=0
SKIPPED=0

have_pubspec() { [ -f "$PROJECT_DIR/pubspec.yaml" ]; }

run_gate() {
  gate="$1"
  RAN=$((RAN + 1))

  case "$gate" in
    format)
      step "format — dart format --set-exit-if-changed"
      if [ -z "$DART" ]; then
        say "   [SKIP] dart not found on PATH"
        SKIPPED=$((SKIPPED + 1)); return 0
      fi
      ( cd "$PROJECT_DIR" && "$DART" $DART_OPTS format --output=none --set-exit-if-changed . )
      rc=$?
      if [ "$rc" -eq 0 ]; then
        say "   [OK] formatting clean"
      else
        say "   [FAIL] formatting differs — run: dart format ."
        FAILED=1
      fi
      return $rc
      ;;

    analyze)
      step "analyze — flutter analyze --fatal-infos --fatal-warnings"
      if [ -z "$FLUTTER" ]; then
        say "   [SKIP] flutter not found on PATH"
        SKIPPED=$((SKIPPED + 1)); return 0
      fi
      ( cd "$PROJECT_DIR" && "$FLUTTER" $FLUTTER_OPTS analyze --fatal-infos --fatal-warnings )
      rc=$?
      if [ "$rc" -eq 0 ]; then
        say "   [OK] no analyzer issues"
      else
        say "   [FAIL] analyzer reported issues"
        FAILED=1
      fi
      return $rc
      ;;

    lint)
      step "lint — project-configured linter"
      AO="$PROJECT_DIR/analysis_options.yaml"
      if [ ! -f "$AO" ]; then
        say "   [SKIP] no analysis_options.yaml"
        SKIPPED=$((SKIPPED + 1)); return 0
      fi
      if [ -z "$DART" ]; then
        say "   [SKIP] dart not found on PATH"
        SKIPPED=$((SKIPPED + 1)); return 0
      fi

      # dart_code_linter is checked first: it is the maintained successor to the
      # discontinued dart_code_metrics, and it is where complexity and
      # maintainability thresholds live. Note that it exits 0 even when it finds
      # violations unless --set-exit-on-violation-level is passed, so the flag is
      # doing the work here - without it this gate would always pass.
      if grep -qE '^[[:space:]]*dart_code_linter:' "$AO" 2>/dev/null; then
        ( cd "$PROJECT_DIR" && "$DART" $DART_OPTS run dart_code_linter:metrics analyze lib \
            --set-exit-on-violation-level=warning --no-congratulate )
        rc=$?
        if [ "$rc" -eq 0 ]; then
          say "   [OK] metrics and anti-patterns clean"
        else
          say "   [FAIL] dart_code_linter reported violations (exit $rc)"
          say "          Refactor the flagged code. Never raise the threshold to pass."
          FAILED=1
        fi
        return $rc
      fi

      if grep -qE '^[[:space:]]*custom_lint:' "$AO" 2>/dev/null \
         || grep -qE '^[[:space:]]*plugins:' "$AO" 2>/dev/null; then
        say "   [WARN] custom_lint / analyzer-plugin rules configured."
        say "          custom_lint is no longer developed, and analyzer plugins need"
        say "          Dart 3.10+, so this gate may be a no-op on your SDK."
        ( cd "$PROJECT_DIR" && "$DART" $DART_OPTS run custom_lint )
        rc=$?
        if [ "$rc" -eq 0 ]; then
          say "   [OK] custom lint clean"
        else
          say "   [FAIL] custom lint reported issues"
          FAILED=1
        fi
        return $rc
      fi

      say "   [SKIP] no dart_code_linter / custom_lint configured"
      say "          To enable complexity gating, add to analysis_options.yaml:"
      say "            dart_code_linter:"
      say "              metrics:"
      say "                cyclomatic-complexity: 20"
      say "                maintainability-index: 50"
      SKIPPED=$((SKIPPED + 1))
      return 0
      ;;

    test)
      step "test — flutter test"
      if [ -z "$FLUTTER" ]; then
        say "   [SKIP] flutter not found on PATH"
        SKIPPED=$((SKIPPED + 1)); return 0
      fi
      if [ ! -d "$PROJECT_DIR/test" ] && [ ! -d "$PROJECT_DIR/integration_test" ]; then
        say "   [SKIP] no test/ directory yet"
        SKIPPED=$((SKIPPED + 1)); return 0
      fi
      ( cd "$PROJECT_DIR" && "$FLUTTER" $FLUTTER_OPTS test )
      rc=$?
      if [ "$rc" -eq 0 ]; then
        say "   [OK] tests passed"
      else
        say "   [FAIL] tests failed"
        FAILED=1
      fi
      return $rc
      ;;

    build)
      step "build — flutter build apk --debug (compile sanity)"
      if [ "${HARNESS_SKIP_BUILD:-}" = "1" ]; then
        say "   [SKIP] HARNESS_SKIP_BUILD=1 — the strongest gate is OFF"
        say "          set it back to 0 before you trust a release build"
        SKIPPED=$((SKIPPED + 1)); return 0
      fi
      if [ -z "$FLUTTER" ]; then
        say "   [SKIP] flutter not found on PATH"
        SKIPPED=$((SKIPPED + 1)); return 0
      fi
      ( cd "$PROJECT_DIR" && "$FLUTTER" $FLUTTER_OPTS build apk --debug )
      rc=$?
      if [ "$rc" -eq 0 ]; then
        say "   [OK] debug APK built"
      else
        say "   [FAIL] build failed (missing Android toolchain? see: flutter doctor)"
        FAILED=1
      fi
      return $rc
      ;;

    *)
      say "   [WARN] unknown gate \"$gate\" in $DEF_FILE — ignored"
      return 0
      ;;
  esac
}

# ── Dry run: print the plan and stop ─────────────────────────────────────────
if [ -n "$DRY_RUN" ]; then
  printf 'profile=%s\n' "$PROFILE"
  printf 'stage=%s\n'   "$STAGE"
  printf 'def=%s\n'     "$DEF_FILE"
  for g in $GATES; do printf 'gate=%s\n' "$g"; done
  exit 0
fi

say ""
say "flu-harness quality — profile: $PROFILE · stage: $STAGE"
say "────────────────────────────────────────"

if ! have_pubspec; then
  say "[FAIL] no pubspec.yaml in $PROJECT_DIR — not a Flutter project root?"
  exit 1
fi

for g in $GATES; do
  run_gate "$g" || true
done

# ── Pre-push: physical device confirmation ───────────────────────────────────
if [ "$STAGE" = "pre-push" ]; then
  ans="${HARNESS_DEVICE_OK:-}"
  if [ -z "$ans" ]; then
    if [ -r /dev/tty ] && [ -t 1 ]; then
      printf '\nRan the app on a real Android device? [y/N] '
      read -r ans < /dev/tty || ans=""
    elif [ -t 0 ]; then
      printf '\nRan the app on a real Android device? [y/N] '
      read -r ans || ans=""
    else
      # No terminal (IDE git panel, CI). Do not silently block a push the user
      # cannot answer — but make the bypass loud.
      say ""
      say "[WARN] no terminal to ask about physical-device testing."
      say "       Set HARNESS_DEVICE_OK=1 to pre-answer, or run the push from a shell."
      ans="y"
    fi
  fi
  case "$ans" in
    y|Y|yes|YES|1) say "   [OK] device check acknowledged" ;;
    *) say "   [FAIL] run it on a physical Android device before pushing."
       say "          (or set HARNESS_DEVICE_OK=1 once you actually have)"
       FAILED=1 ;;
  esac
fi

# ── Summary ──────────────────────────────────────────────────────────────────
say ""
say "────────────────────────────────────────"
if [ "$FAILED" -eq 0 ]; then
  say "OK — $RAN gates, $SKIPPED skipped"
  say "────────────────────────────────────────"
  exit 0
fi
say "FAIL — gates above must pass"
say "────────────────────────────────────────"
exit 1
