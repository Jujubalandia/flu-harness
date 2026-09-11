@echo off
rem ---------------------------------------------------------------------------
rem  flu-harness destructive-operation guard - cmd.exe entry point.
rem
rem  Reads the Claude Code tool-call JSON on stdin and delegates to
rem  pre-tool-use.ps1. There is no batch implementation of the block list on
rem  purpose: writing 22 regular expressions in cmd.exe's pattern syntax would
rem  be a second, subtly different guard - and the one that drifts is the one
rem  that lets a force-push through.
rem
rem  Typical use from .claude\settings.json:
rem      cmd /c .claude\hooks\pre-tool-use.cmd
rem
rem  Exit: 0 allow, 2 block, 3 PowerShell unavailable.
rem ---------------------------------------------------------------------------

setlocal
rem Capture before any parsing: in cmd.exe a `shift` also moves %1 into %0,
rem which would make a later %~dp0 point at the wrong thing.
set "SELFDIR=%~dp0"

set "PS="
where pwsh.exe >nul 2>&1 && set "PS=pwsh.exe"
if not defined PS (
    where powershell.exe >nul 2>&1 && set "PS=powershell.exe"
)
if not defined PS (
    echo   [WARN] pre-tool-use.cmd: PowerShell not found - guard is INACTIVE. 1>&2
    echo          Use the .sh hook via Git Bash, or install PowerShell. 1>&2
    exit /b 3
)

rem `set VAR=value` (not `set "VAR=value"`) so the inner quotes survive.
set PSCMD=-NoProfile -ExecutionPolicy Bypass -File "%SELFDIR%pre-tool-use.ps1"

%PS% %PSCMD%
exit /b %ERRORLEVEL%
