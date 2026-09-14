# P11A community verification and local handoff — September 14, 2026

The community verification gap is closed. Recommend **separate approval for
local landing** of the reviewed branch. It is **NOT LANDED**: main is unchanged;
no merge, push, hosted operation or distribution occurred. This follow-up changes
one SQL test and current-status documentation. P11A implementation is preserved.

## Exact candidate

- Worktree: `/Users/user/.treehouse/GameTime-54367f/3/GameTime`
- Branch: `fm/gametime-p11a-local-recovery-20260913`
- Main/base, still unchanged: `885e8ad3286b14b98650299659a658fdb68db94b`
- Preserved S2 ancestor: `ddc4d805d0793613059d4fe3cf4df23a573c6ac6`
- Preserved P8 ancestor: `8674e071e1811fba1f57ba0d275e55310388f52a`
- Pre-P11A combined candidate: `07fd61b693d3f7545beba3cd31f8ffaba431cf9a`
- Continuation intake/report: `02f97cd3a7dfcd28f1f46cf947b6a460f61e4e16`
- Reviewed final code/test commit: `fc92c7e7d754bfcc4433801aeedabb6baea965ab`
- The separate documentation/result commit containing this report is recorded
  by full ID in the private follow-up index and final delivery message.

The [original P11A report](2026-09-14-p11a-local-recovery.md),
[S2 report](2026-09-13-signal-simulator-integration.md) and
[P8 report](2026-09-13-p8-concurrency.md) retain their original results and limits.
No consolidation was repeated. S2 already adapts the applicable overnight fixes.
All four intake ancestors above remain ancestors of the reviewed tip.

The unchanged implementation supplies durable scoped worker/snapshot invocation
identities, bounded transport/work retries, existing claim/complete processing,
audited individual failed-item recovery and sanitized local status. It leaves
real credentials, hosted schedules and external alerts disabled. This task does
not add operator tooling or retention/deletion behavior.

## Failure investigation and necessary correction

**Populated 48/49:** the trigger was two retained reports outside the transaction's
fixtures. `challenge_support_reports_v1` legitimately returns an audited global
page across report scopes. The test added two more reports, then incorrectly
expected the entire page to contain two. An empty database masked that assumption.
The symptom was assertion 32, actual four versus expected two; it was not evidence
of moderator access to global reports or another authorization bypass.

The unchanged original test passed **49/49** on the fully initialized fresh
candidate. Adding only two unrelated reports reproduced **48/49**, with precisely
assertion 32 failing. A second reproduction with two separately committed reports
from distinct fictional actors produced the same four-versus-two failure.

The correction in [test 506](../../supabase/tests/506_challenge_private_community.test.sql)
creates unrelated scoped/unscoped reports through authorized operations and
compares exact fixture report IDs, subjects, reasons and scopes. It does not
delete retained reports, reduce authorization requirements or substitute an
expected total of four. Dropping scoped reports from the actual support function
still fails the corrected assertion. Moderator, revoked-support and revoked-
moderator denials remain executable and unchanged.

**Prior clean reconstruction failures:** both retained `clean-final-source`
receipts fail assertion 1 (service-only capture) and assertion 2 (private raw
helper) before stopping on unresolved pgTAP `is(...)`. Those are real failed
assertions, not merely the later setup exception. The retained schema dump has
no object ACL restoration entries; the schema-apply receipt contains no grant/
revoke restoration. The actual P6 migration explicitly revokes PUBLIC, anon,
authenticated and service-role execution before assigning the intended grants.
Restoring definitions without ACLs reinstates PostgreSQL's PUBLIC function-execute
default. A schema-only reconstruction also omits seeded private/runtime data.

One-condition controls on the correctly initialized candidate independently
restored PUBLIC execution on capture and on the raw helper. Each reproduced its
corresponding original privilege failure. These assertions are correct and were
preserved. Restoring PUBLIC execution on capture still hits the in-function
service-role guard when called as a participant; it does not authorize capture.
Raw-helper invocation also requires schema and underlying-table permissions.
An effective function privilege alone is not proof of successful data access.

Separately revoking authenticated/PUBLIC usage of the extensions schema reproduced
the unqualified pgTAP function-resolution error. Changing `search_path` cannot
replace missing schema usage. This explains a masking condition in the old
attempts: the later pgTAP error stopped the suite before full role behavior could
be established. The earlier cron error named a non-`postgres` database while
`cron.database_name` targeted `postgres`; subsequent guessed baseline inserts
did not make that reconstruction equivalent to the migration chain. No old
database was reopened to infer unrecorded outcomes, and no old failure was
reclassified as a pass. No runtime SQL defect was demonstrated by this gap.

## Fresh initialization and actual verification

New private evidence directory:
`/Users/user/firstmate-workspace/data/gametime-p11a-local-recovery-20260913/followup-20260914T1510Z`.
Its `report.md` contains exact commands, hashes, receipts and the result commit.

The new database used cached `public.ecr.aws/supabase/postgres:17.6.1.143`
(PostgreSQL 17.6), its bundled `docker-entrypoint.sh` and `migrate.sh` bootstrap,
and cached GoTrue `v2.192.0`'s official `auth migrate` command (77 Auth migration
records). All **78 candidate migration files** then applied in order, each through
`psql -X -v ON_ERROR_STOP=1 -1 -f`, with per-file SHA-256/exit receipts. No schema
dump or invented baseline was used for initialization. pgTAP/dblink were installed
using the existing `scripts/db-test.sh` test-extension statements, without running
that script's reset or targeting its default project.

| Check | Actual result |
| --- | --- |
| Unmodified 506 at intake source, fresh complete chain | **49/49**, no failures/skips; `506-original-clean.log` |
| Final `fc92c7e`, clean 506 | **67/67**, no failures/skips; `506-final-clean.log` |
| Final `fc92c7e`, affected community guards 507 | **18/18**, no failures/skips; `507-final-clean.log` |
| Final `fc92c7e`, affected community progress 508 | **9/9**, no failures/skips; `508-final-clean.log` |
| Final 506 with two independently committed prior reports | **67/67**; counts and ordered-content digests of all **41 challenge relations** identical before/after the rollback-only suite |
| Final test, PUBLIC capture-execute counterfactual | **62 passed / 5 failed** as required; original denial, PUBLIC inheritance and actual-role assertions detect the mutation |
| Final test, PUBLIC raw-helper-execute counterfactual | **62 passed / 5 failed** as required, including service-role raw-helper denial |
| Final test, support guard removed | **65 passed / 2 failed**: moderator and revoked-support reads become wrongly available |
| Final test, scoped reports omitted | **66 passed / 1 failed**: exact report projection detects the missing rows |
| CLI migration and one explicit-local security advisor attempt | Both exit 1, `LegacyDbConnectError / PgClient: Failed to connect`; advisors remain unavailable, not passed |

Every accepted TAP receipt was checked for a contiguous assertion sequence, matching
plan, exit zero and no failure/skip/TODO. A zero psql exit alone does not establish
a passing TAP run. Counterfactual mutations were transaction-local and rolled back.
An intermediate test edit had a missing psql-variable quote and stopped after
seven assertions; that failed receipt is retained separately from the corrected
63-assertion intermediate run and final 67-assertion runs.

Actual `SET LOCAL ROLE anon`, `authenticated` and `service_role` calls prove
capture/helper/table denials, snapshot prepare/dispatch denials and legitimate
service capture/prepare/dispatch. Fictional participants have current SQL session
claims. These are PostgreSQL permission tests, not HTTP JWT-signature checks.
The delayed disclosure checks still pass at 899/900/901 seconds, suppress counts
below five after exits/suspension, preserve current own progress, hide strangers'
activity, retain safe exits during pause and enforce grant expiry/revocation.

There was no runtime/native change requiring another P8 race run, populated
migration-upgrade matrix, worker matrix or native matrix. Their previous results
remain in the original report; they were deliberately not repeated or relabeled
as fresh follow-up evidence. This is not a release audit or capacity test.

## Focused final-candidate review

One self-review covered the installed/source community capture/count paths,
snapshot wrappers, effective grants and PUBLIC inheritance, session/support
checks, fixed definer search paths, private tables/RLS, the corrected test and
actual successful/failing receipts. Dispositions:

- Report-cardinality defect: fixed in the test, reproduced before and verified
  with unrelated and committed retained reports. No product behavior changed.
- Old capture/helper ACL failures: valid assertions against an invalid
  reconstruction; actual migration-chain permissions and role calls pass.
- The reviewed 12 community/report/worker private tables have RLS and no direct
  anon/authenticated/service-role table privileges. Sensitive community and
  invocation functions have the expected restricted execution and fixed paths.
  `app` schema usage remains deliberately available to authenticated/service
  roles for internal predicates; it is not an exposed API schema or a grant to
  execute every helper.
- Two existing P11A non-definer helpers retain PUBLIC execute:
  `challenge_worker_principal_v1` returns only the caller's role and
  `challenge_worker_state_guard_v1` is a trigger function. Actual authenticated
  calls returned `authenticated` and rejected direct trigger invocation. Neither
  supplies service authority or protected rows. Recorded as nonblocking privilege
  cleanup for a later scoped pass; no blanket “all helpers deny execute” claim.
- All migration, application, script and readiness bytes are unchanged from
  `02f97cd`. Signal, historical Personal consent/agreements, missing-data rules,
  deadlines, revocation and exact recovery are preserved. No landing-blocking
  defect remains in this focused verification scope.

The Supabase security checklist and current [API grant guidance](https://supabase.com/docs/guides/api/securing-your-api)
were reviewed. [API exposure changes](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically)
do not replace role/RLS checks. [Extension-version changes](https://supabase.com/changelog/extension-version-pinning-ignored)
were noted without changing historical extensions; the
[self-hosted gateway change](https://supabase.com/changelog/48048-self-hosted-supabase-envoy-becomes-the-default-api-gateway-b)
is outside this DB-only setup. No gateway service was started. Service-role
availability is not least-privilege hosted acceptance.

## Owned resources, preservation and stop

New resource prefix: `gametime-p11a-community-20260914-1510`; DB container `-db`,
volume `-data`, explicit publish **`127.0.0.1:64392:5432` from first start**.
The first owned internal network (`10.253.249.0/24`) also refused loopback.
Before fixtures, only the owned DB was stopped and attached to a second newly
owned network (`-loopback-network`, `10.253.248.0/24`). Its explicit publish
remained intact. Docker HostConfig/actual bindings, `lsof` and rediscovered LAN
IPv4/global/link-local IPv6 refusal all agreed before fixture admission.
IPv6 loopback also refused. Initial tunnel probes timed out; they are retained
and are not described as positive refusal observations. No broad-bound service
was started, and no global Docker/firewall setting was changed.

Cleanup closed all fictional runtime gates, expired the two retained fictional
sessions, disabled the five bootstrap/migration cron registrations through
`cron.alter_job`, and confirmed **zero executed jobs**. `cron.launch_active_jobs`
was off from first start. Only the new DB was stopped; finite Auth migration/help
containers are exited or never started. Volumes, networks, logs and an ACL-inclusive
final dump are retained. The owned port has no listener and refuses loopback.

All 171 prior container identities, bindings, mount sets and networks match
intake. A raw comparison detected only Studio mount-list order and the start/
finish timestamps of the already-restarting original storage container; both
observations are retained, and neither was acted on. All 47 prior networks,
57 prior volumes, Simulator states and primary/S2/P8 source inventories match.
The 11 selected prior failure/index receipts retain their intake hashes.
No prior P11A, S2, P8, overnight, preview or Simulator resource was used or mutated.

## Delivery boundary and next dependency

Firstmate should present the exact report/result tip for separate local landing
approval, then use its guarded fast-forward path only if approved. The concrete
operation is `git -C /Users/user/Documents/GitHub/GameTime merge --ff-only <approved-result-SHA>`
after confirming clean `main` still names the base above. This operation was
**not executed**. No additional owner decision was opened or resolved here.

All 18 readiness entries remain false. Existing S2/P8 landing calls and
`gametime-beta-source-acceptance-b7` / `gametime-beta-release-readiness-b7` remain
unresolved. Beyond local landing, the next dependencies are accepted real-source
P8/P9 contracts and separately approved hosted identity/settings/actions.
Operator-tooling expansion and policy-dependent deletion require later scoped
work. No device/Health access, release, deployment or distribution was performed.
This verification/handoff slice is complete and stops here.
