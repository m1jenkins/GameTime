# Floodlight 09.1 — Toned, refined

September 27, 2026. [Open the prototype](index.html). **Proposal, not adopted.**
Round 9 Toned remains the adopted direction. Round 9 and earlier rounds are
unchanged, and nothing here changes the native app, accounts, services or
product rules.

This round applies a design critique of round 9 Toned. It keeps the Aero gloss
material, Barlow type, layout, fixtures and states (day, 2/4/6 people,
Jordan's three update states, larger text). The page shows only Aero Toned,
because that is what the owner adopted. The depth picker and the Floodlit
material are still available in [round 9](../round-9/index.html).

## Product rule: the shared pot is confirmed

The shared pot is the confirmed rule. If one person reaches the goal, they get
both stakes. The pot, its sheet, the three outcome cards and the full rules
wording are exactly as in round 9. There is no Stakes toggle and no
personal-only variant.

## The fixes, before and after

| # | Fix | Round 9 Toned | 9.1 |
| --- | --- | --- | --- |
| 1 | Blue on blue | The sky gradient filled the whole phone, so the cards, pot and buttons all sat on blue and only the orange You ring stood out. | The sky sits behind each screen's hero only: the Challenge dial and the name row, Home's top challenge card, and the Invitation title and header. It then fades to a near-white cool ground, `#F6F8FB`. The status bar picks up the ground once the page scrolls. |
| 2 | Too much frost | Every card was frosted glass with a backdrop blur. | Each screen has one Toned frosted surface: Home's challenge card and the Invitation header. On Challenge, the glass dial face is the hero, so no card there is frosted. Everything else uses the Quiet card: solid white, a hairline edge, a light shadow and no blur. That covers the Next up rows, "Priya reached their goal", the stake, pot and fee tiles, the rule outcome cards, the facts list, Full rules, the You detail card and the stake card. The tab bar and sheets are solid too. |
| 3 | Marble avatars | Soft spheres with a small highlight, both in the name row and on the dial. | People use the Quiet level everywhere: a flat member-color fill and a soft shadow, with no highlight. The dial markers and the outcome pictograms are flat too. The depth stays in the dial's recessed rings and arcs. |
| 4 | Invitation dial | A large empty glass dial took up the top half before any progress existed. | A compact frosted header: the pot disc at 76px (Toned, same crescent highlight), "20 km each", the dates and the two people. Measured in the phone, the stake tiles move up 129px (438 → 309) and "You both agree to these rules" moves up 172px (602 → 430). |
| 5 | Simulated stakes pill | "Simulated stakes — no real money moves." sat in a pill at the top of every phone. | The pill is gone. The line appears once as a muted footnote under the Invitation's stake tiles, and in the pot sheet as before. Screen readers still hear it first on Challenge and Home. The pot, stake and Home card labels still say "simulated stakes". On the Invitation it is the footnote after the tiles. |
| 6 | Buttons | Deep blue gradient pill (`#2A93E3`→`#0B5CB0`). | Quiet: a flat `#0F63B6` pill with white text and a small shadow. This applies to Review and agree and to the See button. The dial, the pot disc and the arcs stay Toned. |

### Where 9.1 differs from the brief

- **The 20 km each row.** The brief lists this row among the Quiet cards. The
  new Invitation header already says "20 km each" next to the pot. Keeping
  the row would have repeated it a few lines lower, so the row was folded into
  the header, along with its two people. If the owner prefers a separate row,
  it would be a Quiet card.
- **Tab bar and sheets.** These are not cards, but they were frosted in
  round 9. They are solid in 9.1 so that each screen's hero stays the only
  glass surface.

## Values

| Token | Value |
| --- | --- |
| Ground | `#F6F8FB` |
| Sky (hero zone) | `#6CC2F4` → `#A6DDFA` 26% → `#D6EFFC` 56% → `#EBF4FA` 80% → `#F6F8FB` |
| Quiet card | `#FFFFFF`, 1px `rgba(10,45,68,.07)` edge, shadow `0 1px 2px rgba(10,45,68,.05), 0 8px 18px -14px rgba(18,72,120,.32)`, no blur |
| Icon wells inside Quiet cards | `#EEF3F7` |
| Person | flat `var(--p)`, shadow `0 5px 10px -6px`, no highlight |
| Primary button | flat `#0F63B6`, white text |
| Hero card, dial, arcs, pot | unchanged Toned values from round 9 |

## Checks performed

Chromium (Playwright 1.63) at 1440px and 390px
([checks.json](captures/checks.json)):

- No console errors or warnings. No horizontal page overflow at either width.
- The stakes pill is gone from all three phones. The visible footnote appears
  once, on the Invitation, and again in the pot sheet. Challenge and Home keep
  a screen-reader line.
- Only the hero cards have a backdrop blur (none on Challenge, the challenge
  card on Home, the header on Invitation). The Invitation has no dial, and no
  Stakes toggle exists.
- A sweep of 28 combinations (every day, 2/4/6 people, Jordan's three states)
  found no malformed dial paths and no overflow inside a phone. With larger
  text on, the Invitation header does not overflow.
- The pot sheet moves focus to Close, and Escape returns focus to the pot.
- Contrast of white text: flat button `#0F63B6` 6.03:1; pot disc 4.67:1 at
  its lightest stop (`#1A76CB`) and 5.54:1 at its middle; pot bar in the sheet
  5.09:1 at its middle. Muted text on the ground is 6.12:1.
- The unslop phrase and structure scanners report nothing on the page text,
  the pot sheet or either rules sheet.

Captures: [toned.png](captures/toned.png) (all three phones),
[phone-width.png](captures/phone-width.png) (390px),
[invitation.png](captures/invitation.png). Extra captures:
[pot-sheet.png](captures/pot-sheet.png) and
[invitation-rules.png](captures/invitation-rules.png) (scrolled, with the
status bar on the ground).

Not performed: native SwiftUI, VoiceOver, Dynamic Type, a contrast audit of
every state, blur performance on a phone, and any device run.

## Responsible engagement

Nothing new pushes use or stakes. The stakes line moved off every screen's
top, so it is less prominent on Challenge and Home. It is still spoken there
and shown where someone agrees to stakes (the Invitation) and where the pot is
explained (the pot sheet). No rankings, countdowns, money celebrations,
notifications, analytics or payment behavior were added.
