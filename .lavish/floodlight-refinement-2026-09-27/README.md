# Floodlight design review — September 27, 2026

Proposals only. No new visual contract is adopted and no native app, account,
service or installation changed. The reference is the user-supplied
https://claude.ai/artifact/8CfAk9nqDSLvSoEpYnck8r, a browser mock rather than an
installed-app capture. All people and activity are fictional.

## Current proposal: a shared week

After the first refinement, the owner said it still felt like a template:
“Where is the community/fun aspect of it? It's too written and not enough
visual.” They asked whether a visual could replace the numerical presentation
of being behind or ahead. That is feedback on the design study, not approval
for native implementation or a new public-community product.

`index.html`, `social-board.css` and `social-board.js` now explore a shared
board of four people progressing toward their individual goals. It uses the
reference's chalk/ink palette and amber identity, plus subdued participant
colors. Hand-authored SVG lanes replace the dominant score and numeric list.

- Token position = saved activity / that person's own target, capped at the
  finish. Member order stays fixed. This is goal completion, not a ranking,
  raw distance comparison or a prediction about pace or results.
- Names stay visible. Tapping a lane reveals its total, target and the fixture's
  update time where provided. Accessible labels include the values.
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

Viewed default and phone-width renders. Checked selection of Sam and Priya,
exact numbers appearing only after selection, Jordan's separate missing-data
state, Home-to-challenge navigation, and expanded rule text. At 390px browser
width with larger text, the document and phone content had no horizontal
overflow. Fixed the lower panel's flex sizing and rechecked that expanded
content stays within its light background. The browser warning/error log was
empty at completion. These web checks do not establish native Dynamic Type,
VoiceOver, data correctness or release acceptance.

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
