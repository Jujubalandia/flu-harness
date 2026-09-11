<#
.SYNOPSIS
  flu-harness doctor - health checks for a Flutter project (PowerShell).

.DESCRIPTION
  Implements the identical check list as scripts/doctor.sh, so a Windows user in
  PowerShell and a macOS user in zsh get the same 26 answers. tests/test.ps1
  asserts the two agree on the check count.

  Read-only: it never edits your project. Every FAIL ships with the exact fix.

  Targets Windows PowerShell 5.1 (shipped with Windows) and PowerShell 7+.
  Deliberately avoids PS7-only syntax so it runs on a stock Windows box.

.PARAMETER Json
  Emit a single JSON object instead of the human-readable report.

.PARAMETER Quiet
  Print only FAILs.

.PARAMETER ProjectDir
  Project root. Defaults to the current directory.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\doctor.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\doctor.ps1 -Json | ConvertFrom-Json
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$Quiet,
    [string]$ProjectDir = '.'
)

$ErrorActionPreference = 'Continue'

$TotalChecks = 26
$OkCount   = 0
$WarnCount = 0
$FailCount = 0
$Results   = New-Object System.Collections.ArrayList

function Out-Check {
    param(
        [int]$N,
        [ValidateSet('OK', 'WARN', 'FAIL')][string]$Level,
        [string]$Msg,
        [string]$Fix = ''
    )
    switch ($Level) {
        'OK'   { $script:OkCount++ }
        'WARN' { $script:WarnCount++ }
        'FAIL' { $script:FailCount++ }
    }
    [void]$script:Results.Add([ordered]@{ n = $N; level = $Level; msg = $Msg; fix = $Fix })

    if ($Json) { return }
    if ($Quiet -and $Level -ne 'FAIL') { return }

    switch ($Level) {
        'OK'   { Write-Host "  [OK]   $Msg" -ForegroundColor Green }
        'WARN' { Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }
        'FAIL' {
            Write-Host "  [FAIL] $Msg" -ForegroundColor Red
            Write-Host "         fix: $Fix" -ForegroundColor DarkGray
        }
    }
}

function Write-Section {
    param([string]$Title)
    if ($Json -or $Quiet) { return }
    Write-Host ""
    Write-Host "  -- $Title --" -ForegroundColor Cyan
}

if (-not (Test-Path -LiteralPath $ProjectDir)) {
    Write-Error "doctor.ps1: not a directory: $ProjectDir"
    exit 2
}
$ProjectDir = (Resolve-Path -LiteralPath $ProjectDir).Path

if (-not $Json -and -not $Quiet) {
    Write-Host ""
    Write-Host "flu-harness doctor  ($TotalChecks checks)"
    Write-Host "========================================"
}

# ── Environment ──────────────────────────────────────────────────────────────
Write-Section 'Environment'

$Flutter = $null
foreach ($c in @('flutter', 'flutter.bat', 'flutter.ps1')) {
    $cmd = Get-Command $c -ErrorAction SilentlyContinue
    if ($cmd) { $Flutter = $cmd; break }
}

$FlutterVersion = $null
$FlutterVerNum  = $null
$FlutterChannel = $null
if ($Flutter) {
    $raw = (& $Flutter.Source --version 2>$null | Select-Object -First 1)
    if ($raw) { $FlutterVersion = $raw.ToString().Trim() }
    if ($FlutterVersion -match 'Flutter\s+(\d+\.\d+\.\d+)') { $FlutterVerNum = $Matches[1] }
    if ($FlutterVersion -match 'channel\s+(\w+)')            { $FlutterChannel = $Matches[1] }

    if ($FlutterVerNum) {
        Out-Check 1 'OK' "flutter $FlutterVerNum on PATH (channel: $(if ($FlutterChannel) { $FlutterChannel } else { 'unknown' }))"
    } else {
        Out-Check 1 'WARN' "'$($Flutter.Name)' found but did not report a version - the wrapper may be broken" "Try: flutter --version - if it prints a `$'\r' error, see check 26"
    }
} else {
    Out-Check 1 'FAIL' 'flutter not found on PATH' 'Install the SDK: https://docs.flutter.dev/install - then reopen your shell'
}

if ($FlutterVerNum) {
    $parts = $FlutterVerNum.Split('.')
    $fMaj = [int]$parts[0]; $fMin = [int]$parts[1]
    if ($fMaj -gt 3 -or ($fMaj -eq 3 -and $fMin -ge 35)) {
        Out-Check 2 'OK' "Flutter $FlutterVerNum meets the 3.35 baseline"
    } else {
        Out-Check 2 'WARN' "Flutter $FlutterVerNum is older than the 3.35 baseline" 'flutter upgrade'
    }
} else {
    Out-Check 2 'WARN' 'Flutter version undetermined' 'flutter --version'
}

$Dart = $null
foreach ($c in @('dart', 'dart.bat', 'dart.ps1')) {
    $cmd = Get-Command $c -ErrorAction SilentlyContinue
    if ($cmd) { $Dart = $cmd; break }
}
if ($Dart) {
    $dartLine = (& $Dart.Source --version 2>&1 | Select-String -Pattern 'Dart SDK' | Select-Object -First 1)
    if (-not $dartLine) { $dartLine = (& $Dart.Source --version 2>&1 | Select-Object -First 1) }
    Out-Check 3 'OK' ("$dartLine".Trim())
} else {
    Out-Check 3 'FAIL' 'dart not found on PATH (ships with the Flutter SDK)' 'Add <flutter-sdk>\bin to PATH'
}

$Git = Get-Command git -ErrorAction SilentlyContinue
if ($Git) {
    $gv = (& git --version 2>$null) -replace 'git version ', ''
    Out-Check 4 'OK' "git $($gv.Trim()) installed"
} else {
    Out-Check 4 'FAIL' 'git not found' 'https://git-scm.com/downloads'
}

$AndroidSdk = $env:ANDROID_HOME
if (-not $AndroidSdk) { $AndroidSdk = $env:ANDROID_SDK_ROOT }
if (-not $AndroidSdk) {
    foreach ($c in @(
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk'),
        (Join-Path $env:USERPROFILE 'AppData\Local\Android\Sdk'),
        'C:\Android\Sdk'
    )) {
        if ($c -and (Test-Path -LiteralPath $c)) { $AndroidSdk = $c; break }
    }
}
if ($AndroidSdk -and (Test-Path -LiteralPath $AndroidSdk)) {
    Out-Check 5 'OK' "Android SDK found: $AndroidSdk"
} else {
    Out-Check 5 'WARN' 'Android SDK not found in the usual locations' 'Install Android Studio, or set ANDROID_HOME - then run: flutter doctor'
}

$Java = Get-Command java -ErrorAction SilentlyContinue
if ($Java) {
    $jv = (& java -version 2>&1 | Select-Object -First 1)
    Out-Check 6 'OK' "java present: $("$jv".Trim())"
} else {
    Out-Check 6 'WARN' 'java/JDK not found - Gradle builds will fail' 'Install a JDK 17+ (Android Studio bundles one)'
}

# ── Project structure ────────────────────────────────────────────────────────
Write-Section 'Project structure'

$Pubspec = Join-Path $ProjectDir 'pubspec.yaml'
if (Test-Path -LiteralPath $Pubspec) {
    $appName = ''
    foreach ($line in (Get-Content -LiteralPath $Pubspec)) {
        if ($line -match '^name:\s*(.+)$') { $appName = $Matches[1].Trim(); break }
    }
    if (-not $appName) { $appName = 'unknown' }
    Out-Check 7 'OK' "pubspec.yaml present (name: $appName)"
} else {
    Out-Check 7 'FAIL' 'pubspec.yaml not found - not a Flutter project root?' 'flutter create . - or cd into the directory that holds pubspec.yaml'
}

if (Test-Path -LiteralPath (Join-Path $ProjectDir 'CLAUDE.md')) {
    Out-Check 8 'OK' 'CLAUDE.md present'
} else {
    Out-Check 8 'WARN' 'CLAUDE.md missing (flu-harness not initialized)' 'Run /flu-harness:new-flutter-project in Claude Code'
}

$RulesDir = Join-Path $ProjectDir '.claude\rules'
$ruleCount = 0
if (Test-Path -LiteralPath $RulesDir) {
    $ruleCount = @(Get-ChildItem -LiteralPath $RulesDir -Filter '*.md' -ErrorAction SilentlyContinue).Count
}
if ($ruleCount -gt 0) {
    Out-Check 9 'OK' ".claude\rules\ present ($ruleCount rules)"
} else {
    Out-Check 9 'WARN' '.claude\rules\ missing or empty (knowledge rules not installed)' 'Re-run /flu-harness:new-flutter-project'
}

$LibDir = Join-Path $ProjectDir 'lib'
if (Test-Path -LiteralPath $LibDir) {
    $dartFiles = @(Get-ChildItem -LiteralPath $LibDir -Recurse -Filter '*.dart' -ErrorAction SilentlyContinue).Count
    Out-Check 10 'OK' "lib\ present ($dartFiles .dart files)"
} else {
    Out-Check 10 'FAIL' 'lib\ missing' 'flutter create . to scaffold the app'
}

$TestDir = Join-Path $ProjectDir 'test'
$IntTestDir = Join-Path $ProjectDir 'integration_test'
if ((Test-Path -LiteralPath $TestDir) -or (Test-Path -LiteralPath $IntTestDir)) {
    $testFiles = 0
    if (Test-Path -LiteralPath $TestDir)    { $testFiles += @(Get-ChildItem -LiteralPath $TestDir -Recurse -Filter '*_test.dart' -ErrorAction SilentlyContinue).Count }
    if (Test-Path -LiteralPath $IntTestDir) { $testFiles += @(Get-ChildItem -LiteralPath $IntTestDir -Recurse -Filter '*_test.dart' -ErrorAction SilentlyContinue).Count }
    if ($testFiles -gt 0) {
        Out-Check 11 'OK' "test suite present ($testFiles _test.dart files)"
    } else {
        Out-Check 11 'WARN' 'test\ exists but holds no *_test.dart' 'Add a widget test - the pre-push gate runs: flutter test'
    }
} else {
    Out-Check 11 'WARN' 'no test\ directory' 'flutter test needs one; add test\widget_test.dart'
}

$AnalysisOptions = Join-Path $ProjectDir 'analysis_options.yaml'
if (Test-Path -LiteralPath $AnalysisOptions) {
    $aoText = Get-Content -LiteralPath $AnalysisOptions -Raw
    if ($aoText -match 'flutter_lints|very_good_analysis|lints:') {
        Out-Check 12 'OK' 'analysis_options.yaml includes a lint rule set'
    } else {
        Out-Check 12 'WARN' 'analysis_options.yaml has no lint rule set include' 'Add: include: package:flutter_lints/flutter.yaml'
    }
} else {
    Out-Check 12 'FAIL' 'analysis_options.yaml missing - analyzer runs with defaults only' 'Create it with: include: package:flutter_lints/flutter.yaml'
}

# ── Dependencies & config ────────────────────────────────────────────────────
Write-Section 'Dependencies & config'

$pubspecText = ''
if (Test-Path -LiteralPath $Pubspec) { $pubspecText = Get-Content -LiteralPath $Pubspec -Raw }

if ($pubspecText) {
    if ($pubspecText -match '(?m)^environment:' -and $pubspecText -match '(?m)^\s+sdk:\s*(.+)$') {
        Out-Check 13 'OK' "pubspec.yaml pins an SDK constraint ($($Matches[1].Trim()))"
    } else {
        Out-Check 13 'FAIL' 'pubspec.yaml has no environment.sdk constraint' 'Add: environment: { sdk: ^3.11.0 } (match your Dart version)'
    }
} else {
    Out-Check 13 'WARN' 'SDK constraint not checkable (no pubspec.yaml)' ''
}

if (Test-Path -LiteralPath (Join-Path $ProjectDir 'pubspec.lock')) {
    Out-Check 14 'OK' 'pubspec.lock present - builds are reproducible'
} else {
    Out-Check 14 'WARN' 'pubspec.lock missing' 'flutter pub get, then commit pubspec.lock'
}

$Discontinued = @(
    @{ pkg = 'dart_code_metrics'; why = 'discontinued - migrate to dart_code_linter' },
    @{ pkg = 'flutter_appauth_web'; why = 'discontinued' },
    @{ pkg = 'flutter_tindercard'; why = 'unmaintained since 2020' },
    @{ pkg = 'hive'; why = 'superseded by hive_ce (community edition, still maintained)' },
    @{ pkg = 'flutter_launcher_icons_plus'; why = 'unmaintained fork' },
    @{ pkg = 'path_provider_ios'; why = 'merged into path_provider' }
)
if ($pubspecText) {
    $hits = @()
    foreach ($d in $Discontinued) {
        if ($pubspecText -match ("(?m)^\s+" + [regex]::Escape($d.pkg) + ":")) {
            $hits += "$($d.pkg) ($($d.why))"
        }
    }
    if ($hits.Count -gt 0) {
        Out-Check 15 'FAIL' "discontinued/superseded packages in pubspec: $($hits -join '; ')" 'flutter pub remove <package> and pick the maintained alternative'
    } else {
        Out-Check 15 'OK' 'no discontinued packages in direct dependencies'
    }
} else {
    Out-Check 15 'WARN' 'dependency health not checkable (no pubspec.yaml)' ''
}

if (Test-Path -LiteralPath (Join-Path $ProjectDir 'l10n.yaml')) {
    Out-Check 16 'OK' 'l10n.yaml present (gen-l10n configured)'
} elseif ((Test-Path -LiteralPath (Join-Path $ProjectDir 'lib\l10n')) -or (Test-Path -LiteralPath (Join-Path $ProjectDir 'lib\l10n\app_en.arb'))) {
    Out-Check 16 'WARN' 'ARB files exist but l10n.yaml is missing' 'Add l10n.yaml with: arb-dir: lib/l10n, template-arb-file: app_en.arb'
} else {
    Out-Check 16 'WARN' 'no l10n.yaml - no localization pipeline configured' 'Add flutter_localizations + intl and an l10n.yaml (see .claude/rules/i18n.md)'
}

$androidId = ''
foreach ($f in @(
    (Join-Path $ProjectDir 'android\app\build.gradle'),
    (Join-Path $ProjectDir 'android\app\build.gradle.kts')
)) {
    if (Test-Path -LiteralPath $f) {
        foreach ($line in (Get-Content -LiteralPath $f)) {
            if ($line -match 'applicationId\s*=?\s*"([^"]+)"') { $androidId = $Matches[1]; break }
        }
    }
    if ($androidId) { break }
}
$iosId = ''
$pbx = Join-Path $ProjectDir 'ios\Runner.xcodeproj\project.pbxproj'
if (Test-Path -LiteralPath $pbx) {
    foreach ($line in (Get-Content -LiteralPath $pbx)) {
        if ($line -match 'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);') { $iosId = $Matches[1].Trim(); break }
    }
}
if ($androidId -and $iosId) {
    Out-Check 17 'OK' "store identifiers set (android: $androidId, ios: $iosId)"
} elseif ($androidId) {
    Out-Check 17 'WARN' "android applicationId set ($androidId) but iOS bundle id not found" 'Set PRODUCT_BUNDLE_IDENTIFIER in ios\Runner.xcodeproj - required for App Store'
} else {
    Out-Check 17 'WARN' 'android applicationId not set (still com.example.*?)' 'Set applicationId in android\app\build.gradle - it must be unique and permanent'
}

# ── Security & git hygiene ───────────────────────────────────────────────────
Write-Section 'Security & git hygiene'

$gitDir = Join-Path $ProjectDir '.git'
$hasGit = Test-Path -LiteralPath $gitDir
if ($hasGit) {
    Out-Check 18 'OK' 'git repository initialized'
} else {
    Out-Check 18 'FAIL' 'no .git\ directory' "git init; git add .; git commit -m 'chore: init'"
}

$gi = Join-Path $ProjectDir '.gitignore'
if (Test-Path -LiteralPath $gi) {
    $giText = Get-Content -LiteralPath $gi -Raw
    $missing = @()
    foreach ($pat in @('.dart_tool', 'build/', '.env', 'key.properties', '*.keystore', '*.jks', 'google-services.json', 'GoogleService-Info.plist')) {
        if ($giText -notlike "*$pat*") { $missing += $pat }
    }
    if ($missing.Count -eq 0) {
        Out-Check 19 'OK' '.gitignore covers Flutter + secret paths'
    } else {
        Out-Check 19 'FAIL' ".gitignore does not cover: $($missing -join ', ')" 'Append the missing patterns - a leaked *.keystore or key.properties is a release-key compromise'
    }
} else {
    Out-Check 19 'FAIL' '.gitignore missing' 'flutter create generates one; restore it'
}

if ($hasGit) {
    $tracked = & git -C $ProjectDir ls-files 2>$null
    $leaked = @($tracked | Where-Object { $_ -match '(^|/)\.env|key\.properties$|\.keystore$|\.jks$|google-services\.json$|GoogleService-Info\.plist$' } | Select-Object -First 3)
    if ($leaked.Count -eq 0) {
        Out-Check 20 'OK' 'no secrets tracked by git'
    } else {
        Out-Check 20 'FAIL' "secret files tracked by git: $($leaked -join ' ')" 'git rm --cached <file>, add it to .gitignore, and rotate the credential'
    }
} else {
    Out-Check 20 'WARN' 'git index not readable (no .git\)' 'git init'
}

if (Test-Path -LiteralPath $LibDir) {
    $hard = @(
        Get-ChildItem -LiteralPath $LibDir -Recurse -Filter '*.dart' -ErrorAction SilentlyContinue |
        Select-String -Pattern "(apiKey|api_key|secret|clientSecret|password)\s*[:=]\s*['""][A-Za-z0-9_\-]{12,}" -ErrorAction SilentlyContinue |
        Select-Object -First 3
    )
    if ($hard.Count -eq 0) {
        Out-Check 21 'OK' 'no hardcoded credentials found in lib\'
    } else {
        $where = ($hard | ForEach-Object { "$($_.Filename):$($_.LineNumber)" }) -join ' '
        Out-Check 21 'FAIL' "possible hardcoded credential in: $where" 'Move to --dart-define / --dart-define-from-file, or a secret manager. Never commit keys.'
    }
} else {
    Out-Check 21 'WARN' 'lib\ scan skipped' ''
}

# ── Quality gates & hooks ────────────────────────────────────────────────────
Write-Section 'Quality gates & hooks'

$HooksDir = Join-Path $ProjectDir '.githooks'
$hooksPath = ''
if ($hasGit) { $hooksPath = ((& git -C $ProjectDir config core.hooksPath 2>$null) | Select-Object -First 1) }

if (Test-Path -LiteralPath $HooksDir) {
    if ($hooksPath -eq '.githooks') {
        Out-Check 22 'OK' 'git core.hooksPath = .githooks'
    } elseif ($hooksPath) {
        Out-Check 22 'WARN' "core.hooksPath is '$hooksPath', expected .githooks" 'git config core.hooksPath .githooks'
    } else {
        Out-Check 22 'FAIL' '.githooks\ exists but core.hooksPath is unset - hooks never run' 'git config core.hooksPath .githooks'
    }
} else {
    Out-Check 22 'FAIL' '.githooks\ missing - no quality gates installed' 'Re-run /flu-harness:new-flutter-project'
}

$preCommit = Join-Path $HooksDir 'pre-commit'
if (Test-Path -LiteralPath $preCommit) {
    $crlfHooks = @()
    foreach ($f in @($preCommit, (Join-Path $HooksDir 'pre-push'))) {
        if (-not (Test-Path -LiteralPath $f)) { continue }
        $bytes = [System.IO.File]::ReadAllBytes($f)
        # Walk only the first line: a CR there corrupts the shebang.
        $cr = $false
        foreach ($b in $bytes) {
            if ($b -eq 10) { break }
            if ($b -eq 13) { $cr = $true; break }
        }
        if ($cr) { $crlfHooks += (Split-Path $f -Leaf) }
    }
    if ($crlfHooks.Count -gt 0) {
        Out-Check 23 'FAIL' "CRLF line endings in hook script(s): $($crlfHooks -join ', ') - git will refuse to run them" 'Strip CR from both hooks (.githooks\pre-commit and pre-push), then add ".githooks/* text eol=lf" to .gitattributes'
    } else {
        Out-Check 23 'OK' 'hook scripts use LF line endings (git-executable on Windows)'
    }
} else {
    Out-Check 23 'FAIL' '.githooks\pre-commit missing' 'Re-run /flu-harness:new-flutter-project'
}

$LibHooksDir = Join-Path $HooksDir 'lib'
$libOk = $true
foreach ($f in @('quality.sh', 'quality.ps1', 'quality.cmd', 'gates.def')) {
    if (-not (Test-Path -LiteralPath (Join-Path $LibHooksDir $f))) { $libOk = $false }
}
if ($libOk) {
    Out-Check 24 'OK' 'gate library complete (quality.sh/.ps1/.cmd + gates.def)'
} else {
    Out-Check 24 'FAIL' '.githooks\lib\ gate library incomplete or missing - some shells cannot run the gates' 'Re-run /flu-harness:new-flutter-project'
}

$ga = Join-Path $ProjectDir '.gitattributes'
if (Test-Path -LiteralPath $ga) {
    $gaText = Get-Content -LiteralPath $ga -Raw
    if ($gaText -match '(?m)^\*?\s*text\s*=\s*auto\s+eol\s*=\s*lf' -or $gaText -match '\.githooks/\*') {
        Out-Check 25 'OK' '.gitattributes pins LF for hooks'
    } else {
        Out-Check 25 'WARN' '.gitattributes exists but does not pin LF for .githooks/' 'Add: * text=auto eol=lf  and  .githooks/* text eol=lf'
    }
} else {
    Out-Check 25 'WARN' '.gitattributes missing - a Windows clone may convert hooks to CRLF' "Add .gitattributes with '* text=auto eol=lf'"
}

# ── Windows shell health ─────────────────────────────────────────────────────
Write-Section 'Windows shell health'

if ($Flutter) {
    if ($Flutter.Name -match '\.(bat|ps1|cmd)$') {
        Out-Check 26 'OK' "flutter resolves to $($Flutter.Name) (the Windows entry point)"
    } else {
        $sdkBin = Split-Path $Flutter.Source -Parent
        $shared = Join-Path $sdkBin 'internal\shared.sh'
        $sharedCr = $false
        if (Test-Path -LiteralPath $shared) {
            $sharedText = Get-Content -LiteralPath $shared -Raw
            if ($sharedText -match "`r") { $sharedCr = $true }
        }
        if ($sharedCr) {
            Out-Check 26 'FAIL' "Flutter SDK ships internal/shared.sh with CRLF - the '$($Flutter.Name)' wrapper cannot run" 'Repair the SDK by stripping CR from every .sh under <flutter-sdk>\bin - or just use flutter.bat'
        } else {
            Out-Check 26 'OK' 'flutter sh wrapper is intact (no CR in internal/shared.sh)'
        }
    }
} else {
    Out-Check 26 'FAIL' 'shell health not checkable - flutter not on PATH' 'Install the Flutter SDK'
}

# ── Summary ──────────────────────────────────────────────────────────────────
$total = $OkCount + $WarnCount + $FailCount

if ($Json) {
    $payload = [ordered]@{
        ok       = $OkCount
        warn     = $WarnCount
        fail     = $FailCount
        total    = $total
        expected = $TotalChecks
        results  = $Results
    }
    $payload | ConvertTo-Json -Depth 4
} else {
    Write-Host ""
    Write-Host "  ----------------------------------------"
    Write-Host "  OK: $OkCount  WARN: $WarnCount  FAIL: $FailCount  / $total total"
    Write-Host "  ----------------------------------------"
    Write-Host ""
}

if ($FailCount -gt 0) { exit 1 } else { exit 0 }
