# Floodlight design review — September 27, 2026

Proposals only. No new visual contract is adopted and no native app, account,
service or installation changed. The reference is the user-supplied
https://claude.ai/artifact/8CfAk9nqDSLvSoEpYnck8r, a browser mock rather than an
installed-app capture. All people and activity are fictional.

## Current proposal: round 8, Lit

Open [round eight](round-8/index.html), also published at
https://claude.ai/artifact/7XdVqyccrRc5u82KrYZ71U. The owner's words on round
seven: "I think what's missing from Floodlight is a feeling of depth. It's a
very flat design. I feel like um, some Frutiger Arrow or more 3D elements would
do well. Similar to what Whoop app looks like. I also think I want to greatly
cut down on the amount of text on these pages. Use the unslop skill and try to
use visuals where appropriate instead of walls of text and sentences."

- **Depth, two ways.** A Material control switches all three phones between
  Floodlit (WHOOP-style slate, floodlight beams, recessed channels, glowing
  arcs, lit spheres, a smoked-glass pot) and Aero gloss (Frutiger Aero sky,
  glass plate, gel arcs, glossy orbs, an aqua pot, frosted cards). Layout, data
  and rules are the same in both.
- **Fewer words.** Counted the same way for both rounds: Challenge 82 → 43,
  Home 73 → 46, Invitation 130 → 88. The stake became a coin, a groove and a
  flag with a return arrow. The pot opens a sheet of pictograms. The invitation
  rules became three outcome cards and four icon facts, with the complete
  wording under **Full rules**. The simulation line appears once per screen.
- **Unslop.** Round seven's slop was in the review-page captions ("The dial has
  a point of view"). Round eight's visible text has no scanner findings.

[The round record](round-8/DESIGN.md) lists tokens, copy to confirm, checks
performed (Chromium at 1440px and 390px, a 98-state sweep, sheet focus,
contrast of key pairs) and what was not checked (native, VoiceOver, Dynamic
Type, device). Nothing native changed.

### Open decisions for the owner

1. Floodlit, Aero gloss, or somewhere between?
2. Keep the short freshness line ("3 min ago") on screen?
3. Is the pictogram summary on the invitation clear enough to sit above Full rules?

### Responsible engagement review (round 8)

More polish and glow could make the stake feel more exciting. The pot looks the
same all week, outcome pictograms use neutral figures rather than friends'
colors, and there are no rankings, countdowns, projected winnings or money
celebrations. No notification, analytics or payment behavior changed.

## Preserved seventh proposal: round 7, Club chronograph

Open [round seven](round-7/index.html). The file embeds its Barlow fonts and
works offline. The owner liked round six's dial and pot, but asked to remove
the generic cream look and improve the typography using Mobbin references.
This is a new proposal, not a native adoption or implementation authorization.

- **Preserved:** the 270° group dial, center pot, fictional activity and people,
  $20 simulated stake, 2/4/6-person controls, per-person goals, late/missing
  update states, independent phone navigation and existing rules paragraphs.
- **Changed:** white phone backgrounds, Barlow Condensed display lettering,
  Barlow reading text, flat markers and arcs, one solid pot hub and open ruled
  rows. Home pairs personal distance with a compact dial on steel blue.
  After-dark colors use lighter member hues for contrast.
- **Clarity:** You is selected initially; the saved total and update time are
  visible. Simulation is disclosed near amounts. The stake explanation retains
  final-result timing. The invitation is explicitly not started and has no
  implied activity markers. Fixed member order is never a ranking.
- **References actually viewed:** [Nike Run Club's distance typography](https://mobbin.com/screens/3b656c09-f15a-4bab-8339-a40afd3cf5f9)
  and [WHOOP's active arc/track separation](https://mobbin.com/screens/aac78ccc-35b7-459d-abe3-5256ba4dfd6b)
  through the Mobbin plugin. The composition remains GameTime's group dial/pot.

[The scoped design record](round-7/DESIGN.md) records proposed tokens and actual
prototype behavior. [Desktop](round-7/captures/screens.png) and
[phone-width](round-7/captures/mobile-phone.png) captures preserve the rendering.

### Performed checks for round 7

Local Chromium at 1440px and 390px: used fonts loaded, no JavaScript errors,
Tuesday and Sunday activity, $40/$80/$120 pots, pot explanation, missing Jordan
activity, independent Home/Challenge/Invitation navigation, light/dark appearance,
1.3× browser text and horizontal overflow. The first pass found narrow-screen
track sizing and Home metric spacing; corrected. Embedded fonts resolved a
font-loading limitation in Lavish's sandboxed preview. A fresh visual review
found low dark-surface arc contrast; brighter same-hue colors corrected it.
The reviewer passed the design for review, with native and complete accessibility
validation still unperformed. The Impeccable detector ran in degraded regex mode;
its empty findings are not a full accessibility audit.

### Responsible engagement review (round 7)

Intended benefit: clearer personal progress, group participation and understood
simulated amounts. Possible risk: stronger sports styling increases comparison
pressure. The pot stays static across the week, member order stays fixed, missing
activity never implies a miss, and there are no rankings, financial celebrations,
catch-up instructions or new notification/analytics behavior. Whether the style
feels motivating without pressure is still a user-research question. No native,
account, hosted, real-money or current adopted-theme changes were made.

## Preserved sixth proposal: the dial with the pot

Open `round-6/index.html` (self-contained; Archivo from Google Fonts). Every
round lives in its own folder; there is no top-level page.

The owner picked the Dial (C) from round 5 and asked for the pot size, so
people know what's on the line and are motivated to meet their goals. Round 6
shows the Dial on three phones side by side — Challenge, Home and Invite — with
shared controls (Daylight/Night, day, 2/4/6 people, Jordan's update, larger
text); each phone's own buttons navigate within that phone.

- **Challenge.** The pot sits at the center of the dial: "POT", the total in
  Archivo ($80 for four people) and "$20 each", ringed by one segment per
  person in their color (who is in the pot, never whose stake is "safe"). The
  week moves back to the header strip. Under the dial, a white "Your stake"
  card: "$20 · Comes back when you reach 20 km." ("Goal reached. It comes back
  when results are final." once you reach it) and "How the pot works", which
  expands the card with the pot total, "N people × $20", the rules' own split
  sentences and "Simulated stakes — no real money moves." Tapping the dial's
  center opens the same explanation and softens the rings.
- **Home.** Still leads with progress: the small dial shows "$80 pot" in the
  center; the whole dial opens the challenge.
- **Invite.** Before the unchanged rules text, a three-part summary: "Your
  stake $20 · Pot $40 · Fee $0", and the dial's center shows the $40 pot.

Pot = the per-person amount × people still in. The app already has both
(`ChallengeV1` config `amountCents`; members' selected, consented and exited
flags); if someone leaves, their stake comes back and the pot shrinks.

The owner's request fits the adopted requirements, which keep amounts
"accessible and prominent" and say "do not hide maximum loss"
(`docs/BUSINESS_MODEL.md`). The same requirements and D130 rule out the rest,
so the design leaves out: projected winnings from a friend's miss ("do not
optimize for participant failure"), countdowns or last-minute pressure to
protect a stake ("never prescribe last-minute exercise to protect a stake"),
money celebrations, and any per-friend "at risk" marking. The pot reads the
same on Sunday as on Monday, and reaching a goal looks the same at any stake.
This reverses the warm-up plan's proposed cut list (money only at creation,
agreement and results); that list was a proposal, not an adopted rule.

### Open decisions for the owner

1. Pot in the center, or the day in the center with the pot in the row below?
2. Show the pot on Home too, or only inside the challenge?
3. Is the Dial ready for a native plan (SwiftUI plan first, no code until
   approved)?

### Performed checks for round 6

Rendered with Playwright/Chromium at 1440px and 390px (2x): Daylight and
Night; Tuesday, Thursday and Sunday; 2, 4 and 6 people ($40, $80, $120 fit the
center); Jordan None; a selected person; the pot open from the dial's center;
larger text; navigation from Home to the invitation inside one phone. No
console errors or warnings; no horizontal page overflow at 390px. Fixed after
the first look: the stake card squeezed its text beside the link, and the pot
explanation opened below the fold (it now expands inside the card and scrolls
into view within that phone).

These web checks do not establish native Dynamic Type, VoiceOver, data
correctness, design acceptance or release acceptance.

### Responsible engagement review (round 6)

Behavior this increases: attention to the stake as a reason to reach one's own
goal. Risk: money becoming the focus, pressure near the deadline, or rooting
against friends. Controls in the design: the pot is a static fact all week; the
motivating line is about your own goal; the split is explained with the
agreement's own wording; no projections, countdowns, money celebrations,
friend-level money states, notifications or analytics. Whether the stake
motivates without pressure still needs people to try it, and live money would
still need the adopted exposure limits and pause controls first.

## Preserved fifth proposal: three serious directions

`round-5/index.html` (committed as `a2516c1`, published at
https://claude.ai/artifact/Tv4xQNpvY1HNjGJV4RJyqU). The owner's verdict,
September 27: "I really like the dial design. However, I think we should have
something about the pot size. People should know what's on the line and have
it be something to motivate them to meet their goals." Round 6 answers that.

Responding to the round 4 verdict (quoted in the round 4 section below), round 5 keeps round 4's finish and
the same data, states and controls, and shows three phones side by side. Every
control (screen, Daylight/Night, day, 2/4/6 people, Jordan's update, larger
text) and every selection changes all three at once.

- **A · Track** (athletics broadcast): a top-down straight on a blue track,
  one lane per person in member order, painted lane numbers, a start line,
  quarter marks and a finish line that is each person's own goal. A colored
  stripe runs from the start to the runner; a runner who reaches the goal sits
  on the finish line and their segment of the tape takes their color. Night is
  a floodlit stadium. Recommended.
- **B · Board** (race timing tower and sportsbook rows): condensed caps names,
  bold bars against one shared goal line with quarter grid lines, percent of
  own goal at the right, a "Day 2 of 7" clock with lettered segments. Rows stay
  in member order, never sorted by progress. The easiest to build and the best
  fit for Home or widgets.
- **C · Dial** (chronograph): a 270° watch face with one ring per person, the
  week as a segmented subdial in the center and a legend below. Ring spacing
  always clears two markers at the same angle; at six people and on Home the
  markers become dots and the legend names them (including "Updated
  yesterday" for a late update, since a dot can't carry a clock badge).

Encoding and states carry over from round 4: position = latest saved total /
that person's own target, capped at the finish; late updates keep their place
with a clock; with no update the person waits at the start with no position
and "No update yet". People colors return to Floodlight's brights (amber for
you, then mint, violet, coral, lime, rose) on Floodlight's neutral chalk and
ink; titles use Archivo SemiExpanded.

"More serious" deliberately adds no gambling cues: no odds, pot size, payouts,
countdown pressure or ranking on the live screen. The stake stays in the rules
and appears at agreement and results. Copy changes from round 4: "You, Sam and
Priya reached your goals." for mixed finishers, and "Each finish is that
person's goal" (round 4's "own goal" is a soccer term for scoring against
yourself).

### Open decisions at the time (answered: the Dial)

1. Track, Board or Dial? Mixing is possible (for example the Track on the
   challenge screen and the Board on Home).
2. Keep the bright people colors, or tone them down?
3. For the Track, blue or a classic red?

### Performed checks for round 5

Rendered with Playwright/Chromium at 1440px and 390px (2x): all three
directions in Daylight and Night; Monday, Tuesday, Thursday, Friday, Saturday
and Sunday; 2, 4 and 6 people; Jordan Recent, Late and None; a selected
person; Home and the invitation; larger text; a sampled mid-animation frame.
No console errors or warnings; the page body has no horizontal overflow at
390px (the three phones scroll sideways inside their own strip). Fixed after
the first look: runners at the start overlapping lane numbers, Dial markers and
badges colliding at the start and finish, Board grid lines misaligned, and the
invitation Board showing Jordan's September goal. Contrast: initials on all six
person colors 7.5:1 or better; white on the day track 6.6:1; secondary text
6.0:1 on chalk and 7.5:1 on the night background. Person colors against the
blue track range from 2.6:1 to 4.6:1, so every runner carries a white ring.

These web checks do not establish native Dynamic Type, VoiceOver, data
correctness, design acceptance or release acceptance.

### Responsible engagement review (round 5)

Intended benefit: a small private group sees each other's goal progress at a
glance, in a design that feels like sport rather than wellness. Risk: a more
competitive look could make comparison feel like pressure or make the product
feel like gambling. Therefore none of the three directions ranks, sorts, shows
pace targets, catch-up prompts, streaks, money or odds, and none adds
notifications, analytics, reactions or other social mutations. Whether the
competitive tone stays friendly still needs people to try it.

## Preserved fourth proposal: stepping stones to a shared sunrise

On September 27 the owner asked to "continue to iterate on the floodlight
design direction" and to "go more visual for some aspects, such as the
challenge screen tracking progress between friends." That is feedback on the
design study, not approval for native implementation.

`round-4/index.html` (committed as `5c61703`, published at
https://claude.ai/artifact/Anec1ofhVxmeeSbcTyHThv) compares round 4 with the
round 3 captures in `captures/`. The owner's verdict, September 27: "I like how
polished this design looks, and I think it's a step in the right direction. But
at the end of the day, this is sort of a betting app. And this design with the
sun feels like a wellness app of sorts. It seems a little hippie, for lack of a
better term. Could we implement this same general design polish in something
that's a little more serious? I don't know if stones and sunshine is the way
to go." Round 5 answers that; the notes below describe round 4 as built.

- **The picture.** The app icon's stepping stones and rising sun become the
  challenge screen. Each person has a path of ten stones from the ground to the
  crest under the sun. Floodlight amber is the sun; each person's color fills
  the stones they have crossed. The page below the horizon is the ground, so
  details and rules sit in the same landscape. Home carries a compact version
  and the invitation shows two empty paths (You and Jordan) waiting at the start.
- **Encoding.** Token position = latest saved total / that person's own target,
  capped at the sun. Every path has the same length and positions use one even
  scale along it; stones shrink toward the horizon for depth only, never to
  compress progress. Member order is fixed left to right. No ranks, pace lines,
  "behind" labels, catch-up prompts, streaks or money.
- **Numbers on request.** Tapping a name or token shows the total, target, a
  ten-stone strip, what's left and the update time, and dims the other paths.
  A second tap, Close or Escape dismisses it and returns focus to the name.
  With nobody selected, the caption names who reached their goal.
- **Data states.** "Jordan's latest update" previews Recent, Late (keeps the
  last saved position, adds a clock, detail shows "Updated yesterday at
  6:10 PM") and None (no position; a dashed token waits at the start with
  "No update yet"; the detail repeats "Missing or partial activity never counts
  as a miss.").
- **Movement.** The day control (Mon–Sun, Tuesday is the original fixture) moves
  tokens along their paths only when the saved total changes; nothing animates
  from zero when a screen opens. Reduced motion jumps straight to the result.
  Days other than Tuesday are invented for the preview.
- **Scale.** The People control shows 2, 4 and 6 people (the invite picker
  allows up to five friends); at five or more the names stagger in two rows.
- **Night** uses the icon's plum sky instead of round 3's dark moss.

Copy changes from round 3: "Goal reached" replaces "Goal met" while the
challenge is live, matching `LiveDesignComponents.swift`; "Goal met" stays for
results. "No update yet" (the app's wording) replaces "Waiting for activity".
"Priya reached their goal." replaces "Priya reached her goal." because the app
has no pronoun data. `docs/COPY.md` remains authoritative.

What the picture needs from the app: username (initials), own goal, latest
saved total and when it was saved, which `challenge_detail_v1` already
returns for each member. Person colors would be derived from the account ID on
the phone, as Floodlight proposed. No per-day or per-workout history is needed.
Today's `LiveGoalDetail` shows only your own progress on the main page and
keeps friends in the "With you" sheet during a live challenge.

### Open decisions at the time (superseded by round 5)

1. Keep the sunrise paths, or return to round 3's lanes?
2. Night: the icon's plum sky or round 3's moss?
3. Compact picture on Home, or keep Home to rows?
4. Numbers behind a tap, or a small total under each name?

### Responsible engagement review (round 4)

Intended benefit: seeing a small private group's goal progress at a glance.
Risk: watching friends move could make comparison feel like pressure.
Therefore the picture has no ranks, pace lines, catch-up prompts, streaks,
money celebrations or stake incentives, and it adds no notifications,
analytics, reactions or other social mutations. Celebrations mark an athletic
goal the same way at every stake. Whether it feels friendly rather than
pressuring still needs people to try it.

### Performed checks for round 4

Rendered with Playwright/Chromium at 1280px and 390px (2x): Daylight and Night;
Monday–Sunday; 2, 4 and 6 people; Jordan Recent, Late and None; a selected
person; Home and the invitation; larger text. No console errors or warnings;
no horizontal overflow at 390px. Verified Tuesday values against the fixture
(You 6.4/20, Sam 7.8/20, Jordan 1.2/15, Priya 10/10), Sam's 12.2 km to go,
Priya's goal-reached state and Jordan's positionless None state. Contrast:
ink on ground 12.1:1, secondary text on ground 5.4:1 (Daylight) and 8.4:1
(Night); initials on all six person colors 7.8:1 or better.

These web checks do not establish native Dynamic Type, VoiceOver, data
correctness, design acceptance or release acceptance.

## Preserved third proposal

`round-3/` preserves the Daylight lanes (committed as `1ac24fe`): an open chalk
canvas, muted green-gray text, dotted lanes with colored tokens and a flag per
finish, and a dark-moss Night option. The owner then asked for round 4.

## Preserved second proposal

`round-2/` preserves the dark shared-progress board, committed as `0aadbd5`.
That round introduced the fixed-order personal-goal lanes and selectable
activity details. The owner liked the direction and questioned the amount of
black; that feedback did not adopt the proposal.

## Preserved first refinement

`round-1.html` is the initial quieter scoreboard comparison, committed as
`f881d95`. The owner rejected it as still too written and template-driven:
“Where is the community/fun aspect of it? It's too written and not enough
visual.”

The current September 22/24 native visual adoption remains unchanged.
