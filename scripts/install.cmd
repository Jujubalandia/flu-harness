@echo off
rem ---------------------------------------------------------------------------
rem  flu-harness installer - cmd.exe entry point.
rem
rem  Finds PowerShell and runs install.ps1. There is no third implementation of
rem  the install logic on purpose: three copies of "which files go where" is how
rem  a Windows install ends up with a different layout from a Git Bash one.
rem
rem  Usage:
rem      install.cmd [/prefix:DIR] [/from:DIR] [/force] [/uninstall]
rem
rem  Exit: 0 success, 1 failure, 2 PowerShell not found.
rem ---------------------------------------------------------------------------

setlocal
rem Capture before any parsing: in cmd.exe a `shift` also moves %1 into %0,
rem which would make a later %~dp0 point at the wrong thing.
set "SELFDIR=%~dp0"

set "PREFIX="
set "FROM="
set "FORCE="
set "UNINSTALL="

:parse
if "%~1"=="" goto parsed
set "ARG=%~1"
if /i "%ARG%"=="/force"      set "FORCE=1"     & shift & goto parse
if /i "%ARG%"=="/uninstall"  set "UNINSTALL=1" & shift & goto parse
if /i "%ARG%"=="/?"          goto usage
if /i "%ARG%"=="--help"      goto usage

set "KEY="
set "VAL="
for /f "tokens=1,* delims=:=" %%A in ("%ARG%") do (
    set "KEY=%%A"
    set "VAL=%%B"
)
set "KEY=%KEY:/=%"
set "KEY=%KEY:-=%"
if /i "%KEY%"=="prefix" set "PREFIX=%VAL%" & shift & goto parse
if /i "%KEY%"=="from"   set "FROM=%VAL%"   & shift & goto parse

set "FIRSTCHAR=%ARG:~0,1%"
if "%FIRSTCHAR%"=="/" goto unknown
if "%FIRSTCHAR%"=="-" goto unknown
echo [FAIL] install.cmd: unexpected argument "%ARG%" 1>&2
exit /b 2

:unknown
echo [FAIL] install.cmd: unknown option "%ARG%" 1>&2
exit /b 2

:usage
echo.
echo   install.cmd [/prefix:DIR] [/from:DIR] [/force] [/uninstall]
echo.
exit /b 0

:parsed

set "PS="
where pwsh.exe >nul 2>&1 && set "PS=pwsh.exe"
if not defined PS (
    where powershell.exe >nul 2>&1 && set "PS=powershell.exe"
)
if not defined PS (
    echo [FAIL] install.cmd: PowerShell not found ^(neither pwsh.exe nor powershell.exe^) 1>&2
    echo        Use scripts\install.sh from Git Bash instead. 1>&2
    exit /b 2
)

rem `set VAR=value` (not `set "VAR=value"`) so the inner quotes survive verbatim.
set PSARGS=-NoProfile -ExecutionPolicy Bypass -File "%SELFDIR%install.ps1"
if defined PREFIX    set PSARGS=%PSARGS% -Prefix "%PREFIX%"
if defined FROM      set PSARGS=%PSARGS% -From "%FROM%"
if defined FORCE     set PSARGS=%PSARGS% -Force
if defined UNINSTALL set PSARGS=%PSARGS% -Uninstall

%PS% %PSARGS%
exit /b %ERRORLEVEL%
