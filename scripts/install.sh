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

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || SELF_DIR=$(pwd)

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
#
# Two ways in, and the second one is the reason this block is not four lines:
#
#   * A checkout.  ./scripts/install.sh, or the script sitting next to
#     .claude-plugin/ in a clone.
#
#   * Piped.       curl -fsSL <raw-url>/install.sh | sh
#
# The piped form is what the landing page advertises, and it is the one that
# cannot find anything: when a script arrives on stdin, $0 is just "sh", so
# there is no repository next to it and nothing on disk to copy. An earlier
# version of this script simply failed there, which meant the first command a
# visitor to the site runs did not work. So the piped case downloads a tarball
# of the repository and installs from that.
#
# HARNESS_REF picks a branch or tag to download (default: main).

TMP_FETCH=""
cleanup_fetch() {
  if [ -n "$TMP_FETCH" ] && [ -d "$TMP_FETCH" ]; then
    rm -rf "$TMP_FETCH" || true
  fi
}
trap cleanup_fetch EXIT HUP INT TERM

if [ -z "$FROM" ]; then
  if [ -d "$SELF_DIR/../.claude-plugin" ]; then
    FROM=$(CDPATH= cd -- "$SELF_DIR/.." && pwd)
  elif [ -d "$SELF_DIR/scripts" ]; then
    FROM=$(CDPATH= cd -- "$SELF_DIR" && pwd)
  else
    FROM=""
  fi
fi

# An explicit --from that does not hold a checkout is a user error worth naming.
if [ -n "$FROM" ] && [ ! -d "$FROM/scripts" ]; then
  printf 'ERROR: %s does not look like a flu-harness checkout (no scripts/).\n' "$FROM" >&2
  printf '       Pass --from /path/to/flu-harness, or clone it first:\n' >&2
  printf '         git clone https://github.com/Jujubalandia/flu-harness ~/.flu-harness\n' >&2
  exit 1
fi

if [ -z "$FROM" ]; then
  REF="${HARNESS_REF:-main}"
  # HARNESS_TARBALL_URL is for forks, private mirrors, and the test suite, which
  # points it at a file:// tarball so the piped path can be tested offline.
  TARBALL="${HARNESS_TARBALL_URL:-https://github.com/Jujubalandia/flu-harness/archive/refs/heads/$REF.tar.gz}"

  if ! command -v tar >/dev/null 2>&1; then
    printf 'ERROR: tar is required to install from a pipe.\n' >&2
    printf '       Clone instead:\n' >&2
    printf '         git clone https://github.com/Jujubalandia/flu-harness ~/.flu-harness\n' >&2
    exit 1
  fi

  TMP_FETCH=$(mktemp -d 2>/dev/null) || TMP_FETCH=""
  if [ -z "$TMP_FETCH" ]; then
    printf 'ERROR: could not create a temporary directory.\n' >&2
    exit 1
  fi

  printf 'Downloading flu-harness (%s)...\n' "$REF"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$TARBALL" | tar -xz -C "$TMP_FETCH" || {
      printf 'ERROR: download failed: %s\n' "$TARBALL" >&2
      printf '       Check the ref, or clone it instead.\n' >&2
      exit 1
    }
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$TARBALL" | tar -xz -C "$TMP_FETCH" || {
      printf 'ERROR: download failed: %s\n' "$TARBALL" >&2
      exit 1
    }
  else
    printf 'ERROR: neither curl nor wget is available to download the repository.\n' >&2
    printf '       Clone instead:\n' >&2
    printf '         git clone https://github.com/Jujubalandia/flu-harness ~/.flu-harness\n' >&2
    exit 1
  fi

  # The archive extracts to flu-harness-<ref>/, one directory deep.
  for candidate in "$TMP_FETCH"/*/; do
    if [ -d "$candidate/scripts" ]; then FROM="${candidate%/}"; break; fi
  done

  if [ -z "$FROM" ]; then
    printf 'ERROR: the downloaded archive did not contain scripts/.\n' >&2
    exit 1
  fi
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
