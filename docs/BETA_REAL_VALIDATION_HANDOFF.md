# GameTime real-activity handoff

## Current continuation — September 12, 2026 UTC

Use [WORKING_BASELINE.md](WORKING_BASELINE.md) and the
[remaining prompts](FIRSTMATE_REMAINING_IMPLEMENTATION_PROMPTS.md).
The active checkout is `/Users/user/Documents/GitHub/GameTime` on `main`,
with Cobalt/P4/P5/P6, P7 checkpoint `1b8fe6a` and P10 through `01f1dd15`
preserved in one ancestry. P4/P5/P6 are completed locally. P7 is prepared
only: resume the [private physical sessions](BETA_PHYSICAL_SESSIONS.md) after
device-specific opt-in. No physical source or real ingestion is accepted.

P10 device-independent hosted preparation is recorded in the
[hosted plan](BETA_HOSTED_PREPARATION.md) and [P10 handoff](../outputs/reports/2026-09-12-p10-completion.md).
Use those for current operator permissions and remaining release-readiness inputs.
P7–P9 remain pending and all external gates remain closed.

The historical c8 preview resources and commands below are retained references,
not today's checkout, process state or next-task instructions. Recheck resource
ownership before reuse. Normal Cobalt is now the default signed-in shell with a
closed challenge client; the earlier statement that Release uses the old default
shell is superseded by [Cobalt activation](design/crisp-cobalt/DEFAULT_UI.md).

## Historical c8 continuation and evidence

The continuation fixes five reproduced lifecycle/privacy defects and refines native
loading, errors and labeled forms. It remains a local fictional candidate.
**No physical source is accepted; Beta is not finished.** See [exact acceptance
and test evidence](BETA_REAL_VALIDATION_ACCEPTANCE.md) and [screen review](BETA_NATIVE_REVIEW_C8.md).

September 9: Firstmate independently reconciled D9-1 through D9-4 closure and
the complete fresh Prompt 0 gate at `9c84459e88246e1a34cd2acd6c6f9477384cefec`.
[The acceptance update](BETA_REAL_VALIDATION_ACCEPTANCE.md) identifies that private
parent evidence. The captain permits isolated Prompt 0A implementation from this
exact unlanded descendant; acceptance and landing remain pending.

[D135's contract](BETA_REMAINING_WORK_CONTRACT.md) owns current remaining-work
scope. The Prompt 0A branch retires the dedicated Watch runtime across all product
configurations while preserving iPhone HealthKit and inert historical source.
Its clean exact commit becomes the common parent for subsequently authorized
Wave 1 tasks. This task stops after Prompt 0A. Hardware remains required for launch,
not pre-hardware implementation. The retained preview instructions below are
historical c8 resources, not permission for another task to drive them.

## Retained preview state — September 8

As of 2026-09-08 12:32 UTC the newly built c8 app is open at fictional account 1's
Home on the owned Simulator. Preview PID **10336**, tracked foreground PTY **65466**,
owns controller 58339. Do not launch a second controller while it is running.
The installed executable matches c8 after account switching; exact hashes and
manual checks are in the acceptance ledger. If the worker's foreground lifecycle
ends, use the exact relaunch below after checking ownership/ports. Do not assume
that a historical “gates off” test report describes this intentionally live preview.

Product commits: `4744a3d41279b8dbb81703877ecec5726c91bca4`,
`bfcec58a910d54f3a5d64a2ca53045229ff1fac0`,
`2480bca4d1db6253be4b91871af3bedfa50b146e`.
Final fresh checks: 3,882 SQL; 835 Deno; 113 core Swift; 396 native cases
(392 passed, four controller skips); 20 separately executed native HTTP tests;
four native appearance tests/sixteen unfiltered audits. No physical acceptance.

## Open the actual app

Worktree: `/Users/user/.treehouse/gametime-beta-7b9cca/2/gametime-beta`.
Branch: `fm/gametime-beta-real-validation-c8`, directly descended from
`cf82e25bd7905c851525b837259bba0f0aaf3d8f`. b7 and the original checkout are
preserved read-only; no merge or landing is authorized.

Simulator: **GameTimeFinishB7**, iPhone 17 Pro / iOS 26.5,
`72A3249A-2DE0-4695-AF41-DCD2743B4666`. Bundle:
`com.mjenkins.gametime.staging`. **Use the c8 build**:
`/tmp/gametime-real-validation-c8-derived/Build/Products/Debug-iphonesimulator/GameTime.app`.

Only one owner may drive this Simulator, preview or native test controller at a
time. Firstmate confirmed b7 idle before c8 reuse. Inspect controller ownership
and ports before relaunch; do not stop another process or reset the database.
The retained owned stack is `/tmp/gametime-finish-b7-stack`, API 58321 / DB 58322;
controller 58339. The original 5432x database is never a target.

```sh
cd /Users/user/.treehouse/gametime-beta-7b9cca/2/gametime-beta
lsof -nP -iTCP:58339 -sTCP:LISTEN
scripts/beta-preview.py --owned-project gametime-finish-b7 serve \
  --app /tmp/gametime-real-validation-c8-derived/Build/Products/Debug-iphonesimulator/GameTime.app
```

Keep the preview command in its foreground terminal. It creates seven fictional
accounts and privately fills local sign-in. Tap **Sign in**. No consent is
submitted automatically. The private mode-0600 manifest retains the explicit
c8 app path, so account switching uses the same build. Do not copy its credentials
into notes or commits. Only startup errors or selected nonsecret status fields
may be printed from Supabase logs; startup output includes local keys.

From a second terminal in the same c8 checkout:

```sh
scripts/beta-preview.py --owned-project gametime-finish-b7 accounts
scripts/beta-preview.py --owned-project gametime-finish-b7 open --actor 2
```

`accounts` prints fictional usernames/IDs. Tap Sign in after switching. Account 1
has fictional friendships with accounts 2–6; account 7 is the independent local
operator/nonfriend invitation actor. **Ctrl-C** shuts down only this preview's
gates and sessions and retains records. It leaves the owned Supabase stack running.
Do not launch from the preserved b7 checkout or let its default path reinstall b7.

If the build must be recreated, serialize the native owner first:

```sh
xcodebuild build -project ios/GameTime/GameTime.xcodeproj \
  -scheme GameTimeBetaLocal -configuration Debug \
  -destination 'platform=iOS Simulator,id=72A3249A-2DE0-4695-AF41-DCD2743B4666' \
  -derivedDataPath /tmp/gametime-real-validation-c8-derived CODE_SIGNING_ALLOWED=NO
```

The already-running retained stack requires no startup/reset. If it is stopped,
Firstmate must recheck idle ownership and 5832x ports before starting only that
project. Do not print key-bearing `supabase status` or startup logs. No signing
identity or shared Xcode service change is necessary for Simulator builds.

## Three short journeys

1. **Friend goal:** Challenges → confirm age → Create a challenge → Friend goal.
   Pick one of the four activities. After creating the lobby, each person proposes
   their own goal. Invite account 2 using its exact username. Switch to account 2,
   confirm age and propose a goal; switch back, select its roster membership,
   and lock in the roster/goals. Both accounts must separately review and agree.
   Reopening or changing terms requires everyone to agree again.
2. **Friend leaderboard:** Choose **With friends → Leaderboard** in creation.
   Pick steps, Exercise Time, running distance or timed running. There is no goal
   target. Freeze the selected roster and separately consent. Equal normalized
   results are co-winners; missing results cannot silently lose.
3. **Personal goal:** Choose Personal goal, activity and target, then review the
   private agreement and explicitly agree. It has no opponent or leaderboard.
   Home shows its state; details provide safe exit and later review/history.

For fictional progress, downward correction, delayed review, final simulation,
response loss and exact recovery, follow [the executed b7 walkthrough](BETA_LOCAL_PREVIEW.md).
Run its commands from **this c8 checkout**. All those historical outcomes are
inherited evidence until explicitly rerun and recorded in the continuation ledger.

## Remaining integration preparation

Existing tasks remain authoritative: **gametime-beta-source-acceptance-b7**
(`physical-source-actions`) and **gametime-beta-release-readiness-b7**
(`beta-release-identities-retention`). There are no duplicate decisions. The
following are concrete inputs and executable follow-ups, not new authorization.

| Area | Prepared local behavior / next command | Exact missing input and subsequent work |
| --- | --- | --- |
| Sign-in and invitations | Native HTTP command in the acceptance ledger proves authentication, session revocation, age gating, link recovery/reconsent and all thirteen fictional policies. Preview `open --actor 2` proves c8 account switching. | D134 already selects **Sign in with Apple**. Missing inputs are the exact approved environment/host/team/bundle/configuration. Prepare that adopted Apple sign-in and wire its reviewed authenticated client; the new client currently refuses hosted URLs. Repeat two/six-account session isolation and interrupted link-before/after-sign-in checks there after authorization. |
| Universal links | Review `docs/release/beta/apple-app-site-association.json.template`; its placeholders remain intentional. Current Debug custom-scheme invitations carry only an opaque token, no pre-auth social details. | Exact approved HTTPS host, Apple team and release bundle IDs. Then fill association/entitlement paths and verify expired/revoked/full/malformed links and unique redemption; publishing is separately authorized. |
| Support and reviews | Use the explicit owned-project administrator/human credentials and commands in [the local operator guide](BETA_OPERATIONS_LOCAL.md). Scoped review/moderation, separate support/appeals and exact human recovery are locally implemented; see [the operator report](../outputs/reports/2026-09-14-p11a-operator.md). | Accountable legal/support identity, monitored route, named operators and coverage. Wire approved support text/URLs and prove delivery only after permission to send a real test message. Local reports are not a monitored support service. |
| Retention and account deletion | Read `docs/BETA_PRIVACY_TERMS_DRAFT.md` against current stored facts/agreements/reviews/operator audit. c8 tests preserve historical bytes and departed own receipts while ending current counterpart activity. | Retention duration and deletion/deidentification treatment for each record class, retained legal/audit purpose and access. Then implement a forward new-domain workflow and owner controls; test stale sessions, recovery files and historical audit together. Never invoke the legacy destructive deletion path as a substitute or delete the original database. |
| Community settings | `scripts/beta-operator.py publish-fixture --help` describes the existing strictly fictional local command; accepted settings are not inferred from fixture values. | Cohort, common steps target, minimum/capacity, duration/timezone/amount and operator coverage. Review those terms and explicit source rules before real discovery/publication; no real community is enabled. |
| Hosted configuration | `python3 -m json.tool docs/release/beta/readiness.json` inspects the 18 closed acceptance gates. Portable verification above rebuilds only a fresh local stack. | Exact separate project identity, approved candidate, host, credentials and source/attestation policy; then add minimum-data real ingestion and HTTPS client configuration, scoped scheduler/alerts and replay/recovery drills. Local fixture actors/clocks must remain unavailable in hosted code. No hosted configuration or deployment command was executed. |

Apple sign-in reuse points are `AppleSignIn.swift` (nonce and system button),
`AppClients.swift` (`AuthClient`) and `SupabaseClients.swift` (ID-token exchange).
The new local password form is a fictional preview control. After approved
configuration, connect the selected Apple flow to the new shell without widening
the current loopback-only transport or interpreting fixture login as Apple proof.
Test cancellation, failed exchange, account change and invitation preservation;
actual Apple authentication on the approved identity remains unperformed here.

[Rollout preparation](BETA_ROLLOUT_PREPARATION.md) retains the dependency order and
human comprehension script. The unsigned historical Release still selects the
legacy default app; local new-shell acceptance is not production replacement.
No test result opens any readiness gate.

## Remaining physical action and source implementation slice

Firstmate must deliver: **“I opt in to a private on-device investigation on [exact
selected iPhone], paired with [selected Watch].”** No device has yet been selected
or opted in. Then follow [Session A](BETA_PHYSICAL_SESSIONS.md) for steps, followed
early by Exercise/cumulative/timed running in Session B. The document provides
short categorical replies and later edit/delete/sync/permission/boundary sessions.
No private physical screen capture, automation, logs, upload or screenshot is allowed.
Supporting accuracy measurements remain on-device; timed tolerance is unselected.
Empty reads never prove a missed goal.

Hardware-independent work may proceed when separately authorized. After each
source policy is accepted, implement its versioned real-source terms,
adapter, seven-state readiness, applicable on-device suggestions, and minimum-data
attested ingestion with source binding, replay protection, downward corrections
and recovery. Prove progress → correction → review → final simulated history.
Preserve fictional source agreements. All four accepted sources are required before
distribution unless the owner changes scope. Human comprehension and physical
assistive control remain separate actual-person checks.
