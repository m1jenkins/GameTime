# GameTime working baseline

Develop from `main` in `/Users/user/Documents/GitHub/GameTime`; use isolated task
branches when needed. Read `git status --short --branch` and `git log -1` first.

## September 18 P7 device session

The owner now has a paired Apple Watch and opted in to a private investigation
on an iPhone 17. The current Debug iPhone app was built, package and signature
checked, installed and launched in `--health-source-investigation` mode. The
owner confirmed the investigation screen. Session A showed separately visible
iPhone- and Watch-origin steps, flagged overlapping records, and passed the
private session clearing check. Reconciliation and completeness remain
unresolved. No physical source is accepted or enabled. Continue from the
[device-session record](../outputs/reports/2026-09-18-p7-device-session.md)
and [private session guide](BETA_PHYSICAL_SESSIONS.md).

## Verified baseline — September 15, 2026

Local `main`, `origin/main` and GitHub `main` match
`1dacc6644f2100567d85fbaa2970bb7285bbaa35`. All completed slices below are in that
published ancestry, including P9's shared-session connection and the local
deletion/operator/privacy fixes. Later cleanup delivery and the read-only
branch/worktree disposition are recorded in the
[clean-baseline report](../outputs/reports/2026-09-15-clean-baseline.md).
Firstmate owns its final fast-forward, push and guarded resource cleanup; that
report does not claim those actions have already happened.

**Signal is the ordinary native UI.** Shared components, launch/onboarding,
new challenge routes and retained Personal use its semantic colors and system
typography. [The migration contract](design/SIGNAL_UI_MIGRATION.md) and
[original native report](../outputs/reports/2026-09-13-signal-native-migration.md)
record adoption, checks and limits. Supporting migration evidence first excluded
from the native-only push was subsequently committed through `885e8ad` and is
included in this published baseline.

## Current work

| Work | Status | Evidence |
| --- | --- | --- |
| Foundation / Prompts 0, 0A, 3 | Implemented locally; iPhone-only runtime and closed Health contracts; historical cobalt presentation superseded by P9A | [Health contracts](BETA_HEALTH_CONTRACTS.md) |
| P9A — Signal | Native migration included in published main; original source publication at `b351a47`; tested source and acceptance limits recorded separately from real integration/release | [Native report](../outputs/reports/2026-09-13-signal-native-migration.md), [contract](design/SIGNAL_UI_MIGRATION.md) |
| P2 | Historical load baseline preserved, including failures | [Capacity report](load/capacity-report.md) |
| P4 | Scoped locks and durable worker claims completed locally | [P4 report](../outputs/reports/2026-09-11-p4-completion.md) |
| P5 | Bounded history and measured query improvements completed locally | [P5 report](../outputs/reports/2026-09-11-p5-completion.md) |
| P6 | Private 250-member community, moderation and quotas completed locally | [P6 report](../outputs/reports/2026-09-12-p6-completion.md) |
| P7 | Session A observations recorded; steps policy and all four accepted sources pending | [Current session](../outputs/reports/2026-09-18-p7-device-session.md), [preparation](../outputs/reports/2026-09-12-p7-preparation.md) |
| P10 | Device-independent hosted/support/retention preparation included; actual hosting unperformed | [P10 report](../outputs/reports/2026-09-12-p10-completion.md) |
| P11A — local recovery | Combined S2/P8/P11A candidate landed on local main at `a3d2c3f9cafb0c97191b90ce9794dfd36474b3aa`; community verification gap closed with a test-only correction and focused review. Hosted schedules, credentials and external alerts remain disabled | [P11A report](../outputs/reports/2026-09-14-p11a-local-recovery.md), [September 14 follow-up](../outputs/reports/2026-09-14-p11a-community-verification.md) |
| P11A — operator CLI | Landed on local main at `6fea1c2`: scoped review/moderation, revocation, global support, suspension and independent appeals with durable human recovery. Reported verification: 131 CLI/HTTP checks, 8 unit tests and 86 SQL assertions passed; administrator grant response reconciliation remains manual | [Operator report](../outputs/reports/2026-09-14-p11a-operator.md), [local guide](BETA_OPERATIONS_LOCAL.md) |
| Local design preview | Fictional friend/personal journeys with configurable owned resources | [Preview guide](BETA_LOCAL_PREVIEW.md) |
| P9 — shared app session | Bounded local implementation connects configured ordinary Signal to the existing authenticated client; default configuration remains off. Actual HTTPS/Apple identity and real-source journeys remain | [Connection and local checks](BETA_LOCAL_PREVIEW.md#ordinary-app-connection-and-its-local-substitute), [P9 report](../outputs/reports/2026-09-15-p9-authenticated-app.md) |
| P8/P9 remainder | Accepted real-source contracts, ingestion, adapters, HTTPS invitations and integrated source-backed journeys remain | [Remaining prompts](FIRSTMATE_REMAINING_IMPLEMENTATION_PROMPTS.md) |
| P11A — account deletion | Landed through `c6f88cd`, including review repairs; local evidence and substitute limits preserved | [Deletion record](evidence/beta-finish-line-b7/account-deletion-local-20260914.md) |
| P11–13 | Hosted capacity/recovery, physical/human/release acceptance, then authorized private Beta remain | [Remaining plan](GAMETIME_REMAINING_IMPLEMENTATION_PLAN.md) |

## Remaining work and authority

The current task prepares a clean baseline. It does **not** dispatch P7–P13.
Use the [remaining plan](GAMETIME_REMAINING_IMPLEMENTATION_PLAN.md) and
[bounded prompts](FIRSTMATE_REMAINING_IMPLEMENTATION_PROMPTS.md) for their
preserved requirements and dependency order:

- P7: actual iPhone/paired Watch observations, all four accepted sources and
  measured timed-distance tolerance. The first private device session is under
  way; its observations and source decisions remain pending.
- P8/P9: accepted real-source ingestion, adapters and all 13 integrated policies;
  approved HTTPS/Apple identity and invitations. The local shared-session
  connection is complete; source-backed and hosted journeys are not.
- P10/P11: approved hosted identity/settings, scheduled operation, credentials,
  alerts, retention/deletion and recovery/capacity acceptance. Local worker,
  scoped operator CLI and deletion implementation are complete; administrator
  grant response reconciliation remains manual.
- P12/P13: integrated candidate, physical/accessibility/human acceptance,
  replacement acceptance before legacy shell retirement, then authorized private
  Beta. Public submission and funded operation remain separate.

`GAMETIME_CHALLENGE_V1_ENABLED` stays off in checked-in configuration. All 18
readiness entries remain false, including money and optional analytics that
should remain off for simulation. No source, hosted, human or release gate is
closed by cleanup. Preserve Personal/Solo/charity functionality, exact consent
and data. Do not restart P4/P5/P6/P9A, P10 preparation, landed S2/P8/P11A repairs,
or cancelled candidate-gate recovery.

## Evidence and recovery

Dated reports retain their actual source identities, test counts, failures and
unperformed checks. Old paths and next-task statements are historical, not
current resource ownership. The [September 12 consolidation record](WORKTREE_CONSOLIDATION_STATUS.md)
retains recovery locations for the original dirty copy and competing Beta1 work.
The [September 15 branch disposition](HISTORICAL_BRANCH_DISPOSITION_20260915.md)
records all nine exact historical ref tips and the September 16 executed pruning.
The captain's explicit backup-and-delete choice supersedes live-ref retention;
useful profile-retry/controller corrections and distinct evidence remain in the
verified external bundle, with its location, checksum and safe recovery recipe
in that disposition. The static-only profile retry finding remains unresolved
for bounded review before final testing. Preserve the bundle, stashes and
uncommitted work; do not import whole patches or merge cancelled branches merely
to delete them.
