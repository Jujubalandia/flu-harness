<#
.SYNOPSIS
  flu-harness quality gate runner (PowerShell).

.DESCRIPTION
  Runs the gate plan for a profile. Every gate is a plain Flutter/Dart CLI
  call, so this script needs nothing beyond the Flutter SDK and git.

  This is one of three implementations of the same contract:
      quality.sh    POSIX sh   - Git Bash on Windows, and any Unix shell
      quality.ps1   PowerShell - Windows PowerShell 5.1+ and PowerShell 7+
      quality.cmd   CMD        - cmd.exe on Windows
  All three read the same gates.def, so the plan cannot drift between shells.

  Targets Windows PowerShell 5.1 (shipped with Windows) and PowerShell 7+.
  Deliberately avoids PS7-only syntax.

.PARAMETER Stage
  pre-commit (default) or pre-push.

.PARAMETER Profile
  minimal | standard | strict. Defaults to .githooks/.profile, then $env:HARNESS_PROFILE,
  then strict.

.PARAMETER Def
  Explicit path to a gates.def.

.PARAMETER DryRun
  Print the resolved plan and exit. Output is byte-comparable with quality.sh
  and quality.cmd, which is how the test suite proves the three shells agree.

.PARAMETER Quiet
  Suppress the banner.

.PARAMETER ProjectDir
  Project root. Defaults to the git root, then this script's grandparent.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .githooks\lib\quality.ps1 -Stage pre-push
#>
[CmdletBinding()]
param(
    [ValidateSet('pre-commit', 'pre-push')]
    [string]$Stage = 'pre-commit',

    [string]$Profile = '',

    [string]$Def = '',

    [switch]$DryRun,

    [switch]$Quiet,

    [string]$ProjectDir = ''
)

$ErrorActionPreference = 'Continue'

# ── Project root ─────────────────────────────────────────────────────────────
function Resolve-ProjectDir {
    param([string]$Explicit, [string]$SelfDir)

    if ($Explicit) { return (Resolve-Path -LiteralPath $Explicit).Path }

    try {
        $top = & git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $top) {
            return ($top | Select-Object -First 1).ToString().Trim()
        }
    } catch { }

    # lib\ -> .githooks\ -> project root
    return (Resolve-Path -LiteralPath (Join-Path $SelfDir '..\..')).Path
}

$SelfDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$ProjectDir = Resolve-ProjectDir -Explicit $ProjectDir -SelfDir $SelfDir

# ── Resolve profile ──────────────────────────────────────────────────────────
if (-not $Profile) {
    $profileFile = Join-Path $ProjectDir '.githooks\.profile'
    if (Test-Path -LiteralPath $profileFile) {
        $Profile = (Get-Content -LiteralPath $profileFile -Raw).Trim()
    }
}
if (-not $Profile) { $Profile = $env:HARNESS_PROFILE }
if (-not $Profile) { $Profile = 'strict' }

# ── Resolve the gate plan ────────────────────────────────────────────────────
if (-not $Def) {
    $pluginGates = Join-Path $SelfDir "..\git-hooks\profiles\$Profile\gates.def"
    $candidates = @(
        (Join-Path $ProjectDir '.githooks\lib\gates.def'),
        (Join-Path $ProjectDir '.githooks\gates.def'),
        (Join-Path $SelfDir 'gates.def'),
        $pluginGates
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { $Def = (Resolve-Path -LiteralPath $c).Path; break }
    }
}

if (-not $Def -or -not (Test-Path -LiteralPath $Def)) {
    Write-Host "[FAIL] no gates.def found for profile ""$Profile""" -ForegroundColor Red
    Write-Host "       looked in $ProjectDir\.githooks\lib\ and $SelfDir" -ForegroundColor DarkGray
    exit 1
}

# ── Read the gate list for this stage ────────────────────────────────────────
$gates = @()
foreach ($line in (Get-Content -LiteralPath $Def)) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
    $parts = $trimmed.Split('=', 2)
    if ($parts.Count -ne 2) { continue }
    if ($parts[0].Trim() -eq $Stage) {
        $gates = $parts[1].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        break
    }
}

if ($gates.Count -eq 0) {
    Write-Host "[WARN] profile ""$Profile"" defines no gates for stage ""$Stage"" - nothing to do"
    exit 0
}

# ── Dry run ──────────────────────────────────────────────────────────────────
if ($DryRun) {
    Write-Output "profile=$Profile"
    Write-Output "stage=$Stage"
    Write-Output "def=$Def"
    foreach ($g in $gates) { Write-Output "gate=$g" }
    exit 0
}

function Say  { param([string]$m) if (-not $Quiet) { Write-Host $m } }
function Step { param([string]$m) if (-not $Quiet) { Write-Host "`n-> $m" } }

# ── Tool discovery ───────────────────────────────────────────────────────────
$Flutter = $null
foreach ($c in @('flutter', 'flutter.bat', 'flutter.ps1')) {
    if (Get-Command $c -ErrorAction SilentlyContinue) { $Flutter = $c; break }
}
$Dart = $null
foreach ($c in @('dart', 'dart.bat', 'dart.ps1')) {
    if (Get-Command $c -ErrorAction SilentlyContinue) { $Dart = $c; break }
}

$Failed  = $false
$Ran     = 0
$Skipped = 0

# ── Gate implementations ─────────────────────────────────────────────────────
function Invoke-Gate {
    param([string]$Gate)

    $script:Ran++

    switch ($Gate) {

        'format' {
            Step 'format - dart format --set-exit-if-changed'
            if (-not $Dart) { Say '   [SKIP] dart not found on PATH'; $script:Skipped++; return 0 }
            Push-Location $script:ProjectDir
            try { & $Dart format --output=none --set-exit-if-changed . } finally { Pop-Location }
            $rc = $LASTEXITCODE
            if ($rc -eq 0) { Say '   [OK] formatting clean' }
            else { Say '   [FAIL] formatting differs - run: dart format .'; $script:Failed = $true }
            return $rc
        }

        'analyze' {
            Step 'analyze - flutter analyze --fatal-infos --fatal-warnings'
            if (-not $Flutter) { Say '   [SKIP] flutter not found on PATH'; $script:Skipped++; return 0 }
            Push-Location $script:ProjectDir
            try { & $Flutter analyze --fatal-infos --fatal-warnings } finally { Pop-Location }
            $rc = $LASTEXITCODE
            if ($rc -eq 0) { Say '   [OK] no analyzer issues' }
            else { Say '   [FAIL] analyzer reported issues'; $script:Failed = $true }
            return $rc
        }

        'lint' {
            Step 'lint - project-configured linter'
            $ao = Join-Path $script:ProjectDir 'analysis_options.yaml'
            if (-not (Test-Path -LiteralPath $ao)) {
                Say '   [SKIP] no analysis_options.yaml'; $script:Skipped++; return 0
            }
            if (-not $Dart) { Say '   [SKIP] dart not found on PATH'; $script:Skipped++; return 0 }
            $aoText = Get-Content -LiteralPath $ao -Raw

            # dart_code_linter first: the maintained successor to the
            # discontinued dart_code_metrics, and where complexity thresholds
            # live. It exits 0 even on violations unless
            # --set-exit-on-violation-level is passed, so that flag is what makes
            # this a gate rather than a report.
            if ($aoText -match '(?m)^\s*dart_code_linter:') {
                Push-Location $script:ProjectDir
                try {
                    & $Dart run dart_code_linter:metrics analyze lib --set-exit-on-violation-level=warning --no-congratulate
                } finally { Pop-Location }
                $rc = $LASTEXITCODE
                if ($rc -eq 0) { Say '   [OK] metrics and anti-patterns clean' }
                else {
                    Say "   [FAIL] dart_code_linter reported violations (exit $rc)"
                    Say '          Refactor the flagged code. Never raise the threshold to pass.'
                    $script:Failed = $true
                }
                return $rc
            }

            if ($aoText -match '(?m)^\s*custom_lint:' -or $aoText -match '(?m)^\s*plugins:') {
                Say '   [WARN] custom_lint / analyzer-plugin rules configured.'
                Say '          custom_lint is no longer developed, and analyzer plugins need'
                Say '          Dart 3.10+, so this gate may be a no-op on your SDK.'
                Push-Location $script:ProjectDir
                try { & $Dart run custom_lint } finally { Pop-Location }
                $rc = $LASTEXITCODE
                if ($rc -eq 0) { Say '   [OK] custom lint clean' }
                else { Say '   [FAIL] custom lint reported issues'; $script:Failed = $true }
                return $rc
            }

            Say '   [SKIP] no dart_code_linter / custom_lint configured'
            Say '          To enable complexity gating, add to analysis_options.yaml:'
            Say '            dart_code_linter:'
            Say '              metrics:'
            Say '                cyclomatic-complexity: 20'
            Say '                maintainability-index: 50'
            $script:Skipped++
            return 0
        }

        'test' {
            Step 'test - flutter test'
            if (-not $Flutter) { Say '   [SKIP] flutter not found on PATH'; $script:Skipped++; return 0 }
            $hasTest = (Test-Path -LiteralPath (Join-Path $script:ProjectDir 'test')) -or
                       (Test-Path -LiteralPath (Join-Path $script:ProjectDir 'integration_test'))
            if (-not $hasTest) { Say '   [SKIP] no test\ directory yet'; $script:Skipped++; return 0 }
            Push-Location $script:ProjectDir
            try { & $Flutter test } finally { Pop-Location }
            $rc = $LASTEXITCODE
            if ($rc -eq 0) { Say '   [OK] tests passed' }
            else { Say '   [FAIL] tests failed'; $script:Failed = $true }
            return $rc
        }

        'build' {
            Step 'build - flutter build apk --debug (compile sanity)'
            if ($env:HARNESS_SKIP_BUILD -eq '1') {
                Say '   [SKIP] HARNESS_SKIP_BUILD=1 - the strongest gate is OFF'
                Say '          set it back to 0 before you trust a release build'
                $script:Skipped++; return 0
            }
            if (-not $Flutter) { Say '   [SKIP] flutter not found on PATH'; $script:Skipped++; return 0 }
            Push-Location $script:ProjectDir
            try { & $Flutter build apk --debug } finally { Pop-Location }
            $rc = $LASTEXITCODE
            if ($rc -eq 0) { Say '   [OK] debug APK built' }
            else { Say '   [FAIL] build failed (missing Android toolchain? see: flutter doctor)'; $script:Failed = $true }
            return $rc
        }

        default {
            Say "   [WARN] unknown gate ""$Gate"" in $Def - ignored"
            return 0
        }
    }
}

# ── Run ──────────────────────────────────────────────────────────────────────
Say ''
Say "flu-harness quality - profile: $Profile . stage: $Stage"
Say '----------------------------------------'

if (-not (Test-Path -LiteralPath (Join-Path $ProjectDir 'pubspec.yaml'))) {
    Write-Host "[FAIL] no pubspec.yaml in $ProjectDir - not a Flutter project root?" -ForegroundColor Red
    exit 1
}

foreach ($g in $gates) { Invoke-Gate -Gate $g | Out-Null }

# ── Pre-push: physical device confirmation ───────────────────────────────────
if ($Stage -eq 'pre-push') {
    $ans = $env:HARNESS_DEVICE_OK
    if (-not $ans) {
        # No console (IDE git panel, CI): do not hard-block a push the user
        # cannot answer, but say so loudly.
        if ([System.Console]::IsInputRedirected) {
            Say ''
            Say '   [WARN] no console to ask about physical-device testing.'
            Say '          Set HARNESS_DEVICE_OK=1 to pre-answer.'
            $ans = 'y'
        } else {
            $ans = Read-Host 'Ran the app on a real Android device? [y/N]'
        }
    }
    if ($ans -match '^(y|Y|yes|YES|1)$') {
        Say '   [OK] device check acknowledged'
    } else {
        Say '   [FAIL] run it on a physical Android device before pushing.'
        Say '          (or set HARNESS_DEVICE_OK=1 once you actually have)'
        $Failed = $true
    }
}

# ── Summary ──────────────────────────────────────────────────────────────────
Say ''
Say '----------------------------------------'
if (-not $Failed) {
    Say "OK - $Ran gates, $Skipped skipped"
    Say '----------------------------------------'
    exit 0
}
Say 'FAIL - gates above must pass'
Say '----------------------------------------'
exit 1
