# Floodlight design review — September 27, 2026

Proposals only. No new visual contract is adopted and no native app, account,
service or installation changed. The reference is the user-supplied
https://claude.ai/artifact/8CfAk9nqDSLvSoEpYnck8r, a browser mock rather than an
installed-app capture. All people and activity are fictional.

## Current proposal: round 4, stepping stones to a shared sunrise

On September 27 the owner asked to "continue to iterate on the floodlight
design direction" and to "go more visual for some aspects, such as the
challenge screen tracking progress between friends." That is feedback on the
design study, not approval for native implementation.

`index.html` is self-contained (inline CSS and JS; Archivo from Google Fonts).
It compares round 4 with captures of round 3 in `captures/`.

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

### Open decisions for the owner

1. Keep the sunrise paths, or return to round 3's lanes?
2. Night: the icon's plum sky or round 3's moss?
3. Compact picture on Home, or keep Home to rows?
4. Numbers behind a tap, or a small total under each name?

### Responsible engagement review

Intended benefit: seeing a small private group's goal progress at a glance.
Risk: watching friends move could make comparison feel like pressure.
Therefore the picture has no ranks, pace lines, catch-up prompts, streaks,
money celebrations or stake incentives, and it adds no notifications,
analytics, reactions or other social mutations. Celebrations mark an athletic
goal the same way at every stake. Whether it feels friendly rather than
pressuring still needs people to try it.

### Performed checks for this revision

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
