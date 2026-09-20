# GameTime working baseline

Read `git status --short --branch` and `git log -1` first. The current local P9
continuation is `codex/p9-signal-real-activity`, directly from P8 `8a9d1f0`;
local `main` remains `848ef6e` and lacks both. Use this branch or a verified
descendant for continuation, not an older main checkout. No push or merge is implied.

## September 20 P9 local continuation

[D139](../DECISIONS.md#d139-signal-real-activity-and-versioned-apple-exercise-credit)
selects a new Exercise credit policy while preserving strict v1 and historical
consent. The [P9 contract](P9_SIGNAL_REAL_ACTIVITY.md) describes shared delivery
across all five signed writers, separate Health ownership, per-binding protected
comparison state, automatic opportunities plus Refresh, and ordinary Signal
readiness/consent/progress/correction/review/history. The
[local report](../outputs/reports/2026-09-20-p9-signal-real-activity.md) records
synthetic native, Edge, SQL and populated-upgrade checks and their limits.

New agreements can use nine goal policies: four friend, four Personal and
community steps. Four real leaderboards show **Leaderboard — Not available yet**.
Positive activity can prove success; incomplete history never establishes a
miss or complete ranking. The four-metric/all-13 release gate is unchanged.
All external readiness entries and checked-in gates stay closed.

The sections below preserve the earlier source states and evidence. P7 remains
owner-closed. Hosting identities, community publication settings, operating
approval, replacement retirement and P12/P13 remain separate. Start next planning
with [the bounded handoff](P9_NEXT_PLANNING_PROMPT.md).

## September 19 main consolidation

The [consolidation record](../outputs/reports/2026-09-19-main-consolidation.md)
identifies the published main merge, checks and retired branches. Main includes
profile retry (`70584f1`), actor-switch isolation (`9f116ac`), delivered HTTPS
invitations, administrator recovery, review/appeal and community snapshot
monitoring, suspended-account repair, iOS 18 compatibility and the fictional
Personal lifecycle preview.

The [integration record](../outputs/reports/2026-09-19-integrated-candidate.md)
records exact input commits, conflict resolutions, tested source and resource
cleanup. Actual combined checks passed: 159 native tests, 614 SQL assertions in
17 suites, 230 complete operator CLI/Auth/HTTP checks, 11 operator units,
431 populated-upgrade assertions, 18 review/appeal HTTP checks, 23 deletion
race checks, 12 suspended-session lock-wait cases and 14 deletion handler units. The separate
snapshot runner passed 218 SQL assertions and 48 checks (including setup/SQL
summaries and HTTP checks). These are focused local results, not P12 acceptance.
The repaired suspended-account suites pass; their original failures remain in
the untouched dated reports. The later full portable weekly gate passed on the
consolidated source; the consolidation record lists CI status at merge. The full
release matrix remains reserved for P12.

## September 19 P8 local continuation

[D138](../DECISIONS.md#d138-owner-selects-p8-source-rules-and-whole-run-distance-tolerance)
selects source rules and the inclusive 100–102% whole-run distance rule. The
[real Health contract](P8_REAL_HEALTH_CONTRACT.md) describes separately versioned
steps, distance and timed adapters, private signed ingestion, source-aware
server processing and durable local retries. Exercise remains unavailable
because public quantity APIs cannot establish the causal activity needed to
exclude manual/imported/third-party-derived credit. Positive activity can prove
a met goal; incomplete history still cannot prove a miss or complete leaderboard.

The [local software record](../outputs/reports/2026-09-19-p8-real-health.md)
identifies the task branch, checks and remaining limits. P9 must wire the new
contracts into Signal and coordinate signing through committed recovery across
retained writers sharing an App Attest key with the coordinated P8 pair. Checked-in clients and all 18 external
readiness entries remain off. The owner has closed measured P7 testing; the
dated observation record below is historical, not a request to repeat it.

## September 18 P7 device session

The owner now has a paired Apple Watch and opted in to a private investigation
on an iPhone 17. The current Debug iPhone app was built, package and signature
checked, installed and launched in `--health-source-investigation` mode. The
owner confirmed the investigation screen. Session A showed separately visible
iPhone- and Watch-origin steps, flagged overlapping records, and passed the
private session clearing check. Reconciliation and completeness remain
unresolved. An initial Apple Exercise Time read showed clear Watch origin;
its hand-entry field was not supplied, and Exercise eligibility and result
rules remain open. A September 19 continuation observed two Watch-origin running
workouts, including a paused run whose start-to-finish elapsed time exceeded its
reported workout duration. The owner reports one privately measured run as
accurate and a whole record as inspectable in the boundary-window check;
quantified repeated accuracy, the boundary warning, manual/import eligibility
and the distance tolerance remain open. No physical source is accepted or
enabled. On September 19 the owner declared P7 testing passed and requested
[P8 preparation](P8_REAL_SOURCE_PREPARATION.md); that sign-off does not rewrite
the performed-observation record. Continue from the
[device-session record](../outputs/reports/2026-09-18-p7-device-session.md)
and [private session guide](BETA_PHYSICAL_SESSIONS.md).

## Verified baseline — September 15, 2026

On September 15, local `main`, `origin/main` and GitHub `main` matched
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
| P7 | Owner signed off measured testing; D138 supplies the source and timed-distance rules without rewriting historical observations | [Current session](../outputs/reports/2026-09-18-p7-device-session.md), [P8 handoff](P8_REAL_SOURCE_PREPARATION.md) |
| P10 | Device-independent hosted/support/retention preparation included; actual hosting unperformed | [P10 report](../outputs/reports/2026-09-12-p10-completion.md) |
| P11A — local recovery | Combined S2/P8/P11A candidate landed on local main at `a3d2c3f9cafb0c97191b90ce9794dfd36474b3aa`; community verification gap closed with a test-only correction and focused review. Hosted schedules, credentials and external alerts remain disabled | [P11A report](../outputs/reports/2026-09-14-p11a-local-recovery.md), [September 14 follow-up](../outputs/reports/2026-09-14-p11a-community-verification.md) |
| P11A — operator CLI | Landed on local main at `6fea1c2`: scoped review/moderation, revocation, global support, suspension and independent appeals with durable human recovery. Original reported verification: 131 CLI/HTTP checks, 8 unit tests and 86 SQL assertions. Main now includes new administrator receipts and repaired suspended access; historical v1 recovery remains manual | [Operator report](../outputs/reports/2026-09-14-p11a-operator.md), [administrator recovery report](../outputs/reports/2026-09-18-admin-grant-recovery.md), [local guide](BETA_OPERATIONS_LOCAL.md) |
| Local design preview | Fictional friend/personal journeys with configurable owned resources | [Preview guide](BETA_LOCAL_PREVIEW.md) |
| P9 — shared app session | Bounded local implementation connects configured ordinary Signal to the existing authenticated client; default configuration remains off. Actual HTTPS/Apple identity and real-source journeys remain | [Connection and local checks](BETA_LOCAL_PREVIEW.md#ordinary-app-connection-and-its-local-substitute), [P9 report](../outputs/reports/2026-09-15-p9-authenticated-app.md) |
| P9 — HTTPS invitation slice | Main includes exact configured-origin intake/formatting and preserves durable deliberate redemption. Domain, Apple identity, OS association and hosted/device acceptance remain open | [Local contract and inactive templates](BETA_INVITATION_LINKS_LOCAL.md), [checks and actor-switch composition](../outputs/reports/2026-09-18-https-invitations.md) |
| P8 / P9 real activity | Local Signal integration and key-wide recovery implemented on the P9 branch; Exercise credit v2 is separate from unavailable strict v1. Nine goals plus four unavailable leaderboard states; hosted identity/operation and full release acceptance remain | [P9 contract](P9_SIGNAL_REAL_ACTIVITY.md), [local report](../outputs/reports/2026-09-20-p9-signal-real-activity.md) |
| P11A — service monitoring | Review/appeal and selected-cohort snapshot projections are in main and locally verified; no scheduler, alert destination, staffing or freshness threshold is accepted | [Integration record](../outputs/reports/2026-09-19-integrated-candidate.md), [snapshot contract](COMMUNITY_SNAPSHOT_STATUS_LOCAL.md) |
| P11A — account deletion | Landed through `c6f88cd`, including review repairs; local evidence and substitute limits preserved | [Deletion record](evidence/beta-finish-line-b7/account-deletion-local-20260914.md) |
| P11–13 | Hosted capacity/recovery, physical/human/release acceptance, then authorized private Beta remain | [Remaining plan](GAMETIME_REMAINING_IMPLEMENTATION_PLAN.md) |

## Remaining work and authority

The consolidated main source does not qualify the P12 release matrix or dispatch
hosted, physical, human or release work.
Use the [remaining plan](GAMETIME_REMAINING_IMPLEMENTATION_PLAN.md) and
[bounded prompts](FIRSTMATE_REMAINING_IMPLEMENTATION_PROMPTS.md) for their
preserved requirements and dependency order:

- P7: the owner has closed measured testing and D138 supplies explicit source
  and timed-distance rules. Preserve the dated observations; do not restart P7.
- P8/P9: local Signal integration and shared exact delivery are implemented on
  the P9 branch. Exercise credit v2 accepts disclosed unknown causal origin;
  strict v1, complete leaderboards and confirmed misses remain unavailable.
  Approved HTTPS/Apple identity and invitations, operated source-backed journeys
  and all-13 release acceptance are not established by synthetic local checks.
- P10/P11: approved hosted identity/settings, scheduled operation, credentials,
  alerts, retention/deletion and recovery/capacity acceptance. Local worker,
  scoped operator CLI and deletion implementation are complete; administrator
  response recovery for new grants/revokes, suspended-account repair and service
  monitoring are included in main. Historical v1
  reconciliation remains manual.
- P12/P13: source-backed integration and the full release matrix, physical/accessibility/human acceptance,
  replacement acceptance before legacy shell retirement, then authorized private
  Beta. Public submission and funded operation remain separate.

`GAMETIME_CHALLENGE_V1_ENABLED` stays off in checked-in configuration. All 18
readiness entries remain false, including money and optional analytics that
should remain off for simulation. No source, hosted, human or release gate is
closed by local integration. Preserve Personal/Solo/charity functionality, exact consent
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
in that disposition. The profile retry finding now has a bounded client correction
and [focused simulator verification](../outputs/reports/2026-09-18-profile-creation-retry.md);
real database and hosted retry acceptance were not performed. Preserve the bundle, stashes and
uncommitted work; do not import whole patches or merge cancelled branches merely
to delete them.
