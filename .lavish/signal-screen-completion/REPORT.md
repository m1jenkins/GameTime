# Signal screen completion

Local design prototype at `index.html`. No native app, production API, schema,
authentication, Health access, payment or backend setting changed. Nothing was
published externally.

Design source: the user-selected Signal system, using the original September 13
study's semantic palette, system typography, 24px alignment, fine dividers and
opaque goal bands. The September 20 staged native creation captures guide numeric
scale, exact inputs and visible controls. Browser blur and gradients approximate
glass; they do not establish native material acceptance.

## Screen inventory

39 navigable screens, grouped into eight journeys:

| Area | Screens and connected interactions |
| --- | --- |
| Home | Steps initially; Activity minutes and Running distance; weekly totals, keyboard/touch day selection, update states, invitations and current challenges. |
| Challenges | Active / Upcoming / Finished; attention above filters; With friends / Just for you; friend, personal distance and alternate timed-run detail; creation, community and Existing challenges. |
| Invitations | Summary → request → waiting lobby → creator roster selection → participant goal proposal → complete agreement → independent activity check and unchecked consent → saved agreement → simulated second participant consent. Role changes are reviewer controls outside the phone. |
| History and results | Date-grouped history → separate activity result, review and recorded simulated return; provisional result → review request → saved receipt; safe exit → matching saved record with return still pending. |
| Community | Unavailable and published entries → rules/readiness/consent → joined confirmation → scheduled or active private progress. Reviewer controls compare a delayed eligible aggregate with complete count suppression. |
| Existing challenges | Focused list, detail, historical setup and confirmation, review, receipt, payment status, historical cancellation and receipt. Exact historical consent, seven-day review and missing-final-data protection remain intact. |
| Staged creation | Type → Activity and goal → Dates → Amount → Review → saved confirmation → saved goal or open lobby. Direct Personal skips Type. Current defaults: Goals with friends, Steps, blank target/distance, seven days, start +2 days, $20. |
| You | Revised through Lavish feedback: identity header, private win/loss record, Activity / Challenges selector, lifetime activity, retrospective streak, calculation disclosures and saved-record navigation. Support remains a bounded preview. |

The screen picker exposes each screen. Empty receipts explain their prerequisite
and link back to it. Back restores the originating control and scroll; Close
returns to Challenges. Local choices, open disclosures, feedback drafts and saved
receipts survive navigation. Reset demo clears fictional state. A saved creation
cannot be replaced by later draft edits; Reset demo starts another creation.

## Fixtures and boundaries

- Base fictional clock: September 21, 2026, 10:00 AM Pacific. Alex Lee is the
  participant; Sam Parker is the friend/creator.
- Home: September 14–20, 52,480 steps (8,230 + 7,450 + 9,020 + 6,800 + 8,430 +
  7,550 + 5,000). Activity minutes: 138 recorded, with Sunday unknown. Running:
  16.4 km. This is personal activity, separate from GameTime's saved scores.
- Active friend goal: September 18–24; Alex 18,420/50,000 steps; Sam
  21,200/60,000. Personal running: September 21–27; 6.4/20 km. Timed 5K is an
  explicitly labeled alternative personal fixture, not another active slot.
- Invitation: September 30–October 6; Alex proposes a goal, Sam's is 60,000;
  $20 simulated each, fee $0. The expired alternate advances to September 30.
  Alex's consent does not infer Sam's consent.
- Finished friend goal: September 7–13; 52,480/50,000 and 61,200/60,000;
  recorded return $20. Review-open alternate: Alex 48,600; delayed notice
  September 20 noon; review deadline September 22 noon. An open review counts
  toward the three-unfinished limit. Exits remain unsettled until a final return.
- Community: fictional 50,000-step goal, September 23–29, $20, fee $0 and outcome
  minimum two. These values are not selected launch settings. Default progress
  is scheduled; the active alternate advances to September 26 and 18,420 saved
  steps. The visible anonymous count is 12 from a 20-minute-old update. The
  suppressed variant exposes neither numbers nor the reason for suppression;
  it covers fewer than five current members or an update younger than 15 minutes.
  Five is only the disclosure threshold. Individual names, scores and results
  are never exposed as community information.
- Existing Personal: September 1–7; 52,480/50,000 steps; exact $20.00 sandbox
  consent and $0 met-goal charge. Its review-open alternate uses a September 20
  noon notice and September 27 noon deadline. Setup/cancellation replay is
  separately labeled August 31 and cannot rewrite the completed record or review.

All new amounts are nonredeemable simulation. No activity permission, payment,
message delivery or server confirmation is performed by these controls. The
creation link is a locally represented saved state and explicitly says it was
not sent. Support explains its preview boundary and returns to the prior screen.

## Browser verification

The `verification/` directory contains repeatable Chrome scripts and captured
JSON results. Run them against the loaded prototype with
`chrome-devtools-axi run < verification/journeys.js` (and the other scripts).
The scripts use local DOM interactions and native keyboard events; no app or
backend test suite was needed for these isolated prototype files.

- Nine connected journey checks: activity selection and Back retention;
  invitation through explicit consent; review receipt; safe exit; community;
  retained review/payment; historical setup/cancellation; friend creation;
  Personal creation, validation, separate readiness and immutable saved facts.
- Seven keyboard/navigation checks: range arrow keys and exact accessible value;
  row and reviewer-origin focus restoration; one activation after editing;
  keyboard disclosure and retention; Home/Close; bottom navigation clearance.
- Eleven policy checks: capacity, independent exits, unknown activity, stale
  review protection, historical replay isolation, active community privacy,
  Reset demo, creation receipt retention, review capacity, readiness invalidation,
  and active-fixture exit dates.
- 624 rendered combinations: 39 screens × two widths (390/320) × two text sizes
  (100%/130%) × light/dark × glass/solid. Complete disclosures were expanded.
  No horizontal content overflow, missing screen heading, or undersized visible
  action was found in the final matrix. Checkboxes use their full-row labels as
  targets; the chart uses one full-width range target.
- Reduced motion is the initial setting. The explicit toggle and system media
  query disable transitions and animations. Data never uses count-up animation.
- Signal text contrast pairs exceed 4.5:1. Representative ratios: light muted
  text 5.54:1; light primary at its lightest gradient approximately 5.26:1;
  dark muted text 7.85:1; dark primary 7.34:1. Disabled controls are excluded.
- Final visual checks include standard Home, compact dark/large/solid content,
  rule/consent scrolling, and the three-column reference comparison.

Initial verification found and corrected: a shadowed browser history name,
narrow chart hit targets, cross-challenge exit state, mutable agreement/creation
receipts, stale-review navigation, creator consent inference, missing readiness,
capacity omissions, and a Lavish-intercepted Home link. CLI selector-click helpers
failed in this environment; equivalent DOM and native-keyboard checks were used.
No human VoiceOver pass, native Dynamic Type pass or phone installation occurred.

## Rendered comparison and remaining differences

The comparison view uses unchanged copies of the original reference's HTML/CSS/JS
and unchanged native PNG captures. Both existing reference artifacts remain
untouched. It labels original Existing as empty and Community as unavailable;
there was no populated predecessor for those proposed compositions.

- Home retains the original total/chart rhythm and open rows, adds three activity
  choices, and keeps personal totals separate from saved challenge scores.
- Challenges retains aligned open rows while adding attention-first composition,
  grouped lists, a glass status filter and a focused Existing challenges entry.
- Invitation now uses the opaque blue band for “Choose your own goal”; Sam’s
  60,000-step target is secondary. The shared date connector aligns with date
  values. The flow retains separate request, roster, proposal and consent stages.
- History uses separate result, review and return sections. Historical payment
  presentation remains a separate sandbox card with Refresh/Contact Support.
- Staged creation preserves native defaults and steps; this browser version uses
  CSS choice capsules and browser date/input controls. Native sheet geometry,
  keyboard, material refraction and control morphing are not reproduced exactly.
- The original comparison column retains its own preview strip. Native captures
  are static component references and do not change with proposed text/material
  settings. Original appearance/material follows the comparison controls.
- Large text is a 130% browser stress test, not a claim of native Dynamic Type
  equivalence. Browser screen-reader semantics and focus were inspected; human
  VoiceOver behavior remains a separate acceptance task.

## Review

Opened locally in Lavish. Per-screen feedback only queues on the explicit
**Queue feedback** action; selections alone do not send feedback. Normal Lavish
annotations remain available. The local feedback poll is used for requested
revisions; no external publishing was invoked.

Copy review used `docs/COPY.md` and the unslop core contract. The rendered-copy
phrase scan found no hard or soft phrase violations. Its cross-screen structure
scan flagged repeated sentence openings; these are repeated agreement and
protection sentences across separate screens, deliberately preserved. Report
phrase and structure scans passed. Original reference and all eight native
capture copies match their source files byte-for-byte.


## Lavish feedback revision · September 21

All six submitted comments were applied in the existing local session.

| Annotation | Requested change | Revision |
| --- | --- | --- |
| 2 | Shorten the Activity minutes caption | “Apple Exercise credit”. The unknown Sunday still has an unavailable readout and accessible value. |
| 4, 6 | Refine and align the date arrow | One shared solid circular SVG connector, centered on the date values. Compact large text stacks the dates. |
| 5 | Make an individual target more obvious | The invitation leads with “Choose your own goal.” Sam’s 60,000 steps is a secondary row. Alex has no accepted target before proposing and consenting. |
| 7 | Remove the leaderboard clause | Community keeps the private steps/result statement and shared goal, without that clause. |
| 8 | Expand You using fitness profile references | Identity and initials corrected; lifetime activity, a private competitive record and a retrospective streak added with working Activity / Challenges controls. |

The profile draws on [Nike Run Club’s prominent lifetime total](https://mobbin.com/screens/6d298284-0016-475e-b33e-2d67e78515fe)
and [Strava’s identity, statistics and weekly streak layout](https://mobbin.com/screens/7a77b17b-e42b-44ab-a21d-87b157e6663c),
inspected through Mobbin. Signal remains the design source: its semantic palette,
open rows, system typography, solid facts and glass selectors. No external
reference assets or services are needed to render the prototype.

Additional fictional profile fixtures:

- Personal activity recorded since July 20: 683,420 steps and 142.8 km running.
  Weekly step values through September 20 are 69,500; 71,400; 73,980; 78,320;
  unknown; 82,500; 90,120; 165,120; 52,480. Eight weeks have recorded activity.
  The final week matches Home. Totals sum known values and disclose the missing
  week; the unknown value remains null.
- Four consecutive weeks are confirmed from August 24 through September 20.
  The unknown August 17 week neither proves a break nor supplies continuity.
  The streak is a private retrospective record, with no reward, countdown,
  paid-challenge linkage or participation prompt.
- Fourteen earlier friend competitions, July 20–August 30: eight wins, including
  two shared wins; four losses; two that did not count. The rate is 8/12 = 67%
  rounded, and the win/loss ratio is 2:1. Personal, community and individual
  friend goals are excluded. Open reviews, pending or unknown results cannot
  become losses. The completed archive is separate from the current journeys.
- Profile aggregation and competitive records require later implementation and
  acceptance. This archive illustrates deferred leaderboard rules; it does not
  claim that competitive leaderboards have launched. Activity history remains
  distinct from saved GameTime scores and all payment states.

Revision verification: eight focused interaction/copy checks passed, including
keyboard profile switching, retained selection, focus restoration and Reset.
The complete 624-layout matrix passed after the shared date change. Both profile
tabs were additionally checked at compact and standard widths, large and normal
text, light/dark and glass/solid. Visual captures cover the revised invitation
and standard/compact profile. No original reference, staged capture, historical
consent, native implementation or backend file changed.

The profile’s individual-goal row follows the current review state instead of
always claiming both goals were met. That state check also passed. The shortened
Home caption follows annotation 2; complete challenge source definitions and
consent in staged creation remain unchanged. Revised-copy phrase, structure and
silhouette scans found no violations; readability scoring on concatenated screen
labels is not treated as a prose reading-grade result.
