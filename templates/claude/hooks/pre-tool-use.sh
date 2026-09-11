#!/bin/sh
# .claude/hooks/pre-tool-use.sh
#
# flu-harness destructive-operation guard. Runs before every tool call.
#
#   exit 0  allow
#   exit 2  block (stderr is shown to the user)
#
# ── Why there is no python3 here ────────────────────────────────────────────
# The obvious way to do this is `python3 -c 'import json...'`. That is what most
# hooks do, and it is why most hooks silently do nothing on a Windows box where
# only the `py` launcher, or nothing at all, is on PATH.
#
# So this hook uses POSIX tools only. It extracts the command with sed and, when
# that fails (escaped quotes, unicode, a shape we did not anticipate), it falls
# back to scanning the raw payload — which is correct here because the check only
# runs for the Bash tool, where the payload *is* the command.
#
# The PowerShell twin (pre-tool-use.ps1) implements the same list for users who
# wire it up through .claude/settings.json on Windows.

set -u

INPUT=$(cat)

TOOL=$(printf '%s' "$INPUT" | tr -d '\n' \
  | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

# Only shell commands are inspected.
[ "$TOOL" = "Bash" ] || exit 0

CMD=$(printf '%s' "$INPUT" | tr -d '\n' \
  | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

# Extraction is best-effort: a command containing an escaped quote truncates it
# (git commit -m "x" --no-verify stops at the first inner quote). So keep the raw
# payload around and check both. Yes, that can over-block when a description
# field happens to read like a command — over-blocking is the safe direction for
# a destructive-operation guard, and the user can always run it by hand.
RAW=$(printf '%s' "$INPUT" | tr '\n\r\t' '   ')

[ -n "$CMD" ] || CMD="$RAW"
# Flatten so a multi-line command still matches a single-line pattern.
CMD=$(printf '%s' "$CMD" | tr '\n\r\t' '   ')

block() {
  printf '\n  BLOCKED: %s\n' "$1" >&2
  printf '  This operation is destructive or irreversible. flu-harness stops it\n' >&2
  printf '  before it runs.\n\n' >&2
  printf '  If you are certain, run it yourself in a terminal — a human typing it\n' >&2
  printf '  is the confirmation this guard exists to require.\n' >&2
  printf '  To change the list for this project, edit .claude/hooks/pre-tool-use.sh.\n\n' >&2
  exit 2
}

matches() {
  printf '%s' "$CMD" | grep -qiE "$1" && return 0
  printf '%s' "$RAW" | grep -qiE "$1" && return 0
  return 1
}

# ── Publishing: irreversible, and usually a typo away from shipping ─────────
matches '(^|[^a-z])(flutter|dart) +pub +publish'     && block "publishing a package to pub.dev"
matches 'flutter +pub +lish'                          && block "publishing a package to pub.dev"

# ── Store submission / release distribution ────────────────────────────────
matches 'fastlane +(deliver|supply|pilot|precheck)'   && block "store submission via fastlane"
matches 'firebase +appdistribution:distribute'        && block "distributing a build to testers"
matches 'flutter +build +ipa'                         && block "an unsigned iOS archive is easy to upload by accident"
matches 'bundle +exec +fastlane'                      && block "store submission via fastlane"

# ── Git history: rewrites are the one thing git cannot undo for you ────────
matches 'git +push +.*(--force|-f)([^a-z]|$)'         && block "force-push"
matches 'git +commit +.*--no-verify'                  && block "commit with quality gates skipped (--no-verify)"
matches 'git +commit +.*(^| )-n( |$)'                 && block "commit with quality gates skipped (-n)"
matches 'git +reset +--hard'                          && block "git reset --hard"
matches 'git +clean +-[a-z]*f'                        && block "git clean -f (deletes untracked files)"
matches 'git +filter-(branch|repo)'                   && block "history rewriting"
matches 'git +rebase +-i'                             && block "interactive rebase on a shared branch"

# ── Filesystem ────────────────────────────────────────────────────────────
matches 'rm +-[a-z]*r[a-z]*f? +/( |$)'                && block "rm -rf /"
matches 'rm +-[a-z]*r[a-z]*f? +~'                     && block "rm -rf ~"
matches 'rm +-[a-z]*r[a-z]*f? +/mnt/[a-z](/|$)'       && block "recursive delete at a filesystem root"
matches 'Remove-Item .*-Recurse .*-Force .*[A-Z]:\\\\?$' && block "recursive delete at a drive root"

# ── Databases ─────────────────────────────────────────────────────────────
matches 'supabase +db +reset'                         && block "supabase db reset"
matches 'firebase +firestore:delete'                  && block "firebase firestore:delete"
matches 'DROP +(TABLE|DATABASE|SCHEMA)'               && block "DROP TABLE/DATABASE/SCHEMA"
matches 'TRUNCATE +TABLE'                             && block "TRUNCATE TABLE"
matches 'DELETE +FROM +[a-z_]+ *(;|$)'                && block "DELETE with no WHERE clause"
matches 'psql .*--command=.*(DROP|TRUNCATE)'          && block "destructive SQL through psql"

# ── Release signing material ──────────────────────────────────────────────
matches 'keytool +-genkey'                            && block "generating a new signing key (rotating your release key locks you out of updates)"

exit 0
