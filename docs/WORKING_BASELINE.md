# GameTime working baseline

Read `git status --short --branch` and `git log -1` first. Continue from local
`main`, which contains reviewed P11 source `8e45132` and its P8/P9 ancestors
through merge `9652bc9`. The P11B installation receipt was committed as `4c8183b`.
The owner directed completed authorized work to be committed and merged into
`main`; push remains separately authorized. This consolidation was not pushed.

## September 22 friends Phase 3 native

- **Friends in the app.**
  - Friends under You, Add a friend, safety, Blocked people.
  - Home action rows.
  - The invite-step friend picker, and "Challenge saved." for open friend
    lobbies.
  - The "Before you start" 21+ and Apple Watch onboarding step.
  - All follow the approved mocks and are backed by the new `FriendsStore` and
    the Phase 2 friend RPCs.
- **Server-reported policies.** Creation follows `challenge_availability_v1`.
  - A server without it keeps the trial's two pairs for Staging.
  - Links stay hidden unless the server opens them.
  - The Earlier challenges row stays hidden after a failed load.
- **TestFlight build.** A fourth configuration, `TestFlight`: production
  bundle, P11B, challenges and account mode on, no payment provider, plus its
  scheme. `scripts/check-beta-candidate.sh --testflight` checks it.
- **Not done here.** Nothing was installed, signed, uploaded, applied to hosted
  or pushed. Phase 4 local verification is next.

See the [receipt](../outputs/reports/2026-09-22-friends-phase-3-native.md) for
checks and open items.

## September 22 friends Phase 1 mocks and Phase 2 server

- **Phase 1 mocks, approved September 22 with no changes.** The board is in
  [`.lavish/gametime-friends-2026-09-22/`](../.lavish/gametime-friends-2026-09-22/README.md).
  It covers Friends under You, Add a friend, safety, Home action rows, the
  invite picker, the 21+ and Apple Watch onboarding step, and "Challenge
  saved." for open friend lobbies. All data is fictional.
- **Phase 2 server, local only.** Migration `20260922210000` adds the friend
  commands, their journal and the `commands_only` write guard. Migration
  `20260922210100` adds the per-policy allowlist, account mode and
  `challenge_availability_v1`. pgTAP `529`–`531` add 147 assertions. The full
  suite passed with 114 files and 5,205 assertions. A hosted-order rehearsal
  applied `20260920162025` after `20260922150718`, and an in-flight Personal
  goal kept its terms and result across the upgrade.
  - Every new setting defaults to current behavior.
  - Nothing was applied to `gametime-p11b` or pushed.
  - The owner accepted block as the remedy for re-requests after a decline.
  See the [receipt](../outputs/reports/2026-09-22-friends-phase-2-server.md).

## September 22 fixture admission age fix

Migration `20260922181912` restores the 21+ check on the fixture path of
`app.challenge_admit_v1`, which `20260920010824` had dropped. Everything else
in the `20260920160248` definition is unchanged. pgTAP `528` covers it. See the
[receipt](../outputs/reports/2026-09-22-fixture-admission-age.md) for the
disposable-stack results. Local only: not applied to `gametime-p11b`, where
fixtures are off, and not pushed.

## September 22 Phase 0: friends TestFlight scope and landed trial work

[D142](../DECISIONS.md#d142-first-private-testflight-adds-friends-opens-apple-sign-up-and-ships-goals-first)
and the [friends TestFlight plan](FRIENDS_TESTFLIGHT_PLAN.md) set the next work.
Phase 0 landed the in-flight work and recorded the scope. It changed nothing on
hosted and pushed nothing.

- **`2baf7ff`** lands migration `20260922150718` and its
  [receipt](../outputs/reports/2026-09-22-private-trial-outdoor-runs.md). The
  migration was already applied to `gametime-p11b` on September 22. The private
  trial now accepts personal Steps and personal Outdoor runs for its one
  enrolled account. This supersedes the "steps only" trial note in the
  September 21 entry below. `20260920162025` is still unapplied on hosted, so
  the hosted migration list is not the repo list.
- **`1fbd997`** lands the Personal Outdoor runs and Steps choice and the
  "Challenge locked in." post-save screen, plus a fix to how one layout test
  measures text.
  - Checks on the iPhone 17 Pro iOS 27.0 simulator: 56 of 57 focused unit tests
    passed, and all 8 `LiveDesignUITests` passed. Controller-backed UI journeys
    were skipped.
  - The one unit failure,
    `testReceivedLeaderboardCreationAndHealthCopyAtLargeTextInLightAndDark`,
    fails the same way on clean `ca92d25`. It is an existing failure, not caused
    by this change.
  - Known limit: a friend lobby also lands on "Challenge locked in." before
    anyone has agreed. The Phase 1 mocks replace that state.
  - Not reinstalled on the phone. The September 21 Staging installation remains
    the last device receipt.
- **D142 docs change:** records D142, the friends plan, the responsible-engagement
  review, `docs/COPY.md` glossary rows for friends and the no-device-check
  disclosure, and updated pointers.
- **Left untracked:** the owner's real-device QA screenshot in
  `.lavish/gametime-native-live-2026-09-22/qa/` stays out of this public
  repository, and `sim-check/` is scratch.

## September 22 locked mock adoption and native UI rewrite

The owner adopted the September 21 Home, Goal / Rules, Challenges, You and
create/invite mockups for the actual app and authorized replacing the existing
UI, then comparing native screenshots with those references and revising them.
The [current visual contract](design/SIGNAL_UI_MIGRATION.md#locked-mock-adoption-and-native-rewrite--september-22-2026)
locks background `#FAFBFC`, surface `#F0F2F5`, text `#111318`, accent `#245BFF`,
warning `#9A6700`, athletic metric typography and light appearance. It supersedes
the conflicting September 13 cobalt-retirement/type/appearance requirements
for this exact direction; earlier dated design records remain historical.

Current source routes ordinary signed-in use through `LiveChallengeShell` and
the new Home, Challenges, You, Goal / Rules and Settings presentation. New
launch/sign-in/profile-entry views, creation/invitation/community review, consent,
activity, results, account actions and retained Personal-history presentation
use the same system. The former tab UI is not a service-unavailable fallback.
Real `AppModel`, challenge and retained Personal stores continue to own actions;
the rewrite does not replace live records with the mock's example data.
Production challenge titles and avatar initials derive from available data;
named mock records and portraits are explicit DEBUG screenshot fixtures.

The [native implementation record](../.lavish/gametime-native-live-2026-09-22/IMPLEMENTATION.md)
owns performed validation, screenshots, comparison revisions and remaining
limits. This entry records adoption and current wiring, not a claim that final
checks or release acceptance have completed. Existing exact agreement targets,
stakes, allocations, consent and review rules are preserved; no backend,
admission or money gate changes with this UI work. No hardware installation is
performed in this task. The September 21 Staging installation below remains
the last device receipt until a later installation is recorded.

## September 20 challenge-creation recovery

The connected iPhone had been overwritten by the ordinary Debug product,
`0.8.1 (1)`. Debug and Staging intentionally share
`com.mjenkins.gametime.staging`, but Debug uses the closed public challenge
configuration. The signed challenge-enabled Staging product
`0.8.1 (926.21.1)` was verified, installed in place and launched; the existing
container, Apple account and saved challenges were preserved. Hosted private
trial admission, ingestion and processing remain enabled for the single enrolled
account. See the [recovery receipt](../outputs/reports/2026-09-20-challenge-creation-recovery.md).

Do not run the `GameTime` Debug scheme on Mason's iPhone while the private trial
is active: it replaces this Staging bundle and closes new challenge transport.
Use `GameTime-Staging` with the `Staging` configuration for physical-device work.

## September 21 native Signal follow-through

The [native report](../outputs/reports/signal-native-2026-09-21/REPORT.md) records
the local response to the installed 0.8.1 (926.20.1) feedback: two-stage direct
Personal creation, grouped Challenges, saved-goal Home, corrected ordinary-profile
ownership and consistent secondary routes. The [profile data contract](design/SIGNAL_PROFILE_DATA.md)
keeps new records separate from retained Personal and distinguishes missing,
partial and stale data. The signed Staging successor is prepared for a coordinated
in-place update; it is not installed by this task. Hosted state and product rules
are unchanged. See the report for source and actual verification.

The subsequent [native create/invite integration](../.lavish/gametime-live-goal-2026-09-21/NATIVE_CREATE_INVITE.md)
connects the approved metric cards and SF Symbols to creation, then opens real
invitations after a friend lobby saves. Username/link requests, agreement rules,
Personal consent and product gates remain intact. Its first Staging build,
926.21.2, was installed but retained too much of the old form layout. The owner's
phone screenshot triggered a native layout correction: full-screen creation,
inline units, calendar dates, compact agreement rows and docked actions. Corrected
Staging **0.8.1 (926.21.3)** is now installed and launched normally on Mason's iPhone.
The linked report distinguishes the 22 passing creation/layout tests plus 35
passing regression tests, simulator captures, physical installation, and remaining
human checks. The private phone/server trial remains Personal Apple Watch steps
only; no private admission, hosted state, account-verification choice or product
agreement changed.

## September 20 private iPhone trial

The [private-device receipt](../outputs/reports/2026-09-20-private-device-goal.md)
records the owner's authorized Staging connection to `gametime-p11b`, deployment
of the existing App Attest and signed Health endpoints, and the new project-local
account guard. Staging now targets the selected backend with ordinary Signal
transport enabled; Debug/Release and historical credentials/data are preserved.
The app is installed and launched normally on Mason's iPhone. Apple account setup,
21+ confirmation, single-account enrollment and actual device verification passed.
Additional signup is closed; real admission/ingestion are enabled behind the
private guard. A genuine newer assertion format exposed a parser defect, now
fixed and deployed with focused regressions. The owner subsequently chose to keep
Apple sign-in and skip device verification. The selected Staging build and an
explicit, enrolled-account-only server setting now support that mode; other
installations retain their device-proof requirement. Real Watch steps readiness
and deliberate consent succeeded: one 4,703-total-step personal goal is scheduled
for September 22–28, with $20 in nonredeemable simulation. Exact request replay
returns the same receipt without another goal or consent. Counting and the full
result/review cycle still await real deadlines. This is a private device milestone,
not wider Beta readiness; use the receipt's exact performed/pending checks.
The selected backend has 95 applied migrations. The separately merged
received-score leaderboard migration remains local and was not deployed by this
device milestone; do not equate the current `main` migration list with hosted state.

The September 20 [activation receipt](../outputs/reports/2026-09-20-p11-hosted-activation.md)
records scheduled operation on an empty backend: worker, monitor and processing
remain enabled after bounded acceptance. This supersedes their inactive state
in the installation record below. The later private-device receipt above records
the owner's account gates; no community is selected, and full operational
acceptance and wider beta readiness remain unestablished.

## September 20 received-score leaderboards

D141 adds four optional local `friend_*_leaderboard_v2` policies from D140
`110c470`, using existing adapters, ingestion, allocation and Signal. See the
[contract](RECEIVED_LEADERBOARD_V2.md) and [focused checks](../outputs/reports/2026-09-20-received-leaderboard-v2.md).
Saved partial scores rank through the correction cutoff; missing scores are
unranked with entries returned, and fewer than two valid scores voids. Old
agreements, strict Exercise v1 and Personal's promise remain unchanged. D140's
nine-goal release scope remains; this is not a hosted or release acceptance.
The sections below retain the earlier completion states and evidence.

## September 20 bounded P11B hosted installation

The [installation receipt](../outputs/reports/2026-09-20-p11b-hosted-installation.md)
records the approved installation of all 93 migrations and only the three
challenge machine functions in `gametime-p11b` (`lyushhqoednheqwzsmxh`), Better Bet,
`us-west-1`, Free plan, quoted $0/month within the owner's $20 ceiling. The owner
is commissioning owner and credential custodian; distinct secrets are in Vault
and Edge secret storage. All eight jobs, product gates and fixtures remain off;
Auth is closed, private schemas unexposed and no community selected. The single
readback, one authenticated closed-status monitor request and three unauthenticated
denials passed. Canonical migrations are unchanged. No broader acceptance ran.

Use the [next planning prompt](P11B_NEXT_PLANNING_PROMPT.md). Existing local P11
verification and this bounded installation are established evidence. Active
operation, app identities/connectivity, remaining operating decisions and release
acceptance remain separate. Older unfilled hosting worksheets do not reopen the
selected project, region, cost ceiling or owner custody.

## September 20 local P11 scheduling boundary

The owner selected Supabase Cron + Edge. Three fixed machine interfaces now
connect durable worker invocations, selected-community snapshots and sanitized
read-only monitoring. Dedicated worker and monitor credentials have separate
authority; new Cron jobs and private configuration start off. The
[local report](../outputs/reports/2026-09-20-p11-local-scheduling.md) owns exact
source, performed checks, failures, resource cleanup and remaining limits. The
[hosting worksheet](BETA_HOSTED_PREPARATION.md#september-20-local-cron-and-edge-continuation)
records local defaults separately from unapproved hosted settings.

The local report completes the bounded scheduling connection; the installation
above adds only its approved closed hosted configuration and checks. Active
operation, named operators and remaining operating settings are separate.
External alerts, hosted capacity/recovery, physical/human
acceptance and release qualification remain unperformed. All 18 readiness
entries stay false; D140 makes the nine goals the working Beta scope and defers
the four unavailable leaderboards. Four goal-metric source acceptance and other
release gates remain open. The older P9 next-planning
prompt below is dated context, not a request to repeat this completed slice.

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
miss or complete ranking. Under D140, these nine goals form the working Beta
scope; the four friend leaderboards no longer gate distribution. Four goal-metric
source acceptance and the other release gates remain open.
All external readiness entries and checked-in gates stay closed.

The sections below preserve the earlier source states and evidence. P7 remains
owner-closed. Hosting identities, community publication settings, operating
approval, replacement retirement and P12/P13 remain separate. Start next planning
with [the current bounded handoff](P11B_NEXT_PLANNING_PROMPT.md).

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
  and nine-goal release acceptance are not established by synthetic local checks.
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
