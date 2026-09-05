# Better Bet mockups — LLM handoff

> **Historical design reference — September 4, 2026.** Better Bet is an old
> concept name, not the current GameTime identity. These assets and embedded
> prompts remain visual exploration only. Use the adopted model in
> [BUSINESS_MODEL.md](../../BUSINESS_MODEL.md) and the current roadmap before
> new product work; no mockup establishes a live balance, payout or feature.

Everything a fresh chat (or a different LLM) needs to continue refining these designs without re-discovery.

## If the next chat is in this workspace

Just say: **"Continue the Better Bet design mockups in `docs/design/better-bet-mockups/`"** and point at this file. All sources are local and self-contained.

## If it's a different LLM or tool

Attach or paste, in priority order:

1. **The HTML source of the screen(s) you want to iterate on** — each `*.html` file is fully self-contained (inline CSS + SVG, system fonts, no external assets). This is the ground truth; an LLM can read and edit it directly.
2. **The PNG renders** for visual reference (`a-position-*.png`, `b-traininglog-*.png`, `c-nightsplits-*.png`).
3. **The brief below**, pasted verbatim.

## Ready-to-paste brief

```
You are refining mobile app mockups for "Better Bet" — an iOS app where you bet
$10 on yourself: hit 70,000 verified steps across 7 days (daily goal 10,000,
data from Apple Health) or lose the stake. Screens are 853x1844 px, built as
self-contained HTML (inline CSS/SVG, -apple-system fonts, tabular numerals)
rendered via headless Chrome: --window-size=853,1844 --screenshot.

Current directions (each has a Today screen and a Week screen):
- A "Position" — dark #0C0C0E, Robinhood-style: one huge number, neon green
  #00FF23 P&L line chart vs dashed required-pace line to a 70,000 goal line,
  flush day ledger rows (MET/LIVE/—), stake stated as plain text.
- B "Training Log" — light #F7F6F2, Strava-style: heavy black grotesque numbers,
  hot orange #FF4D00 reserved for the live day, seven-day bar strip with dashed
  future days, week view as a feed where Today inverts to a black block.
- C "Night Splits" — dark #151515 athletic instrument: the 7 days are a vertical
  split ladder; completed days compress (green #48D08C MET), today expands into
  a saturated coral band #FF453A with the only big number; week view is
  horizontal split bars against a 10K tick.
- A2 "Position · Liquid Glass" — evolution of A: frosted floating sheets and tab
  bar (backdrop blur 44px + saturate 170%, 165° gradient fill, hairline rim,
  specular top highlight), ambient aurora glow field behind the glass, and a
  stateful accent: the whole screen flips green #00FF23 → red #FF4D3D when
  behind pace (behind screen: three MISSED days, −7,900, CTA "Sync now — still
  winnable").

Hard product constraints (do not add unsupported data):
- Supported: 7 daily step totals, daily goal + verified progress, current day +
  exact local cutoff (11:59 PM CDT), challenge end + frozen timezone
  (America/Chicago), Apple Health source + freshness, $10.00 test commitment.
- Forbidden: intraday curves, route maps, calories, heart rate, streaks,
  leaderboards, social mechanics, real balances/winnings.
- The $10 stake is always plain text — never a hero element, never casino chrome.
- Data must be internally consistent: day rows sum exactly to week totals;
  sub-10K days are MISSED, not MET.

Canonical demo data: Day 4 of 7 (Thursday), today 7,350/10,000, week 42,350,
+2,350 ahead of pace, days Mon 12,430 / Tue 11,980 / Wed 10,590 / Thu 7,350.
```

## File map

| File | What it is |
| --- | --- |
| `README.md` | Direction write-ups, palettes, rationale, render notes |
| `gen.py` / `gen2.py` | Generators for v1 directions / A2 — edit these, don't hand-edit HTML |
| `a-position-*.html/png` | Direction A (dark money) — PNGs are first-pass (edge labels clip) |
| `b-traininglog-*.html/png` | Direction B (light athletic) — week PNG crops Sunday row |
| `c-nightsplits-*.html/png` | Direction C (dark splits) — final renders |
| `a2-glass-*.html` | A2 Liquid Glass core screens (Today / Week ahead / Week behind) — final sources |
| `a3-commit.html`, `a3-result-won.html`, `a3-result-lost.html`, `a3-you.html` | A3 full-set pages: place-bet modal, win/lose results, profile — final sources |
| `gen3.py` (in `tmp/bet_mockups/`) | Generator for the A3 set — canonical source for structural edits |
| `sheet.html` | Contact sheet of all v1 screens |

## Re-render command

```
cd docs/design/better-bet-mockups
for f in *.html; do
  [ "$f" = "sheet.html" ] && continue
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu \
    --hide-scrollbars --window-size=853,1844 --screenshot="${f%.html}.png" "file://$PWD/$f"
done
```

Note: `gen.py` and `gen2.py` write their HTML output next to themselves — run them from this directory (or copy them back to a build dir) before re-rendering.

## Open threads

- A/B v1 PNGs predate two fixes already in the HTML (chart edge-label clipping; Sunday row cropped on week screens) — re-render to refresh.
- No A2/A3 PNGs have been rendered yet (headless-Chrome command approvals kept expiring) — all A2/A3 HTML is final; open in a browser or run the re-render command.
- Likely next explorations: type upgrade to a condensed grotesque for the hero numerals, motion spec (live dot pulse, chart draw-on, glass sheet spring-in), empty/first-run state, and a "syncing" interstitial between Commit and Today.
