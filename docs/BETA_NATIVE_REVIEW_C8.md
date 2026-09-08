# Native screen review — c8

This review uses the actual GameTime Simulator app and supplied Matchday/custom-icon
references. Activity, accounts and stakes are fictional. It is software/visual
preparation, not physical observation or human comprehension/accessibility acceptance.
The [local visual artifact](../.lavish/gametime-real-validation-c8.html) presents the
comparison with appearance controls. Firstmate owns its registered feedback monitoring;
this worker does not poll. No hosted sharing is enabled.

## What the functioning screens show

| Screen / reference | Observed behavior and refinement |
| --- | --- |
| Refined Matchday Home (`outputs/design/2026-09-07-matchday-visuals/02-home-refined.png`) | Native Home retains editorial type, the custom steps icon, dark challenge card, orange own values and clear simulated disclosure. The reference is a design proposal; its illustrative values are not activity evidence. |
| Home initial/failed/empty | The old empty message could appear while reads were pending or unavailable. c8 distinguishes loading, failed refresh and a confirmed empty account; section and actor-race tests prove those states. |
| Friend goal creation | With friends → Goal explains that each person chooses a goal before the roster is locked and everyone agrees. The current run also exercised fictional age confirmation. |
| Leaderboard creation | With friends → Leaderboard explains best result/co-winners; no target field appears. [Actual capture](evidence/beta-real-validation-c8/screens/preview-leaderboard.png). |
| Personal goal form | Its own target label persists, invalid nonempty input explains the required format, and Review stays disabled. Actual entry `1.5` into steps produced the correct whole-number help. [Actual capture](evidence/beta-real-validation-c8/screens/preview-personal-invalid.png). No agreement was submitted during this manual inspection. |
| Timezone and action feedback | Native labeled timezone row allows long values to wrap and disables autocapitalization. Sign-in/reading/saving show progress; duplicate local sign-in attempts are bounded. |
| Departed participant | Native member rendering guards identity/current goal/activity in addition to the server projection. Historical agreement and own receipt are retained. |
| Exact-data charts | Only the person's returned canonical value is charted. No invented daily series, inferred missing activity, routes, private raw samples or departed counterpart activity is introduced. |

The reference's compact light personal card and some dashboard density are still
visually different: the current shell uses the shared dark card across formats.
This review preserves the functioning journey and prioritizes data permission,
state clarity, forms and accessibility. It does not claim pixel parity with a mock.
Human review should assess comprehension, reading order and comfort using the
actual populated app; an automated audit is not that acceptance.

## Executed visual checks

Four final tests passed in light, dark, largest system text and a 320-point compact
viewport, with sixteen unfiltered screen audits. They exercise Home, creation,
detail, age confirmation and actual duration/amount increments/decrements.
The compact viewport is simulated; no physical small phone was used.

Three earlier failures remain recorded in the acceptance ledger: clipped creation
disclosure contrast; distinct single-line timezone clipping; and a redundant
compact-detail goal heading at the visible edge. Corrective changes retained the
native field, semantic labels, uncapped text and audit categories. The final
native suite separately executed 396 cases: 392 passed, four controller skips,
zero failures. The production HTTP controller separately passed 20 tests.

The [acceptance ledger](BETA_REAL_VALIDATION_ACCEPTANCE.md) records exact commits,
commands, pass/fail/skip counts and evidence limits. Named captures under
`docs/evidence/beta-real-validation-c8/screens/` are actual fictional Simulator
screens; no physical investigation capture exists.

The local artifact was opened using chrome-devtools-axi. Images loaded, the Dark
selector switched the actual capture and its accessible pressed state, and widths
500 and 1280 had no horizontal overflow. Its desktop screenshot was visually
inspected. These are artifact checks, not an additional native acceptance suite.

## Review the working preview

The fresh c8 executable was installed and reopened, then selected again through
`open --actor 2` and `open --actor 1`. Its installed executable hash matched the
c8 build after switching. Actor 2 reached its own empty Home; actor 1 returned to
Home. These manual checks are separate from the scripted full agreement journeys.
See [launch instructions and walkthrough](BETA_REAL_VALIDATION_HANDOFF.md).
