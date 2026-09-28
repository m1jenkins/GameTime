# Floodlight 09.2: Toned, light and dark

September 27, 2026. [Open the prototype](index.html). **Proposal, not adopted.**
Round 9 Toned remains the adopted direction. Round 9.1, round 9 and earlier
rounds are unchanged, and nothing here changes the native app, accounts,
services or product rules.

The owner decided that Floodlit, the WHOOP-style slate material, becomes
GameTime's dark mode, and that round 9.1's Aero Toned is light mode. This round
builds that dark mode with the same restraint 9.1 applied to light. Both modes
come from one set of semantic tokens.

## Product rule: the shared pot is confirmed

Unchanged from 9.1. If one person reaches the goal, they get both stakes. The
pot, its sheet, the three outcome cards and the full rules wording are the same
in both modes. There is no Stakes toggle.

## Dark mode, toned the way 9.1 toned light

| 9.1 rule for light | Dark mode in 9.2 |
| --- | --- |
| The sky sits only behind the hero, then fades to a near-white ground. | Floodlight beams and a soft bloom sit only behind the hero (Challenge's dial and names, Home's top card, the Invitation's title and header). They fade into a plain slate ground, `#0E161A`. The status bar takes the slate color once the page scrolls. |
| One frosted surface per screen. | One lit surface per screen: the dial plate on Challenge, the top card on Home, the header on the Invitation. The lit card is a slate gradient (`#22343D` → `#18252B`) with a brighter top highlight and a faint wash of beam light along its top edge. It has no backdrop blur. |
| Everything else is a Quiet card. | Everything else is a quiet dark card: solid `#172227`, a 7% white top hairline, a soft shadow, no glow and no blur. The tab bar and sheets are solid too. |
| People are flat. | People are flat member-color fills, including the selected person, who had a glow in round 9 Floodlit. |
| Buttons are flat. | Buttons are a flat `#1D6CBE` pill with white text. |
| The dial, arcs and pot stay Toned. | The dial plate, recessed tracks, arcs with a soft bloom and a smoked-glass pot stay at Toned depth. See below. |

### Depth kept at Toned

Round 9's Floodlit Round 8 values are the reference. Each part steps down the
way Aero did from Round 8 to Toned.

| Part | Round 8 Floodlit | Round 9 Floodlit Toned | 9.2 dark |
| --- | --- | --- | --- |
| Arc bloom | 0.8 | 0.36 | 0.34 |
| Arc highlight | 30% white | 12% | 12% |
| Arc tail (lean toward slate) | 60% | 45% | 30%, so every tail stays at or above 4:1 on its track |
| Token halo | 0.34 | 0.10 | 0.08 |
| Pot | glossy dome | crescent, 22% | smoked glass: `#3A5561` → `#22363F` → `#111D22`, a metal bezel and a 22% crescent |
| Beams | 0.7 plus glints | 0.28 | 0.30, behind the hero only |
| Text and number glow | 26px glow | 16px on numbers | none |
| Pip, tab and bar glow | full | halved | none |

## One part, one counterpart

| Light (9.1 Aero Toned) | Dark (9.2 Floodlit Toned) | Tokens |
| --- | --- | --- |
| Sky | Floodlight beams | `backdrop-1…4`, `backdrop-art` |
| Glass dial face | Lit slate plate | `plate-*`, `track*`, `tick*` |
| Aero pot | Smoked-glass pot | `pot-*` |
| Frosted hero card | Top-highlight card | `hero-*` |
| Near-white ground | Slate ground | `ground` |
| White Quiet card | Quiet dark card | `card*`, `well*` |
| Flat blue button | Flat blue button, one step lighter | `button*` |
| Member colors | Lighter tints of the same hue | `member-*` |

The page shows this as a part-by-part grid, painted from the same tokens.

## Tokens

The CSS defines each token once under `[data-mode=light]` and once under
`[data-mode=dark]`. The screens read only the tokens, and the prototype's
script reads them back from the CSS (member colors, dial and pot paint, and the
on-page table), so the table below cannot drift from what the phones show.

For SwiftUI, each color row is one asset color in the catalog with an Any
appearance (Light) and a Dark appearance. Rows marked *modifier* become
`.shadow` or `.background(.ultraThinMaterial)` (light) versus a solid fill
(dark). Rows marked *number* are constants per scheme.

| Token | Paints | Light | Dark | SwiftUI |
| --- | --- | --- | --- | --- |
| **Surfaces** | | | | |
| `--gt-ground` | Screen ground below the hero | `#F6F8FB` | `#0E161A` | `Ground` |
| `--gt-backdrop-1` | Hero backdrop, top (sky / beams) | `#6CC2F4` | `#2A3E48` | `Backdrop1` |
| `--gt-backdrop-2` | Hero backdrop, 26% | `#A6DDFA` | `#1E2E36` | `Backdrop2` |
| `--gt-backdrop-3` | Hero backdrop, 56% | `#D6EFFC` | `#162329` | `Backdrop3` |
| `--gt-backdrop-4` | Hero backdrop, 80%, then Ground | `#EBF4FA` | `#111B20` | `Backdrop4` |
| `--gt-backdrop-art` | Opacity of the swoosh / beam art | `.32` | `.3` | number |
| **Hero card** | | | | |
| `--gt-hero-top` | Lit surface, top (Home card, Invitation header) | `rgba(255,255,255,.86)` | `#22343D` | `HeroTop` |
| `--gt-hero-bottom` | Lit surface, bottom | `rgba(255,255,255,.52)` | `#18252B` | `HeroBottom` |
| `--gt-hero-edge` | Lit surface border | `rgba(255,255,255,.96)` | `rgba(255,255,255,.07)` | `HeroEdge` |
| `--gt-hero-highlight` | Top inner highlight line | `#FFFFFF` | `rgba(255,255,255,.16)` | `HeroHighlight` |
| `--gt-hero-glow` | Light falling on the top edge | `rgba(255,255,255,0)` | `rgba(150,214,245,.12)` | `HeroGlow` |
| `--gt-hero-material` | Backdrop material | `blur(14px) saturate(1.5)` | `none` | modifier |
| `--gt-hero-shadow` | Drop shadow | `0 12px 26px -16px rgba(18,92,146,.42)` | `0 14px 30px -16px rgba(0,0,0,.6)` | modifier |
| **Quiet card** | | | | |
| `--gt-card` | Lists, tiles, outcome cards, facts, You card | `#FFFFFF` | `#172227` | `Card` |
| `--gt-card-edge` | Card border | `rgba(10,45,68,.07)` | `rgba(255,255,255,.05)` | `CardEdge` |
| `--gt-card-highlight` | Top hairline highlight | `rgba(255,255,255,0)` | `rgba(255,255,255,.07)` | `CardHighlight` |
| `--gt-card-shadow` | Drop shadow | `0 1px 2px rgba(10,45,68,.05),0 8px 18px -14px rgba(18,72,120,.32)` | `0 1px 2px rgba(0,0,0,.3),0 10px 20px -14px rgba(0,0,0,.7)` | modifier |
| `--gt-well` | Icon wells and chips inside cards | `#EEF3F7` | `#213038` | `Well` |
| `--gt-well-edge` | Well border | `rgba(10,45,68,.09)` | `rgba(255,255,255,.06)` | `WellEdge` |
| **Chrome** | | | | |
| `--gt-bar` | Tab bar | `#FFFFFF` | `#121B20` | `Bar` |
| `--gt-bar-edge` | Tab bar and sheet top edge | `rgba(10,45,68,.08)` | `rgba(255,255,255,.07)` | `BarEdge` |
| `--gt-sheet` | Sheets | `#FFFFFF` | `#162026` | `Sheet` |
| `--gt-scrim` | Behind a sheet | `rgba(8,48,78,.3)` | `rgba(3,7,9,.62)` | `Scrim` |
| `--gt-status-scrolled` | Status bar once the page scrolls | `rgba(246,248,251,.94)` | `rgba(14,22,26,.94)` | `StatusScrolled` |
| **Text** | | | | |
| `--gt-ink` | Primary text | `#0A2D44` | `#EEF4F7` | `Ink` |
| `--gt-muted` | Secondary text | `#3E6278` | `#9FB2BB` | `Muted` |
| `--gt-hero-muted` | Secondary text on the hero backdrop | `#365A70` | `#D2DDE2` | `HeroMuted` |
| `--gt-faint` | Inactive tab labels | `#5E7F93` | `#8FA3AD` | `Faint` |
| `--gt-line` | Dividers | `rgba(10,45,68,.12)` | `rgba(255,255,255,.08)` | `Line` |
| **Accent** | | | | |
| `--gt-accent` | Today pip, fact icons, active tab | `#0E86E0` | `#BFEBFF` | `Accent` |
| `--gt-brand` | GameTime mark | `#E2461E` | `#FF6B45` | `Brand` |
| **Button** | | | | |
| `--gt-button` | Flat primary button | `#0F63B6` | `#1D6CBE` | `Button` |
| `--gt-button-ink` | Button label | `#FFFFFF` | `#FFFFFF` | `ButtonInk` |
| `--gt-button-shadow` | Button shadow | `0 4px 10px -6px rgba(10,90,170,.45)` | `0 4px 10px -6px rgba(0,0,0,.6)` | modifier |
| **Dial** | | | | |
| `--gt-plate-top` | Dial face, center top | `rgba(255,255,255,.96)` | `#2A3E48` | `PlateTop` |
| `--gt-plate-mid` | Dial face, 60% | `rgba(238,248,255,.86)` | `#17242B` | `PlateMid` |
| `--gt-plate-bottom` | Dial face, edge | `rgba(213,237,251,.84)` | `#0C1418` | `PlateBottom` |
| `--gt-plate-rim-top` | Dial rim, top | `#FFFFFF` | `rgba(200,236,255,.4)` | `PlateRimTop` |
| `--gt-plate-rim-bottom` | Dial rim, bottom | `#A9D6F0` | `rgba(200,236,255,0)` | `PlateRimBottom` |
| `--gt-plate-light` | Light across the upper face | `rgba(255,255,255,.4)` | `rgba(191,235,255,.07)` | `PlateLight` |
| `--gt-track` | Recessed track | `rgba(255,255,255,.86)` | `#050A0D` | `Track` |
| `--gt-track-edge` | Track lip | `rgba(10,70,112,.2)` | `rgba(255,255,255,.055)` | `TrackEdge` |
| `--gt-tick` | Minor ticks | `rgba(10,45,68,.3)` | `rgba(205,230,242,.4)` | `Tick` |
| `--gt-tick-major` | Major ticks and finish flag | `rgba(10,45,68,.78)` | `rgba(236,248,255,.92)` | `TickMajor` |
| `--gt-arc-bloom` | Arc bloom opacity | `.2` | `.34` | number |
| `--gt-arc-highlight` | Arc top highlight | `rgba(255,255,255,.26)` | `rgba(255,255,255,.12)` | `ArcHighlight` |
| `--gt-arc-tail` | Color the arc starts from | `#FFFFFF` | `#0B1418` | `ArcTail` |
| `--gt-arc-tail-mix` | How far the tail leans to ArcTail | `.28` | `.3` | number |
| **Pot** | | | | |
| `--gt-pot-top` | Pot disc, top | `#1A76CB` | `#3A5561` | `PotTop` |
| `--gt-pot-mid` | Pot disc, middle | `#1569BD` | `#22363F` | `PotMid` |
| `--gt-pot-bottom` | Pot disc, bottom | `#0A4F99` | `#111D22` | `PotBottom` |
| `--gt-pot-rim-top` | Pot bezel, top | `#FFFFFF` | `#B7CBD4` | `PotRimTop` |
| `--gt-pot-rim-bottom` | Pot bezel, bottom | `#C7E4F5` | `#10191D` | `PotRimBottom` |
| `--gt-pot-shine` | Crescent highlight | `rgba(255,255,255,.45)` | `rgba(255,255,255,.22)` | `PotShine` |
| `--gt-pot-label` | “POT” caption | `rgba(255,255,255,.92)` | `rgba(214,236,246,.85)` | `PotLabel` |
| `--gt-pot-ink` | Pot amount | `#FFFFFF` | `#FFFFFF` | `PotInk` |
| `--gt-pot-bar-top` | Pot bar in the sheet, top | `#1F84D8` | `#2A424D` | `PotBarTop` |
| `--gt-pot-bar-bottom` | Pot bar in the sheet, bottom | `#0A55A6` | `#14222A` | `PotBarBottom` |
| **People** | | | | |
| `--gt-member-you` | You | `#FF6428` | `#FF8B5E` | `MemberYou` |
| `--gt-member-sam` | Sam | `#1C98F4` | `#55B2F7` | `MemberSam` |
| `--gt-member-jordan` | Jordan | `#27B155` | `#5DC580` | `MemberJordan` |
| `--gt-member-priya` | Priya | `#9357F6` | `#AE81F8` | `MemberPriya` |
| `--gt-member-maya` | Maya | `#F2A00C` | `#F5B849` | `MemberMaya` |
| `--gt-member-theo` | Theo | `#F24A93` | `#F577AE` | `MemberTheo` |

### Member colors across modes

Each dark member color is the light color mixed 25% toward white. Measured in
OKLCH, every dark tint is lighter than its light color and keeps its hue
within 7°: You 2.2°, Sam 4.3°, Jordan 3.2°, Priya 3.0°, Maya 6.9° and Theo
3.6°. You stays orange and Sam stays blue.

### Where light differs from 9.1

Light keeps 9.1's values except in two places:

- **`hero-muted` is new.** It colors secondary text on the sky: dates,
  "Jordan invited you", "Not started" and the names under the dial. With
  9.1's Muted, Challenge's dates measured 4.40:1 and Home's date 4.42:1.
  With `#365A70`, every measured hero label is 4.97:1 or better. Dark needs
  the same split. On the beams, plain Muted measured 3.34:1 on "Not started",
  3.82:1 on Home's date and 4.25:1 on "Jordan invited you". With `#D2DDE2`
  the worst is 5.31:1.
- **Sheets are flat white.** 9.1 faded them to `#F6F8FB` at the bottom. One
  flat value per mode maps directly to an asset color.

## Page layout

- An **Appearance** control offers Light, Dark and Side by side. Side by side
  is the default. It shows one row per screen, with light beside dark and a
  short list of that screen's part mapping next to them.
- Light or Dark shows the three phones in one mode, and the review page
  switches to match.
- **prefers-color-scheme.** When the single-mode view opens without a pick,
  it follows the system setting and follows later changes until someone taps
  a mode. That happens at phone width (760px or less), where two tall phones
  per row are cramped, and when the page is opened with `#single`. `#light`,
  `#dark` and `#both` open a fixed view. At 1440px the default stays Side by
  side, whatever the system setting.

## Checks performed

Chromium through Playwright 1.63, at 1440px and 390px. Full results are in
[checks.json](captures/checks.json).

- No console errors or warnings. No horizontal page overflow at 1440px or at
  390px, in Side by side, Light or Dark.
- Appearance: Side by side by default at 1440px under both a light and a dark
  system setting, with six phones. Tapping Dark or Light shows three phones.
  At 390px the view follows the system (a dark system shows the dark phones).
  `#single` follows the system, including a live switch from dark to light.
- Structure in each dark phone: exactly one lit surface (the dial plate on
  Challenge, the top card on Home, the header on the Invitation). There is no
  backdrop blur anywhere in dark. People are flat fills with no gradient, and
  buttons are a single flat color. The rendered card, ground and button
  colors equal their tokens. There is no stakes pill.
- A sweep of 49 combinations (every day, 2/4/6 people, Jordan's three update
  states) across all six phones found no malformed dial paths and no overflow
  inside a phone. With larger text on, the dark Invitation header does not
  overflow.
- The dark pot sheet moves focus to Close and shows the simulated-stakes
  footnote. Escape returns focus to the pot. The dark Invitation's status bar
  turns slate once it scrolls.

### Dark contrast (target 4.5:1 for text, 3:1 for arcs)

| Pair | Ratio |
| --- | --- |
| White amount on the pot: top / middle / bottom | 7.92 / 12.59 / 17.18 |
| "POT" caption on the pot's top | 5.22 |
| White amount on the pot bar: top / bottom | 10.58 / 16.25 |
| White on the button (`#1D6CBE`) | 5.33 |
| Ink on ground / quiet card / top-highlight card top / sheet / tab bar | 16.47 / 14.61 / 11.63 / 14.91 / 15.72 |
| Muted on ground / quiet card / well / top-highlight card top / sheet | 8.32 / 7.38 / 6.19 / 5.88 / 7.54 |
| Inactive tab label on the tab bar | 6.66 |
| Hero-zone labels, measured from pixels behind the glyphs (dates, invited by, Not started, home date) | 5.31 to 7.35 |
| Initials on member fills | 6.52 (Priya) to 10.58 (Maya) |
| Arc head on its track | 6.91 (Priya) to 11.21 (Maya) |
| Arc tail on its track | 4.00 (Priya) to 6.00 (Maya) |

All dark pairs meet their target. checks.json also records light mode for
reference. These light values are unchanged from 9.1 and miss 4.5:1: the
"POT" caption at the pot's lightest stop (4.21), the pot bar's lightest stop
under its amount (3.92), and inactive tab labels (4.26). Light arcs on their
white tracks measure 2.1–4.2:1. These are open items for light mode, not
changes made here.

The unslop phrase and structure scanners report nothing on the page text or
the pot sheet. Both rules sheets get one soft sentence-rhythm flag. Their
wording is unchanged from 9.1 and was left alone.

Captures:
[side-by-side.png](captures/side-by-side.png) (all six phones),
[dark.png](captures/dark.png) (three dark phones),
[dark-pot-sheet.png](captures/dark-pot-sheet.png) and
[phone-width-dark.png](captures/phone-width-dark.png) (390px, dark system).

Not performed: native SwiftUI, VoiceOver, Dynamic Type, OLED rendering on a
phone, a contrast audit of every state, and any device run.

## Responsible engagement

Nothing new pushes use or stakes. Dark mode adds no rankings, countdowns,
money celebrations, notifications, analytics or payment behavior. The pot
stays a dim smoked disc rather than a bright object, and the stakes wording is
where 9.1 put it.
