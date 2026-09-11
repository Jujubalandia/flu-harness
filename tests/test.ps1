<#
.SYNOPSIS
  flu-harness test suite for Windows (PowerShell).

.DESCRIPTION
  The PowerShell counterpart to tests/test.sh. Run both:

      bash tests/test.sh
      powershell -ExecutionPolicy Bypass -File tests\test.ps1

  test.sh covers the repo structure, the sh runner, the POSIX guard and the
  installer. This one covers what only a native Windows shell can check:

    * every .ps1 parses
    * the three gate runners produce an identical plan, for every profile
    * the PowerShell and cmd guard wrappers return the right exit codes
    * doctor.ps1 -Json is valid and reports all 26 checks
    * hooks are LF, so git can actually execute them
    * hooks really fire on `git commit` from both cmd.exe and PowerShell

  That last one is the point of the whole harness and cannot be tested from a
  POSIX shell on Windows, so it lives here.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tests\test.ps1
#>
#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

$RepoDir = Split-Path $PSScriptRoot -Parent
$Pass = 0; $Fail = 0; $Skip = 0
$Errors = New-Object System.Collections.ArrayList

function Pass-Test { param([string]$m) Write-Host "  OK   $m" -ForegroundColor Green; $script:Pass++ }
function Fail-Test { param([string]$m) Write-Host "  FAIL $m" -ForegroundColor Red; $script:Fail++; [void]$script:Errors.Add($m) }
function Skip-Test { param([string]$m) Write-Host "  SKIP $m" -ForegroundColor Yellow; $script:Skip++ }
function Section   { param([string]$m) Write-Host ""; Write-Host $m -ForegroundColor Cyan }

function Assert-True {
    param([bool]$Condition, [string]$Label)
    if ($Condition) { Pass-Test $Label } else { Fail-Test $Label }
}

function Assert-Exists {
    param([string]$Path, [string]$Label)
    Assert-True (Test-Path -LiteralPath $Path) ($(if ($Label) { $Label } else { "$Path exists" }))
}

function Invoke-Exit {
    # Run a batch/executable and return its exit code, quietly.
    param([string]$File, [string]$Arguments)
    $p = Start-Process -FilePath $File -ArgumentList $Arguments -NoNewWindow -Wait -PassThru `
                       -RedirectStandardOutput "$env:TEMP\fh-test-out.txt" `
                       -RedirectStandardError  "$env:TEMP\fh-test-err.txt"
    return $p.ExitCode
}

$Tmp = Join-Path $env:TEMP ("flu-harness-test-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null

try {

# ═══════════════════════════════════════════════════════════════════════════
Section "1. Structure and manifests"

Assert-Exists (Join-Path $RepoDir '.claude-plugin\plugin.json')
Assert-Exists (Join-Path $RepoDir '.claude-plugin\marketplace.json')
Assert-Exists (Join-Path $RepoDir '.gitattributes')
Assert-Exists (Join-Path $RepoDir 'docs\WINDOWS.md')
Assert-Exists (Join-Path $RepoDir 'README.md')
Assert-Exists (Join-Path $RepoDir 'README.pt-BR.md')

foreach ($f in @('scripts\quality.sh','scripts\quality.ps1','scripts\quality.cmd',
                 'scripts\doctor.sh','scripts\doctor.ps1','scripts\doctor.cmd',
                 'scripts\install.sh','scripts\install.ps1','scripts\install.cmd',
                 'git-hooks\pre-commit','git-hooks\pre-push',
                 'git-hooks\pre-commit.ps1','git-hooks\pre-commit.cmd',
                 'git-hooks\pre-push.ps1','git-hooks\pre-push.cmd',
                 'templates\claude\hooks\pre-tool-use.sh',
                 'templates\claude\hooks\pre-tool-use.ps1',
                 'templates\claude\hooks\pre-tool-use.cmd')) {
    Assert-Exists (Join-Path $RepoDir $f)
}

foreach ($m in @('.claude-plugin\plugin.json','.claude-plugin\marketplace.json','templates\claude\settings.json')) {
    $ok = $true
    try { $null = Get-Content (Join-Path $RepoDir $m) -Raw | ConvertFrom-Json } catch { $ok = $false }
    Assert-True $ok "$m is valid JSON"
}

Assert-True ((Get-Content (Join-Path $RepoDir '.claude-plugin\plugin.json') -Raw) -match '"name"\s*:\s*"flu-harness"') 'plugin name is flu-harness'

# ═══════════════════════════════════════════════════════════════════════════
Section "2. PowerShell syntax"

$psFiles = Get-ChildItem -Path $RepoDir -Recurse -Filter '*.ps1' -File |
           Where-Object { $_.FullName -notmatch 'node_modules|\.tmp' }
foreach ($f in $psFiles) {
    $errs = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs)
    Assert-True (($errs -eq $null) -or ($errs.Count -eq 0)) "PowerShell parses $(Split-Path $f.FullName -Leaf)"
}
Assert-True ($psFiles.Count -gt 0) "found .ps1 files to check ($($psFiles.Count))"

# ═══════════════════════════════════════════════════════════════════════════
Section "3. Gate plan parity across the three shells"

$Proj = Join-Path $Tmp 'proj'
New-Item -ItemType Directory -Force -Path (Join-Path $Proj '.githooks\lib') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Proj 'lib') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Proj 'test') | Out-Null
[System.IO.File]::WriteAllText((Join-Path $Proj 'pubspec.yaml'), "name: fixture_app`nenvironment:`n  sdk: ^3.11.0`n")
[System.IO.File]::WriteAllText((Join-Path $Proj 'analysis_options.yaml'), "include: package:flutter_lints/flutter.yaml`n")

Copy-Item (Join-Path $RepoDir 'scripts\quality.ps1') (Join-Path $Proj '.githooks\lib') -Force
Copy-Item (Join-Path $RepoDir 'scripts\quality.cmd') (Join-Path $Proj '.githooks\lib') -Force

function Get-Plan {
    param([string]$Shell, [string]$Profile, [string]$Stage)
    switch ($Shell) {
        'ps1' {
            $out = & (Join-Path $Proj '.githooks\lib\quality.ps1') -Stage $Stage -Profile $Profile -DryRun 2>$null
            return (($out | Where-Object { $_ -like 'gate=*' }) -join ' ')
        }
        'cmd' {
            $out = & "$env:TEMP\fh-plan.cmd" $Profile $Stage 2>$null
            return (($out | Where-Object { $_ -like 'gate=*' }) -join ' ')
        }
    }
}

# A tiny cmd shim avoids fighting Start-Process argument quoting.
$shim = @"
@echo off
call "$Proj\.githooks\lib\quality.cmd" /stage:%2 /profile:%1 /dry-run
"@
[System.IO.File]::WriteAllText("$env:TEMP\fh-plan.cmd", $shim)

$expected = @{
    'minimal|pre-commit'  = 'gate=analyze'
    'minimal|pre-push'    = 'gate=analyze gate=test'
    'standard|pre-commit' = 'gate=format gate=analyze'
    'standard|pre-push'   = 'gate=format gate=analyze gate=lint gate=test'
    'strict|pre-commit'   = 'gate=format gate=analyze gate=lint'
    'strict|pre-push'     = 'gate=format gate=analyze gate=lint gate=test gate=build'
}

foreach ($profile in @('minimal','standard','strict')) {
    Copy-Item (Join-Path $RepoDir "git-hooks\profiles\$profile\gates.def") (Join-Path $Proj '.githooks\lib\gates.def') -Force
    foreach ($stage in @('pre-commit','pre-push')) {
        $key = "$profile|$stage"
        $want = $expected[$key]
        $psPlan  = Get-Plan -Shell 'ps1' -Profile $profile -Stage $stage
        $cmdPlan = Get-Plan -Shell 'cmd' -Profile $profile -Stage $stage
        Assert-True ($psPlan -eq $want)  "PowerShell plan $key = [$want]"
        Assert-True ($cmdPlan -eq $want) "cmd.exe plan $key = [$want]"
        Assert-True ($psPlan -eq $cmdPlan) "PowerShell and cmd agree on $key"
    }
}

# exit codes
$dryCode = Invoke-Exit 'powershell.exe' "-NoProfile -ExecutionPolicy Bypass -File `"$Proj\.githooks\lib\quality.ps1`" -Stage pre-commit -DryRun"
Assert-True ($dryCode -eq 0) "dry run exits 0 (got $dryCode)"

# ═══════════════════════════════════════════════════════════════════════════
Section "4. Destructive-operation guard"

$guard = Join-Path $RepoDir 'templates\claude\hooks\pre-tool-use.ps1'
$guardCmd = Join-Path $RepoDir 'templates\claude\hooks\pre-tool-use.cmd'

function Test-Guard {
    param([int]$Expected, [string]$Label, [string]$Json, [switch]$ViaCmd)
    $inFile = Join-Path $Tmp 'payload.json'
    [System.IO.File]::WriteAllText($inFile, $Json)
    if ($ViaCmd) {
        $code = Invoke-Exit 'cmd.exe' "/c `"`"$guardCmd`" < `"$inFile`"`""
    } else {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$guard`""
        $psi.RedirectStandardInput = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.StandardInput.Write($Json)
        $p.StandardInput.Close()
        $p.WaitForExit()
        $code = $p.ExitCode
    }
    $want = if ($Expected -eq 2) { 'BLOCK' } else { 'allow' }
    Assert-True ($code -eq $Expected) "guard ($(if($ViaCmd){'cmd'}else{'ps1'})): $Label -> $want"
}

$block = @(
    @('flutter pub publish',      '{"tool_name":"Bash","tool_input":{"command":"flutter pub publish"}}'),
    @('dart pub publish',         '{"tool_name":"Bash","tool_input":{"command":"dart pub publish"}}'),
    @('git push --force',         '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'),
    @('git commit --no-verify',   '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"x\" --no-verify"}}'),
    @('git reset --hard',         '{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD~3"}}'),
    @('rm -rf /',                 '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}'),
    @('DROP TABLE',               '{"tool_name":"Bash","tool_input":{"command":"psql -c \"DROP TABLE users;\""}}'),
    @('supabase db reset',        '{"tool_name":"Bash","tool_input":{"command":"supabase db reset"}}'),
    @('fastlane deliver',         '{"tool_name":"Bash","tool_input":{"command":"bundle exec fastlane deliver"}}'),
    @('keytool -genkey',          '{"tool_name":"Bash","tool_input":{"command":"keytool -genkey -keystore r.jks"}}')
)
$allow = @(
    @('flutter test',             '{"tool_name":"Bash","tool_input":{"command":"flutter test"}}'),
    @('git push origin feat',     '{"tool_name":"Bash","tool_input":{"command":"git push origin feat/x"}}'),
    @('rm -rf build/',            '{"tool_name":"Bash","tool_input":{"command":"rm -rf build/"}}'),
    @('DELETE with WHERE',        '{"tool_name":"Bash","tool_input":{"command":"psql -c \"DELETE FROM t WHERE id=1\""}}'),
    @('Write mentioning force',   '{"tool_name":"Write","tool_input":{"file_path":"a.md","content":"never git push --force"}}')
)

foreach ($c in $block) { Test-Guard -Expected 2 -Label $c[0] -Json $c[1] }
foreach ($c in $allow) { Test-Guard -Expected 0 -Label $c[0] -Json $c[1] }
# One pass through the cmd wrapper, since that adds its own quoting layer.
Test-Guard -Expected 2 -Label 'git push --force' -Json '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}' -ViaCmd

# ═══════════════════════════════════════════════════════════════════════════
Section "5. flutter-doctor"

$doctorSh  = Join-Path $RepoDir 'scripts\doctor.sh'
$doctorPs  = Join-Path $RepoDir 'scripts\doctor.ps1'
$doctorCmd = Join-Path $RepoDir 'scripts\doctor.cmd'

$jsonPath = Join-Path $Tmp 'doctor.json'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $doctorPs -Json -ProjectDir $Tmp 2>$null |
    Out-File -FilePath $jsonPath -Encoding utf8

try {
    $d = Get-Content $jsonPath -Raw | ConvertFrom-Json
    Assert-True ($null -ne $d) 'doctor -Json parses'
    Assert-True ($d.expected -eq 26) "doctor declares 26 checks (got $($d.expected))"
    Assert-True ($d.results.Count -eq $d.expected) "reported $($d.results.Count) checks, expected $($d.expected)"
    Assert-True (($d.ok + $d.warn + $d.fail) -eq $d.total) 'ok + warn + fail = total'
    $nums = $d.results | ForEach-Object { $_.n } | Sort-Object
    $want = 1..26
    Assert-True ((Compare-Object $nums $want) -eq $null) 'check numbers are exactly 1..26, no gaps or duplicates'
    $badLevel = $d.results | Where-Object { $_.level -notin @('OK','WARN','FAIL') }
    Assert-True ($null -eq $badLevel) 'every level is OK, WARN or FAIL'
    $failNoFix = $d.results | Where-Object { $_.level -eq 'FAIL' -and [string]::IsNullOrWhiteSpace($_.fix) }
    Assert-True ($null -eq $failNoFix) 'every FAIL carries a fix line'
} catch {
    Fail-Test "doctor -Json invalid: $_"
}

# The two native implementations must cover the same checks.
$shNums = (Select-String -Path $doctorSh -Pattern '_out (OK|WARN|FAIL) (\d+)' -AllMatches |
           ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[2].Value } |
           Sort-Object -Unique) -join ','
$psNums = (Select-String -Path $doctorPs -Pattern "Out-Check (\d+) '" -AllMatches |
           ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } |
           Sort-Object -Unique) -join ','
Assert-True ($shNums -eq $psNums) 'doctor.sh and doctor.ps1 cover the same check numbers'

# doctor.cmd must delegate, not reimplement.
Assert-True ((Get-Content $doctorCmd -Raw) -match 'doctor\.ps1') 'doctor.cmd delegates to doctor.ps1'
Assert-True ((Get-Content (Join-Path $RepoDir 'scripts\quality.cmd') -Raw) -match 'SELFDIR') 'quality.cmd captures %~dp0 before parsing'
Assert-True ((Get-Content (Join-Path $RepoDir 'scripts\install.cmd') -Raw) -match 'SELFDIR') 'install.cmd captures %~dp0 before parsing'

# ═══════════════════════════════════════════════════════════════════════════
Section "6. Line endings"

function Assert-LF {
    param([string]$Path, [string]$Label)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $cr = $false
    foreach ($b in $bytes) { if ($b -eq 13) { $cr = $true; break } }
    Assert-True (-not $cr) "$Label is LF (git can execute it)"
}

Assert-LF (Join-Path $RepoDir 'git-hooks\pre-commit') 'git-hooks\pre-commit'
Assert-LF (Join-Path $RepoDir 'git-hooks\pre-push')   'git-hooks\pre-push'
foreach ($s in (Get-ChildItem (Join-Path $RepoDir 'scripts') -Filter '*.sh')) {
    Assert-LF $s.FullName "scripts\$($s.Name)"
}

$attrs = Get-Content (Join-Path $RepoDir '.gitattributes') -Raw
Assert-True ($attrs -match 'eol=lf') '.gitattributes pins eol=lf'
Assert-True ($attrs -match '\.githooks/') '.gitattributes covers .githooks/'

# ═══════════════════════════════════════════════════════════════════════════
Section "7. The hook actually fires (the whole point)"

$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) {
    Skip-Test 'git not on PATH, cannot test hook execution'
} else {

    # Build a fixture project wired to the real hook and the real runner.
    function New-HookFixture {
        param([string]$Name, [string]$GatesDef)
        $p = Join-Path $Tmp $Name
        New-Item -ItemType Directory -Force -Path (Join-Path $p '.githooks\lib') | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $p 'pubspec.yaml'), "name: hook_fixture`n")
        Copy-Item (Join-Path $RepoDir 'git-hooks\pre-commit') (Join-Path $p '.githooks\pre-commit') -Force
        Copy-Item (Join-Path $RepoDir 'scripts\quality.sh') (Join-Path $p '.githooks\lib\quality.sh') -Force
        [System.IO.File]::WriteAllText((Join-Path $p '.githooks\lib\gates.def'), $GatesDef)
        [System.IO.File]::WriteAllText((Join-Path $p '.githooks\.profile'), 'minimal')
        & git -C $p init -q 2>$null | Out-Null
        & git -C $p config core.hooksPath .githooks 2>$null | Out-Null
        & git -C $p config user.email 'test@example.com' 2>$null | Out-Null
        & git -C $p config user.name 'Test' 2>$null | Out-Null
        return $p
    }

    function Invoke-Commit {
        param([string]$Path)
        # Capture everything: the hook's banner is the evidence that git ran it.
        $out = & git -C $Path commit --allow-empty -m 'test: hook' 2>&1 | Out-String
        return @{ Output = $out; Code = $LASTEXITCODE }
    }

    # Case A: a gate that passes here. The fixture has no test/ directory, so
    # the `test` gate skips itself and the plan succeeds without needing Flutter.
    # Nothing is stubbed, so this exercises the real chain:
    #   git.exe -> Git for Windows sh.exe -> .githooks/pre-commit
    #           -> quality.sh -> gates.def
    $passProj = New-HookFixture -Name 'hookpass' -GatesDef "# a gate that self-skips without a test/ dir`npre-commit=test`n"
    $a = Invoke-Commit -Path $passProj
    Assert-True ($a.Output -match 'flu-harness quality') 'git ran .githooks/pre-commit (its banner appeared)'
    Assert-True ($a.Code -eq 0) "a passing gate plan lets the commit through (git exited $($a.Code))"
    $head = (& git -C $passProj log --oneline 2>$null | Out-String)
    Assert-True ($head -match 'test: hook') 'the commit was actually created'

    # Case B: a real gate that cannot pass here (no Flutter in the fixture), so
    # the same hook must block the commit. This is the behaviour the harness
    # exists for, and it can only be verified by making git do it.
    $failProj = New-HookFixture -Name 'hookfail' -GatesDef "# one gate that will fail`npre-commit=analyze`n"
    $b = Invoke-Commit -Path $failProj
    Assert-True ($b.Output -match 'flu-harness quality') 'the hook ran in the failing fixture too'
    Assert-True ($b.Code -ne 0) "a failing gate blocks the commit (git exited $($b.Code))"
    $headB = (& git -C $failProj log --oneline 2>$null | Out-String)
    Assert-True ($headB -notmatch 'test: hook') 'no commit was created when the gate failed'

    # Case C: the same commit succeeds once the gate is satisfied, proving the
    # block came from the gate and not from a broken repository.
    [System.IO.File]::WriteAllText((Join-Path $failProj '.githooks\lib\gates.def'), "# a gate that self-skips`npre-commit=test`n")
    $c = Invoke-Commit -Path $failProj
    Assert-True ($c.Code -eq 0) "the same commit succeeds once the gate passes (git exited $($c.Code))"
}

# ═══════════════════════════════════════════════════════════════════════════
Section "8. Installer"

$prefix = Join-Path $Tmp 'prefix'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoDir 'scripts\install.ps1') `
    -Prefix $prefix -From $RepoDir 2>$null | Out-Null

Assert-Exists (Join-Path $prefix '.installed')
Assert-Exists (Join-Path $prefix 'scripts\doctor.ps1')
Assert-Exists (Join-Path $prefix 'scripts\quality.cmd')
Assert-Exists (Join-Path $prefix 'git-hooks\pre-commit')
Assert-Exists (Join-Path $prefix 'git-hooks\profiles\strict\gates.def')
Assert-Exists (Join-Path $prefix 'templates\rules')
Assert-LF (Join-Path $prefix 'git-hooks\pre-commit') 'installed pre-commit'

$reinstall = Invoke-Exit 'powershell.exe' "-NoProfile -ExecutionPolicy Bypass -File `"$RepoDir\scripts\install.ps1`" -Prefix `"$prefix`" -From `"$RepoDir`""
Assert-True ($reinstall -eq 1) "installer refuses to clobber (exit $reinstall)"

$uninstall = Invoke-Exit 'powershell.exe' "-NoProfile -ExecutionPolicy Bypass -File `"$RepoDir\scripts\install.ps1`" -Prefix `"$prefix`" -Uninstall"
Assert-True ($uninstall -eq 0) 'installer -Uninstall exits 0'
Assert-True (-not (Test-Path -LiteralPath $prefix)) 'uninstall removed the prefix'

} finally {
    Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:TEMP\fh-plan.cmd","$env:TEMP\fh-test-out.txt","$env:TEMP\fh-test-err.txt" -Force -ErrorAction SilentlyContinue
}

# ═══════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "========================================"
Write-Host "PASS: $Pass   FAIL: $Fail   SKIP: $Skip"
Write-Host "========================================"
Write-Host ""

if ($Fail -gt 0) {
    Write-Host "Failures:" -ForegroundColor Red
    foreach ($e in $Errors) { Write-Host "  - $e" -ForegroundColor Red }
    Write-Host ""
    exit 1
}
exit 0
