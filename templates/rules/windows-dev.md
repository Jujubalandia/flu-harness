---
description: Windows development rules for a Flutter project used from PowerShell, cmd.exe and Git Bash, covering line endings, git hooks, the Flutter SDK sh wrapper, cmd.exe quoting traps, execution policy, PowerShell version floors, path and long-path limits, antivirus exclusions and Developer Mode. Load before writing scripts, hooks or build config that has to work on Windows.
globs: ["**/*.dart", "lib/**/*.dart"]
alwaysApply: false
---

# Windows development (PowerShell, cmd.exe, Git Bash)

Flutter on Windows means three shells that disagree about quoting, path separators, exit codes and even about what `%~dp0` means. Nothing below is theoretical: each item is a failure that looks like something else, which is why the fix has to be mechanical rather than remembered.

## 1. Which shell runs what

Git never runs your hook through PowerShell or cmd. On Windows it hands the hook to the `sh.exe` bundled with Git for Windows, so hooks are POSIX `sh` no matter which terminal you committed from. That single fact causes the CRLF problem in the next section.

| File | Runs under | Invoked by |
|------|-----------|------------|
| `.githooks/pre-commit` | Git for Windows' own `sh.exe` | git, automatically, from any shell |
| `.githooks/pre-commit.ps1` | PowerShell 5.1+ | you, by hand |
| `.githooks/pre-commit.cmd` | cmd.exe | you, by hand, or a `.cmd` wrapper |

## 2. Line endings: a CRLF hook is a dead hook

If a hook is checked out with CRLF its shebang is literally `#!/bin/sh\r`, and git looks for an interpreter named `/bin/sh\r`. The error names the shell, never line endings:
```
/bin/sh^M: bad interpreter: No such file or directory
```
`text=auto` alone is not enough: on a clone with `core.autocrlf=true`, git still converts on checkout. Pin it in `.gitattributes`, which is load-bearing configuration rather than decoration:
```
* text=auto eol=lf
.githooks/*   text eol=lf
scripts/**    text eol=lf
*.ps1 text eol=crlf
*.cmd text eol=crlf
```
Verify that git applies it per file instead of assuming, then renormalise anything already committed wrong:
```bash
git check-attr eol -- .githooks/pre-commit    # -> .githooks/pre-commit: eol: lf
git add --renormalize . && git commit -m "Normalise line endings"
```
Repairing just the working copy, in either shell:
```bash
sed -i 's/\r$//' .githooks/pre-commit .githooks/pre-push
```
```powershell
$p = '.githooks\pre-commit'
[System.IO.File]::WriteAllText((Resolve-Path $p).Path,
  ((Get-Content $p -Raw) -replace "`r`n", "`n"))
```
Do not reach for `Set-Content` or `Out-File` here; section 9 explains why.

## 3. The Flutter SDK's own sh wrapper ships with CRLF (and who it actually breaks)

`bin/flutter` is a bash wrapper that sources `bin/internal/shared.sh`, and in the Windows distribution that file carries CRLF line endings (283 CR bytes in Flutter 3.41.6, measured rather than assumed).

**Whether that matters depends on which `sh` you are.** This was established by running both, because the obvious reading is wrong:

| Shell | Result |
|-------|--------|
| Git for Windows (MSYS/MinGW, i.e. Git Bash) | **Works.** MSYS bash tolerates the CR and the wrapper runs normally. |
| WSL, or any Linux/macOS bash | **Broken.** Dies before doing anything: |
```
internal/shared.sh: line 5: $'\r': command not found
```

So the symptom is not "flutter works in cmd but not in Git Bash". It is "flutter works in cmd and in Git Bash, but not from WSL". If you are in Git Bash and someone reports this error, they are in WSL, or on a Linux shell reaching a Windows SDK through `/mnt/c`.

What to do:

- **Git Bash / MSYS**: nothing. The wrapper is fine. Do not "repair" the SDK chasing a warning.
- **WSL or Linux bash**: repair the SDK once, or run the gates from PowerShell or cmd, which use `flutter.bat`.

```bash
find "$FLUTTER_ROOT/bin" -name '*.sh' -exec sed -i 's/\r$//' {} +
```
```powershell
Get-ChildItem (Split-Path (Get-Command flutter.bat).Source -Parent) -Recurse -Filter *.sh |
  ForEach-Object { [System.IO.File]::WriteAllText($_.FullName,
    ((Get-Content $_.FullName -Raw) -replace "`r`n", "`n")) }
```
A `flutter upgrade` can restore the CRLF, so re-check after upgrading rather than debugging it twice.

One detection gotcha: under MSYS, `command -v flutter` returns the extensionless wrapper and `command -v flutter.bat` returns nothing, even though `flutter.bat` sits in the same directory. MSYS does not apply PATHEXT to `command -v`. A script therefore cannot "prefer flutter.bat" on Git Bash by probing for it; it has to branch on `uname -s` and trust the wrapper, which is what `quality.sh` and `doctor.sh` do.

## 4. cmd.exe: `shift` moves `%1` into `%0`, destroying `%~dp0`

`%~dp0` means "drive and path of the script being run". After a `shift`, `%0` holds the old `%1`, so `%~dp0` silently becomes the first argument's directory. The script works perfectly until someone passes a flag:
```bat
echo before: %~dp0   ->  C:\work\project\
shift
echo after:  %~dp0   ->  C:\project:C:\src\app\
```
The mangled value then reaches PowerShell, which blames the path rather than the cause:
```
The argument 'C:\project:C:\src\app\doctor.ps1' to the -File parameter does not exist.
```
Capture the script directory on the first lines, before parsing anything that can shift, and use that variable everywhere below:
```bat
@echo off
setlocal
set "SELFDIR=%~dp0"
rem ... only now parse arguments, which may shift %0 along with them ...
```

## 5. cmd.exe: `set "VAR=value"` strips only the outer quotes

The form that looks safest is the one that corrupts the value. `set "X=..."` removes the outer quotes and keeps everything inside literally, so doubled inner quotes stay doubled:
```bat
rem WRONG: PSARGS becomes  -File ""C:\work\project\doctor.ps1""
set "PSARGS=-File ""%SELFDIR%doctor.ps1"""

rem RIGHT: quotes survive exactly as written
set PSARGS=-File "%SELFDIR%doctor.ps1"
```
PowerShell then receives an empty argument followed by garbage and reports a `-File` failure, or runs the script with no parameters. The unquoted `set VAR=value` form is the only one that preserves embedded quotes literally. Trailing whitespace counts too, so never put a space before the `=` or after the value.

## 6. cmd.exe: a batch file must be invoked with `call`

Running a batch file from a batch file without `call` transfers control instead of calling it: the outer script never resumes, its cleanup is skipped, and its exit code handling never runs.
```bat
rem WRONG - control never comes back to this script
"%~dp0lib\quality.cmd" /stage:pre-commit

rem RIGHT - call it, then propagate the exit code deliberately
call "%~dp0lib\quality.cmd" /stage:pre-commit %*
exit /b %ERRORLEVEL%
```
`%ERRORLEVEL%` must be read before any other command runs, and inside a `(` `)` block it is expanded at parse time - use `setlocal enabledelayedexpansion` with `!ERRORLEVEL!` there. Always `exit /b`, never bare `exit`, which closes the user's console window.

## 7. PowerShell: execution policy and how to invoke a script

Script execution is blocked by default on client Windows, and a `.ps1` file has no run association, so double-clicking opens an editor or flashes a window and closes. Invoke it explicitly, with the bypass scoped to that one process:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .githooks\pre-commit.ps1
```
- `-NoProfile` keeps a user's aliases and profile functions out of your gate, which is the difference between a reproducible build and a local-only one.
- `-File` takes a script path plus parameters. Do not use `-Command` with a path: quoting rules differ and exit codes get swallowed.
- `-ExecutionPolicy Bypass` affects that process only and does not weaken the machine policy; `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` is the interactive alternative.
- A script downloaded from the internet is also blocked by the Zone.Identifier mark; `Unblock-File .\script.ps1` clears it.

## 8. Write PowerShell for 5.1, which is still the floor

Windows PowerShell 5.1 ships with Windows and may be the only `powershell.exe` on a machine; `pwsh` (7+) is a separate install. 5.1 has no null-coalescing operator, no ternary operator and no parallel pipeline:
```powershell
# WRONG on 5.1 - these are parse errors, not graceful fallbacks
$path  = $env:FLUTTER_ROOT ?? 'C:\flutter'
$label = $isDebug ? 'Debug' : 'Release'
1..10 | ForEach-Object -Parallel { $_ }

# RIGHT on 5.1, and still valid on 7+
$path  = if ($env:FLUTTER_ROOT) { $env:FLUTTER_ROOT } else { 'C:\flutter' }
$label = if ($isDebug) { 'Debug' } else { 'Release' }
```
Also missing on 5.1: the `&&` and `||` pipeline chain operators, `Get-Error`, `Test-Json`, and `ConvertFrom-Json -AsHashtable`. Treat 5.1 as the floor and the same script runs everywhere.

## 9. Writing LF-only files from PowerShell

`Set-Content` and `Out-File` join array elements with the platform newline, which is CRLF on Windows; `-NoNewline` only removes the final one. Windows PowerShell 5.1 also writes UTF-16LE by default, and a UTF-16 BOM breaks a shebang just as effectively as CRLF does.
```powershell
# WRONG - CRLF, and on 5.1 a UTF-16LE file with a BOM
$lines | Set-Content .githooks\pre-commit

# RIGHT - LF, UTF-8 without BOM, byte for byte
$text = "#!/bin/sh`nset -eu`n"
[System.IO.File]::WriteAllText((Join-Path $PWD '.githooks\pre-commit'), $text,
  (New-Object System.Text.UTF8Encoding($false)))
```
PowerShell 7 has `Set-Content -Encoding utf8NoBOM`, but 5.1 does not, so the .NET call is the portable form. Assert the result with `git check-attr eol -- <path>` and a look at the first line, rather than trusting the writer.

## 10. Console encoding: keep tool output ASCII

cmd.exe defaults to a legacy code page (CP850, CP437 or CP1252 depending on locale) and renders box-drawing characters, em dashes and accented text as mojibake - and a script that greps its own output can then fail to match its own messages.
- Print `[OK]`, `[WARN]`, `[FAIL]`, `->` and `-`. No emoji, no em dashes, no smart quotes, not even inside echoed comments.
- `chcp 65001` switches a console to UTF-8, but it is per console, does not survive a new window, and interacts badly with some PowerShell 5.1 redirection paths. Depend on ASCII output instead.
- Set `[Console]::OutputEncoding` only when you must print non-ASCII, and still expect the user's console font to be the next limit.

## 11. Path separators in Dart and Flutter

Dart accepts `/` on Windows and Flutter tooling normalises them, so forward slashes are the portable choice in Dart source and in `pubspec.yaml` asset paths.
```dart
// WRONG - needs escaping to survive review, and breaks on a non-Windows host
final file = File(appDir + '\\exports\\report.csv');

// RIGHT - forward slashes, or better, let package:path build it
final file = File('$appDir/exports/report.csv');
final file = File(p.join(appDir, 'exports', 'report.csv'));
```
Never hand-concatenate separators and never hardcode a drive letter or `C:\Users\...`. Use `path_provider` (`getApplicationDocumentsDirectory`, `getTemporaryDirectory`, `getApplicationSupportDirectory`) for writable locations, `p.join` / `p.normalize` / `p.basename` for manipulation, and `Uri.file(path)` or `Uri.parse(url).toFilePath()` at the boundary between a URL and a filesystem path.

## 12. Long paths: Flutter build directories nest deep

`.dart_tool\flutter_build\...` and `build\app\intermediates\...` under a `C:\Users\<name>\Documents\projects\...` checkout pass the 260-character limit, and the failure appears as "file not found" for a path that plainly exists.
```powershell
git config --system core.longpaths true    # needs an elevated shell
```
Set `HKLM\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled` (DWORD) to `1`: that registry value is what lifts the Win32 limit, and the Group Policy equivalent is "Computer Configuration > Administrative Templates > System > Filesystem > Enable Win32 long paths". Some tools still do not opt in, so also keep project roots short: `C:\src\<project>` beats a deep Documents tree, and the same applies to the Pub and Gradle caches.

## 13. Antivirus and Windows Defender slow every Gradle build

Real-time scanning inspects every file Gradle, the Kotlin compiler and Dart write, which turns a 40-second build into three minutes and occasionally produces "the process cannot access the file because it is being used by another process".
```powershell
Add-MpPreference -ExclusionPath 'C:\src\<project>'          # elevated shell
Add-MpPreference -ExclusionPath "$env:USERPROFILE\.gradle"
Add-MpPreference -ExclusionPath "$env:LOCALAPPDATA\Pub\Cache"
```
Excluding the caches is the highest-leverage part; excluding only the project gets you perhaps half the win. If corporate policy manages Defender, request the exclusions rather than disabling protection, and configure the same list in any third-party AV.

## 14. Developer Mode is required for Flutter's symlink support

Flutter creates symlinks for plugins (`.plugin_symlinks` and the Windows plugin registration), and creating a symlink without Developer Mode fails. The error is explicit:
```
Building with plugins requires symlink support.
Please enable Developer Mode in your system settings.
Run start ms-settings:developers to open settings.
```
```powershell
start ms-settings:developers   # Settings > System > For developers > Developer Mode: On
```
Check this first when a fresh Windows machine builds a plain app but not one with plugins. It has nothing to do with your code.

## 15. Common mistakes

| Symptom | Cause | Fix |
|---------|-------|-----|
| `bad interpreter: No such file or directory` on `git commit` | hook checked out with CRLF, shebang is `#!/bin/sh\r` | `eol=lf` for `.githooks/*` in `.gitattributes`, then `git add --renormalize .` |
| `$'\r': command not found` from `bin/internal/shared.sh` | the Windows SDK's `.sh` files ship with CRLF, and you are in WSL or Linux bash (Git Bash tolerates it) | run the gates from PowerShell or cmd, or strip CR from `$FLUTTER_ROOT/bin/**/*.sh` |
| `The argument 'C:\project:C:\src\app\x.ps1' to the -File parameter does not exist` | `%~dp0` read after a `shift` | `set "SELFDIR=%~dp0"` first, before parsing arguments |
| PowerShell gets an empty argument then garbage | `set "VAR=-File ""%~dp0x.ps1"""` keeps doubled quotes | `set VAR=-File "%SELFDIR%x.ps1"` |
| a `.cmd` wrapper runs one stage and the console closes | batch file invoked without `call` | `call ...` then `exit /b %ERRORLEVEL%` |
| `cannot be loaded because running scripts is disabled` | execution policy blocks `.ps1` | `powershell -NoProfile -ExecutionPolicy Bypass -File script.ps1` |
| double-clicking a `.ps1` does nothing useful | there is no run association for script files | always invoke with `-File` from a shell |
| `??` or `? :` is a parse error on a build machine | that machine only has Windows PowerShell 5.1 | write `if (...) { } else { }`; treat 5.1 as the floor |
| a generated hook is still rejected by git | `Set-Content` wrote CRLF, or 5.1 wrote UTF-16LE with a BOM | `[System.IO.File]::WriteAllText` with `UTF8Encoding($false)` |
| file operations fail on a path containing a backslash | separators concatenated by hand | `/` in Dart strings, `package:path` to join, `path_provider` for locations |
| `The filename or extension is too long` from a build | deep project path plus nested build dirs | `core.longpaths true`, `LongPathsEnabled=1`, short project root |
| Gradle builds take minutes | Defender scanning the caches | exclude project, `.gradle`, `.android`, Pub cache, SDK |
| `Building with plugins requires symlink support` | Developer Mode is off | `start ms-settings:developers` and enable it |
