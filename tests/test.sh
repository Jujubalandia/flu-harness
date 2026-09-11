#!/usr/bin/env bash
# tests/test.sh — flu-harness test suite (POSIX-ish bash, no external deps)
#
#   bash tests/test.sh
#
# Covers:
#   1. Repo structure and plugin manifests
#   2. Placeholder hygiene (CLAUDE.md.tmpl, stubs)
#   3. Shell syntax for every script this repo ships
#   4. Gate plans — the sh runner against the expected plan per profile
#   5. Cross-shell plan parity (skipped unless PowerShell + cmd are reachable)
#   6. The destructive-operation guard — block list and allow list
#   7. flutter-doctor — check count, JSON validity, exit codes
#   8. Line-ending policy — hooks must be LF
#   9. Skill files reference the plugin root, not hardcoded paths
#  10. Installer
#
# Exits non-zero if any assertion fails.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
SKIP=0
ERRORS=()

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; BOLD='\033[1m'; NC='\033[0m'

pass()    { printf '  %sOK%s   %s\n'   "$GREEN" "$NC" "$1"; PASS=$((PASS + 1)); }
fail()    { printf '  %sFAIL%s %s\n'   "$RED"   "$NC" "$1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }
skip()    { printf '  %sSKIP%s %s\n'   "$YELLOW" "$NC" "$1"; SKIP=$((SKIP + 1)); }
section() { printf '\n%s%s%s\n' "$BOLD" "$1" "$NC"; }

assert_file()  { [ -f "$1" ] && pass "${2:-$1 exists}" || fail "${2:-$1} — MISSING"; }
assert_dir()   { [ -d "$1" ] && pass "${2:-$1 exists}" || fail "${2:-$1} — MISSING"; }
assert_has()   { grep -q -- "$2" "$1" 2>/dev/null && pass "${3:-$1 contains '$2'}" || fail "${3:-$1} does NOT contain '$2'"; }
assert_lacks() { ! grep -q -- "$2" "$1" 2>/dev/null && pass "${3:-$1 lacks '$2'}" || fail "${3:-$1} unexpectedly contains '$2'"; }
assert_ok()    { "$@" >/dev/null 2>&1 && pass "$LABEL" || fail "$LABEL"; }

# run and check exit code
assert_exit() {
  # assert_exit EXPECTED LABEL cmd...
  local expected="$1" label="$2"; shift 2
  local actual=0
  "$@" >/dev/null 2>&1 || actual=$?
  [ "$actual" -eq "$expected" ] \
    && pass "$label (exit $expected)" \
    || fail "$label — expected exit $expected, got $actual"
}

TMPBASE="$(mktemp -d)"
# Fixtures that get handed to a Windows binary must live somewhere Windows can
# see: /tmp under WSL is invisible to powershell.exe and cmd.exe.
WINBASE="$REPO_DIR/.tmp-test"
cleanup() { rm -rf "$TMPBASE" "$WINBASE"; }
trap cleanup EXIT
mkdir -p "$WINBASE"

# Translate a POSIX path for a Windows binary. cygpath on Git Bash, wslpath on
# WSL, identity everywhere else (where a native pwsh takes POSIX paths anyway).
win_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"
  elif command -v wslpath >/dev/null 2>&1; then wslpath -w "$1"
  else printf '%s' "$1"; fi
}

# Cross-shell tooling (present on Windows, usually absent on Linux CI)
PWSH=""
for c in pwsh powershell powershell.exe; do
  command -v "$c" >/dev/null 2>&1 && { PWSH="$c"; break; }
done
CMD=""
command -v cmd.exe >/dev/null 2>&1 && CMD="cmd.exe"

# ═══════════════════════════════════════════════════════════════════════════
section "1. Repo structure"
# ═══════════════════════════════════════════════════════════════════════════

assert_file "$REPO_DIR/.claude-plugin/plugin.json"      "plugin.json exists"
assert_file "$REPO_DIR/.claude-plugin/marketplace.json" "marketplace.json exists"
assert_file "$REPO_DIR/README.md"                       "README.md exists"
assert_file "$REPO_DIR/README.pt-BR.md"                 "README.pt-BR.md exists"
assert_file "$REPO_DIR/.gitattributes"                  ".gitattributes exists"
assert_file "$REPO_DIR/docs/WINDOWS.md"                 "docs/WINDOWS.md exists"

assert_dir "$REPO_DIR/skills/new-flutter-project" "new-flutter-project skill dir"
assert_dir "$REPO_DIR/skills/flutter-doctor"      "flutter-doctor skill dir"
assert_file "$REPO_DIR/skills/new-flutter-project/SKILL.md"
assert_file "$REPO_DIR/skills/flutter-doctor/SKILL.md"

# The three-shell contract: every runner exists for every supported shell.
for f in scripts/quality.sh scripts/quality.ps1 scripts/quality.cmd \
         scripts/doctor.sh  scripts/doctor.ps1  scripts/doctor.cmd \
         scripts/install.sh scripts/install.ps1 scripts/install.cmd; do
  assert_file "$REPO_DIR/$f"
done

# Hooks: extensionless sh files that git executes, plus manual runners.
for f in git-hooks/pre-commit git-hooks/pre-push \
         git-hooks/pre-commit.ps1 git-hooks/pre-commit.cmd \
         git-hooks/pre-push.ps1   git-hooks/pre-push.cmd; do
  assert_file "$REPO_DIR/$f"
done

for p in minimal standard strict; do
  assert_file "$REPO_DIR/git-hooks/profiles/$p/gates.def" "gates.def for profile $p"
done

for f in docs/01-spec.md docs/02-dev-plan.md docs/03-quality-gates.md \
         docs/04-testing.md docs/05-store-launch.md docs/06-marketing.md; do
  assert_file "$REPO_DIR/templates/$f"
done

for f in CLAUDE.md.tmpl DECISIONS.md.stub TODO.md.stub \
         claude/settings.json claude/hooks/pre-tool-use.sh \
         claude/hooks/pre-tool-use.ps1 claude/hooks/pre-tool-use.cmd; do
  assert_file "$REPO_DIR/templates/$f"
done

# Manifest sanity
if command -v python3 >/dev/null 2>&1; then
  for m in .claude-plugin/plugin.json .claude-plugin/marketplace.json templates/claude/settings.json; do
    python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$REPO_DIR/$m" 2>/dev/null \
      && pass "$m is valid JSON" || fail "$m is not valid JSON"
  done
else
  skip "JSON validation (no python3)"
fi

assert_has "$REPO_DIR/.claude-plugin/plugin.json" '"name": "flu-harness"' "plugin name is flu-harness"

# ═══════════════════════════════════════════════════════════════════════════
section "2. Placeholder hygiene"
# ═══════════════════════════════════════════════════════════════════════════

# Every {{TOKEN}} in CLAUDE.md.tmpl must be one the wizard knows how to fill.
if command -v python3 >/dev/null 2>&1; then
  TOKENS=$(python3 - "$REPO_DIR/templates/CLAUDE.md.tmpl" <<'PY'
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
# {{DOMAIN_RULES — ex: ...}} style placeholders: take the identifier before any separator
found = set()
for raw in re.findall(r'\{\{(.*?)\}\}', text, re.S):
    found.add(raw.strip().split('—')[0].split('-')[0].strip())
print('\n'.join(sorted(found)))
PY
)
  SKILL="$REPO_DIR/skills/new-flutter-project/SKILL.md"
  UNKNOWN=""
  while IFS= read -r tok; do
    [ -z "$tok" ] && continue
    grep -q -- "{{$tok}}" "$SKILL" || grep -q -- "$tok" "$SKILL" || UNKNOWN="$UNKNOWN $tok"
  done <<< "$TOKENS"
  if [ -z "$UNKNOWN" ]; then
    pass "every CLAUDE.md.tmpl placeholder is documented in the wizard skill"
  else
    fail "undocumented placeholders in CLAUDE.md.tmpl:$UNKNOWN"
  fi
else
  skip "placeholder lint (no python3)"
fi

# The shipped .stub files keep deliberate placeholders; the wizard must mention them.
for tok in APP_NAME START_DATE FEATURE_1 FEATURE_2 FEATURE_3; do
  assert_has "$REPO_DIR/skills/new-flutter-project/SKILL.md" "$tok" \
    "wizard documents the $tok placeholder"
done

# ═══════════════════════════════════════════════════════════════════════════
section "3. Shell syntax"
# ═══════════════════════════════════════════════════════════════════════════

SH_COUNT=0
while IFS= read -r f; do
  SH_COUNT=$((SH_COUNT + 1))
  if sh -n "$f" 2>/dev/null; then
    pass "sh -n $(basename "$f")"
  else
    fail "sh -n $(basename "$f") — syntax error"
  fi
done < <(find "$REPO_DIR/scripts" "$REPO_DIR/git-hooks" "$REPO_DIR/templates" -name '*.sh' -type f | sort)
[ "$SH_COUNT" -gt 0 ] || fail "no .sh files found to check"

# Extensionless hooks
for f in "$REPO_DIR/git-hooks/pre-commit" "$REPO_DIR/git-hooks/pre-push"; do
  sh -n "$f" 2>/dev/null && pass "sh -n $(basename "$f")" || fail "sh -n $(basename "$f") — syntax error"
done

if [ -n "$PWSH" ]; then
  PS_COUNT=0
  while IFS= read -r f; do
    PS_COUNT=$((PS_COUNT + 1))
    # Parse the text from stdin rather than by path: a Windows PowerShell cannot
    # resolve a POSIX path, and that failure looks like a syntax error.
    if "$PWSH" -NoProfile -Command "
      \$text = [Console]::In.ReadToEnd()
      \$e = \$null
      \$null = [System.Management.Automation.Language.Parser]::ParseInput(\$text, [ref]\$null, [ref]\$e)
      if (\$e -and \$e.Count -gt 0) { exit 1 } else { exit 0 }" < "$f" >/dev/null 2>&1; then
      pass "PowerShell parse $(basename "$f")"
    else
      fail "PowerShell parse $(basename "$f") — syntax error"
    fi
  done < <(find "$REPO_DIR" -name '*.ps1' -type f | sort)
  [ "$PS_COUNT" -gt 0 ] || fail "no .ps1 files found to check"
else
  skip "PowerShell syntax checks (no pwsh/powershell on PATH)"
fi

# cmd.exe has no parser, so at least assert balanced parentheses per line-set and
# the two patterns that are always bugs.
while IFS= read -r f; do
  base=$(basename "$f")
  # Comments in these files discuss shift and %~dp0, so strip them first.
  code=$(grep -vE '^[[:space:]]*rem([[:space:]]|$)' "$f")
  # `%~dp0` must never be *used* after a shift: cmd moves %1 into %0, so a later
  # %~dp0 expands to the first argument instead of this script's directory.
  if printf '%s\n' "$code" | grep -q 'shift' && printf '%s\n' "$code" | grep -q '%~dp0'; then
    first_shift=$(printf '%s\n' "$code" | grep -n 'shift'  | head -1 | cut -d: -f1)
    first_dp0=$(printf '%s\n' "$code" | grep -n '%~dp0' | head -1 | cut -d: -f1)
    if [ -n "$first_shift" ] && [ -n "$first_dp0" ] && [ "$first_dp0" -lt "$first_shift" ]; then
      pass "$base captures %~dp0 before the first shift"
    else
      fail "$base uses %~dp0 at or after a shift — cmd moves %1 into %0, so it expands to garbage"
    fi
  fi
  # A nested batch file must be invoked with `call` or control never returns.
  if grep -qE '^\s*"[^"]*\.cmd"' "$f" && ! grep -qE '^\s*call ' "$f"; then
    fail "$base invokes a .cmd without 'call' — control will not return"
  fi
done < <(find "$REPO_DIR" -name '*.cmd' -type f | sort)

# ═══════════════════════════════════════════════════════════════════════════
section "4. Gate plans (sh runner)"
# ═══════════════════════════════════════════════════════════════════════════

PROJ="$WINBASE/proj"
mkdir -p "$PROJ/.githooks/lib" "$PROJ/lib" "$PROJ/test"
printf 'name: fixture_app\nenvironment:\n  sdk: ^3.11.0\n' > "$PROJ/pubspec.yaml"
printf 'include: package:flutter_lints/flutter.yaml\n'      > "$PROJ/analysis_options.yaml"
printf 'void main() {}\n' > "$PROJ/lib/main.dart"
printf 'void main() {}\n' > "$PROJ/test/widget_test.dart"
( cd "$PROJ" && git init -q . ) >/dev/null 2>&1

# All three runners, so the parity checks below have something to compare.
cp "$REPO_DIR/scripts/quality.sh"  "$PROJ/.githooks/lib/"
cp "$REPO_DIR/scripts/quality.ps1" "$PROJ/.githooks/lib/"
cp "$REPO_DIR/scripts/quality.cmd" "$PROJ/.githooks/lib/"

check_plan() {
  # check_plan PROFILE STAGE EXPECTED
  local profile="$1" stage="$2" expected="$3"
  cp "$REPO_DIR/git-hooks/profiles/$profile/gates.def" "$PROJ/.githooks/lib/gates.def"
  local got
  got=$(sh "$PROJ/.githooks/lib/quality.sh" --stage "$stage" --profile "$profile" --dry-run 2>/dev/null \
        | sed -n 's/^gate=//p' | tr '\n' ' ' | sed 's/ $//')
  [ "$got" = "$expected" ] \
    && pass "$profile/$stage plan = [$expected]" \
    || fail "$profile/$stage plan = [$got], expected [$expected]"
}

check_plan minimal  pre-commit "analyze"
check_plan minimal  pre-push   "analyze test"
check_plan standard pre-commit "format analyze"
check_plan standard pre-push   "format analyze lint test"
check_plan strict   pre-commit "format analyze lint"
check_plan strict   pre-push   "format analyze lint test build"

# The profile is remembered in .githooks/.profile when --profile is omitted.
printf 'minimal' > "$PROJ/.githooks/.profile"
cp "$REPO_DIR/git-hooks/profiles/minimal/gates.def" "$PROJ/.githooks/lib/gates.def"
got=$(sh "$PROJ/.githooks/lib/quality.sh" --stage pre-commit --dry-run 2>/dev/null | sed -n 's/^profile=//p')
[ "$got" = "minimal" ] && pass "reads the profile from .githooks/.profile" \
                       || fail "profile from .profile = [$got], expected [minimal]"

# Exit codes
printf 'strict' > "$PROJ/.githooks/.profile"
cp "$REPO_DIR/git-hooks/profiles/strict/gates.def" "$PROJ/.githooks/lib/gates.def"
assert_exit 0 "dry-run always exits 0" sh "$PROJ/.githooks/lib/quality.sh" --stage pre-commit --dry-run
assert_exit 2 "unknown flag exits 2" sh "$PROJ/.githooks/lib/quality.sh" --bogus

# Missing pubspec is a FAIL, not a crash.
NOPUB="$TMPBASE/nopub"
mkdir -p "$NOPUB/.githooks/lib"
cp "$REPO_DIR/scripts/quality.sh" "$NOPUB/.githooks/lib/"
cp "$REPO_DIR/git-hooks/profiles/strict/gates.def" "$NOPUB/.githooks/lib/"
cp "$REPO_DIR/git-hooks/profiles/strict/gates.def" "$NOPUB/.githooks/lib/"
assert_exit 1 "no pubspec.yaml in project root exits 1" \
  sh "$NOPUB/.githooks/lib/quality.sh" --stage pre-commit --profile strict

# ═══════════════════════════════════════════════════════════════════════════
section "5. Cross-shell plan parity"
# ═══════════════════════════════════════════════════════════════════════════

if [ -n "$PWSH" ]; then
  for p in minimal standard strict; do
    cp "$REPO_DIR/git-hooks/profiles/$p/gates.def" "$PROJ/.githooks/lib/gates.def"
    sh_plan=$(sh "$PROJ/.githooks/lib/quality.sh" --stage pre-push --profile "$p" --dry-run 2>/dev/null \
              | sed -n 's/^gate=//p' | tr '\n' ' ' | sed 's/ $//')
    ps_plan=$("$PWSH" -NoProfile -ExecutionPolicy Bypass \
              -File "$(win_path "$PROJ/.githooks/lib/quality.ps1")" -Stage pre-push -Profile "$p" -DryRun 2>/dev/null \
              | tr -d '\r' | sed -n 's/^gate=//p' | tr '\n' ' ' | sed 's/ $//')
    if [ "$sh_plan" = "$ps_plan" ]; then
      pass "sh and PowerShell agree on the $p plan"
    else
      fail "sh/PowerShell plan mismatch for $p: [$sh_plan] vs [$ps_plan]"
    fi
  done
else
  skip "PowerShell parity (no pwsh/powershell on PATH)"
fi

if [ -n "$CMD" ]; then
  for p in minimal standard strict; do
    cp "$REPO_DIR/git-hooks/profiles/$p/gates.def" "$PROJ/.githooks/lib/gates.def"
    sh_plan=$(sh "$PROJ/.githooks/lib/quality.sh" --stage pre-push --profile "$p" --dry-run 2>/dev/null \
              | sed -n 's/^gate=//p' | tr '\n' ' ' | sed 's/ $//')
    libwin=$(win_path "$PROJ/.githooks/lib")
    cmd_plan=$("$CMD" /c "${libwin}\\quality.cmd /stage:pre-push /profile:$p /dry-run" 2>/dev/null \
              | tr -d '\r' | sed -n 's/^gate=//p' | tr '\n' ' ' | sed 's/ $//')
    if [ "$sh_plan" = "$cmd_plan" ]; then
      pass "sh and cmd.exe agree on the $p plan"
    else
      fail "sh/cmd plan mismatch for $p: [$sh_plan] vs [$cmd_plan]"
    fi
  done
else
  skip "cmd.exe parity (no cmd.exe on PATH)"
fi

# ═══════════════════════════════════════════════════════════════════════════
section "6. Destructive-operation guard"
# ═══════════════════════════════════════════════════════════════════════════

GUARD="$REPO_DIR/templates/claude/hooks/pre-tool-use.sh"

guard_case() {
  # guard_case EXPECTED LABEL JSON
  local expected="$1" label="$2" payload="$3"
  local actual=0
  printf '%s' "$payload" | sh "$GUARD" >/dev/null 2>&1 || actual=$?
  [ "$actual" -eq "$expected" ] \
    && pass "guard: $label -> $([ "$expected" = 2 ] && echo BLOCK || echo allow)" \
    || fail "guard: $label -> exit $actual, expected $expected"
}

guard_case 2 "flutter pub publish"  '{"tool_name":"Bash","tool_input":{"command":"flutter pub publish"}}'
guard_case 2 "dart pub publish"     '{"tool_name":"Bash","tool_input":{"command":"dart pub publish"}}'
guard_case 2 "git push --force"     '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'
guard_case 2 "git push -f"          '{"tool_name":"Bash","tool_input":{"command":"git push -f origin main"}}'
guard_case 2 "git commit --no-verify" '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"x\" --no-verify"}}'
guard_case 2 "git reset --hard"     '{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD~3"}}'
guard_case 2 "git clean -fd"        '{"tool_name":"Bash","tool_input":{"command":"git clean -fd"}}'
guard_case 2 "rm -rf /"             '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}'
guard_case 2 "DROP TABLE"           '{"tool_name":"Bash","tool_input":{"command":"psql -c \"DROP TABLE users;\""}}'
guard_case 2 "TRUNCATE TABLE"       '{"tool_name":"Bash","tool_input":{"command":"mysql -e \"TRUNCATE TABLE x\""}}'
guard_case 2 "supabase db reset"    '{"tool_name":"Bash","tool_input":{"command":"supabase db reset"}}'
guard_case 2 "firestore:delete"     '{"tool_name":"Bash","tool_input":{"command":"firebase firestore:delete --all-collections"}}'
guard_case 2 "fastlane deliver"     '{"tool_name":"Bash","tool_input":{"command":"bundle exec fastlane deliver"}}'
guard_case 2 "keytool -genkey"      '{"tool_name":"Bash","tool_input":{"command":"keytool -genkey -keystore release.jks"}}'
guard_case 2 "flutter build ipa"    '{"tool_name":"Bash","tool_input":{"command":"flutter build ipa --release"}}'

guard_case 0 "flutter test"         '{"tool_name":"Bash","tool_input":{"command":"flutter test"}}'
guard_case 0 "flutter analyze"      '{"tool_name":"Bash","tool_input":{"command":"flutter analyze"}}'
guard_case 0 "git push origin feat" '{"tool_name":"Bash","tool_input":{"command":"git push origin feat/x"}}'
guard_case 0 "git commit"           '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: paywall\""}}'
guard_case 0 "rm -rf build/"        '{"tool_name":"Bash","tool_input":{"command":"rm -rf build/"}}'
guard_case 0 "DELETE with WHERE"    '{"tool_name":"Bash","tool_input":{"command":"psql -c \"DELETE FROM t WHERE id=1\""}}'
guard_case 0 "flutter build apk"    '{"tool_name":"Bash","tool_input":{"command":"flutter build apk --release"}}'
# A non-Bash tool must never be blocked, even when its payload reads like a command.
guard_case 0 "Write tool mentioning force-push" \
  '{"tool_name":"Write","tool_input":{"file_path":"a.md","content":"never git push --force"}}'
guard_case 0 "Read tool"            '{"tool_name":"Read","tool_input":{"file_path":"lib/main.dart"}}'

# ═══════════════════════════════════════════════════════════════════════════
section "7. flutter-doctor"
# ═══════════════════════════════════════════════════════════════════════════

DOCTOR="$REPO_DIR/scripts/doctor.sh"

assert_exit 1 "doctor exits 1 on a project full of FAILs" sh "$DOCTOR" "$TMPBASE"
assert_exit 2 "doctor exits 2 on an unknown flag"          sh "$DOCTOR" --bogus

sh "$DOCTOR" --json "$TMPBASE" > "$TMPBASE/doctor.json" 2>/dev/null || true

if command -v python3 >/dev/null 2>&1; then
  python3 - "$TMPBASE/doctor.json" <<'PY' && pass "doctor --json is valid and complete" || fail "doctor --json invalid or incomplete"
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print("not JSON:", e); sys.exit(1)
need = {'ok', 'warn', 'fail', 'total', 'expected', 'results'}
if not need.issubset(d):
    print("missing keys:", need - set(d)); sys.exit(1)
ns = [r['n'] for r in d['results']]
if len(ns) != d['expected']:
    print(f"reported {len(ns)} checks, expected {d['expected']}"); sys.exit(1)
if sorted(ns) != list(range(1, d['expected'] + 1)):
    print("check numbers are not 1..N without gaps or duplicates:", sorted(ns)); sys.exit(1)
if d['ok'] + d['warn'] + d['fail'] != d['total']:
    print("ok+warn+fail != total"); sys.exit(1)
for r in d['results']:
    if r['level'] not in ('OK', 'WARN', 'FAIL'):
        print("bad level:", r['level']); sys.exit(1)
    if not r['msg']:
        print("empty message at check", r['n']); sys.exit(1)
    if r['level'] == 'FAIL' and not r['fix']:
        print("FAIL without a fix line at check", r['n']); sys.exit(1)
PY
else
  skip "doctor JSON assertions (no python3)"
fi

# The check list must not silently drift between the native implementations.
# A check can be emitted from several branches, so compare the SET of numbers.
sh_nums=$(grep -oE '_out (OK|WARN|FAIL) [0-9]+' "$REPO_DIR/scripts/doctor.sh" \
          | awk '{print $3}' | sort -n -u | tr '\n' ' ')
ps_nums=$(grep -oE "Out-Check [0-9]+ '" "$REPO_DIR/scripts/doctor.ps1" \
          | awk '{print $2}' | sort -n -u | tr '\n' ' ')
declared=$(sed -n 's/^TOTAL_CHECKS=\([0-9]*\)$/\1/p' "$REPO_DIR/scripts/doctor.sh" | head -1)
expected_nums=$(seq 1 "${declared:-0}" | tr '\n' ' ')
if [ "$sh_nums" = "$ps_nums" ] && [ "$sh_nums" = "$expected_nums" ]; then
  pass "doctor checks 1..$declared present and identical in both implementations"
else
  fail "doctor check drift — sh=[$sh_nums] ps1=[$ps_nums] expected=[$expected_nums]"
fi

ps_declared=$(sed -n 's/^\$TotalChecks = \([0-9]*\)$/\1/p' "$REPO_DIR/scripts/doctor.ps1" | head -1)
[ "$ps_declared" = "$declared" ] \
  && pass "doctor.ps1 \$TotalChecks matches ($ps_declared)" \
  || fail "doctor.ps1 \$TotalChecks = $ps_declared, doctor.sh declares $declared"

# doctor.cmd must delegate, not reimplement. A third copy is how they drift.
assert_has "$REPO_DIR/scripts/doctor.cmd" "doctor.ps1" "doctor.cmd delegates to doctor.ps1"
assert_has "$REPO_DIR/scripts/quality.cmd" "SELFDIR"   "quality.cmd captures %~dp0 before parsing"

# ═══════════════════════════════════════════════════════════════════════════
section "8. Line endings"
# ═══════════════════════════════════════════════════════════════════════════

check_lf() {
  local f="$1" label="$2"
  # A CR before the first LF means the shebang is corrupt and git cannot run it.
  if head -c 400 "$f" | tr -dc '\r' | grep -q .; then
    if head -c 400 "$f" | head -n 1 | grep -q "$(printf '\r')"; then
      fail "$label has CRLF — git would refuse to execute it"
      return
    fi
  fi
  pass "$label is LF"
}

check_lf "$REPO_DIR/git-hooks/pre-commit" "git-hooks/pre-commit"
check_lf "$REPO_DIR/git-hooks/pre-push"   "git-hooks/pre-push"

assert_has "$REPO_DIR/.gitattributes" 'eol=lf' ".gitattributes pins LF"
assert_has "$REPO_DIR/.gitattributes" '.githooks/' ".gitattributes covers .githooks/"

# ═══════════════════════════════════════════════════════════════════════════
section "9. Skill integrity"
# ═══════════════════════════════════════════════════════════════════════════

for s in new-flutter-project flutter-doctor; do
  f="$REPO_DIR/skills/$s/SKILL.md"
  assert_has "$f" "^name: $s" "SKILL.md frontmatter names $s"
  assert_has "$f" "^description: " "$s has a description"
  # Skills must reference the plugin root, never an absolute path from a dev box.
  assert_lacks "$f" "/mnt/c/" "$s does not hardcode the author's drive path"
  assert_lacks "$f" "C:\\\\flu-harness" "$s does not hardcode an absolute Windows path"
done

assert_has "$REPO_DIR/skills/new-flutter-project/SKILL.md" 'CLAUDE_PLUGIN_ROOT' \
  "wizard uses \${CLAUDE_PLUGIN_ROOT}"
assert_has "$REPO_DIR/skills/flutter-doctor/SKILL.md" 'CLAUDE_PLUGIN_ROOT' \
  "doctor skill uses \${CLAUDE_PLUGIN_ROOT}"

# Every rule referenced by the wizard must exist on disk.
if command -v python3 >/dev/null 2>&1; then
  MISSING=$(python3 - "$REPO_DIR" <<'PY'
import os, re, sys
repo = sys.argv[1]
skill = open(os.path.join(repo, 'skills', 'new-flutter-project', 'SKILL.md'), encoding='utf-8').read()
rules_dir = os.path.join(repo, 'templates', 'rules')
on_disk = {f for f in os.listdir(rules_dir) if f.endswith('.md')}
referenced = set(re.findall(r'`([a-z0-9\-]+\.md)`', skill))
missing = sorted(r for r in referenced if r not in on_disk and not r.startswith('docs/'))
print('\n'.join(missing))
PY
)
  if [ -z "$MISSING" ]; then
    pass "every rule the wizard references exists in templates/rules/"
  else
    fail "wizard references rules that do not exist: $(echo "$MISSING" | tr '\n' ' ')"
  fi
else
  skip "rule reference check (no python3)"
fi

# Every rule file must carry the frontmatter the loader needs.
RULE_BAD=""
for f in "$REPO_DIR"/templates/rules/*.md; do
  head -1 "$f" | grep -q '^---$' || RULE_BAD="$RULE_BAD $(basename "$f")"
  grep -q '^description: ' "$f" || RULE_BAD="$RULE_BAD $(basename "$f"):nodesc"
done
[ -z "$RULE_BAD" ] && pass "all rule files have frontmatter with a description" \
                   || fail "rule files missing frontmatter:$RULE_BAD"

# The always-on rules must actually say alwaysApply: true.
for r in patterns performance security accessibility forbidden testing; do
  assert_has "$REPO_DIR/templates/rules/$r.md" "alwaysApply: true" "$r.md is always-on"
done

# ═══════════════════════════════════════════════════════════════════════════
section "10. Documentation links"
# ═══════════════════════════════════════════════════════════════════════════

# A README that links to a file nobody wrote is the most common rot in a
# template repo, and the cheapest to catch mechanically.
if command -v python3 >/dev/null 2>&1; then
  BROKEN=$(python3 "$REPO_DIR/tests/check_links.py" "$REPO_DIR")
  if [ -z "$BROKEN" ]; then
    pass "every relative link in the docs resolves"
  else
    fail "broken relative links: $(printf '%s' "$BROKEN" | tr '\n' ' ')"
  fi
else
  skip "documentation link check (no python3)"
fi

# The files the README promises must exist.
assert_file "$REPO_DIR/docs/GETTING_STARTED.md" "docs/GETTING_STARTED.md exists (README links it)"
assert_file "$REPO_DIR/docs/WINDOWS.md"         "docs/WINDOWS.md exists (README links it)"

# ═══════════════════════════════════════════════════════════════════════════
section "11. Installer"
# ═══════════════════════════════════════════════════════════════════════════

PREFIX="$TMPBASE/install-prefix"
assert_exit 0 "install.sh runs" sh "$REPO_DIR/scripts/install.sh" --prefix "$PREFIX" --from "$REPO_DIR"
assert_file "$PREFIX/.installed"                       "installer stamps .installed"
assert_file "$PREFIX/scripts/doctor.sh"                "installer copies the doctor"
assert_file "$PREFIX/scripts/quality.ps1"              "installer copies the PowerShell runner"
assert_file "$PREFIX/scripts/quality.cmd"              "installer copies the cmd runner"
assert_file "$PREFIX/git-hooks/pre-commit"             "installer copies the hook"
assert_file "$PREFIX/git-hooks/profiles/strict/gates.def" "installer copies the gate profiles"
assert_dir  "$PREFIX/templates/rules"                  "installer copies the rules"

check_lf "$PREFIX/git-hooks/pre-commit" "installed pre-commit"

assert_exit 1 "installer refuses to clobber an existing install" \
  sh "$REPO_DIR/scripts/install.sh" --prefix "$PREFIX" --from "$REPO_DIR"
assert_exit 0 "installer --force overwrites" \
  sh "$REPO_DIR/scripts/install.sh" --prefix "$PREFIX" --from "$REPO_DIR" --force
assert_exit 0 "installer --uninstall removes" \
  sh "$REPO_DIR/scripts/install.sh" --prefix "$PREFIX" --uninstall
[ ! -d "$PREFIX" ] && pass "uninstall really removed the prefix" \
                   || fail "uninstall left $PREFIX behind"

# ═══════════════════════════════════════════════════════════════════════════
printf '\n%s%s%s\n' "$BOLD" "════════════════════════════════════════" "$NC"
printf '%sPASS: %d%s   %sFAIL: %d%s   %sSKIP: %d%s\n' \
  "$GREEN" "$PASS" "$NC" "$RED" "$FAIL" "$NC" "$YELLOW" "$SKIP" "$NC"
printf '%s%s%s\n\n' "$BOLD" "════════════════════════════════════════" "$NC"

if [ "$FAIL" -gt 0 ]; then
  printf '%sFailures:%s\n' "$RED" "$NC"
  for e in "${ERRORS[@]}"; do printf '  - %s\n' "$e"; done
  printf '\n'
  exit 1
fi

exit 0
