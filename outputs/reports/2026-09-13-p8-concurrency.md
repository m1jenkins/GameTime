# P8 concurrency — September 13, 2026

Privacy1 and S1 are reproduced and corrected locally. Successful authorized
reads, create-first completion, exact retries and historical access remain
functional. This finishes only these two concerns; it does not accept real
ingestion, a source, a candidate or release readiness.

## Source and scope

- Branch: `fm/gametime-p8-concurrency-20260913`, worktree
  `/Users/user/.treehouse/GameTime-54367f/2/GameTime`.
- Verified clean primary/main and isolated intake:
  `885e8ad3286b14b98650299659a658fdb68db94b`.
- Fix and regression/upgrade fixtures:
  `e3d7e6e53aaed1c49a80ee4200170c0b1b8e6f00`.
- Final code/tests, strengthening recorded revoke **commit** order:
  `d1fc9c71c19bdd43f5cf80000ff330058703ecad`.
- The separate report/result commit is the commit containing this report; its
  exact ID is recorded after commit in the private `report.md` and final handoff.

S2 remains clean at `ddc4d805d0793613059d4fe3cf4df23a573c6ac6`, with final code
`08850da5ec2e1f115d2af25a3d5bc36b43075c95` and app/controller code
`401b8b241d2ba33e4725ad0e62023b282f964c69`. Its entire `b351a47..ddc4d80`
Supabase diff is empty. No S2 changes were imported. The older overnight branch
remains `264bbd00bccc4f924b36c9e2146c7350bdf406d6`, preserving code
`a3e77333a2c788d67243b51b84bce8bf82a89461`.

The only production change is the 32-line forward migration
[20260914031018](../../supabase/migrations/20260914031018_challenge_reviewer_and_create_serialization_v1.sql),
named by `supabase migration new` (September 14 UTC, September 13 locally).
It changes two installed function bodies. No original migration, app/UI,
agreement, consent, source policy, permission grant, readiness input or historical
data definition changes. No merge, push, hosted operation, deployment,
distribution, simulator or physical-device action occurred.

## Authorization boundaries and findings

**Privacy1 — demonstrated missing P6 synchronization, not an ungranted-reader
bypass.** [Private community contract](../../docs/PRIVATE_COMMUNITY_V1.md),
lines 71–76, requires grant reads to synchronize with revocation and denies
expiry equality. The implemented comparison is
`20260912013929_challenge_private_community_v1.sql:235–256`:
`challenge_operator_reports_v1` takes the exact moderator grant `FOR SHARE`;
service-only `challenge_revoke_operator_v1` updates that row. P6 lines 396–398
attempt the same lock for reviewer cases, but its replacement needle omits an
already-present actor-unavailable prefix and matches nothing. P6 originated at
`05f405c24453fe6743ece994d646058958bfdbb2`; the installed baseline confirms
the missed replacement.

The affected guard and normalized context are in
`20260908071000_challenge_review_context_v1.sql:3–22`, public
`challenge_operator_cases_v1(uuid)`. An independent, granted, active reviewer
was initially authorized in every successful baseline case. Sequential committed
revocation already denied access, masking the missing synchronization.

A read seeing an old committed grant while revocation is uncommitted can
legitimately linearize first under ordinary snapshot authorization. Finishing
later is **not alone a privacy violation**, including the context-barrier case
below. The demonstrated defect is narrower: it fails the explicitly adopted
P6 transaction synchronization, unlike the moderator path and the attempted
reviewer patch. Revocation could finish and commit while the previously
authorized reader still awaited its case-data query. This does not prove that
an actor revoked before its authorization began could obtain a case; that
negative control passed. The fix restores the existing common boundary rather
than inventing an immediate recall rule for already-disclosed data.

The new exact `(actor, challenge, review)` grant SHARE lock protects the guard
and ensuing context read through transaction completion. A revoker holding that
row first finishes before the reader rechecks current grant/expiry and denies.
A reader acquiring it first can complete successfully while revocation waits.
No challenge-wide or global production read lock is added.

**S1 — demonstrated new-draft admission escaping suspension.** The same
contract, lines 78–82, requires suspension to coordinate with admissions,
perform synchronous safe exits and retry a newly discovered membership union.
[Beta plan](../../docs/BETA_IMPLEMENTATION_PLAN.md):157–159 preserves participant
serialization and exact recovery; its identity/safety requirements and D134
require audited suspension. The current admission guard in
`20260908050901_challenge_access_links_safety_v1.sql:32–38` denies suspended
actors. It is already used by friend `create`, so this correction does not
redefine whether drafting is allowed during suspension.

`20260908050105_challenge_policy_matrix_v1.sql:143–152` checks admission before
inserting the lobby and selected creator membership. P6 copies this into
`app.challenge_mutate_unmetered_v1`, reached through public
`challenge_command_v1 → challenge_mutate_v1`. Its creator foreign key later
takes profile KEY SHARE, checking existence rather than suspension. Support
suspension, `20260912013929:293–321`, locks the challenge/profile membership union.
P4's `20260911224043:1–31,65–81` defines profile coordination and already rechecks
session/admission after personal/join waits.

When support held the profile first, friend creation saw the old nonsuspended
state and waited at the foreign key. After support committed, creation also
committed: `suspended=true`, **one lobby, one selected unexited membership, one
saved create request, one worker claim**. Processing was paused; a later worker
could otherwise mask the escaped draft. No funded agreement or consent bypass
is claimed. The minimal fix takes the creator profile UPDATE lock before the
admission check, rechecks session/admission and refreshes the clock after waiting.
It follows the existing lock order and leaves saved-request recovery ahead of
this branch. A fresh denied request now leaves all four effect counts at zero.

Create-first completion is legitimate: suspension waits, discovers the new
membership, returns `40001/challenge_retry_safety`, and a fresh suspension retry
synchronously cancels the draft. The original create receipt remains recoverable
exactly; the suspended owner can still read the cancelled draft. Those controls
passed before and after the fix.

## Actual-session proof

[The focused reproducer](../../scripts/beta-p8-concurrency.py) adapts P4's psql
session/barrier approach. All cases use distinct actual PostgreSQL connections,
explicit `BEGIN ISOLATION LEVEL READ COMMITTED`, server PIDs, psql completion
barriers, `pg_stat_activity` and `pg_blocking_pids`. An idle observation must
match the pending RPC, preventing an earlier idle barrier from masquerading as
completion. Statements have a 15-second bound; waits are observed, not inferred
from sleeps.

Application connections log in as `authenticator`, then use `SET LOCAL ROLE
authenticated` with fictional actor/live-session claims. Grant/revoke connections
use `service_role`; the suspender is an independently granted authenticated
support actor. Owner connections only seed fixtures, control the fictional clock,
observe state or establish the documented table barrier. Reviewer direct-table
access is denied. These are real SQL/RPC permission tests, not HTTP JWT-signature
or native transport tests.

The only timing instrumentation is an owner-held ACCESS EXCLUSIVE lock on
`app.challenge_reviews_v1`, making the unchanged RPC wait at its final context
SELECT after its guard/audit. It changes scheduling only, adds no server hook and
does not replace a guard. Uninstrumented reads and both primary orderings also
run. Holding a transaction after its RPC models transaction completion ordering,
not additional application operations.

Representative baseline-03 and final-04 receipts below use database-local PIDs.
The private JSON retains every begin/barrier/commit order, payload/error and
observed blocker; numbers from separate databases are not global identifiers.

| Interleaving | Actual baseline | Actual corrected result |
| --- | --- | --- |
| Revoke updates grant first, reader starts before revoke commit | Service 526; reviewer 527 completes with fact `200`, no blocker | Service 1690 blocks reviewer 1691; commit → `42501/challenge_operator_required`, no payload |
| Reviewer finishes authorized RPC first, holds transaction, revoke starts | Reviewer 534; revoker 535 completes and commits before reader commit | Reviewer 1698 blocks revoker 1699 until reader commits; authorized data still returns |
| Reviewer authorized, case SELECT held, revoke starts | Barrier 538 blocks reader 539; revoker 541 **commits at event 173**, barrier releases 175, reader returns fact `200` then commits 178 | Barrier 1702 blocks reader 1703; revoker 1705 waits on reader. Barrier release 170, reader commit 173, revoke commit 176 |
| Existing moderator comparison, revocation first | Waits then denies correctly | Same successful wait/deny |
| Support suspension first, friend create waits | Support 544 blocks creator 545; suspension commits, then draft/member/request/claim each become 1 | Support 1708 blocks creator 1709; commit → `42501/challenge_admission_paused`; all four counts 0 |
| Friend create first, support starts before create commit | Creator 557 blocks support 558; support returns `40001`, fresh retry closes draft | Creator 1725 blocks support 1727; same retry/closure; exact create recovery and own access pass |
| Existing personal admission comparison | Profile wait then suspension denial | Same successful wait/deny |

Additional controls: normalized authorized case content; moderator-only review
denial; private-table denial; committed-revocation denial; nonoverlapping
suspended/eligible creation; unrelated eligible creation while another profile
is held; and exact retries after suspension. Existing SQL suites add absent,
expired/equality, independent-role, session, consent, missing-data and safe-exit
checks. No separate reviewer-suspension race or general backend audit is claimed.

## Verification and retained failures

| Lane | Actual result |
| --- | --- |
| Baseline races 01/02 on untouched installed baseline | Each **21 passed / 6 failed / 0 skipped**, no harness error. Failed assertions represent four Privacy1 and two S1 expectations, not six separate defects. |
| Baseline 03 with final committed reproducer | Same **21/6/0**; additionally proves actual revoke commit overtaking the held data read. |
| Final `d1fc9c7`, race runs 04–06 | **27/27 per run**, zero failures/skips/errors. Three repetitions, 27 unique checks; no deadlocks. Earlier e3d7e6e runs 01–03 also passed 27 each. |
| Final `d1fc9c7`, SQL/RLS | **626 assertions / 22 files**, zero failures/skips, all plans matched and commands exited 0. Exact files: 490–508 (498 assertions) plus 440, 450, 480 (128 historical assertions). |
| Populated baseline → forward migration, final `d1fc9c7` | **210 assertions passed**, zero failures/skips. All **199 app/public tables** retain identical ordered row-content digests immediately across migration. Includes two-/five-person historical weekly agreements, seven consents, Personal terms, new-domain agreements/facts/reviews/requests/grants/audit. |
| Upgrade access/privileges | Old exact create retry with admission off; own historical Personal RLS/weekly access; participant review access; retained grant reads original fact `20000`; function ACLs, definer status and search paths unchanged. Included in the 210. |
| Fresh application | All **77 migrations** apply, exit 0, to the independently initialized second backend. No reset or reused prior-task DB. Final installed bodies on both databases exactly equal the two intended baseline replacements. |
| Resource/format checks | Both owned databases report zero deadlocks; unrelated-creator control passes. `git diff --check` passes. 2,362 primary and 2,328 S2 tracked-file hashes and clean identities match intake. All 165 original container identities/states, 52 original volumes and 45 original networks remain. |

Baseline definitions and the populated baseline dump are retained. For baseline
03, the second owned database reinstated **only the two exact captured original
function definitions**; these are precisely the production objects this migration
changes. This reconstructed the verified baseline without deleting rows or
inventing weaker guards. The same forward migration restored final definitions.
The final populated-upgrade pass repeated this reconstruction, seeded the reused
historical fixtures, snapshotted every app/public table and applied the committed
migration. [Before](p8-20260913/upgrade-before.sql) and
[after](p8-20260913/upgrade-after.sql) inputs are committed. Fresh application,
baseline reconstruction and populated upgrade are separate evidence lanes.

Retained setup failures: CLI `migration up --db-url` and explicitly scoped
`db advisors --db-url` both failed with `LegacyDbConnectError / PgClient: Failed
to connect`, while psql worked. No CLI repair, installation, cloud login or
default linked target was attempted. **Advisor checks remain unperformed**;
the security checklist was reviewed against actual role/RLS tests and unchanged
ACLs. Direct UPDATE of cron metadata was denied twice; the installed owner
`cron.alter_job(..., active:=false)` API disabled only owned jobs. An initial
upgrade fixture requested a fictional clock with fixtures off and correctly
failed `challenge_invalid_runtime`; its entire transaction rolled back. The
corrected fixture and successful logs are separate. No failed artifact is erased
or counted as a pass.

One concise self-review checked unique migration markers, narrowly scoped locks,
profile/session ordering, unchanged successful payloads/projections, early exact
recovery, ACL/search-path retention and the distinction between synchronization
and previously legitimate reads. No additional reviewer, pipeline or broad audit
was run. The final test-only adjustment records a previously unobserved commit
ordering and does not change the migration.

## Commands, resources and handoff

Private root (0700):
`/Users/user/firstmate-workspace/data/gametime-p8-concurrency-20260913`.
Its `report.md` indexes complete sanitized session events, original failures,
migration logs/hashes, dumps, source inventories, SQL results and final receipts.
Credentials are absent from project commits and status messages.

Each race invocation uses `python3 scripts/beta-p8-concurrency.py` with explicit
`--db-url`, `--auth-db-url`, `--owned-root`, `--owned-project`, and a new
`--output` path. SQL lanes use `psql -XqAt -v ON_ERROR_STOP=1 -f <exact file>`;
the runner also verifies pgTAP plans and rejects `not ok` or skips. Migrations
use bounded psql application and per-file source-hash receipts after CLI failure.
No `db reset` or full release/weekly gate was run.

Supabase CLI 2.109.1 and its installed help were inspected. Both task-owned DB-only
backends use installed PostgreSQL 17.6 image `17.6.1.143`, custom network
`gametime-p8-concurrency-20260913-network`, subnet `10.253.220.0/24`:

- `gametime-p8-concurrency-20260913`: DB port 61322, config under `stack`.
- `gametime-p8-fresh-20260913`: DB port 62322, config under `fresh-stack`.

All calls target `127.0.0.1`. Docker actually published DB ports on `0.0.0.0` and
`::`; the task-network loopback binding option did not override the CLI's publish
configuration. This is **not loopback-only host exposure**. Both owned containers
are stopped, ports no longer listen, and their volumes/network/dumps/evidence
are retained. Fictional sessions are expired, admission/fixture/processing/
discovery gates are off, and owned historical cron jobs are inactive. Cleanup
occurs after preservation comparisons; it is not a claim those runtime/session
rows remain identical after cleanup. S2 ports 6032x/subnet 219, retained subnet
218 and all other resources were untouched.

Current [Supabase changelog](https://supabase.com/changelog.md),
[RLS](https://supabase.com/docs/guides/database/postgres/row-level-security) and
[CLI configuration](https://supabase.com/docs/guides/local-development/cli/config)
guidance were checked; relevant extension deprecation was reviewed without
changing historical extensions. Current
PostgreSQL pages resolve to 18, so the implementation was checked against actual
[PostgreSQL 17 isolation](https://www.postgresql.org/docs/17/transaction-iso.html)
and [locking](https://www.postgresql.org/docs/17/explicit-locking.html) guidance.
READ COMMITTED locking reads wait for conflicting writers; separate subsequent
checks see committed changes. [PostgREST transaction guidance](https://docs.postgrest.org/en/stable/references/transactions.html)
describes READ COMMITTED as its default; no role/function isolation override was
found in repository migrations. No HTTP timing guarantee is inferred here.

Existing unresolved dependencies stay under their existing keys:
`gametime-beta-source-acceptance-b7` and
`gametime-beta-release-readiness-b7`. Firstmate already recorded them with
bookkeeping-only permission. Neither was duplicated, changed, closed or approved.
No automatic safety rejection occurred in this task. All 18 readiness entries
remain false. P7 sources, timed-distance tolerance, real ingestion/transport,
hosting, operating/human acceptance and release remain unresolved.

Firstmate can review this independent local branch and S2 through its existing
landing process. The next useful independent implementation task is a separately
scoped P11A local worker/scheduler recovery slice using the existing durable
claims, with hosting and release gates still closed. That work was not started.

An iPhone 17 would help a later **phone-only Signal rendering, human VoiceOver,
Dynamic Type and foreground/background check** on an explicitly selected signed
candidate. It would not improve these DB proofs or establish P7's paired-Watch
source acceptance. Minimum later setup: connect/unlock/trust the phone, pair it
in Xcode, enable Settings → Privacy & Security → Developer Mode and confirm after
restart; select it as the run destination with compatible Xcode platform support.
Use the existing development team/provisioning for the Debug bundle
`com.mjenkins.gametime.staging` (iOS minimum 18.0), matching its Apple sign-in,
HealthKit and App Attest entitlements. No signing/account change was made here.
[Apple device/signing guidance](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices),
[Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).

The future phone check needs a deliberately selected fictional/mounted test route
and separate device-test authorization. Ordinary challenges still use
`UnavailableChallengeV1Client` (`AppModel.swift:114`); the Debug local session and
real challenge client accept only explicit loopback URLs
(`ChallengeV1Views.swift:17–23`, `ChallengeV1Client.swift:59–64`). A physical
phone's `127.0.0.1` is the phone, not the Mac. The existing authenticated Simulator
journey therefore does not work unchanged on a connected phone; a separately
authorized transport design is needed for that journey. No physical Health
investigation, permission prompt or data read is authorized by the phone offer.
