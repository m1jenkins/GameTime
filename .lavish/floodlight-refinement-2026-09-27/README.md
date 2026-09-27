# Floodlight design review — September 27, 2026

Proposals only. No new visual contract is adopted and no native app, account,
service or installation changed. The reference is the user-supplied
https://claude.ai/artifact/8CfAk9nqDSLvSoEpYnck8r, a browser mock rather than an
installed-app capture. All people and activity are fictional.

## Current proposal: daylight and shared progress

After the first refinement, the owner said it still felt like a template:
“Where is the community/fun aspect of it? It's too written and not enough
visual.” They asked whether a visual could replace the numerical presentation
of being behind or ahead. That is feedback on the design study, not approval
for native implementation or a new public-community product.

The owner then said the shared visual direction was better and asked for
further polish, particularly questioning the amount of black. Round 3 keeps
the shared progress idea and proposes Daylight as the default: an open chalk
canvas, muted green-gray text, subtle dotted paths and individual colored
markers. Night offers a dark moss alternative in the review controls. Neither
mood is adopted for native implementation.

`index.html`, `social-board.css` and `social-board.js` contain this current
proposal. It derives from the reference's chalk background and amber identity,
then follows the owner's feedback toward a lighter, more social composition.
Hand-authored SVG lanes replace the dominant score and numeric list.

- Token position = saved activity / that person's own target, capped at the
  finish. Member order stays fixed. This is goal completion, not a ranking,
  raw distance comparison or a prediction about pace or results.
- Names stay visible. Tapping a lane reveals its total, target and the fixture's
  update time where provided. Accessible labels include the values.
- Selecting a person updates only the detail region. Expanded rules, focus
  and scroll context stay intact. A second tap, Close or Escape dismisses the
  detail. Close/Escape restore focus to the selected person.
- Daylight/Night changes only this preview. It also applies to the invitation
  reading screen. Navigation restores focus to the destination/return control.
- Goal met is an athletic milestone, not finality or a simulated return.
- The missing-update toggle explores a separate fictional state: Jordan has
  no saved score and appears without a progress position. A later native
  implementation must retain an existing saved position for a merely late
  update and explain its age.
- The goal title, Home return, invitation reading preview, person selection,
  rule summary and text-size controls work. Tabs and Park runs are shown for
  context. Joining/declining are outside this visual study.

The expanded “How it works” is a summary, not the full agreement. Later native
work must retain the full rules and exact saved deadlines, refresh, leave and
report actions. `docs/COPY.md`, `LiveGoalRules.swift` and the Beta contract
remain authoritative. Original date/target errors remain only in the recreated
reference; proposed text uses individual targets and actual notice-based review.

### Responsible engagement review

Intended benefit: understanding friends' goal progress and feeling part of a
small private group. Additional use could make comparison feel pressuring;
therefore the proposal has no ranks, pace targets, catching-up prompts,
auto-rematches, new invitations, money celebrations or stake incentives.
It does not add notifications, analytics or social mutations. Greater social
comfort is a hypothesis; comprehension and pressure still require human review.

### Performed checks for this revision

Viewed Daylight and Night, including a selected person, at desktop width.
At 390px browser width with larger text, checked person selection, the separate
missing-activity state and invitation navigation; document and phone content
had no horizontal overflow. Verified Sam's 7.8/20 km, 12.2 km remaining and
fixture update time; Priya's goal-met state; Jordan without a score or progress
SVG when missing activity is selected. The overview fits within the default
phone composition, with room reserved for ordinary selected-person details;
larger text and longer messages scroll naturally.

Verified open rules survive person selection and the missing-state toggle.
Verified second-tap dismissal, Close/Escape focus return, invitation/back focus,
persistent spoken-status text with explicit sentence spacing, and consistent
night styling through navigation. Removed overlapping finish/check marks.
Calculated secondary-text contrast is 5.07:1 for Daylight and 8.18:1 for Night;
the Daylight track is 3.15:1 against its canvas. Browser warning/error output
was empty. The external JavaScript passed Node's syntax check.

These web checks do not establish native Dynamic Type, VoiceOver, data
correctness, design acceptance or release acceptance. No native tests apply
to this artifact-only revision.

## Preserved second proposal

`round-2/` preserves the dark shared-progress board, committed as `0aadbd5`.
That round introduced the fixed-order personal-goal lanes and selectable
activity details. The owner liked the direction and requested the current
refinement; that feedback did not adopt the proposal.

## Preserved first refinement

`round-1.html` is the initial quieter scoreboard comparison, committed as
`f881d95`. It concentrated Archivo on the score, removed extra containers and
showed individual targets. The owner rejected that composition as still too
written and template-driven. Its original browser navigation, rule expansion
and larger-text checks passed, but that did not establish design acceptance.

The current September 22/24 native visual adoption remains unchanged. Feedback
is held locally until explicitly queued through Lavish. Google Fonts supplies
Archivo for the recreated reference and the preserved first refinement; the
new lane visualization uses system text and self-contained SVG.
