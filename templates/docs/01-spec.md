# 01 — Spec + market research

> Phase D1-D2. Fill this in **before** writing production code. The point is not
> documentation, it is deciding once instead of re-deciding every day.

**DoD for D1-D2:** problem statement + 3 competitors + an approved cut/keep list +
a one-sentence differentiator + a viral loop (or an explicit "none yet").

---

## Problem

Who suffers, and from what? One paragraph. If you cannot write it without the
word "platform", it is not a problem yet.

>

## Target audience

| | |
|---|---|
| Primary profile | |
| Rough size | |
| Where they are | |
| What they use today | |
| Their main pain | |

## Competitors

| # | App | Downloads | Strengths | Weaknesses | What we do differently |
|---|-----|-----------|-----------|------------|------------------------|
| 1 | | | | | |
| 2 | | | | | |
| 3 | | | | | |

## Differentiator

One sentence:

> Unlike **[competitor]**, our app **[does X]** for **[whom]**.

## MVP scope — cut / keep

The rule: **if it is not required for the first user's main flow, cut it.**

| Feature | Keep / Cut | Why |
|---------|-----------|-----|
| | | |
| | | |
| | | |

### Explicitly out of v1

-
-

## The main flow

The one path a first-time user takes. Everything else is secondary.

```
install -> onboarding -> ??? -> value delivered -> return reason
```

## Design system

| Token | Value |
|-------|-------|
| Primary color | |
| Surface / background | |
| Accent | |
| Error | |
| Heading font | |
| Body font | |
| Spacing scale | 4 / 8 / 12 / 16 / 24 / 32 |
| Corner radius | |

Decide light/dark now. Retrofitting dark mode is a full pass over every widget.

## Monetization

- Model: freemium / IAP / subscription / ads / none
- What is free, what is paid:
- Price point and why:
- When the paywall appears (first run? after N uses? behind a feature?):
- Realistic revenue estimate for month 1:

## Viral loop

How does it spread without paid acquisition? "None yet" is a valid answer at D1 —
write it down so it stays a decision rather than an oversight.

>

## Top 3 risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| | | | |
| | | | |
| | | | |

## Platform decisions

| Decision | Value | Why |
|----------|-------|-----|
| Minimum Android SDK | | |
| Minimum iOS version | | |
| Tablet support | yes / no | |
| Landscape | yes / no | |
| Web build | yes / no | |
| Offline mode | yes / no | |

Note: raising the minimum OS later is effectively free; lowering it never is.
Start narrower than you think you need.
