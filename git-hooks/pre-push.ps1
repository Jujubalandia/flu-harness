<#
.SYNOPSIS
  flu-harness pre-push gate - manual runner for PowerShell.

.DESCRIPTION
  Git runs the *hook* itself through its bundled sh.exe, so .githooks/pre-push
  is the file that actually fires on `git push`. This wrapper runs the same gate
  plan by hand:

      powershell -ExecutionPolicy Bypass -File .githooks\pre-push.ps1

  Set HARNESS_DEVICE_OK=1 to pre-answer the physical-device question.

.PARAMETER DryRun
  Print the resolved plan instead of running it.
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

$forward = @{ Stage = 'pre-push' }
if ($Profile) { $forward['Profile'] = $Profile }
if ($DryRun)  { $forward['DryRun']  = $true }

& $lib @forward
exit $LASTEXITCODE
