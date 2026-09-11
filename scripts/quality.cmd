@echo off
rem ===========================================================================
rem  flu-harness quality gate runner (cmd.exe)
rem
rem  Runs the gate plan for a profile. Every gate is a plain Flutter/Dart CLI
rem  call, so this file needs nothing beyond the Flutter SDK and git.
rem
rem  This is one of three implementations of the same contract:
rem      quality.sh    POSIX sh   - Git Bash on Windows, and any Unix shell
rem      quality.ps1   PowerShell - Windows PowerShell 5.1+ and PowerShell 7+
rem      quality.cmd   CMD        - cmd.exe on Windows
rem  All three read the same gates.def, so the plan cannot drift between shells.
rem
rem  Usage:
rem      quality.cmd [/stage:pre-commit^|pre-push] [/profile:NAME] [/def:FILE]
rem                  [/dry-run] [/quiet] [/project:DIR]
rem
rem  Env:
rem      HARNESS_PROFILE     default profile when /profile is omitted
rem      HARNESS_SKIP_BUILD  =1 to skip the build gate (prints a loud warning)
rem      HARNESS_DEVICE_OK   =1 to answer "yes" to the pre-push device prompt
rem
rem  Exit: 0 = every gate passed (or was skipped), 1 = at least one gate failed.
rem ===========================================================================

setlocal enabledelayedexpansion

set "STAGE=pre-commit"
set "PROFILE="
set "DEF="
set "DRYRUN="
set "QUIET="
set "PROJECTDIR="
set "SELFDIR=%~dp0"

rem ── Parse arguments ────────────────────────────────────────────────────────
:parse
if "%~1"=="" goto parsed
set "ARG=%~1"
if /i "%ARG%"=="/dry-run"    set "DRYRUN=1" & shift & goto parse
if /i "%ARG%"=="--dry-run"   set "DRYRUN=1" & shift & goto parse
if /i "%ARG%"=="/quiet"      set "QUIET=1"  & shift & goto parse
if /i "%ARG%"=="--quiet"     set "QUIET=1"  & shift & goto parse
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

if /i "%KEY%"=="stage"      set "STAGE=%VAL%"      & shift & goto parse
if /i "%KEY%"=="profile"    set "PROFILE=%VAL%"    & shift & goto parse
if /i "%KEY%"=="def"        set "DEF=%VAL%"        & shift & goto parse
if /i "%KEY%"=="project"    set "PROJECTDIR=%VAL%" & shift & goto parse
if /i "%KEY%"=="projectdir" set "PROJECTDIR=%VAL%" & shift & goto parse

rem Anything that looks like a flag but matched nothing is a typo, not a path.
set "FIRSTCHAR=%ARG:~0,1%"
if "%FIRSTCHAR%"=="/" goto unknown_option
if "%FIRSTCHAR%"=="-" goto unknown_option

rem Bare argument: treat as project dir if we don't have one yet.
if "%PROJECTDIR%"=="" (
    set "PROJECTDIR=%ARG%"
    shift
    goto parse
)

:unknown_option
echo [FAIL] quality.cmd: unknown option "%ARG%" 1>&2
exit /b 2

:usage
echo.
echo   quality.cmd [/stage:pre-commit^|pre-push] [/profile:NAME] [/def:FILE]
echo               [/dry-run] [/quiet] [/project:DIR]
echo.
exit /b 0

:parsed

rem ── Project root ──────────────────────────────────────────────────────────
if "%PROJECTDIR%"=="" (
    for /f "delims=" %%T in ('git rev-parse --show-toplevel 2^>nul') do (
        if not defined PROJECTDIR set "PROJECTDIR=%%T"
    )
)
if "%PROJECTDIR%"=="" (
    rem lib\ -> .githooks\ -> project root
    pushd "%SELFDIR%..\.." >nul 2>&1 && ( set "PROJECTDIR=%CD%" & popd ) || set "PROJECTDIR=%SELFDIR%"
)
rem Normalise git's forward slashes for cmd.exe
set "PROJECTDIR=%PROJECTDIR:/=\%"

rem ── Resolve profile ───────────────────────────────────────────────────────
if "%PROFILE%"=="" (
    if exist "%PROJECTDIR%\.githooks\.profile" (
        set /p PROFILE=<"%PROJECTDIR%\.githooks\.profile"
    )
)
if "%PROFILE%"=="" if defined HARNESS_PROFILE set "PROFILE=%HARNESS_PROFILE%"
if "%PROFILE%"=="" set "PROFILE=strict"
rem strip stray whitespace/CR
for /f "tokens=* delims= " %%P in ("%PROFILE%") do set "PROFILE=%%P"

rem ── Resolve the gate plan ─────────────────────────────────────────────────
if "%DEF%"=="" (
    if exist "%PROJECTDIR%\.githooks\lib\gates.def" set "DEF=%PROJECTDIR%\.githooks\lib\gates.def"
)
if "%DEF%"=="" (
    if exist "%PROJECTDIR%\.githooks\gates.def" set "DEF=%PROJECTDIR%\.githooks\gates.def"
)
if "%DEF%"=="" (
    if exist "%SELFDIR%gates.def" set "DEF=%SELFDIR%gates.def"
)
if "%DEF%"=="" (
    if exist "%SELFDIR%..\git-hooks\profiles\%PROFILE%\gates.def" (
        set "DEF=%SELFDIR%..\git-hooks\profiles\%PROFILE%\gates.def"
    )
)

if "%DEF%"=="" (
    echo [FAIL] no gates.def found for profile "%PROFILE%"
    echo        looked in %PROJECTDIR%\.githooks\lib\ and %SELFDIR%
    exit /b 1
)

rem ── Read the gate list for this stage ─────────────────────────────────────
set "GATES="
for /f "usebackq tokens=1,* delims==" %%A in ("%DEF%") do (
    set "K=%%A"
    set "K=!K: =!"
    if /i "!K!"=="%STAGE%" set "GATES=%%B"
)

if not defined GATES (
    echo [WARN] profile "%PROFILE%" defines no gates for stage "%STAGE%" - nothing to do
    exit /b 0
)
rem commas and spaces are both CMD for-delimiters, so this splits cleanly
set "GATES=%GATES:,= %"

rem ── Dry run ───────────────────────────────────────────────────────────────
if defined DRYRUN (
    echo profile=%PROFILE%
    echo stage=%STAGE%
    echo def=%DEF%
    for %%G in (%GATES%) do echo gate=%%G
    exit /b 0
)

rem ── Tool discovery ────────────────────────────────────────────────────────
set "FLUTTER="
for %%C in (flutter flutter.bat) do (
    if not defined FLUTTER (
        where %%C >nul 2>&1 && set "FLUTTER=%%C"
    )
)
set "DART="
for %%C in (dart dart.bat) do (
    if not defined DART (
        where %%C >nul 2>&1 && set "DART=%%C"
    )
)

set "FAILED=0"
set "RAN=0"
set "SKIPPED=0"

echo.
echo flu-harness quality - profile: %PROFILE% . stage: %STAGE%
echo ----------------------------------------

if not exist "%PROJECTDIR%\pubspec.yaml" (
    echo [FAIL] no pubspec.yaml in %PROJECTDIR% - not a Flutter project root?
    exit /b 1
)

for %%G in (%GATES%) do call :run_gate %%G

rem ── Pre-push: physical device confirmation ────────────────────────────────
if /i not "%STAGE%"=="pre-push" goto summary

if defined HARNESS_DEVICE_OK (
    set "ANS=%HARNESS_DEVICE_OK%"
) else (
    set "ANS="
    set /p "ANS=Ran the app on a real Android device? [y/N] "
)
if /i "%ANS%"=="y"   goto device_ok
if /i "%ANS%"=="yes" goto device_ok
if "%ANS%"=="1"      goto device_ok
echo    [FAIL] run it on a physical Android device before pushing.
echo           ^(or set HARNESS_DEVICE_OK=1 once you actually have^)
set "FAILED=1"
goto summary
:device_ok
echo    [OK] device check acknowledged

:summary
echo.
echo ----------------------------------------
if "%FAILED%"=="0" (
    echo OK - %RAN% gates, %SKIPPED% skipped
    echo ----------------------------------------
    exit /b 0
)
echo FAIL - gates above must pass
echo ----------------------------------------
exit /b 1

rem ═══════════════════════════════════════════════════════════════════════════
rem  Gate implementations
rem ═══════════════════════════════════════════════════════════════════════════
:run_gate
set "GATE=%~1"
set /a RAN+=1

if /i "%GATE%"=="format"  goto gate_format
if /i "%GATE%"=="analyze" goto gate_analyze
if /i "%GATE%"=="lint"    goto gate_lint
if /i "%GATE%"=="test"    goto gate_test
if /i "%GATE%"=="build"   goto gate_build
echo    [WARN] unknown gate "%GATE%" in %DEF% - ignored
exit /b 0

:gate_format
echo.
echo -^> format - dart format --set-exit-if-changed
if not defined DART (
    echo    [SKIP] dart not found on PATH
    set /a SKIPPED+=1
    exit /b 0
)
pushd "%PROJECTDIR%"
call %DART% format --output=none --set-exit-if-changed .
set "RC=%ERRORLEVEL%"
popd
if "%RC%"=="0" (
    echo    [OK] formatting clean
    exit /b 0
)
echo    [FAIL] formatting differs - run: dart format .
set "FAILED=1"
exit /b %RC%

:gate_analyze
echo.
echo -^> analyze - flutter analyze --fatal-infos --fatal-warnings
if not defined FLUTTER (
    echo    [SKIP] flutter not found on PATH
    set /a SKIPPED+=1
    exit /b 0
)
pushd "%PROJECTDIR%"
call %FLUTTER% analyze --fatal-infos --fatal-warnings
set "RC=%ERRORLEVEL%"
popd
if "%RC%"=="0" (
    echo    [OK] no analyzer issues
    exit /b 0
)
echo    [FAIL] analyzer reported issues
set "FAILED=1"
exit /b %RC%

:gate_lint
echo.
echo -^> lint - project-configured linter
if not exist "%PROJECTDIR%\analysis_options.yaml" (
    echo    [SKIP] no analysis_options.yaml
    set /a SKIPPED+=1
    exit /b 0
)
if not defined DART (
    echo    [SKIP] dart not found on PATH
    set /a SKIPPED+=1
    exit /b 0
)
rem dart_code_linter first: the maintained successor to the discontinued
rem dart_code_metrics, and where complexity thresholds live. It exits 0 even on
rem violations unless --set-exit-on-violation-level is passed, so that flag is
rem what turns the report into a gate.
findstr /r /c:"^ *dart_code_linter:" "%PROJECTDIR%\analysis_options.yaml" >nul 2>&1
if not errorlevel 1 (
    pushd "%PROJECTDIR%"
    call %DART% run dart_code_linter:metrics analyze lib --set-exit-on-violation-level=warning --no-congratulate
    set "RC=%ERRORLEVEL%"
    popd
    if "%RC%"=="0" (
        echo    [OK] metrics and anti-patterns clean
        exit /b 0
    )
    echo    [FAIL] dart_code_linter reported violations ^(exit %RC%^)
    echo           Refactor the flagged code. Never raise the threshold to pass.
    set "FAILED=1"
    exit /b %RC%
)
findstr /i /c:"custom_lint:" /c:"plugins:" "%PROJECTDIR%\analysis_options.yaml" >nul 2>&1
if not errorlevel 1 (
    echo    [WARN] custom_lint / analyzer-plugin rules configured.
    echo           custom_lint is no longer developed, and analyzer plugins need
    echo           Dart 3.10+, so this gate may be a no-op on your SDK.
    pushd "%PROJECTDIR%"
    call %DART% run custom_lint
    set "RC=%ERRORLEVEL%"
    popd
    if "%RC%"=="0" (
        echo    [OK] custom lint clean
        exit /b 0
    )
    echo    [FAIL] custom lint reported issues
    set "FAILED=1"
    exit /b %RC%
)
echo    [SKIP] no dart_code_linter / custom_lint configured
echo           To enable complexity gating, add to analysis_options.yaml:
echo             dart_code_linter:
echo               metrics:
echo                 cyclomatic-complexity: 20
echo                 maintainability-index: 50
set /a SKIPPED+=1
exit /b 0

:gate_test
echo.
echo -^> test - flutter test
if not defined FLUTTER (
    echo    [SKIP] flutter not found on PATH
    set /a SKIPPED+=1
    exit /b 0
)
if not exist "%PROJECTDIR%\test" if not exist "%PROJECTDIR%\integration_test" (
    echo    [SKIP] no test\ directory yet
    set /a SKIPPED+=1
    exit /b 0
)
pushd "%PROJECTDIR%"
call %FLUTTER% test
set "RC=%ERRORLEVEL%"
popd
if "%RC%"=="0" (
    echo    [OK] tests passed
    exit /b 0
)
echo    [FAIL] tests failed
set "FAILED=1"
exit /b %RC%

:gate_build
echo.
echo -^> build - flutter build apk --debug ^(compile sanity^)
if "%HARNESS_SKIP_BUILD%"=="1" (
    echo    [SKIP] HARNESS_SKIP_BUILD=1 - the strongest gate is OFF
    echo           set it back to 0 before you trust a release build
    set /a SKIPPED+=1
    exit /b 0
)
if not defined FLUTTER (
    echo    [SKIP] flutter not found on PATH
    set /a SKIPPED+=1
    exit /b 0
)
pushd "%PROJECTDIR%"
call %FLUTTER% build apk --debug
set "RC=%ERRORLEVEL%"
popd
if "%RC%"=="0" (
    echo    [OK] debug APK built
    exit /b 0
)
echo    [FAIL] build failed ^(missing Android toolchain? see: flutter doctor^)
set "FAILED=1"
exit /b %RC%
