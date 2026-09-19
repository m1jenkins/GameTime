# P10 hosted operation preparation

Prepared September 12, 2026 UTC from working baseline `fd193e7`. This continues
**gametime-beta-release-readiness-b7** (`beta-release-identities-retention`),
using its existing handoff, rollout, privacy and operator material. It creates
no duplicate decision/task. The current source and performed checks are in the
[P10 handoff](../outputs/reports/2026-09-12-p10-completion.md).

Current September 19 status: [main consolidation](../outputs/reports/2026-09-19-main-consolidation.md)
includes configured HTTPS invitations, durable administrator recovery, repaired
suspended-account access and service-only review/appeal/snapshot monitoring.
Local weekly acceptance passed; the consolidation record lists CI status at
merge. P7 has partial private observations but no accepted source. The ordinary shared-session
connection is implemented; real facts, adapters, approved domain/Apple delivery
and hosted operating acceptance remain pending. All 18 [readiness entries](release/beta/readiness.json)
remain false. Nothing here provisions, deploys, changes credentials, registers a
scheduler, publishes, deletes records or sends a message.

September 14 current local status: the combined S2/P8/P11A recovery candidate
landed on local main at `a3d2c3f9cafb0c97191b90ce9794dfd36474b3aa`. The subsequent
[operator CLI slice](../outputs/reports/2026-09-14-p11a-operator.md) completes the
minimum local human interface and also landed on local main at `6fea1c2`.
Its [guide](BETA_OPERATIONS_LOCAL.md)
records role separation, exact human recovery and administrator-retry limits.
The P10 inventory and dated reports below retain their original scope; neither
local landing nor CLI verification accepts a hosted target or operating policy.

## Configuration and identities

The dated P10 source inventory is historical; current implementation is in the
[working baseline](WORKING_BASELINE.md). Proposed hosted requirements remain open.

[hosted-settings.draft.json](release/beta/hosted-settings.draft.json) is a review
worksheet, **not executable configuration**. Every unselected owner value is null.
Its proposed settings do not grant approval. Never substitute fixture values or
copy `supabase/config.toml` as a hosted deployment manifest.

| Area | Current implementation | Prepared hosted requirement / dependency |
| --- | --- | --- |
| Candidate and project | Signal/P4/P5/P6/P7 preparation and the isolated September 19 integration candidate; local Supabase 17 | Owner names immutable candidate, separate project/organization, region, budget and permitted actions. P8/P9 and source acceptance block source-backed operation. No existing project was inspected or selected. |
| Public native client | `PublicClient.xcconfig` names historical project `jrkzdttophnmkxjoyioo`; ordinary Signal supports the shared-session client when explicitly configured; the checked-in challenge flag remains off | Existing URL is not the selected new Beta target. Bind reviewed HTTPS origin and publishable key to exact build configuration. Preserve historical Personal access until replacement acceptance. |
| Apple identity | Project declares team `87Z29RTC26`, Release `com.mjenkins.gametime`, Debug/Staging `.staging` | These are observed source identities, not P10 owner approval. Confirm exact team/bundle and Apple native client ID allowlist. Do not reuse conformance/debug IDs as release audiences. |
| Sign-in | D134 already adopts Apple; `AppleSignIn.swift`, `AuthClient`, `SupabaseClients.swift` implement nonce/ID-token exchange | Keep native system sign-in and nonce verification; qualify the existing shared-session connection on the approved Apple/hosted identity in P9. Preview email/password actors are local fixtures. Email/SMS/anonymous signup and manual linking remain off. |
| Sessions | Refresh rotation; live `auth.sessions` actor/session/expiry checks at protected RPCs | JWT expiry 3,600s and refresh reuse 10s are proposed carryovers, not an approved hosted session policy. Continue checking current session/account after waits. User-editable metadata never grants support, Beta or source authority. |
| Auth redirects | Local `site_url`/redirects are loopback placeholders | Approve exact site/redirect URLs. Native ID-token sign-in is distinct from web OAuth; only if web OAuth is actually selected, configure Services ID and the exact project `/auth/v1/callback`, with an owner for its signing-secret renewal. Avoid wildcard redirects. |
| Invitation links | [Local HTTPS slice](BETA_INVITATION_LINKS_LOCAL.md): configured exact-origin parser/formatter and durable native intake; fixture links retained. Checked-in origin remains unconfigured. | Approve HTTPS host, exact application identifier, `/challenge-invite/<64-hex-token>`, [association template](release/beta/apple-app-site-association.json.template), entitlement and provisioned binary. No active associated-domain entitlement or published host exists. Actual OS delivery, Apple sign-in and hosted redemption remain unaccepted. |
| URLs/support | Three `UNCONFIGURED` public settings; preflight correctly blocks | Approved new-product privacy/terms and a staffed support route; do not publish the historical Personal policy as the new product policy. No support test message is authorized here. |
| API | Local exposed schemas `public`, `graphql_public`; `app` private | Proposed hosted schema allowlist is `public` only, with explicit grants. Confirm actual hosted Data API settings after authorization. Review historical public RPCs too; a prefix in the client is not an access boundary. Disable unused GraphQL, Realtime, Storage/vector and Edge deployments for the separate target after review. |

Native sign-in does not require a web OAuth secret solely to exchange an Apple
ID token. The exact selected flow determines the Apple setup; Supabase documents
native and web requirements separately. [Apple sign-in](https://supabase.com/docs/guides/auth/social-login/auth-apple)
and [session documentation](https://supabase.com/docs/guides/auth/sessions) were
checked September 12. No Apple portal or credential was changed.

For invitations, require explicit sign-in and 21+ confirmation before redemption;
opening never consents, creates friendship or chooses a roster. Successful redemption
grants Beta access and a pending request; revoking the link does not revoke access
already granted. The existing 20-unique-account/30-day bounds and earlier lobby
closure/start cutoff still apply. Keep tokens out of web access/referrer logs and
third-party page assets. Retain only the locator through interrupted authentication;
clear resolved account data on sign-out/change. Verify cold/warm launch, cancellation,
failed exchange, refresh, expired/revoked/full/malformed links, duplicate redemption
and two/six-account isolation on the approved identity later. Apple's
[associated-domain guidance](https://developer.apple.com/documentation/xcode/supporting-associated-domains)
is the publication reference; publication remains unauthorized.

## Runtime switches and non-executable boundaries

The readiness JSON is an acceptance register, not a switch controller.
`app.challenge_runtime_v1` is the current local control row:

| Switch / control | Actual baseline constraint | Hosted preparation |
| --- | --- | --- |
| `admission`, `processing`, `discovery`, `fixtures` | Default false; local mutators/work discovery depend on fixtures/allowlisted actors | Never turn `fixtures` on to make hosted admission or the scheduler work. Add reviewed versioned real admission/worker controls after the accepted P8 contract; keep safe own reads, reviews, exits and exact recovery independent. |
| `ingestion`, four `*_source`, `analytics` | Database `CHECK` constraints force false | Cannot be enabled by a settings edit. Source gates require P7/P8/P9 implementation and evidence; analytics remains off. |
| `actors`, `fictional_now` | Empty allowlist and no fictional clock in closed baseline | No fixture actor or clock in the hosted runtime; do not copy preview state or test seed. |
| Money, push, photos | No new-product money implementation; push/photos deferred | No Stripe/payment or `deliver-push` deployment for this product. Historical functions/configuration are not a new Beta allowlist. |

No control API is being widened by P10. Admission pause and processing pause are
different operations. Do not remove an actor allowlist or hide work in order to
make monitoring report zero. Future real controls must preserve historical
agreements and support recovery of saved requests while new admission is paused.

## RPC exposure and least privilege

The [read-only audit](release/beta/inspect-access.sql) checks effective grants
(including inheritance/PUBLIC), fixed empty search paths on public definers,
private helper/relation access, RLS and closed runtime values. Its
[executed inventory](../outputs/reports/p10-20260912/access-audit.json) enumerates
all 46 public challenge RPC signatures and the other public functions. Result:
**29 authenticated, 17 service-only, zero anonymous; 43 private helpers and 36
private relations; zero local-boundary violations.** This is the September 12 local
inventory, not proof of a least-privilege hosted worker or gateway.

| Principal | Permitted current interface | Additional boundary |
| --- | --- | --- |
| Anonymous | No challenge RPC, table or helper | No pre-auth roster/detail/lookup. Public mobile key alone grants nothing. |
| Participant, active session | Preview, age/access, detail/list/sections, commands, invitation/join, own report/review/exit/appeal | Own/selected membership, current account, terms, consent, block/suspension and quotas checked by RPC. Calling an operator RPC as `authenticated` alone does not confer a capability. |
| Challenge reviewer | `challenge_operator_cases_v1`, `challenge_operator_action_v1` with `resolve` | Explicit `review` grant for one challenge; independent nonmember; active session; bounded expiry. No raw Health proof, global reports or moderation authority implied. |
| Challenge moderator | `challenge_operator_reports_v1`, operator action `remove`, `challenge_operator_close_v1` | Explicit `moderate` grant for that challenge; nonmember. **Cannot globally suspend.** |
| Global support | `challenge_support_reports_v1`, `challenge_support_suspend_v1`, `challenge_support_appeals_v1`, `challenge_resolve_appeal_v1` | Separate support grant. Independent appeal decider must differ from appellant and suspender. Read/action audit; expiry and revocation. |
| Local service administrator | Grant/revoke operator/support; status; worker; fixture/publication/runtime RPCs | Broad local authority. Never place its key in the app, operator session, scheduler URL or logs. Not a least-privilege hosted worker credential. |

Before hosted deployment, separately implement/review the credential-to-RPC
boundary: a scheduler should reach only claim, completion and approved snapshot
operations; a monitor only sanitized status; a grant administrator owns grant
changes. Existing guards require `service_role`; simply creating a narrower SQL
role will not work without a reviewed compatible boundary. An Edge wrapper holding
a broad service key still carries that key's privilege and needs a strict fixed
allowlist and threat review. The authentication/issuance choice is an owner input,
not a credential created here. Retain actor-session checks for human operators.

Deny the hosted scheduler runtime/grant controls, fictional readiness/capture,
fixture publication/discovery, old `challenge_process_v1`/`challenge_resolve_v1`
shortcuts and new old-style batch runs. `challenge_run_batch_v1` only recovers
historical saved batches; use claim + complete for new work. Preserve old receipts.
All 17 service grants are shown, rather than labeling the current service key safe
for hosting. P8 must add real-source contracts without exposing raw source data or
client-authored completeness/finality.

Data API grants and RLS are separate checks; hosted defaults can differ. The
[Supabase API security reference](https://supabase.com/docs/guides/api/securing-your-api)
requires explicit exposure review. P10 did not change applied migrations or legacy
APIs. After any approved hosted application, rerun a reviewed catalog audit plus
actual HTTP role/session denials on that exact target. Never infer hosted ACLs from
this local report or a successful `psql` invocation.

## Scheduler and monitoring plan

Reuse `scripts/challenge_worker.py:run_once`: the local P11A path persists an
invocation scope and limit before dispatch, then each completion has its own
transaction and claim token. Proposed cadence is one pass per 60 seconds, limit
20, five completion lanes, five-second RPC timeout, no overlapping trigger
executions. These remain unapproved operating defaults; the existing server
allows 1–50 claims, 60-second leases, five attempts and exponential failure
backoff (`min(300, 2^attempts)` seconds). A failed/abandoned fifth attempt
becomes dead work. P11 must measure backlog/connection headroom on the chosen
host; P2's failures and long-soak history remain unchanged.

Persist the invocation UUID, exact scope digest and limit before dispatch. After
response loss, retry that exact invocation to recover the saved claims; retry
completion with its same token. An expired/replaced token is stale and must never
overwrite a later completion. A later fresh invocation reclaims abandoned leases,
not the old UUID. Durable receipts survive process restart, and one selected dead
item can be recovered only through the audited privileged recovery RPC. There is
no hosted runner, scheduler registration or credential here. These are explicit
integration deliverables before enabling a schedule; do not emulate them with
unreviewed direct updates or an automatic infinite loop.

Add a separately authorized snapshot job for the one selected cohort:
`challenge_capture_community_snapshot_v1(p_id)`, proposed every 900 seconds.
Server determines timestamp and count, captures at most once per 15 minutes,
and refuses without local fixture/discovery authorization today. Hosted capture
therefore needs a reviewed real-publication boundary too. Client reads cannot
capture or request fresher counts. First disclosure waits at least 900 seconds;
under five remains null regardless of scheduler success. Delay keeps counts
pending/older, never substitutes current counts. No active cohort ID is selected.

The fresh migration audit found four **active legacy jobs**: activation, quarantine
review deadlines, push dispatch and raw-evidence retention; Personal result
publication is inactive. There is no challenge job. Before an approved hosted
migration, review an environment-specific plan that prevents legacy jobs from
running during application (not just afterward), inventories and disables unwanted
registrations through supported Cron controls, and leaves new jobs disabled.
Do not edit historical migrations or run them blindly with hosted secrets/data.
No schedule, push provider or retention action was enabled by P10. The owned test
DB had no user records or provider secrets; it is stopped with its backup retained.
Supabase [Cron documentation](https://supabase.com/docs/guides/cron) describes the
scheduler mechanism; it is not a substitute for the transaction-separated worker.

Monitoring has a separate proposed 60-second poll and 180-second missed-heartbeat
warning. A scheduler with no due work still needs a successful heartbeat. Inspect
runtime gates before interpreting `challenge_operations_status_v1`; its work and
failure counts cover only the currently eligible work set, and fixture shutdown
can hide backlog. It is not a complete historical incident ledger.

| Signal | Proposed response; thresholds require owner approval |
| --- | --- |
| Any `dead_letter_count`, `notice_overdue_count`, `review_overdue_count` | Escalate to named primary/backup; inspect restricted status; preserve actual notice/filing windows. No automatic result rewrite. |
| `oldest_due` more than 300 seconds behind server time, rising due/retry/abandoned count | Check scheduler heartbeat, database connections/locks and SQLSTATE. Distinguish pause from outage. Bound retries; diagnose repeated failures. |
| No successful snapshot capture for 1,800 seconds when publication is enabled | Investigate job/gates; retain delayed/null display. Never include member counts in alerts. The service-only [local snapshot status](COMMUNITY_SNAPSHOT_STATUS_LOCAL.md) now reports actual capture age separately from invocation success; hosted monitoring and this threshold remain unapproved. Client counts cannot serve as its health check. |
| RPC latency/error rate, connection headroom, authorization denial/429 spikes | Aggregate metrics only; endpoint family and SQLSTATE/status, no payload, actor, token or link. P11 sets operational limits from real measurements. |
| Grant expiry/coverage lapse, unassigned review or support queue | Route to the staffed operator owner; no silent auto-renewal. The local `challenge_local_review_status_v1` projection reports authorization gaps and relevant expirations; staffed coverage and delivery proof remain unverified. |

The existing restricted status keeps `failed_work` challenge IDs and timestamps
for authorized item selection. P11A adds a separate
`challenge_local_worker_status_v1` projection containing only bounded state,
counts, timestamps and SQLSTATE codes. Do not forward the restricted JSON to
external alerts or generic logs. Tokens, Health facts, request bodies, usernames,
raw errors and link paths are excluded.

The local `challenge_local_review_status_v1()` service projection adds aggregate
outstanding-review and pending-appeal authorization gaps, existing resolution /
filing times and relevant grant expirations. It counts saved cases independently
of the worker allowlist and preserves explicit paused/disabled/unavailable states.
It supplements the existing worker and overdue monitors; it does not establish
staffed support, define an appeal response deadline or activate a poller. See the
[local projection contract and tests](../outputs/reports/2026-09-19-review-appeal-monitoring.md).

Select log retention and alert recipients in the retention worksheet. No telemetry
or alert destination was configured. The September 12 changelog check found the
[September 23 `logs.all` removal](https://supabase.com/changelog/48235-migration-of-supabase-management-api-logs-all-analytics-endpoint-to-logs-endpoint);
future monitoring should use supported APIs. This repository has no new log poller.

## Pause, rollback and recovery runbook

These steps are prepared for a later authorized exact environment. The
[local-only CLI](BETA_OPERATIONS_LOCAL.md) now requires explicit owned-project
credentials and a numeric loopback port; it never accepts a hosted target.

1. Record affected candidate/project, incident time, gate state and last durable
   run/claim receipts in restricted storage. Check approved operator identity and
   scope. Keep Health/user payloads out of the incident summary.
2. Pause **new admission** and discovery through reviewed controls. Keep sign-in,
   own history, reviews, safe exits and exact request recovery available. If result
   processing itself is suspect, pause processing and its trigger separately;
   record delay instead of shortening anyone's review window.
3. Contain a compromised human operator by revoking their precise challenge or
   support grant and session. Inspect audited reads/actions. Do not suspend a
   participant as a substitute for operator credential revocation. Credential
   rotation needs a separately approved target/custodian; never copy a service key
   into incident notes.
4. Diagnose with redacted status/SQLSTATE and claim state. Keep all receipts. A
   transient timeout resumes through exact retry/lease recovery; a dead letter
   uses the implemented P11A audited item-specific local recovery operation;
   hosted execution remains unauthorized. No direct
   `UPDATE` of finals, consent, review dates, claim attempts or audit history.
5. Roll application code back only to a schema-compatible known candidate with
   admission/processing still paused. Applied migrations stay forward-only.
   Do not reset the database, drop tables, delete accounts or restore over newer
   accepted agreements to undo a deployment.
6. If database recovery is necessary, obtain an approved backup/RPO/RTO plan and
   restore first into a separate authorized target. Reconcile post-backup requests,
   notices, exits, corrections and grant/session revocations before any switch.
   A restored stale authorization must not regain access. Compare agreement/final
   digests and account separation. Preserve the affected database for investigation.
7. Resume one bounded pass only after the fix/replay checks succeed. Use actual
   later notice timestamps and complete 48-hour notice/72-hour filed-review
   windows; confirm safe actions, exact retries, delayed counts and backlog health.
   Re-enable admission separately only with its own acceptance and authority.

Backup capabilities depend on the selected Supabase plan. Its
[backup documentation](https://supabase.com/docs/guides/platform/backups) is the
reference; P10 selects no paid plan or retention period and runs no restore.
Code rollback, data recovery and privacy deletion are three separate operations.

## Support, retention and remaining acceptance

[Support and retention preparation](BETA_SUPPORT_RETENTION_PREPARATION.md) owns
record classes, operator intake/actions, missing owner inputs and deletion safeguards.
P6's [contract](PRIVATE_COMMUNITY_V1.md) owns implemented scope, independence,
quotas and reinstatement. A local report save is not a monitored support service.

| Remaining dependency | Owner / completion evidence |
| --- | --- |
| Exact host, budget, identity, credentials, support, retention and publication settings | Existing release-readiness-b7 decision; fill/approve worksheet. No device participation needed to make these decisions later; no decisions fabricated while owner is away. |
| Four accepted source policies and timed band | P7 physical opt-in and actual observations; no Simulator substitute. |
| Real admission, minimum facts/integrity, nonfixture worker/publication boundary | P8 and subsequent reviewed integration; do not repurpose fixture gates. |
| HTTPS/native Apple/link integration and actual source journeys | P9 plus approved identities. All 13 policies, two/six-person isolation and historical Personal preservation. |
| Hosted scheduler credential isolation, dispatch journal, alert redaction/delivery, safe pause and recovery | Approved target/actions plus source-backed integration; repeat current local drills there. |
| Legacy job/API/Edge allowlist and backup/retention workflow | Review before any deployment; preserve existing agreements and old receipt meanings. |
| Hosted capacity/recovery, immutable release candidate, physical/human accessibility/comprehension | P11–P13 under their separate approvals. TestFlight/recruitment still require explicit authorization. |

No P7–P9 device wait is needed for this preparation. No later prompt is executed.
