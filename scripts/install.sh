#!/bin/sh
# flu-harness installer (POSIX sh).
#
# Copies the scripts, templates, hooks and skills into a prefix directory so the
# doctor and the gate runners work from anywhere, with or without Claude Code.
#
#   ./install.sh                       install from this checkout into ~/.flu-harness
#   ./install.sh --prefix /opt/flu     install somewhere else
#   ./install.sh --from /path/to/repo  install from another checkout
#   ./install.sh --force               overwrite an existing install
#   ./install.sh --uninstall           remove the install
#
# Windows: this same file runs under Git Bash. For PowerShell use install.ps1,
# and for cmd.exe use install.cmd (which delegates to install.ps1). All three
# produce the same layout.

set -u

PREFIX="${HOME:-/tmp}/.flu-harness"
FROM=""
FORCE=""
UNINSTALL=""

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix)    PREFIX="$2"; shift 2 ;;
    --from)      FROM="$2"; shift 2 ;;
    --force)     FORCE=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help)
      sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) printf 'install.sh: unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# ── Uninstall ────────────────────────────────────────────────────────────────
if [ -n "$UNINSTALL" ]; then
  if [ -d "$PREFIX" ]; then
    rm -rf "$PREFIX"
    printf 'Removed %s\n' "$PREFIX"
  else
    printf 'Nothing to remove at %s\n' "$PREFIX"
  fi
  exit 0
fi

# ── Find the source ──────────────────────────────────────────────────────────
# A checkout of this repo has .claude-plugin/ next to scripts/.
if [ -z "$FROM" ]; then
  if [ -d "$SELF_DIR/../.claude-plugin" ]; then
    FROM=$(CDPATH= cd -- "$SELF_DIR/.." && pwd)
  else
    FROM=$(CDPATH= cd -- "$SELF_DIR" && pwd)
  fi
fi

if [ ! -d "$FROM/scripts" ]; then
  printf 'ERROR: %s does not look like a flu-harness checkout (no scripts/).\n' "$FROM" >&2
  printf '       Pass --from /path/to/flu-harness, or clone it first:\n' >&2
  printf '         git clone https://github.com/Jujubalandia/flu-harness ~/.flu-harness\n' >&2
  exit 1
fi

# ── Refuse to clobber silently ───────────────────────────────────────────────
if [ -d "$PREFIX" ] && [ -z "$FORCE" ]; then
  if [ -f "$PREFIX/.installed" ]; then
    printf 'ERROR: %s is already installed.\n' "$PREFIX" >&2
    printf '       Re-run with --force to overwrite, or --uninstall first.\n' >&2
    exit 1
  fi
fi

printf '\nflu-harness installer\n=====================\n'
printf 'from:   %s\n' "$FROM"
printf 'prefix: %s\n\n' "$PREFIX"

# ── Copy ─────────────────────────────────────────────────────────────────────
copy_tree() {
  src="$1"; dest="$2"
  [ -d "$src" ] || return 0
  mkdir -p "$dest"
  # -R preserves structure; the trailing /. copies contents, including dotfiles.
  cp -R "$src/." "$dest/" 2>/dev/null || {
    printf 'ERROR: could not copy %s -> %s\n' "$src" "$dest" >&2
    exit 1
  }
}

for d in scripts git-hooks templates skills docs; do
  [ -d "$FROM/$d" ] || continue
  printf '  . %s\n' "$d"
  copy_tree "$FROM/$d" "$PREFIX/$d"
done

for f in README.md README.pt-BR.md .gitattributes; do
  [ -f "$FROM/$f" ] && { printf '  . %s\n' "$f"; cp "$FROM/$f" "$PREFIX/$f"; }
done

# ── Make the shell entry points executable ───────────────────────────────────
# Windows has no execute bit, and Git Bash's chmod is a no-op there. That is
# fine: the hooks are invoked as `sh <file>` by git, which does not need it.
chmod +x "$PREFIX"/scripts/*.sh 2>/dev/null || true
chmod +x "$PREFIX"/git-hooks/pre-commit "$PREFIX"/git-hooks/pre-push 2>/dev/null || true

printf '%s\n' "$(date +%Y-%m-%d 2>/dev/null || echo unknown)" > "$PREFIX/.installed"

# ── Protect the hooks from CRLF ──────────────────────────────────────────────
# A hook checked out or copied with CRLF cannot run: the shebang becomes
# "#!/bin/sh\r" and git looks for an interpreter named "/bin/sh\r".
if [ -f "$PREFIX/git-hooks/pre-commit" ]; then
  FIRST=$(head -c 200 "$PREFIX/git-hooks/pre-commit" | head -n 1)
  case "$FIRST" in
    *"$(printf '\r')"*)
      printf '\n  WARNING: hooks were copied with CRLF line endings. Stripping.\n'
      for h in "$PREFIX"/git-hooks/pre-commit "$PREFIX"/git-hooks/pre-push; do
        [ -f "$h" ] && sed -i 's/\r$//' "$h" 2>/dev/null
      done
      ;;
  esac
fi

# ── Done ─────────────────────────────────────────────────────────────────────
printf '\nInstalled.\n\n'
printf 'Verify it:\n'
printf '  sh %s/scripts/doctor.sh --help\n\n' "$PREFIX"

printf 'Use it in a project (the wizard does this for you):\n'
printf '  mkdir -p .githooks/lib\n'
printf '  cp %s/git-hooks/pre-commit .githooks/\n' "$PREFIX"
printf '  cp %s/git-hooks/pre-push   .githooks/\n' "$PREFIX"
printf '  cp %s/scripts/quality.sh   .githooks/lib/\n' "$PREFIX"
printf '  cp %s/scripts/quality.ps1  .githooks/lib/\n' "$PREFIX"
printf '  cp %s/scripts/quality.cmd  .githooks/lib/\n' "$PREFIX"
printf '  cp %s/git-hooks/profiles/strict/gates.def .githooks/lib/\n' "$PREFIX"
printf '  printf %%s strict > .githooks/.profile\n'
printf '  git config core.hooksPath .githooks\n\n'

printf 'Optional - run the doctor by name from any shell:\n'
printf '  Git Bash : echo '\''export PATH="$PATH:%s/scripts"'\'' >> ~/.bashrc\n' "$PREFIX"
printf '  PowerShell:\n'
printf '    [Environment]::SetEnvironmentVariable("Path",\n'
printf '      [Environment]::GetEnvironmentVariable("Path","User") + ";%s\\scripts", "User")\n' "$PREFIX"
printf '\n'
