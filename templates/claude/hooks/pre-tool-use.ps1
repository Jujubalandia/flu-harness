<#
.SYNOPSIS
  flu-harness destructive-operation guard, PowerShell implementation.

.DESCRIPTION
  Same block list as pre-tool-use.sh, for users who wire the hook up through
  .claude/settings.json on Windows.

  Reads the Claude Code tool-call JSON on stdin.
      exit 0  allow
      exit 2  block (stderr is shown to the user)

  Claude Code's hook contract is the same on every platform; only the
  interpreter differs. Wire it up with, in .claude/settings.json:

      {
        "hooks": {
          "PreToolUse": [
            { "matcher": "Bash",
              "hooks": [ { "type": "command",
                           "command": "powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/pre-tool-use.ps1" } ] }
          ]
        }
      }
#>
#Requires -Version 5.1

$ErrorActionPreference = 'Continue'

$raw = [Console]::In.ReadToEnd()
if (-not $raw) { exit 0 }

$tool = ''
if ($raw -match '"tool_name"\s*:\s*"([^"]*)"') { $tool = $Matches[1] }

# Only shell commands are inspected.
if ($tool -ne 'Bash') { exit 0 }

$cmd = ''
if ($raw -match '"command"\s*:\s*"(.*?)"\s*[,}]') { $cmd = $Matches[1] }
$flatRaw = $raw -replace '[\r\n\t]', ' '
$flatCmd = $cmd -replace '[\r\n\t]', ' '

function Test-Blocked {
    param([string]$Pattern)
    if ($flatCmd -match $Pattern) { return $true }
    # Best-effort extraction can truncate on escaped quotes; the raw payload is
    # the backstop. Over-blocking is the safe direction here.
    if ($flatRaw -match $Pattern) { return $true }
    return $false
}

function Block {
    param([string]$What)
    Write-Host ''
    Write-Host "  BLOCKED: $What" -ForegroundColor Red
    Write-Host '  This operation is destructive or irreversible. flu-harness stops it'
    Write-Host '  before it runs.'
    Write-Host ''
    Write-Host '  If you are certain, run it yourself in a terminal - a human typing it'
    Write-Host '  is the confirmation this guard exists to require.'
    Write-Host '  To change the list for this project, edit .claude\hooks\pre-tool-use.ps1.'
    Write-Host ''
    exit 2
}

# -- Publishing: irreversible, and usually a typo away from shipping ---------
if (Test-Blocked '(^|[^a-z])(flutter|dart)\s+pub\s+publish') { Block 'publishing a package to pub.dev' }

# -- Store submission / release distribution --------------------------------
if (Test-Blocked 'fastlane\s+(deliver|supply|pilot|precheck)') { Block 'store submission via fastlane' }
if (Test-Blocked 'firebase\s+appdistribution:distribute')     { Block 'distributing a build to testers' }
if (Test-Blocked 'flutter\s+build\s+ipa')                     { Block 'an unsigned iOS archive is easy to upload by accident' }
if (Test-Blocked 'bundle\s+exec\s+fastlane')                  { Block 'store submission via fastlane' }

# -- Git history: rewrites are the one thing git cannot undo for you --------
if (Test-Blocked 'git\s+push\s+.*(--force|-f)([^a-z]|$)')     { Block 'force-push' }
if (Test-Blocked 'git\s+commit\s+.*--no-verify')              { Block 'commit with quality gates skipped (--no-verify)' }
if (Test-Blocked 'git\s+reset\s+--hard')                      { Block 'git reset --hard' }
if (Test-Blocked 'git\s+clean\s+-[a-z]*f')                    { Block 'git clean -f (deletes untracked files)' }
if (Test-Blocked 'git\s+filter-(branch|repo)')                { Block 'history rewriting' }
if (Test-Blocked 'git\s+rebase\s+-i')                         { Block 'interactive rebase on a shared branch' }

# -- Filesystem -------------------------------------------------------------
if (Test-Blocked 'rm\s+-[a-z]*r[a-z]*f?\s+/(\s|$)')           { Block 'rm -rf /' }
if (Test-Blocked 'rm\s+-[a-z]*r[a-z]*f?\s+~')                 { Block 'rm -rf ~' }
if (Test-Blocked 'Remove-Item\s+.*-Recurse\s+.*-Force\s+[A-Z]:\\?(\s|$)') { Block 'recursive delete at a drive root' }

# -- Databases --------------------------------------------------------------
if (Test-Blocked 'supabase\s+db\s+reset')                     { Block 'supabase db reset' }
if (Test-Blocked 'firebase\s+firestore:delete')               { Block 'firebase firestore:delete' }
if (Test-Blocked 'DROP\s+(TABLE|DATABASE|SCHEMA)')            { Block 'DROP TABLE/DATABASE/SCHEMA' }
if (Test-Blocked 'TRUNCATE\s+TABLE')                          { Block 'TRUNCATE TABLE' }
if (Test-Blocked 'DELETE\s+FROM\s+[a-z_]+\s*(;|$)')           { Block 'DELETE with no WHERE clause' }

# -- Release signing material ----------------------------------------------
if (Test-Blocked 'keytool\s+-genkey')                         { Block 'generating a new signing key (rotating your release key locks you out of updates)' }

exit 0
