# GameTime working baseline

Develop in `/Users/user/Documents/GitHub/GameTime` on `main`.
Read `git status --short --branch` and `git log -1` before starting work.
This is the current local development line; GitHub publication is a separate step.

The history contains Cobalt, completed P4/P5/P6, P7 preparation and P10 through
`01f1dd159839769fe31ce33804e757876eb4b573`, followed by the consolidated preview
launcher and current entry documents. Existing commits are preserved without
squashing. The [consolidation map](WORKTREE_CONSOLIDATION_STATUS.md) records the
archive branches, backup and disposition of old checkouts.

## Current work

| Work | Status | Evidence |
| --- | --- | --- |
| Foundation / Cobalt / Prompts 0, 0A, 3 | Implemented locally; iPhone-only runtime, closed Health contracts, default Cobalt UI | [Cobalt](design/crisp-cobalt/DEFAULT_UI.md), [Health contracts](BETA_HEALTH_CONTRACTS.md) |
| P2 | Historical load baseline preserved, including failures | [Capacity report](load/capacity-report.md) |
| P4 | Scoped locks and durable worker claims completed locally | [P4 report](../outputs/reports/2026-09-11-p4-completion.md) |
| P5 | Bounded history and measured query improvements completed locally | [P5 report](../outputs/reports/2026-09-11-p5-completion.md) |
| P6 | Private 250-member community, moderation and quotas completed locally | [P6 report](../outputs/reports/2026-09-12-p6-completion.md) |
| P7 | Preparation only; physical sessions and four accepted sources pending | [P7 checkpoint](../outputs/reports/2026-09-12-p7-preparation.md) |
| P10 | Device-independent hosted/support/retention preparation included; actual hosting unperformed | [P10 report](../outputs/reports/2026-09-12-p10-completion.md) |
| Local design preview | Fictional friend/personal journeys with configurable owned resources | [Preview guide](BETA_LOCAL_PREVIEW.md) |
| P8/P9 | Real ingestion, four adapters and integrated journeys remain | [Remaining prompts](FIRSTMATE_REMAINING_IMPLEMENTATION_PROMPTS.md) |
| P11–13 | Hosted capacity/recovery and physical/human/release acceptance remain | [Remaining plan](GAMETIME_REMAINING_IMPLEMENTATION_PLAN.md) |

## Next work

Design review can use the local fictional preview. P7 resumes the
[physical sessions](BETA_PHYSICAL_SESSIONS.md) after device-specific opt-in naming
the iPhone and paired Watch. Its prepared binary and raw outputs are historical
resources; rebuild if absent and never substitute query success for acceptance.
P8 needs accepted source policies; P9 connects their adapters and actual journeys.
P10's independent preparation is complete. Do not recreate it or restart P4/P5/P6
or the cancelled candidate-gate recovery.

Normal signed-in Cobalt still uses `UnavailableChallengeV1Client`; development
transport remains loopback-only. All 18 readiness entries remain false.
Consolidation does not enable real activity scoring, community publication,
hosting, money or distribution. Preserve existing Personal agreements and access
until replacement acceptance. Cobalt is the implemented default; design review
remains an owner decision.

## Evidence and archived work

The P4/P5/P6/P7/P10 reports retain their performed checks, failures and original
source identities. Their old paths and next-task instructions are historical.
The cleanup's actual checks are recorded in the consolidation map; they do not
replace physical, hosted or release acceptance.

The old dirty copy, earlier Beta1 code and old branch tips are preserved separately.
Do not apply their whole patches to this source. Use a short-lived branch from
current `main` for future work, and use a worktree only when isolation is needed.
