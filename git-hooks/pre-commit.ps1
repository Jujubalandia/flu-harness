<#
.SYNOPSIS
  flu-harness pre-commit gate - manual runner for PowerShell.

.DESCRIPTION
  Git runs the *hook* itself through its bundled sh.exe, so .githooks/pre-commit
  is the file that actually fires on `git commit`. This wrapper exists so you
  can run the exact same gates by hand from PowerShell, without waiting for git
  to reject you:

      powershell -ExecutionPolicy Bypass -File .githooks\pre-commit.ps1

  Both paths read the same gates.def, so they can never disagree.

  Prefer the hook to fire automatically? It already does — this is only for
  running it early, on purpose.
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Profile = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'

$lib = Join-Path $PSScriptRoot 'lib\quality.ps1'
if (-not (Test-Path -LiteralPath $lib)) {
    Write-Host "[FAIL] $lib is missing - the harness hook library was not installed." -ForegroundColor Red
    Write-Host '       Re-run /flu-harness:new-flutter-project, or copy scripts/ into .githooks\lib\.' -ForegroundColor DarkGray
    exit 1
}

$forward = @{ Stage = 'pre-commit' }
if ($Profile) { $forward['Profile'] = $Profile }
if ($DryRun)  { $forward['DryRun']  = $true }

& $lib @forward
exit $LASTEXITCODE
