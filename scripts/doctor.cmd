@echo off
rem ===========================================================================
rem  flu-harness doctor - cmd.exe entry point.
rem
rem  There are two native implementations of the 26 checks:
rem      scripts\doctor.sh    POSIX sh   - Git Bash, Linux, macOS, WSL
rem      scripts\doctor.ps1   PowerShell - Windows PowerShell 5.1+ and PS 7+
rem
rem  Rather than maintain a third copy of the check list in batch - which is
rem  how the three drift apart - this wrapper locates PowerShell and runs the
rem  same doctor.ps1. Windows has shipped PowerShell since Windows 7, so this
rem  is available on every machine the harness supports.
rem
rem  Usage:
rem      scripts\doctor.cmd [/json] [/quiet] [/project:DIR]
rem
rem  Exit: 0 = no FAIL, 1 = at least one FAIL, 2 = PowerShell not found.
rem ===========================================================================

setlocal

rem ── Capture our own directory BEFORE parsing anything ─────────────────────
rem  This ordering is not style, it is correctness.
rem
rem  In cmd.exe, `shift` also moves %1 into %0. After the first shift, %0 is no
rem  longer this script's path - it is whatever argument came first - so a later
rem  %~dp0 silently expands to nonsense like "C:\project:C:\src\app\".
rem  Capturing %~dp0 up here, before any shift, is the only safe way to use it.
rem  (Observed on Windows 11 / cmd.exe 10.0.26100: `echo %~dp0` before a shift
rem  prints the script dir, after a shift prints the first argument.)
set "SELFDIR=%~dp0"

set "JSON="
set "QUIET="
set "PROJECTDIR="

:parse
if "%~1"=="" goto parsed
set "ARG=%~1"
if /i "%ARG%"=="/json"     set "JSON=1"  & shift & goto parse
if /i "%ARG%"=="-json"     set "JSON=1"  & shift & goto parse
if /i "%ARG%"=="/quiet"    set "QUIET=1" & shift & goto parse
if /i "%ARG%"=="-quiet"    set "QUIET=1" & shift & goto parse
if /i "%ARG%"=="/?"        goto usage
if /i "%ARG%"=="--help"    goto usage

set "KEY="
set "VAL="
for /f "tokens=1,* delims=:=" %%A in ("%ARG%") do (
    set "KEY=%%A"
    set "VAL=%%B"
)
set "KEY=%KEY:/=%"
set "KEY=%KEY:-=%"
if /i "%KEY%"=="project"    set "PROJECTDIR=%VAL%" & shift & goto parse
if /i "%KEY%"=="projectdir" set "PROJECTDIR=%VAL%" & shift & goto parse

set "FIRSTCHAR=%ARG:~0,1%"
if "%FIRSTCHAR%"=="/" goto unknown
if "%FIRSTCHAR%"=="-" goto unknown
if "%PROJECTDIR%"=="" (
    set "PROJECTDIR=%ARG%"
    shift
    goto parse
)

:unknown
echo [FAIL] doctor.cmd: unknown option "%ARG%" 1>&2
exit /b 2

:usage
echo.
echo   doctor.cmd [/json] [/quiet] [/project:DIR]
echo.
exit /b 0

:parsed

rem ── Locate PowerShell ─────────────────────────────────────────────────────
set "PS="
where pwsh.exe >nul 2>&1 && set "PS=pwsh.exe"
if not defined PS (
    where powershell.exe >nul 2>&1 && set "PS=powershell.exe"
)
if not defined PS (
    echo [FAIL] doctor.cmd: PowerShell not found ^(neither pwsh.exe nor powershell.exe^) 1>&2
    echo        Use scripts\doctor.sh from Git Bash instead. 1>&2
    exit /b 2
)

rem ── Build the argument list ───────────────────────────────────────────────
rem  Note the deliberate `set VAR=value` form instead of `set "VAR=value"`.
rem  The quoted form strips only the outermost pair, so inner "" would survive
rem  as two literal quote characters and PowerShell would receive a mangled
rem  -File argument. Writing the quotes plainly is the only form that works.
set PSARGS=-NoProfile -ExecutionPolicy Bypass -File "%SELFDIR%doctor.ps1"
if defined JSON       set PSARGS=%PSARGS% -Json
if defined QUIET      set PSARGS=%PSARGS% -Quiet
if defined PROJECTDIR set PSARGS=%PSARGS% -ProjectDir "%PROJECTDIR%"

%PS% %PSARGS%
exit /b %ERRORLEVEL%
