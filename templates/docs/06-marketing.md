# 06 — Marketing

> Phase D17-D20. A shipped app nobody hears about is a hobby.

---

## Calendar

| Day | Action | Channel |
|-----|--------|---------|
| D-7 | Tease: one screenshot, no link | X / Bluesky / Mastodon |
| D-3 | Short demo clip (≤20s), still no link | same |
| D-1 | "Tomorrow." + the strongest screenshot | same + relevant subreddit |
| **D0** | Launch post + store links + landing page | all channels at once |
| D0 | Product Hunt listing goes live (00:01 PT) | Product Hunt |
| D+1 | Reply to every comment | everywhere |
| D+3 | "What I learned building X" — the build story | dev communities |
| D+7 | First metrics review; log them in `DECISIONS.md` | — |
| D+14 | Update post: what shipped since launch | all channels |

Concentration beats spread. Two channels done properly outperforms six abandoned
accounts.

---

## What to post on D0

### Short version (X / Bluesky / Mastodon)

```
I built <APP> in 20 days.

<one sentence on the problem>
<one sentence on the solution>

Free, no account needed: <link>

Built with Flutter. Ask me anything about the build.
```

The "ask me anything" line is what turns a post into a thread. Answer everything
for the first two hours.

### Reddit

Read the subreddit's self-promotion rules **first** — most ban link-dropping
outright. The post that works is a build story with the link in the comments, not
an ad. Lead with the numbers and the mistakes.

```
Title: I shipped <APP> in 20 days — here's what actually took the time

Body:
- what it does (2 lines)
- the part that took longest, and why
- the part I got wrong
- what I'd cut if I did it again
- link in the comments
```

### Product Hunt

| Field | Value |
|-------|-------|
| Name | |
| Tagline (≤60 chars) | |
| Topics | |
| First comment | |

The first comment is the pitch. Write it as a person, not a landing page.

---

## Landing page

One page. Above the fold: what it is, one screenshot, one line of copy, the store
badges. Below: three feature blocks, one testimonial-or-fact, one closing CTA.

Host it anywhere static. Ship it on D18, not D20 — an unreachable link in a
launch post is a wasted launch.

| | |
|---|---|
| URL | |
| Host | |
| Analytics | |

---

## Assets

| Asset | Size | Where used |
|-------|------|-----------|
| App icon | 1024×1024 | stores, landing, posts |
| Screenshots | 3-5, real data | stores, landing |
| Demo clip | ≤20s, captioned | social |
| OG image | 1200×630 | link previews everywhere |

Captions on the demo clip: most people watch social video muted.

---

## Metrics to log on D+7

| Metric | Value |
|--------|-------|
| Installs (Android / iOS) | |
| Landing page visits | |
| Store page views → installs | |
| Crash-free sessions | |
| D1 / D7 retention | |
| Revenue | |
| Best-performing channel | |

Log them in `DECISIONS.md`. The D+7 numbers decide what v1.1 is about — and they
are the only feedback that is not someone being polite.

---

## DoD for D18-D20

- [ ] Landing page live and reachable from a device with no cache
- [ ] Store links verified
- [ ] D0 posts published on at least two channels
- [ ] Product Hunt listing created
- [ ] D+7 metrics logged in `DECISIONS.md`
