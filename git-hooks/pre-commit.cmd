@echo off
rem ---------------------------------------------------------------------------
rem  flu-harness pre-commit gate - manual runner for cmd.exe.
rem
rem  Git runs the *hook* itself through its bundled sh.exe, so
rem  .githooks\pre-commit is the file that actually fires on `git commit`.
rem  This wrapper exists so you can run the exact same gates by hand from CMD:
rem
rem      .githooks\pre-commit.cmd
rem
rem  Both paths read the same gates.def, so they can never disagree.
rem ---------------------------------------------------------------------------

call "%~dp0lib\quality.cmd" /stage:pre-commit %*
exit /b %ERRORLEVEL%
