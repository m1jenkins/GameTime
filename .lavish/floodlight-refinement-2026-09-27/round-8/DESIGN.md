# Floodlight 08 — Lit

Design-only proposal, September 27, 2026. [Open the prototype](index.html).
Round seven stays preserved. Nothing here changes the native app, its adopted
theme, accounts, services or product rules.

## The request

The owner, on round seven: "I think what's missing from Floodlight is a feeling
of depth. It's a very flat design. I feel like um, some Frutiger Arrow or more
3D elements would do well. Similar to what Whoop app looks like. I also think I
want to greatly cut down on the amount of text on these pages. Use the unslop
skill and try to use visuals where appropriate instead of walls of text and
sentences."

## Two materials, one layout

The Material control switches every phone between two treatments of the same
screens, data and rules.

| | Floodlit (WHOOP-style) | Aero gloss (Frutiger Aero) |
| --- | --- | --- |
| Ground | Slate `#2B3D46` to `#0A1114`, floodlight beams from the top corners | Sky `#6CC2F4` to white, two glass swooshes, a lens flare |
| Dial face | Dark plate `#283B45`/`#0B1317` with a lit rim | Clear glass plate with a white sheen and an aqua rim |
| Tracks | Recessed channels `#050A0D` with an inner shadow | White glass tubes with a soft inner shadow |
| Progress | Arcs run from a dim to a bright member color, with a bloom | Gel arcs with a darker edge and a white highlight stripe |
| People | Lit spheres with a specular highlight and a colored halo | Glossy orbs with a top gloss |
| Pot | Domed smoked-glass lens in a steel bezel | Aqua glass orb, navy `POT` caption |
| Cards | Top highlight, deep drop shadow | Frosted glass (`backdrop-filter`), top-half gloss |
| Primary button | Lit white pill, ink `#0A1519` | Light gel, navy ink `#04233D` |

Member colors (Floodlit / Aero): You `#FF7B4F`/`#FF6428`, Sam `#4DC3FF`/`#1C98F4`,
Jordan `#6CD49A`/`#27B155`, Priya `#B99DFF`/`#9357F6`, Maya `#FFC95C`/`#F2A00C`,
Theo `#FF8AC3`/`#F24A93`. Barlow Condensed and Barlow stay, embedded.

## Words turned into pictures

Words on each phone at the default state, counted by one script for both rounds
([words.json](captures/words.json)):

| Screen | Round 7 | Round 8 |
| --- | ---: | ---: |
| Challenge | 82 | 43 |
| Home | 73 | 46 |
| Invitation | 130 | 88 |

- **Your stake:** a $20 coin, your progress groove and a 20 km flag, with a
  return arrow from the flag to the coin. "Comes back when results are final."
  appears once you reach the goal.
- **The pot:** tapping the hub or the stake opens a sheet. Each person drops
  $20 into one pot bar, and four pictograms show the outcomes: reach your goal,
  confirmed misses shared, everyone misses, no activity yet.
- **Invitation rules:** three outcome cards (both reach it, one reaches it,
  both miss) and four icon facts replace the two rule paragraphs. The complete
  wording sits under **Full rules**, the native label.
- **People:** orbs with badges (check for goal reached, clock for a late
  update, dashed for no update) replace the text legend and its notes.
- **Freshness:** a sync icon and "3 min ago". The spoken label keeps "Updated
  from Apple Health 3 min ago".
- **Simulation:** "Simulated stakes — no real money moves." appears once per
  screen as a banner under the status bar, and again in the pot sheet. Round
  seven repeated it up to three times on the challenge screen.

Outcome pictograms use neutral figures, never a member's color, so no picture
shows a friend's miss paying you. Member order stays fixed. There are no
rankings, countdowns, projections or money celebrations.

## Unslop pass

Round seven's visible text passed the unslop scanners, but a line-by-line read
found the weak writing in the review-page captions: tool personification ("The
dial has a point of view") and vague abstractions ("gives Home its own rhythm",
"a more deliberate sporting character"). Round eight replaces the captions with
instructions and keeps the page to a title, a two-sentence lede and labels. The
scanners report no banned phrases and no structure or silhouette flags on round
eight's visible text. The only readability flag is repetition, from three
phones sharing the same labels.

## Copy to confirm before any adoption

- The visible freshness line drops "Updated from Apple Health". `docs/COPY.md`
  would need a row for the short form.
- "Both stakes back", "They get both" and "Neither back" summarize the rules;
  the rules text itself is unchanged.
- "Review and agree" and "Decline" on the invitation are inert and show
  "Preview only. Nothing is saved."

## Checks performed

Chromium through Playwright at 1440px and 390px ([checks.json](captures/checks.json)):
no console errors or warnings, no horizontal page overflow, embedded fonts
loaded. A sweep of all 98 combinations of material, day, people count and
Jordan's update found no errors or malformed dial paths. Also exercised:
selection, the pot and Full rules sheets (focus moves to Close, the phone
behind goes inert, and Escape or Close returns focus to the opener), navigation
inside one phone, the preview toast and 1.3× text. Key contrast pairs measure 4.5:1 or better, including navy on the
Aero gel button (5.6:1 at its darkest) and white on the calendar tile (5.8:1).

Not performed: native SwiftUI, VoiceOver, Dynamic Type, a full contrast audit
of every state, performance of blur filters on a phone, and any device run.
