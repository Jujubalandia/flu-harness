# Windows: PowerShell, CMD and Git Bash

flu-harness is built so that the same gates behave the same way whether you type
`git commit` in PowerShell, in `cmd.exe`, or in Git Bash. That is not free — the
three shells disagree about quoting, path separators, exit codes and even about
what `%~dp0` means. This document records how the harness handles each of those,
including the four failures that were found by actually running things rather
than by reading documentation.

---

## The one-paragraph version

Git runs hooks itself, through its own interpreter — not through your shell. On
Windows that interpreter is the `sh.exe` bundled with Git for Windows. So the
hook file is a single POSIX `sh` script, and it fires identically no matter which
shell you typed the commit in. Everything else — the gate runner, the doctor —
ships in all three shells, because those you *do* invoke by hand.

```
                        you type: git commit
                               │
              ┌────────────────┼────────────────┐
              ▼                ▼                ▼
         PowerShell         cmd.exe          Git Bash
              └────────────────┼────────────────┘
                               ▼
                    git runs .githooks/pre-commit
                    with Git for Windows' own sh.exe
                               │
                               ▼
                    .githooks/lib/quality.sh
                    (reads gates.def, one plan)
```

---

## What each shell gets

| File | Shell | Who runs it |
|------|-------|-------------|
| `.githooks/pre-commit` | POSIX sh | **git**, automatically, from any shell |
| `.githooks/pre-push` | POSIX sh | **git**, automatically, from any shell |
| `.githooks/pre-commit.ps1` | PowerShell | you, by hand, to fail early |
| `.githooks/pre-commit.cmd` | cmd.exe | you, by hand |
| `.githooks/lib/quality.sh` | POSIX sh | the hooks, and Git Bash |
| `.githooks/lib/quality.ps1` | PowerShell | PowerShell and `quality.cmd` |
| `.githooks/lib/quality.cmd` | cmd.exe | cmd.exe |
| `.githooks/lib/gates.def` | data | all three — the single source of truth |
| `scripts/doctor.sh` | POSIX sh | Git Bash, Linux, macOS, WSL |
| `scripts/doctor.ps1` | PowerShell | Windows PowerShell 5.1+ and PowerShell 7+ |
| `scripts/doctor.cmd` | cmd.exe | finds PowerShell and delegates to `doctor.ps1` |

### Why `gates.def` exists

Three shells means three chances to drift: someone adds a gate to the PowerShell
runner, forgets the batch one, and a Windows user silently ships without it.

So the gate *plan* is not code in three languages. It is one file:

```
pre-commit=format,analyze,lint
pre-push=format,analyze,lint,test,build
```

All three runners parse that same file. `flutter-doctor` check 24 verifies all
three implementations are present, and `tests/test.sh` asserts that
`quality.sh`, `quality.ps1` and `quality.cmd` produce an **identical** plan for
every profile — that is what `--dry-run` / `-DryRun` / `/dry-run` is for.

```bash
sh    .githooks/lib/quality.sh  --dry-run            # gate=format, gate=analyze, ...
pwsh  .githooks/lib/quality.ps1 -DryRun
cmd   /c .githooks\lib\quality.cmd /dry-run
```

---

## Failures found while building this, and what the harness does about them

### 1. `cmd.exe`: `shift` also shifts `%0`, destroying `%~dp0`

This one is nasty because the script works until the moment someone passes an
argument.

```bat
@echo off
echo before: %~dp0      ->  C:\work\project\
shift
echo after:  %~dp0      ->  C:\project:C:\src\app\
```

`shift` moves `%1` into `%0`. After that, `%~dp0` is no longer "the directory of
this script" — it is "the drive and path of the first argument". A batch wrapper
that parses flags first and resolves its sibling script afterwards will hand
PowerShell a mangled path and you will get:

```
O argumento 'C:\doctor.ps1' para o parâmetro -File não existe.
```

**Harness rule:** capture `%~dp0` into a variable on the first lines of the
script, before any `shift`. Every `.cmd` file here does exactly that:

```bat
setlocal
set "SELFDIR=%~dp0"
rem ... only now parse arguments, which may shift ...
```

### 2. `cmd.exe`: `set "VAR=value"` strips only the outer quotes

The other half of the same bug. Writing the *value* with doubled quotes to
protect embedded quotes does not work:

```bat
set "PSARGS=-File ""%~dp0doctor.ps1"""     rem WRONG: value keeps literal ""
set  PSARGS=-File "%SELFDIR%doctor.ps1"    rem RIGHT: quotes survive as written
```

The first form produces `-File ""C:\...\doctor.ps1""` and PowerShell receives an
empty argument followed by garbage. The `set VAR=value` form (no quotes around
the whole assignment) is the only one that preserves inner quotes literally.

### 3. The Flutter SDK's own `sh` wrapper ships with CRLF (but only breaks one way)

Not a harness bug, but one that makes the harness look broken, so it is detected
and reported rather than passed through.

`bin/flutter` is a bash wrapper that sources `bin/internal/shared.sh`, and in the
**Windows distribution of the SDK that file carries CRLF line endings** (283 CR
bytes in Flutter 3.41.6, measured).

The interesting part is who it actually breaks, because the obvious reading is
wrong. Verified by running both:

| Shell | Result |
|-------|--------|
| **Git for Windows (Git Bash / MSYS / MinGW)** | **Works.** MSYS bash tolerates the CR; the wrapper runs normally. |
| **WSL, or Linux/macOS bash reaching a Windows SDK** | **Broken.** Dies immediately: |

```
$ flutter --version
/mnt/c/flutter/flutter/bin/internal/shared.sh: line 5: $'\r': command not found
```

So the real symptom is not "flutter works in cmd but not Git Bash". It is
"flutter works in cmd **and** in Git Bash, but not from WSL". That distinction
matters: an earlier version of this harness warned about the CRLF under Git Bash
too, which was a false alarm in the shell most Windows users are actually in.

**Harness behaviour:**
- Under **MSYS** (`uname -s` is `MINGW*`/`MSYS*`/`CYGWIN*`), the bash wrapper is
  trusted and nothing is reported. `flutter.bat` is not even reachable by name
  here: MSYS does not apply `PATHEXT` to `command -v`, so `command -v flutter.bat`
  returns empty while the file sits in the same directory.
- Under a **POSIX shell that is not MSYS**, the wrapper is checked, and a CR in
  `bin/internal/shared.sh` is a genuine FAIL with the repair command.
- `flutter-doctor` check 26 answers "can this shell run the Flutter entry point?",
  so it reports OK on Git Bash and FAIL on WSL, for the same SDK.

Repair the SDK once and the wrapper works everywhere:

```bash
find "$FLUTTER_ROOT/bin" -name '*.sh' -exec sed -i 's/\r$//' {} +
```

```powershell
Get-ChildItem "$env:FLUTTER_ROOT\bin" -Recurse -Filter *.sh |
  ForEach-Object {
    (Get-Content $_.FullName -Raw) -replace "`r`n", "`n" |
      Set-Content -NoNewline $_.FullName
  }
```

Override detection with `HARNESS_FLUTTER` / `HARNESS_DART` if you have an
unusual layout.

### 4. A CRLF hook is a dead hook

If `.githooks/pre-commit` is checked out with CRLF, the shebang line becomes
`#!/bin/sh\r`. Git for Windows then looks for an interpreter literally named
`/bin/sh\r` and reports something unrelated to line endings.

`text=auto` alone does not save you: on a clone where `core.autocrlf=true`, git
would still convert these files on checkout. So `.gitattributes` pins them
explicitly, and the doctor checks for it:

```
* text=auto eol=lf
.githooks/*   text eol=lf
scripts/**    text eol=lf
```

`flutter-doctor` check 23 reads the first line of each hook and FAILs on a CR.

---

## Shell cheat sheet

| Task | PowerShell | cmd.exe | Git Bash |
|------|-----------|---------|----------|
| Run the gates | `powershell -ExecutionPolicy Bypass -File .githooks\pre-commit.ps1` | `.githooks\pre-commit.cmd` | `sh .githooks/pre-commit` |
| Dry run | `... -DryRun` | `.githooks\pre-commit.cmd /dry-run` | `sh .githooks/pre-commit --dry-run` |
| Doctor | `powershell -ExecutionPolicy Bypass -File scripts\doctor.ps1` | `scripts\doctor.cmd` | `sh scripts/doctor.sh` |
| Doctor as JSON | `... -Json` | `scripts\doctor.cmd /json` | `sh scripts/doctor.sh --json` |
| Set env var | `$env:HARNESS_DEVICE_OK = '1'` | `set HARNESS_DEVICE_OK=1` | `export HARNESS_DEVICE_OK=1` |
| Set profile | `$env:HARNESS_PROFILE = 'minimal'` | `set HARNESS_PROFILE=minimal` | `export HARNESS_PROFILE=minimal` |

### Environment variables

| Variable | Effect |
|----------|--------|
| `HARNESS_PROFILE` | `minimal` / `standard` / `strict` when no `.githooks/.profile` exists |
| `HARNESS_DEVICE_OK` | `1` pre-answers the pre-push "tested on a real device?" prompt |
| `HARNESS_SKIP_BUILD` | `1` skips the `build` gate and prints a loud warning that it did |
| `HARNESS_FLUTTER` | Override the `flutter` binary |
| `HARNESS_DART` | Override the `dart` binary |

---

## Output encoding

`cmd.exe` defaults to a legacy codepage (CP850/CP437 in much of the world,
CP1252 elsewhere) and will happily turn box-drawing characters and em dashes
into mojibake. Every status line the harness prints is therefore **ASCII only**:
`[OK]`, `[WARN]`, `[FAIL]`, `->`, and `-` instead of `—`. `gates.def` is ASCII
too, because `for /f` parses it under that same codepage.

This is a deliberate constraint, not an oversight. If you add output to a script
that runs under `cmd.exe`, keep it ASCII.

---

## Exit codes

All three implementations agree, and the wrappers propagate rather than swallow:

| Code | Meaning |
|------|---------|
| `0` | every gate passed, or was skipped with a reason |
| `1` | at least one gate failed |
| `2` | bad usage (unknown flag) |

Note that a `.cmd` wrapper must `call` the inner script, not run it bare —
running a batch file without `call` transfers control and never comes back:

```bat
call "%~dp0lib\quality.cmd" /stage:pre-commit %*
exit /b %ERRORLEVEL%
```

---

## Line endings, everywhere

`.gitattributes` is load-bearing, not decoration. If you copy the harness into a
new repo, copy that file too. Then check it took effect:

```bash
git check-attr eol -- .githooks/pre-commit     # -> .githooks/pre-commit: eol: lf
```

If a hook already has CRLF and you cannot re-clone:

**PowerShell**
```powershell
$p = '.githooks\pre-commit'
[System.IO.File]::WriteAllText((Resolve-Path $p),
  ((Get-Content $p -Raw) -replace "`r`n", "`n"))
```

**Git Bash / WSL**
```bash
sed -i 's/\r$//' .githooks/pre-commit .githooks/pre-push
```

Then re-run `flutter-doctor` until check 23 is `[OK]`.
