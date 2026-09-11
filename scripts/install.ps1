<#
.SYNOPSIS
  flu-harness installer (PowerShell).

.DESCRIPTION
  Copies the scripts, templates, hooks and skills into a prefix directory so the
  doctor and the gate runners work from anywhere, with or without Claude Code.

  Mirrors scripts/install.sh exactly - same layout, same result. Use this one on
  Windows, install.sh under Git Bash, or install.cmd from cmd.exe (which calls
  this script).

.PARAMETER Prefix
  Install location. Defaults to "$env:USERPROFILE\.flu-harness".

.PARAMETER From
  Source checkout. Defaults to the repository this script lives in.

.PARAMETER Force
  Overwrite an existing install.

.PARAMETER Uninstall
  Remove the install and exit.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\install.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\install.ps1 -Uninstall
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Prefix = (Join-Path $env:USERPROFILE '.flu-harness'),
    [string]$From = '',
    [switch]$Force,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Continue'

$SelfDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

# -- Uninstall ---------------------------------------------------------------
if ($Uninstall) {
    if (Test-Path -LiteralPath $Prefix) {
        Remove-Item -LiteralPath $Prefix -Recurse -Force
        Write-Host "Removed $Prefix"
    } else {
        Write-Host "Nothing to remove at $Prefix"
    }
    exit 0
}

# -- Find the source ---------------------------------------------------------
if (-not $From) {
    $parent = Split-Path $SelfDir -Parent
    if (Test-Path -LiteralPath (Join-Path $parent '.claude-plugin')) {
        $From = $parent
    } else {
        $From = $SelfDir
    }
}
$From = (Resolve-Path -LiteralPath $From).Path

if (-not (Test-Path -LiteralPath (Join-Path $From 'scripts'))) {
    Write-Host "ERROR: $From does not look like a flu-harness checkout (no scripts\)." -ForegroundColor Red
    Write-Host '       Pass -From C:\path\to\flu-harness, or clone it first:' -ForegroundColor DarkGray
    Write-Host '         git clone https://github.com/Jujubalandia/flu-harness $env:USERPROFILE\.flu-harness' -ForegroundColor DarkGray
    exit 1
}

# -- Refuse to clobber silently ---------------------------------------------
if ((Test-Path -LiteralPath $Prefix) -and -not $Force) {
    if (Test-Path -LiteralPath (Join-Path $Prefix '.installed')) {
        Write-Host "ERROR: $Prefix is already installed." -ForegroundColor Red
        Write-Host '       Re-run with -Force to overwrite, or -Uninstall first.' -ForegroundColor DarkGray
        exit 1
    }
}

Write-Host ''
Write-Host 'flu-harness installer'
Write-Host '====================='
Write-Host "from:   $From"
Write-Host "prefix: $Prefix"
Write-Host ''

# -- Copy --------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $Prefix | Out-Null

foreach ($d in @('scripts', 'git-hooks', 'templates', 'skills', 'docs')) {
    $src = Join-Path $From $d
    if (-not (Test-Path -LiteralPath $src)) { continue }
    Write-Host "  . $d"
    Copy-Item -LiteralPath $src -Destination $Prefix -Recurse -Force
}

foreach ($f in @('README.md', 'README.pt-BR.md', '.gitattributes')) {
    $src = Join-Path $From $f
    if (Test-Path -LiteralPath $src) {
        Write-Host "  . $f"
        Copy-Item -LiteralPath $src -Destination $Prefix -Force
    }
}

# -- Force LF on the hook scripts -------------------------------------------
# This is the step that makes the install actually work on Windows.
#
# Git for Windows runs hooks through its bundled sh.exe. A hook with CRLF has the
# shebang "#!/bin/sh\r", so git looks for an interpreter literally named
# "/bin/sh\r" and reports something unrelated to line endings. Copy-Item itself
# does not convert, but a checkout that was converted before install would carry
# the damage in - so normalise here rather than hope.
foreach ($h in @('git-hooks\pre-commit', 'git-hooks\pre-push')) {
    $p = Join-Path $Prefix $h
    if (-not (Test-Path -LiteralPath $p)) { continue }
    $bytes = [System.IO.File]::ReadAllBytes($p)
    $crlf = $false
    for ($i = 0; $i -lt [Math]::Min($bytes.Length, 400); $i++) {
        if ($bytes[$i] -eq 13) { $crlf = $true; break }
        if ($bytes[$i] -eq 10) { break }
    }
    if ($crlf) {
        Write-Host "  ! $h had CRLF - rewriting with LF"
        $text = [System.IO.File]::ReadAllText($p)
        $text = $text.Replace("`r`n", "`n")
        [System.IO.File]::WriteAllText($p, $text)
    }
}

# Same for the shell runners: a .sh with CRLF is equally dead.
foreach ($s in Get-ChildItem -Path (Join-Path $Prefix 'scripts') -Filter '*.sh' -ErrorAction SilentlyContinue) {
    $text = [System.IO.File]::ReadAllText($s.FullName)
    if ($text.Contains("`r`n")) {
        Write-Host "  ! scripts\$($s.Name) had CRLF - rewriting with LF"
        [System.IO.File]::WriteAllText($s.FullName, $text.Replace("`r`n", "`n"))
    }
}

# -- Stamp -------------------------------------------------------------------
[System.IO.File]::WriteAllText((Join-Path $Prefix '.installed'),
    (Get-Date -Format 'yyyy-MM-dd'))

# -- Done --------------------------------------------------------------------
Write-Host ''
Write-Host 'Installed.' -ForegroundColor Green
Write-Host ''
Write-Host 'Verify it:'
Write-Host "  powershell -ExecutionPolicy Bypass -File `"$Prefix\scripts\doctor.ps1`" -Help"
Write-Host ''
Write-Host 'Use it in a project (the wizard does this for you):'
Write-Host '  New-Item -ItemType Directory -Force .githooks\lib | Out-Null'
Write-Host "  Copy-Item `"$Prefix\git-hooks\pre-commit`"    .githooks\"
Write-Host "  Copy-Item `"$Prefix\git-hooks\pre-push`"      .githooks\"
Write-Host "  Copy-Item `"$Prefix\scripts\quality.sh`"      .githooks\lib\"
Write-Host "  Copy-Item `"$Prefix\scripts\quality.ps1`"     .githooks\lib\"
Write-Host "  Copy-Item `"$Prefix\scripts\quality.cmd`"     .githooks\lib\"
Write-Host "  Copy-Item `"$Prefix\git-hooks\profiles\strict\gates.def`" .githooks\lib\"
Write-Host '  Set-Content -NoNewline .githooks\.profile strict'
Write-Host '  git config core.hooksPath .githooks'
Write-Host ''
Write-Host 'Optional - run the doctor by name from any shell:'
Write-Host "  [Environment]::SetEnvironmentVariable('Path',"
Write-Host "    [Environment]::GetEnvironmentVariable('Path','User') + ';$Prefix\scripts', 'User')"
Write-Host ''
