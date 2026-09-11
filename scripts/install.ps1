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
#
# Two ways in, and the second one is why this block is not five lines:
#
#   * A checkout.  .\scripts\install.ps1, or the script sitting next to
#     .claude-plugin\ in a clone.
#
#   * Piped.       irm <raw-url>/install.ps1 | iex
#
# The piped form cannot find anything: Invoke-Expression has no $PSScriptRoot,
# so there is no repository next to the script and nothing on disk to copy. The
# POSIX installer had the same hole, which meant the first command a visitor to
# the landing page runs did not work. The piped case downloads a tarball of the
# repository and installs from that.
#
# HARNESS_REF picks a branch or tag (default: main).
# HARNESS_TARBALL_URL overrides the download entirely, for forks and mirrors.
# It must point at a .zip, because Expand-Archive cannot read a .tar.gz.

$TempFetch = $null

function Remove-TempFetch {
    if ($script:TempFetch -and (Test-Path -LiteralPath $script:TempFetch)) {
        Remove-Item -LiteralPath $script:TempFetch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (-not $From) {
    $parent = if ($SelfDir) { Split-Path $SelfDir -Parent } else { '' }
    if ($parent -and (Test-Path -LiteralPath (Join-Path $parent '.claude-plugin'))) {
        $From = $parent
    } elseif (Test-Path -LiteralPath (Join-Path $SelfDir 'scripts')) {
        $From = $SelfDir
    } else {
        $From = ''
    }
}

# An explicit -From that does not hold a checkout is a user error worth naming.
if ($From -and -not (Test-Path -LiteralPath (Join-Path $From 'scripts'))) {
    Write-Host "ERROR: $From does not look like a flu-harness checkout (no scripts\)." -ForegroundColor Red
    Write-Host '       Pass -From C:\path\to\flu-harness, or clone it first:' -ForegroundColor DarkGray
    Write-Host '         git clone https://github.com/Jujubalandia/flu-harness $env:USERPROFILE\.flu-harness' -ForegroundColor DarkGray
    exit 1
}

if (-not $From) {
    $Ref = if ($env:HARNESS_REF) { $env:HARNESS_REF } else { 'main' }
    # A .zip, not the .tar.gz the POSIX installer uses: Expand-Archive reads
    # zip only. HARNESS_TARBALL_URL must therefore point at a zip as well.
    $Tarball = if ($env:HARNESS_TARBALL_URL) {
        $env:HARNESS_TARBALL_URL
    } else {
        "https://github.com/Jujubalandia/flu-harness/archive/refs/heads/$Ref.zip"
    }

    $TempFetch = Join-Path ([System.IO.Path]::GetTempPath()) ("flu-harness-fetch-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $TempFetch | Out-Null

    Write-Host "Downloading flu-harness ($Ref)..."
    try {
        $archive = Join-Path $TempFetch 'source.zip'
        Invoke-WebRequest -Uri $Tarball -OutFile $archive -UseBasicParsing -ErrorAction Stop
        Expand-Archive -LiteralPath $archive -DestinationPath $TempFetch -Force -ErrorAction Stop
    } catch {
        Remove-TempFetch
        Write-Host "ERROR: download failed: $Tarball" -ForegroundColor Red
        Write-Host "       $_" -ForegroundColor DarkGray
        Write-Host '       Clone instead:' -ForegroundColor DarkGray
        Write-Host '         git clone https://github.com/Jujubalandia/flu-harness $env:USERPROFILE\.flu-harness' -ForegroundColor DarkGray
        exit 1
    }

    # The archive extracts to flu-harness-<ref>\, one directory deep.
    $found = Get-ChildItem -LiteralPath $TempFetch -Directory -ErrorAction SilentlyContinue |
             Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'scripts') } |
             Select-Object -First 1
    if (-not $found) {
        Remove-TempFetch
        Write-Host 'ERROR: the downloaded archive did not contain scripts\.' -ForegroundColor Red
        exit 1
    }
    $From = $found.FullName
}

$From = (Resolve-Path -LiteralPath $From).Path

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

# -- Drop the downloaded copy, it has served its purpose ---------------------
Remove-TempFetch

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
