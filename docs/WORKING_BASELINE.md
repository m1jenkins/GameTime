# GameTime working baseline

Develop in `/Users/user/Documents/GitHub/GameTime` on `main`.
Read `git status --short --branch` and `git log -1` before starting work.
This is the current local development line; GitHub publication is a separate step.

September 14: the owner approved and completed the local fast-forward of the
operator slice to `6fea1c28d98ef0ee86a3f9aec72e47b8088c5ec1`. This includes the
previously landed S2/P8/P11A recovery candidate at `a3d2c3f`. The following
documentation-only update records the landing for a fresh Beta plan review.
No push or readiness change accompanied this landing. The dated test reports
remain the verification record; those suites were not rerun for the fast-forward.

The history contains Cobalt, completed P4/P5/P6, P7 preparation and P10 through
`01f1dd159839769fe31ce33804e757876eb4b573`, followed by the consolidated preview
launcher, entry documents and September 13 browser design studies at `b25834c`.
Existing commits are preserved without squashing. The
[consolidation map](WORKTREE_CONSOLIDATION_STATUS.md) records the
archive branches, backup and disposition of old checkouts.

September 13: **Signal is the official native UI/UX.** Native source, tests and
configuration are published on GitHub `main` at `b351a4775a938056ca229301caa513c3e1d85022`.
They replace the ordinary shell and shared presentation, preserve retained
Personal access, and remove superseded rendering and fonts. See the
[P9A report](../outputs/reports/2026-09-13-signal-native-migration.md) for source
identity, actual checks and limits, and the [contract](design/SIGNAL_UI_MIGRATION.md)
for continuing design requirements. The complete migration, including its local
documentation and screenshots, is preserved at `823ee0a` on
`codex/signal-native-migration`. Automatic approval review excluded those supporting
files from the original native-only push; the later `885e8ad` consolidation
committed them, and they are tracked in the current baseline.
The later combined S2/P8/P11A candidate landed on local main at
`a3d2c3f9cafb0c97191b90ce9794dfd36474b3aa`. See the current-work record below.

## Current work

| Work | Status | Evidence |
| --- | --- | --- |
| Foundation / Prompts 0, 0A, 3 | Implemented locally; iPhone-only runtime and closed Health contracts; historical cobalt presentation superseded by P9A | [Historical UI](design/crisp-cobalt/DEFAULT_UI.md), [Health contracts](BETA_HEALTH_CONTRACTS.md) |
| P9A — Signal | Native source published on `main` at `b351a47`; tested source and acceptance limits recorded separately from real integration/release | [Native report](../outputs/reports/2026-09-13-signal-native-migration.md), [contract](design/SIGNAL_UI_MIGRATION.md) |
| P2 | Historical load baseline preserved, including failures | [Capacity report](load/capacity-report.md) |
| P4 | Scoped locks and durable worker claims completed locally | [P4 report](../outputs/reports/2026-09-11-p4-completion.md) |
| P5 | Bounded history and measured query improvements completed locally | [P5 report](../outputs/reports/2026-09-11-p5-completion.md) |
| P6 | Private 250-member community, moderation and quotas completed locally | [P6 report](../outputs/reports/2026-09-12-p6-completion.md) |
| P7 | Preparation only; physical sessions and four accepted sources pending | [P7 checkpoint](../outputs/reports/2026-09-12-p7-preparation.md) |
| P10 | Device-independent hosted/support/retention preparation included; actual hosting unperformed | [P10 report](../outputs/reports/2026-09-12-p10-completion.md) |
| P11A — local recovery | Combined S2/P8/P11A candidate landed on local main at `a3d2c3f9cafb0c97191b90ce9794dfd36474b3aa`; community verification gap closed with a test-only correction and focused review. Hosted schedules, credentials and external alerts remain disabled | [P11A report](../outputs/reports/2026-09-14-p11a-local-recovery.md), [September 14 follow-up](../outputs/reports/2026-09-14-p11a-community-verification.md) |
| P11A — operator CLI | Landed on local main at `6fea1c2`: scoped review/moderation, revocation, global support, suspension and independent appeals with durable human recovery. Reported verification: 131 CLI/HTTP checks, 8 unit tests and 86 SQL assertions passed; administrator grant response reconciliation remains manual | [Operator report](../outputs/reports/2026-09-14-p11a-operator.md), [local guide](BETA_OPERATIONS_LOCAL.md) |
| Local design preview | Fictional friend/personal journeys with configurable owned resources | [Preview guide](BETA_LOCAL_PREVIEW.md) |
| P9 — shared app session | Bounded local implementation connects configured ordinary Signal to the existing authenticated client; default configuration remains off. Actual HTTPS/Apple identity and real-source journeys remain | [Connection and local checks](BETA_LOCAL_PREVIEW.md#ordinary-app-connection-and-its-local-substitute), [P9 report](../outputs/reports/2026-09-15-p9-authenticated-app.md) |
| P8/P9 remainder | Accepted real-source contracts, ingestion, adapters, HTTPS invitations and integrated source-backed journeys remain | [Remaining prompts](FIRSTMATE_REMAINING_IMPLEMENTATION_PROMPTS.md) |
| P11A — account deletion | Landed through `c6f88cd`, including review repairs; local evidence and substitute limits preserved | [Deletion record](evidence/beta-finish-line-b7/account-deletion-local-20260914.md) |
| P11–13 | Hosted capacity/recovery, physical/human/release acceptance, then authorized private Beta remain | [Remaining plan](GAMETIME_REMAINING_IMPLEMENTATION_PLAN.md) |

## Next work

The owner requested a fresh implementation-plan review of the path to private
Beta from the consolidated local main. Identify remaining implementation,
owner decisions and physical/hosted/human acceptance in dependency order.
The owner has an iPhone 17 available and previously reported no Apple Watch;
phone availability alone does not authorize device or Health actions. The
bounded P11A local recovery slice and S2/P8 corrections landed on local main at
`a3d2c3f9cafb0c97191b90ce9794dfd36474b3aa`, reverified September 14. The
[community follow-up](../outputs/reports/2026-09-14-p11a-community-verification.md)
retains its original pre-landing status and validation limits. The subsequent
[operator CLI slice](../outputs/reports/2026-09-14-p11a-operator.md) also landed,
at `6fea1c28d98ef0ee86a3f9aec72e47b8088c5ec1`. Its dated pre-landing report is
preserved; there is no remaining merge dependency for these completed slices.
P7 source acceptance remains deferred until
hardware is available; simulator success cannot accept a source or select
timed-distance tolerance. All four sources still gate distribution. The next
dependency is approved real-source P8/P9 work and, separately, an authorized
hosted target for operation. Do not recreate P9A/P10/P4/P5/P6 or the cancelled
candidate-gate recovery.

The landed combined candidate includes S2's Signal adaptations of the older
overnight issued-link, redemption and detail-response fixes, plus P8's verified
reviewer/revocation synchronization and friend-create/suspension correction.
Their original branches and reports remain preserved; do not import the overnight
implementation a second time. The follow-up changed only community tests and
documentation; prior native, P8 race and upgrade results were not rerun there.

Normal signed-in Signal now obtains its challenge client from shared app services.
The explicit `GAMETIME_CHALLENGE_V1_ENABLED` setting remains off in checked-in
configuration; an approved HTTPS target or explicit non-Release loopback can use
the existing authenticated client. See the [P9 report](../outputs/reports/2026-09-15-p9-authenticated-app.md)
for focused local checks and their limits. All 18 readiness entries remain false.
Consolidation does not enable real activity scoring, community publication,
hosting, money or distribution. Preserve existing Personal agreements and access
until replacement acceptance. P9A's native checks are recorded in its report;
they do not validate the earlier unlocated candidate or establish source,
hosted, physical or human acceptance.

## Evidence and archived work

The P4/P5/P6/P7/P10 reports retain their performed checks, failures and original
source identities. Their old paths and next-task instructions are historical.
The cleanup's actual checks are recorded in the consolidation map; they do not
replace physical, hosted or release acceptance.

The old dirty copy, earlier Beta1 code and old branch tips are preserved separately.
Do not apply their whole patches to this source. Use a short-lived branch from
current `main` for future work, and use a worktree only when isolation is needed.
