---
name: Feature request
about: Suggest a check, a rule, a gate or a shell fix
title: ''
labels: enhancement
assignees: ''
---

**What problem are you hitting?**

Describe the situation, not the solution. "The pre-push gate takes four minutes
on a cold Gradle cache and I push ten times a day" is more useful than "add a
--fast flag".

**What would you like to happen?**

**If this is a new doctor check**

The doctor has 26 checks, and they exist because each one caught something real.
For a new one:

| | |
|---|---|
| What it would detect | |
| Level when it fails (`FAIL` or `WARN`) | |
| The exact fix line it would print | |
| Does it work on all three shells, or only some? | |

A check that cannot suggest a concrete fix is usually not ready. The test suite
asserts that every `FAIL` carries a non-empty `fix`.

**If this is a new knowledge rule**

`templates/rules/` files load by glob when you edit a matching file. For a new one:

| | |
|---|---|
| Rule name | |
| Which `globs` | |
| Which stack detection should copy it | |
| The three or four mistakes it exists to prevent | |

**Which shell does this concern?**

- [ ] PowerShell
- [ ] cmd.exe
- [ ] Git Bash
- [ ] WSL / Linux / macOS
- [ ] All of them

**Alternatives you considered**

**Anything else**
