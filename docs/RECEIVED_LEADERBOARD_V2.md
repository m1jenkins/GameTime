# Received-score friend leaderboards v2

D141 authorizes local implementation from D140 `110c470`. D140's nine-goal
Beta release scope remains unchanged. Four new friend policies are optional
local capability, not a release requirement or permission to enable hosting.

## Frozen contract

New `friend_steps_leaderboard_v2`, `friend_exercise_leaderboard_v2`,
`friend_distance_leaderboard_v2` and `friend_timed_leaderboard_v2` agreements
freeze `score_rule = received_by_correction_cutoff_v2`, the missing/partial/failure
rules, source version, existing exact window and correction cutoff before consent.
Existing agreement bytes, source registries, consent and pending requests stay
unchanged. New v2 requires an available matching real source. Strict Exercise v1
stays unavailable; Activity minutes use Exercise credit v2 with its disclosure.

Use the latest valid replacement successfully committed by GameTime through
end +48 hours, inclusive. This includes a first score during the correction
window. Old agreements keep the +24-hour first-submission limit. Client clocks
and observation times cannot backdate receipt; late replacements are rejected.
An exact retry can retrieve an already committed receipt after cutoff or gate
closure without adding a fact.

Quantity scores are eligible saved totals, even when only part of the person's
history is visible. Timed scores are the fastest eligible saved whole run;
missing workouts cannot improve that time. Existing source, reconciliation,
normalization, whole-window and inclusive 100–102% distance rules still apply.
An unreadable or conflicting replacement stays unresolved; it never certifies a
zero or a complete history. Explicit deletions and downward corrections replace
old values rather than accumulating or taking the maximum.

No valid saved score means unranked and return of that simulated entry. Exits
and review exclusions also return entries. With fewer than two valid remaining
scores the entire challenge voids and every entry returns. Otherwise the highest
total / lowest elapsed seconds wins. Equal normalized scores share only the valid
participants' simulated pool; indivisible cents remain unallocated.

## Native and recovery path

Signal selects v2 only for new real leaderboard creation. Old leaderboard
agreements remain unavailable for activity submission/ranking and retain their
review, exit, history and void handling. No target or suggestion is introduced.
The existing readiness, roster freeze and deliberate consent remain required.

Detail shows **Your saved score**, **Last saved update**, **Save activity by** and
an explicit **Refresh**. It ranks authorized server facts, not local reader output.
Local activity and pending delivery remain labeled separately. A failed upload
keeps its exact signed request; Refresh recovers it before any later signing.
If it cannot be recovered, the screen directs the person to review when results
arrive. A confirmed GameTime failure belongs in recovery/review, not an inferred
participant miss. Existing review filing pauses finalization, and exclusions or
voids return simulated entries; normal review/exit/privacy timing is unchanged.

This rule may rank a person lower when less activity was saved. Consent discloses
that consequence without encouraging more exercise, larger entries or loss
recovery. No new notification, incentive, social sharing or financial access is
added. All amounts remain nonredeemable simulation.

## Local verification

[The focused record](../outputs/reports/2026-09-20-received-leaderboard-v2.md)
identifies commands actually run and limitations. Use the existing P8/P9 owned
loopback harness and pgTAP/native tests. No new test framework, weekly gate,
release matrix, load/soak or physical-device campaign is required for this slice.
