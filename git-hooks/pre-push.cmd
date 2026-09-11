@echo off
rem ---------------------------------------------------------------------------
rem  flu-harness pre-push gate - manual runner for cmd.exe.
rem
rem  Git runs the *hook* itself through its bundled sh.exe, so
rem  .githooks\pre-push is the file that actually fires on `git push`.
rem  This wrapper runs the same gate plan by hand:
rem
rem      .githooks\pre-push.cmd
rem
rem  Set HARNESS_DEVICE_OK=1 to pre-answer the physical-device question.
rem ---------------------------------------------------------------------------

call "%~dp0lib\quality.cmd" /stage:pre-push %*
exit /b %ERRORLEVEL%
