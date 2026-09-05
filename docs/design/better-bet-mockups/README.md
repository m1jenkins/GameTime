# Better Bet — three new visual directions

> **Historical design reference — September 4, 2026.** Better Bet is an old
> concept name, not the current GameTime identity. These assets and embedded
> prompts remain visual exploration only. Use the adopted model in
> [BUSINESS_MODEL.md](../../BUSINESS_MODEL.md) and the current roadmap before
> new product work; no mockup establishes a live balance, payout or feature.

Status: concept mockups. No production SwiftUI has been changed.
Rendered at 853×1844. Sources: `gen.py` generates the per-screen HTML; PNGs are headless renders of those HTML files. `sheet.html` shows all six screens side by side.

## The brief

Replace the beige/lavender editorial look and the plain ledger look with something that feels like a performance instrument you have money on. Two poles requested: Strava's athletic energy, Robinhood's numerical confidence. Product truth is unchanged: seven daily step totals, daily goal 10,000, weekly goal 70,000, exact local cutoff, Apple Health freshness, $10.00 test commitment, frozen timezone.

## Direction A — Position (dark, money-led)

Files: `a-position-today.png`, `a-position-week.png`

The week is framed like a portfolio position. True near-black canvas (#0C0C0E), one enormous tabular number, and a single neon green (#00FF23) that means one thing: verified progress. The cumulative line is drawn like a P&L chart against a dashed required-pace line and a dashed 70,000 goal line; the glow sits on the live point only. Days are flush holdings-style rows with MET/LIVE/— states, no cards anywhere. Behind-pace states would flip to a hot red (#FF4D3D), giving the app a genuine win/loss nerve.

- Today screen: today's steps as the hero number, hairline progress rule with a glowing live dot, week chart as evidence below, stake stated in plain text ($10.00).
- Week screen: 42,350 with "+2,350 ahead of pace" treated exactly like an unrealized-gain readout; day ledger beneath.

Feel: confident, serious, a little dangerous. Most "Robinhood" of the three.

## Direction B — Training Log (light, athletic-led)

Files: `b-traininglog-today.png`, `b-traininglog-week.png`

The week is framed like a training log. Warm off-white canvas (#F7F6F2), heavy black grotesque numbers, and one hot orange (#FF4D00) reserved for whatever is live right now. Completed days are solid black bars; future days are dashed outlines that are structurally present but quiet; today is an orange fill climbing toward a dashed 10K goal line.

- Today screen: 7,350 in heavy black, a thick orange progress bar, and the seven-day bar strip as the week's fingerprint.
- Week screen: a feed of day entries; today inverts to a solid black block with orange accents — the one "card" in the system, earned by being live.

Feel: energetic, outdoorsy, immediate. Most "Strava" of the three.

## Direction C — Night Splits (dark, athletic instrument)

Files: `c-nightsplits-today.png`, `c-nightsplits-week.png`

A fusion: dark charcoal instrumentation (#151515) where the seven days are the entire interface, rendered as a split ladder. Completed days compress into factual rows with green (#48D08C) MET marks. Today expands into a saturated coral band (#FF453A) that contains the only large metric on the screen, its own progress rule, the cutoff time, and the Apple Health pulse. Future days queue beneath in graphite.

- Today screen: the split ladder with the live coral band in the middle — you read your week top to bottom like lap times.
- Week screen: horizontal split bars per day against a 10K tick; green = banked, coral = in progress, empty track = queued. Commitment sits at the bottom as a one-line receipt.

Feel: a lap sheet, not a dashboard. The most differentiated of the three.

## Known render notes

- The checked-in A/B PNGs are from the first render pass: A's chart edge labels (Mon/Sun) clip by a few pixels, and the A/B week screens crop the Sunday row at the tab bar. The checked-in HTML sources already contain those fixes — re-render `a-position-*` and `b-traininglog-*` with headless Chrome to refresh the PNGs:

  ```
  cd docs/design/better-bet-mockups
  for n in a-position-today a-position-week b-traininglog-today b-traininglog-week; do
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu \
      --hide-scrollbars --window-size=853,1844 --screenshot="$n.png" "file://$PWD/$n.html"
  done
  ```

## Direction A2 — Position · Liquid Glass (polished evolution of A)

Files: `a2-glass-today.html`, `a2-glass-week-ahead.html`, `a2-glass-week-behind.html` (PNGs pending re-render — open the HTML in any browser at 853×1844 for full fidelity)

A2 keeps A's skeleton (hero number, P&L chart, ledger) and rebuilds the material layer:

- **Liquid Glass surfaces.** The ledger sheet and the tab bar float as frosted panels: 44px backdrop blur with 170% saturation, a 165° white-to-clear gradient fill, a hairline rim, an inset top specular highlight, and a deep ambient shadow. The active tab sits in a tinted glass pill.
- **Ambient glow field.** The near-black canvas (#08080A) carries large blurred aurora fields — accent green up top, a cool blue counter-glow mid-screen — so the glass has color to refract. The accent tints the entire environment, not just UI chrome.
- **Chart craft.** Area fill fades from the line, a Gaussian-softened under-stroke gives the line its glow, the live point gets a halo ring, and day labels are inset so nothing clips.
- **Stateful accent.** The whole screen — glow field, chart, delta, CTA, live dot, active tab — flips from neon green (#00FF23) to hot red (#FF4D3D) when the week falls behind pace. The behind screen tells a coherent story: three MISSED days, −7,900, and a CTA that reads "Sync now — still winnable".
- **CTA as lit surface.** Solid accent fill with an inset top highlight and a colored drop shadow, so the button reads as glowing, not painted.

Data integrity: all day rows sum exactly to the week totals on every screen; sub-goal days are marked MISSED, not MET.

## The full screen set (A3)

The design now covers every page of the app. The three core screens live in the
`a2-glass-*` files; the four new pages are `a3-*`. Same design system, same tokens.

| Screen | File | Notes |
| --- | --- | --- |
| Today (live, ahead) | `a2-glass-today.html` | hero steps, glowing progress rule, week chart, Health + stake sheet |
| Week (ahead) | `a2-glass-week-ahead.html` | P&L chart, day ledger, green state |
| Week (behind) | `a2-glass-week-behind.html` | full red state flip, MISSED days, "still winnable" CTA |
| Commit (place bet) | `a3-commit.html` | modal, no tab bar, glass close button, $10 hero, terms ledger, ghost "How verification works" |
| Result — won | `a3-result-won.html` | 71,240 verified, CHALLENGE WON, per-day split bars vs 10K tick, stake RETURNED |
| Result — lost | `a3-result-lost.html` | 62,480 verified, short by 7,520, stake FORFEITED, "Run it back" CTA |
| You | `a3-you.html` | glass avatar, BETS/WON/STEPS stat strip, live + history ledger, Health/timezone/terms |

Data integrity across the set: result weeks sum exactly (71,240 and 62,480),
sub-10K days render gray (below the tick) rather than green, and the You screen
history matches the result screens (Aug 4 won 71,240 · Jul 28 lost 62,480 ·
Jul 21 won 73,510; totals 4 bets / 2 won / 249,580 steps incl. live week).

## What every direction keeps

- Exact local cutoff and frozen timezone always visible.
- Apple Health source and freshness always on the primary screen.
- The $10.00 commitment stated as plain text — never a hero, never gamified with currency chrome.
- No intraday curves, routes, calories, streaks, leaderboards, or social mechanics.
