# Floodlight 09.3: light contrast and a blue dark pot

September 27, 2026. [Open the prototype](index.html). **Adopted.** On
September 27 the owner adopted 9.3 as the visual direction: Aero Toned in
light, Floodlit (toned) in dark, one shared token set, native following the
system appearance, and Barlow bundled under the OFL. The adoption record is the
top entry of [the UI adoption history](../../../docs/design/SIGNAL_UI_MIGRATION.md).
Rounds 9.2, 9.1, 9 and earlier are unchanged, and nothing here changes the
native app, accounts, services or product rules.

9.3 is round 9.2 with three fixes. The token system, layout, shared pot,
Appearance control, copy and rules wording are unchanged. [Round 9.2's
record](../round-9-2/DESIGN.md) still describes everything this page doesn't
mention.

## 1. Light text contrast reaches 4.5:1

9.2 measured these against gradient stops. 9.3 also measures the pixels behind
each glyph, with the text hidden and shown, at 2× scale. That caught a problem
the stop-based number missed: the "POT" caption sits on the brightest point of
the pot's radial gradient, under the bottom of the crescent. Pure white there
measured only 3.93:1 on Home's small pot, so changing the caption color alone
was not enough.

| Token | 9.2 | 9.3 | Before | After |
| --- | --- | --- | --- | --- |
| `--gt-pot-label` | `rgba(255,255,255,.92)` | `#FFFFFF` | 4.21 (stop) / 3.93 (pixels) | 5.06 (stop) / 4.52 (pixels, worst) |
| `--gt-pot-shine` | `rgba(255,255,255,.45)` | `rgba(255,255,255,.3)` | | |
| `--gt-pot-top` | `#1A76CB` | `#1770C4` | amount 4.67 | amount 5.06 |
| `--gt-pot-bar-top` | `#1F84D8` | `#1A79CC` | 3.92 | 4.52 (stop) / 5.07 (pixels) |
| `--gt-faint` | `#5E7F93` | `#5A7B8F` | 4.26 | 4.50 |

For the caption, the smallest passing combination was a white caption, a
slightly weaker crescent and a pot top about one step darker. Darkening the pot
top alone needed `#146ABC`, which nearly matches the middle stop and flattens
the pot. Weakening the crescent alone needed .2, which mostly removes it. Per
pot, the worst caption pixels now measure 4.70 (Challenge), 4.52 (Home) and
4.64 (Invitation).

`pot-bar-top` moves 23% of the way toward `pot-bar-bottom`, the smallest step
along the bar's own gradient that passes. `faint` moves 5% toward `ink`.

## 2. Light arcs read against their tracks at 3:1

9.2 measured the white tracks as `#FCFEFF`. The rendered track is actually
`#F3F7F9`, because the 86% white fill lets the plate's blue through and the
inset shadow darkens it. It also measured arcs only at full opacity. When a
person is selected, the other lanes drop to 78% opacity, and that is the
Challenge screen's default state.

A darker or shaded track can't fix this. The member colors are mid-light, and
Maya's `#F2A00C` is only 2.14:1 even on pure white. Every step darker on the
track lowers contrast further. So 9.3 does two things:

- **A stronger fill.** `--gt-track` goes from `rgba(255,255,255,.86)` to opaque
  `#FFFFFF`. It renders as `#FFFFFF`, which gives the arcs the most room. The
  lip and inset shadow still show the recess.
- **A deeper arc, with a less washed-out start.** Each person gets an arc
  token. In light it is the member color with its OKLCH lightness lowered just
  enough to pass, keeping chroma and hue. The tail leans 16% toward white
  instead of 28%. Dimmed lanes use 88% opacity instead of 78% (new number
  token `--gt-arc-dim`, both modes).

People, avatars, legends and every other use of the member colors are
unchanged. Only the stroke on the dial uses the arc tokens. Dark arc tokens
equal the dark member colors, so dark arcs look the same as in 9.2.

| Person | Member (light) | `--gt-arc-*` light | Lightness drop | Hue shift | 9.2 tail / head | 9.3 head | 9.3 tail | 9.3 dimmed tail |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| You | `#FF6428` | `#D94000` | 0.104 | 2.3° | 2.21 / 2.92 | 4.48 | 3.62 | 3.11 |
| Sam | `#1C98F4` | `#0074CD` | 0.113 | 3.4° | 2.21 / 3.03 | 4.79 | 3.69 | 3.11 |
| Jordan | `#27B155` | `#008429` | 0.142 | 3.1° | 2.07 / 2.76 | 4.85 | 3.69 | 3.11 |
| Priya | `#9357F6` | `#894CEA` | 0.033 | 0.1° | 2.71 / 4.20 | 4.90 | 3.71 | 3.11 |
| Maya | `#F2A00C` | `#A95C00` | 0.218 | 13.1° | 1.72 / 2.11 | 4.98 | 3.73 | 3.11 |
| Theo | `#F24A93` | `#DA3180` | 0.065 | 0.3° | 2.45 / 3.36 | 4.44 | 3.62 | 3.12 |

9.2's ratios are against `#FCFEFF`, as recorded. 9.3's are against the rendered
`#FFFFFF`. The sweep also samples the rendered tail pixel of every lane in both
states. The lowest is 3.48 (Maya, dimmed).

Maya is the visible cost. A yellow can't reach 3:1 on white while staying
bright, and lowering its lightness at a fixed hue falls out of sRGB, so the
nearest in-gamut color shifts 13° toward orange. Her arc reads as a deep amber
beside her yellow avatar. It stays clearly apart from You's red-orange arc.
The other five stay within 3.4°.

There is still no gel edge, gloss or extra glow. The arc highlight and bloom
keep their 9.2 values.

## 3. Dark pot: smoked blue, the one saturated money element

9.2's smoked-glass pot went charcoal (OKLCH chroma 0.03–0.04), the same
family as the slate cards. 9.3 gives it the light pot's hue, darker and
smoked. The light pot is hue 252°–255° at chroma 0.14–0.15. The dark pot keeps
those hues at chroma 0.075–0.115 and a lower lightness, so it is still the
most saturated surface on a dark screen. The crescent stays the thin Toned
shape at 24% white, and the bezel turns a cool steel blue.

| Token | 9.2 dark | 9.3 dark | White amount, 9.2 → 9.3 |
| --- | --- | --- | --- |
| `--gt-pot-top` | `#3A5561` | `#215D99` | 7.92 → 6.80 |
| `--gt-pot-mid` | `#22363F` | `#164477` | 12.59 → 9.87 |
| `--gt-pot-bottom` | `#111D22` | `#072549` | 17.18 → 15.33 |
| `--gt-pot-rim-top` | `#B7CBD4` | `#A9C0DB` | |
| `--gt-pot-rim-bottom` | `#10191D` | `#0D1723` | |
| `--gt-pot-shine` | `rgba(255,255,255,.22)` | `rgba(255,255,255,.24)` | |
| `--gt-pot-label` | `rgba(214,236,246,.85)` | `rgba(220,233,249,.92)` | caption 5.22 → 4.95 (stop), worst pixels 4.64 |
| `--gt-pot-bar-top` | `#2A424D` | `#1E5790` | 10.58 → 7.44 (pixels 8.80) |
| `--gt-pot-bar-bottom` | `#14222A` | `#08284F` | 16.25 → 14.72 |

The same tokens paint the Challenge dial, Home's small dial, the Invitation
header pot, the part-by-part grid and the pot bar in the sheet. The page's
part mapping now says "Smoked blue pot".

## Token changes

The token table on the page is generated from the CSS, so it cannot drift. It
now has 71 rows: 64 from 9.2, plus `arc-dim` and six `arc-*` colors. Changed and
new rows:

| Token | Paints | Light | Dark | SwiftUI |
| --- | --- | --- | --- | --- |
| `--gt-faint` | Inactive tab labels | `#5A7B8F` | `#8FA3AD` | `Faint` |
| `--gt-track` | Recessed track | `#FFFFFF` | `#050A0D` | `Track` |
| `--gt-arc-tail-mix` | How far the tail leans to ArcTail | `.16` | `.3` | number |
| `--gt-arc-dim` *(new)* | Arc opacity while someone else is selected | `.88` | `.88` | number |
| `--gt-pot-top` | Pot disc, top | `#1770C4` | `#215D99` | `PotTop` |
| `--gt-pot-mid` | Pot disc, middle | `#1569BD` | `#164477` | `PotMid` |
| `--gt-pot-bottom` | Pot disc, bottom | `#0A4F99` | `#072549` | `PotBottom` |
| `--gt-pot-rim-top` | Pot bezel, top | `#FFFFFF` | `#A9C0DB` | `PotRimTop` |
| `--gt-pot-rim-bottom` | Pot bezel, bottom | `#C7E4F5` | `#0D1723` | `PotRimBottom` |
| `--gt-pot-shine` | Crescent highlight | `rgba(255,255,255,.3)` | `rgba(255,255,255,.24)` | `PotShine` |
| `--gt-pot-label` | “POT” caption | `#FFFFFF` | `rgba(220,233,249,.92)` | `PotLabel` |
| `--gt-pot-bar-top` | Pot bar in the sheet, top | `#1A79CC` | `#1E5790` | `PotBarTop` |
| `--gt-pot-bar-bottom` | Pot bar in the sheet, bottom | `#0A55A6` | `#08284F` | `PotBarBottom` |
| `--gt-arc-you` *(new)* | Your arc on the dial | `#D94000` | `#FF8B5E` | `ArcYou` |
| `--gt-arc-sam` *(new)* | Sam’s arc | `#0074CD` | `#55B2F7` | `ArcSam` |
| `--gt-arc-jordan` *(new)* | Jordan’s arc | `#008429` | `#5DC580` | `ArcJordan` |
| `--gt-arc-priya` *(new)* | Priya’s arc | `#894CEA` | `#AE81F8` | `ArcPriya` |
| `--gt-arc-maya` *(new)* | Maya’s arc | `#A95C00` | `#F5B849` | `ArcMaya` |
| `--gt-arc-theo` *(new)* | Theo’s arc | `#DA3180` | `#F577AE` | `ArcTheo` |

Some rows keep their light value and appear here because the dark value
changed, or the reverse.

## Checks performed

Chromium 153 through Playwright 1.63, at 1440px and 390px, 2× scale, reduced
motion. Full results are in [checks.json](captures/checks.json).

- No console errors or warnings. No horizontal page overflow at 1440px (Side
  by side, Light, Dark) or at 390px (light system, dark system, `#both`).
- Appearance: Side by side by default at 1440px under a light or a dark system
  setting, six phones. Tapping Dark or Light shows three phones. At 390px the
  view follows the system. `#single` follows the system, including a live
  switch from dark to light.
- Structure: one lit surface per phone (dial plate, Home top card, Invitation
  header), no backdrop blur in dark, and flat people in both modes.
- Rendered pot gradient stops and pot bar gradients equal their tokens in both
  modes. The 71 token rows render.
- Pot sheet in light and dark moves focus to Close and shows the
  simulated-stakes footnote. Escape returns focus to the pot. With larger text
  on, neither Invitation header overflows.
- The sweep covered 49 combinations: every day, 2, 4 or 6 people, and each of
  Jordan's three update states, across all six phones. It found no malformed
  dial paths and no overflow inside a phone.
- The contrast sweep has three parts. Token pairs cover text, buttons and
  icons. Pixel measurements cover every POT caption and amount, every inactive
  tab label, and the pot bar's amount and subline in both sheets. Arcs are
  checked with six people, with You selected and with nobody selected, using
  each lane's rendered track and tail pixels. Every item meets its target
  (4.5:1 for text, 3:1 for arcs and icons), and `contrastFailures` is empty.
  Dark results are unchanged from 9.2 apart from the pot rows above.

Captures:
[side-by-side.png](captures/side-by-side.png),
[light.png](captures/light.png), [dark.png](captures/dark.png),
[pot-sheet-light.png](captures/pot-sheet-light.png) and
[pot-sheet-dark.png](captures/pot-sheet-dark.png).

Not performed: native SwiftUI, VoiceOver, Dynamic Type, rendering on a phone
display, and any device run. `faint` and the pot bar top pass with little
margin (4.50 and 4.52), so a native build should re-measure them after color
management.

## Responsible engagement

Nothing new pushes use or stakes. The dark pot is more saturated so that it
reads as the same object as the light pot. There are no new money
celebrations, counts, countdowns, notifications, analytics or payment
behavior, and the simulated-stakes wording stays where 9.1 put it.
