# Getting started

Empty folder to shipped app, with nothing left implicit. Two things this document
exists to answer: *what do I actually write in the spec*, and *what am I supposed
to be doing on day 6*.

[`README.md`](../README.md) is the full reference. This is the walk order.

---

## 0. Once per machine

```bash
flutter --version        # need 3.35+ on the stable channel
git --version
```

On Windows, two extra steps that cost five minutes each and prevent an afternoon:

```powershell
start ms-settings:developers     # Developer Mode: Flutter needs symlink support
```

Install **Git for Windows** if it is not already there. You never have to open
Git Bash, but its bundled `sh.exe` is what git uses to run your hooks, so the
gates depend on it. Then:

```
/plugin marketplace add Jujubalandia/flu-harness
/plugin install flu-harness@flu-harness
```

Everything ships inside the plugin: templates, skills, the doctor, the gate
runners for all three shells. Nothing to place by hand.

---

## 1. Fill this in before you run the wizard

This is answer-first prep. It maps one to one onto `docs/01-spec.md`, which the
wizard creates **empty** for you to fill on D1-D2. Answering these now turns those
two days into copy-paste instead of a blank page.

- [ ] **Problem** — one paragraph: who suffers, and from what
- [ ] **Audience** — primary profile, rough size, where they are, their main pain
- [ ] **Top 3 competitors** — downloads, strengths, weaknesses, what you do differently
- [ ] **Differentiator** — one sentence: "Unlike X, our app does Y for Z"
- [ ] **MVP cut/keep** — rule: if it is not required for the first user's main
      flow, cut it
- [ ] **Monetization** — model, when it activates, rough revenue estimate
- [ ] **Viral loop** — how it spreads without paid acquisition ("none yet" is fine)
- [ ] **Top 3 risks** — likelihood, impact, mitigation each

Do not overthink. The DoD for D1-D2 is only: problem statement, three
competitors, an approved cut/keep list, a one-sentence differentiator, and a viral
loop. Good enough beats perfect here.

### And start the clocks that cannot be rushed

Two things on D0 have multi-week lead times, and both are longer than this plan:

- **Google Play**: a personal developer account needs 12 testers opted in
  **continuously for 14 days** before it can publish to production. Push a
  placeholder build to closed testing on D0, and make sure those 12 are a
  **different group** from your internal testers: Play makes internal testers
  ineligible for closed tests, so the same people on both tracks means the clock
  never starts. Details in `05-store-launch.md`.
- **Apple**: Developer Program approval can take days.

---

## 2. Run the wizard

```bash
mkdir ~/projects/my-app && cd ~/projects/my-app
claude
```

Then:

```
/flu-harness:new-flutter-project
```

What it does, in order:

1. **Detects your stack** from `pubspec.yaml` across 16 dimensions: state, routing,
   backend, local DB, HTTP, serialization, secure storage, i18n, animation,
   monetization, notifications, testing, linting, release tooling, design system,
   extras. It prints the table and waits for confirmation.
   - If two libraries of the same kind are installed (Riverpod *and* Bloc), it
     warns instead of guessing. Tell it which one is real.
2. **Checks your shell environment** and reports which of the three shells this
   machine can run, plus the Flutter SDK version and entry point.
3. **Asks only what it cannot infer**: app name, org, description, languages,
   monetization, hook profile, editor, primary shell.
4. **Creates**: a filled `CLAUDE.md` (no `{{PLACEHOLDERS}}` left), `DECISIONS.md`,
   `TODO.md`, `docs/01-spec.md` through `docs/06-marketing.md`, `.githooks/` with
   a runner for all three shells, `.claude/rules/` (selective, by stack),
   `.claude/settings.json`, the pre-tool-use hooks, and `.gitattributes`.
5. **Proves the three shells agree**, by dry-running the gate plan in each and
   comparing. If they ever disagree, the install is broken and it says so.

Then:

```
/flu-harness:flutter-doctor
```

26 checks. You want zero FAILs before moving on. Two WARNs are normal at D0:
`l10n.yaml` and store identifiers, both of which come later.

---

## 3. Where you are, day by day

The literal day-by-day lives in **`docs/02-dev-plan.md`** in your project. Open
that rather than duplicating it here. It is a real checklist with milestones and
DoD gates: you do not advance past a milestone until its DoD passes.

Phase shape, so you know where you are:

| Days | Phase | File you are editing | Gate to leave |
|------|-------|---------------------|---------------|
| D0 | Start the clocks | `TODO.md` | Play closed test live, 12 testers opted in |
| D1-D3 | Spec + setup | `01-spec.md` | app runs on a real device, auth works, 2 screens navigate |
| D4-D10 | Core features | `02-dev-plan.md` | ~1 feature/day; stuck over 4h, log it and move on |
| D11-D13 | Polish | `03-quality-gates.md` | i18n done, a11y labels, loading and error states |
| D14-D15 | QA + store prep | `04-testing.md` | release build on a real device, golden paths pass |
| D16-D17 | Submission | `05-store-launch.md` | both submissions confirmed, build number logged |
| D18-D20 | Marketing | `06-marketing.md` | landing page live, posts published, D+7 metrics logged |

---

## 4. The commands you will actually type

```bash
# the doctor, from any shell
sh scripts/doctor.sh                                  # Git Bash, WSL, macOS, Linux
powershell -ExecutionPolicy Bypass -File scripts\doctor.ps1   # PowerShell
scripts\doctor.cmd                                    # cmd.exe

# the gates, by hand, before git rejects you
sh .githooks/lib/quality.sh --stage pre-push
powershell -ExecutionPolicy Bypass -File .githooks\lib\quality.ps1 -Stage pre-push
.githooks\lib\quality.cmd /stage:pre-push

# what would run, without running it
sh .githooks/lib/quality.sh --dry-run
```

Switching profile, when `strict` is too slow for a fast day:

```bash
echo minimal > .githooks/.profile
```

---

## 5. Sharp edges, so you do not re-debug them

**Your first commit will probably fail.** That is the harness working. A fresh
`flutter create` project fails `flutter analyze` on info-level lints, because
`flutter analyze` treats infos and warnings as fatal by default. Run
`dart format .`, fix what the analyzer names, commit again.

**`flutter-doctor` check 23 says your hook has CRLF.** Something checked the hooks
out with CRLF, and git will refuse to run them. The fix is in the message; the
permanent fix is `.gitattributes`, which the wizard wrote. Verify with
`git check-attr eol -- .githooks/pre-commit` (it must say `lf`).

**`flutter` fails with `$'\r': command not found`.** Your SDK's
`bin/internal/shared.sh` has CRLF. Git Bash tolerates it; WSL and Linux bash do
not. So this error means you are in WSL, not Git Bash. Run the gates from
PowerShell or cmd, or repair the SDK as doctor check 26 describes.

**The three runners disagree.** They cannot, by construction: all three parse the
same `gates.def`. If `--dry-run` output differs, one of them is a stale copy.
Re-run the wizard.

**"Set up a Mac" is not a plan.** A cloud Mac by the hour for the archive step, or
a CI runner that archives and uploads to TestFlight. Both need an Apple Developer
account and an App Store Connect API key. Do this on **D1**.

---

*Read alongside: [`WINDOWS.md`](WINDOWS.md) for the shell reference, and the
`templates/docs/` files the wizard puts in your project.*
