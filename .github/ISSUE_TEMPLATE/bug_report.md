---
name: Bug report
about: A gate, a check, or a hook behaved differently from what the docs say
title: ''
labels: bug
assignees: ''
---

<!--
Before filing: run `flutter-doctor` and paste its output below. Most reports
turn out to be one of the checks it already names.

  sh scripts/doctor.sh
  powershell -ExecutionPolicy Bypass -File scripts\doctor.ps1
  scripts\doctor.cmd
-->

**What happened**

A clear and concise description of the bug.

**What you expected instead**

**Which shell were you in?**

This matters more here than in most projects, because the three shells are the
point and they can genuinely differ. Tick every shell you tried:

- [ ] PowerShell 5.1 (Windows PowerShell)
- [ ] PowerShell 7+ (pwsh)
- [ ] cmd.exe
- [ ] Git Bash
- [ ] WSL
- [ ] Linux / macOS shell

Did the same thing happen in all of them, or only some? That difference is
usually the whole bug.

**Reproduce**

1.
2.
3.

**`flutter-doctor` output**

```
paste here
```

**Environment**

| | |
|---|---|
| OS and version | <!-- e.g. Windows 11 25H2, Ubuntu 24.04 --> |
| Flutter version (`flutter --version`) | |
| Dart version | |
| `flutter` entry point that resolved (`flutter`, `flutter.bat`) | |
| Hook profile (`.githooks/.profile`) | |
| Shell(s) affected | |

**Is it a gate or a check being wrong, or the code it flags?**

If a quality gate blocks something it should not, say which gate
(`format` / `analyze` / `lint` / `test` / `build`) and paste the command it ran.
Never work around it with `--no-verify` before reporting; that hides the case.

**Anything else**

Logs, screenshots, the contents of your `gates.def`, whatever is relevant.
