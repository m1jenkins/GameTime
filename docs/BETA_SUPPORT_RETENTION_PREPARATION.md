# Beta support and retention preparation

P10 extension of **gametime-beta-release-readiness-b7**, September 12, 2026 UTC.
This is an unpublished operating worksheet, not approved legal language, retention
policy, staffed service or authorization to contact anyone. Read the
[hosted plan](BETA_HOSTED_PREPARATION.md), [P6 contract](PRIVATE_COMMUNITY_V1.md)
and existing [privacy/terms draft](BETA_PRIVACY_TERMS_DRAFT.md) together.

## Assign and operate support

The owner must name the accountable entity/regions, primary and backup support
operators, monitored intake route, coverage hours and response target. Assign
independent reviewers and an appeal decider who was not the original suspender.
A grant administrator and credential custodian must also be named. No identity,
inbox, response promise, policy URL or publication value is selected by P10.

Prepare intake with only account/challenge reference where needed, a structured
category and the person's requested action. Do not solicit raw Health exports,
routes, screenshots of private investigation screens, passwords or sign-in tokens.
No new freeform intake store is implemented here. If an external inbox is selected,
its data handling, access, retention and deletion must be approved too.

| Intake | Authorized operator procedure | Required evidence / limit |
| --- | --- | --- |
| Own activity/result question | Authenticated independent reviewer with a `review` grant calls `challenge_operator_cases_v1(p_id)`; resolves via `challenge_operator_action_v1(request, payload)` using `op: resolve`, `id`, `review_id`, `decision: upheld` or `exclude` | Only agreed policy/window, normalized fact and own allocation. Match the frozen agreement; missing source data alone is not failure. Deadline is actual filing +72h. No off-ledger result editing. |
| Report scoped to a challenge | Independent moderator with `moderate` reads `challenge_operator_reports_v1(p_id)`; uses action `remove` with `actor_id`, `reason`, challenge `id`, stable request UUID when justified | Report must actually carry that challenge scope. No unrelated/global report access. Removal preserves own history and safe simulated returns. |
| Community must close | Assigned independent moderator calls `challenge_operator_close_v1(p_request_id,p_id)` | Review scope/terms before action. Returns simulated entries and preserves agreement/audit. This is a consequential action, not a rollback test to run on an unapproved real cohort. |
| Global username/account safety | Separately granted support reads `challenge_support_reports_v1(p_before,p_before_id)`; uses `challenge_support_suspend_v1(p_request_id,p_subject,p_reason)` | Both cursor fields travel together; pages contain at most 100 rows. Reasons are `username`, `unwanted_contact`, `unsafe_behavior`. Challenge moderators cannot suspend globally. Support cannot suspend itself. |
| Suspension appeal | Person files `challenge_appeal_v1(p_request_id)` and reads `challenge_own_appeals_v1()`; support reads `challenge_support_appeals_v1()` and decides through `challenge_resolve_appeal_v1(p_request_id,p_appeal,p_decision)` | Decision `upheld` or `reinstate`; decider differs from appellant and original suspender. Reinstatement permits future admission, never restores ended membership or consent. |
| Access withdrawn from operator | Administrator calls `challenge_revoke_operator_v1(p_actor,p_id,p_capability)` or `challenge_revoke_support_v1(p_actor)` | Record named operator, exact scope and reason in approved restricted operational record; verify revoked session/grant cannot read or act. No direct audit-row edits. |
| Deletion/retention request | Use the scoped account-deletion receipt flow below; independent reviewer/appeal decider releases the applicable restricted record after deciding | This is the limited September 14 approval only. Do not invoke historical `delete-account` or a SQL cascade by itself, do not extend it to another record class, and do not promise backup erasure without verification. |

Grant/revoke APIs are service-only; human work uses the human's active authenticated
session. `challenge_grant_operator_v1(p_actor,p_id,p_capability,p_expires)` and
`challenge_grant_support_v1(p_actor,p_expires)` allow expiry at most seven days
from the current server clock. Proposed practice is the shortest staffed interval,
not automatic seven-day renewal. Expiry equality and revocation deny new access.
Account blocks/suspensions and session changes still apply. Saved mutation retries
retain their original receipt semantics; a retry does not confer new authority.

For every mutation, persist one request UUID and exact body under the correct
operator identity before sending; on ambiguous response, retry those exact bytes.
Do not retry as another operator, create a new request reflexively or store tokens
in reports. Inspect server time and saved state first. Reads and actions enter
immutable audit. Actual response coverage, external intake delivery, operator
training and unassigned-queue monitoring are unverified.

September 14 current implementation: the [local operator CLI](BETA_OPERATIONS_LOCAL.md)
now includes scoped review/moderation, grant revocation, separately granted global
support, suspension and independent appeal decisions. Administrator and human
credential files/commands are separate. Human mutations persist a credential-free,
account/target-bound request before HTTP and recover by exact replay. The obsolete
challenge-scoped `suspend` command is rejected; suspension uses only the separate
support RPC. At that baseline, grant/revoke APIs had no durable request receipt,
so ambiguous administrator responses required inspection before reissue. See the
[operator report](../outputs/reports/2026-09-14-p11a-operator.md) for actual local
checks. The combined local recovery candidate landed at `a3d2c3f`; the operator
slice also landed on local main at `6fea1c2`, with owner approval on September 14.
Dated reports retain their original pre-landing status and verification limits.
This remains fictional loopback operation, not hosted Apple authentication,
real operator assignment, monitored support or retention-policy acceptance.

September 18 review-branch addition: new administrator grants/revokes use the
explicit `challenge_admin_request_v2` / `challenge_admin_receipt_v2` contract and
a credential-free version-2 journal before dispatch. Exact replay returns the
original receipt without repeating the mutation or audit; receipts do not assert
current authority. Historical v1 calls still require manual reconciliation and
are never backfilled. See [recovery instructions](BETA_OPERATIONS_LOCAL.md#exact-administrator-recovery-for-new-requests)
and the [actual checks and limits](../outputs/reports/2026-09-18-admin-grant-recovery.md).
This adds no named administrator identity, external operation or retention policy.

## Retention decision worksheet

For **every row except the limited account-deletion scope below**, owner approval must specify: purpose; event starting the clock;
duration; active/dispute/legal holds; deletion versus deidentification; approver;
which roles retain access; backup expiration/restoration treatment; and verification
of completion. Every other duration and deletion policy remains **unselected**. Local
immutable fixture retention is implementation behavior, not permission to retain
future participants' data forever. Agreement deadlines and local cursor lifetimes
are not retention approvals.

| Record class / current storage | Current behavior and policy decision needed |
| --- | --- |
| Auth identity, sessions, `public.profiles`, private `challenge_age_v1` / `challenge_access_v1` | Username/timezone, 21+ confirmation/time and eligibility; no date of birth. Define sign-out/revocation, identity minimization and tombstone/linkability policy. Deleting Auth alone does not reliably reject an unexpired token; retain current live-session checks. |
| Lobbies/members/slots, immutable agreements/consents | Preserve exact terms/digests and unsettled exposure through exits. Define finality/dispute hold and permitted deidentification without losing participants' own receipts or altering consent. |
| `challenge_facts_v1`, readiness records | Fictional normalized values/revisions today. P8 will add accepted minimal real facts; approve separate source-policy/freshness/integrity retention then. Raw samples, source names, routes and baselines must not enter the upload or support store. |
| Notices, reviews, resolutions, exits, finals | Append-only outcome/review history and nonredeemable simulation. Define review/support/audit purpose and hold/release. Never overwrite an earlier allocation or shorten review time to purge. |
| Durable `challenge_requests_v1`, worker run receipts, claim rows | Exact recovery links requests/identities to effects; worker leases/backoff are operational state. Define supported retry lifetime, terminal retention and recovery behavior after expiration before any pruning. |
| Invitation links/redemptions | Server token hashes plus issuance/expiry/revocation and redemption history. Issuance retry responses may retain the original opaque bearer token in the private request ledger. A 30-day link expiry is not automatic deletion of token-bearing receipts. Define retention for both and exclude them from logs/exports. |
| Reports/scopes, suspensions, support grants/appeals/decisions, operator audit | Private scoped support and independent decision history. Define access after closure, retention for safety review, appeal holds and audit minimization. Never infer a challenge scope for historical global reports. |
| Community publications, capacities, member revisions and snapshots | Private publisher/parameters and delayed anonymous counts; historical exits retain unsettled returns. Snapshot tables are internal, not a public archive. Define snapshot pruning and policy metadata retention without exposing under-five membership. |
| History projections/revisions, page/cursor state, quotas | Derived private data still links to actors. Define bounded cleanup after source retention expires and cursor invalidation. Do not delete source agreement/history as a cache cleanup. |
| iPhone pending commands/invitation intent and caches | Actor/terms-bound protected durable requests; stale account content clears. Define response-loss/relogin recovery and cleanup coordination with server retention. Never copy device containers into the support record. |
| Operational logs, scheduler journal, alert incidents, external support intake | No P10 hosted destination exists. Approve minimal fields, staff access, duration and deletion for each provider. Strip tokens, link paths, Health facts and raw request/error bodies before emission. |
| Backups, exports, provider logs, replicas | Select plan, RPO/RTO and lifecycle; define expiring copies and how restored data replays deletion/revocation decisions. Logical database backups do not automatically cover every external provider/store. Verify exact coverage on the selected plan. |
| Historical Personal/Solo/charity/duel/weekly/commitment rows | Existing agreements and their own retention holds remain separate. New Beta policy does not reinterpret, purge or authorize operating historical payment/push/retention paths. |

### Scoped account-deletion approval — September 14, 2026

This records the owner-approved, local `challenge_*_v1` account-deletion scope;
it does **not** approve this worksheet as a whole, legal clearance, a legal hold,
hosting, provider operation, or backup erasure.

- From server acceptance, remove identifying profile/contact/access data and
  unnecessary Beta drafts or invitation material within **seven days** (the
  implementation may remove it sooner). Retain only necessary normalized facts
  and case content until **thirty days** after the relevant result and case are
  closed. Retain the minimum pseudonymous Beta agreements, consent, results and
  operator audit until **one hundred eighty days** after finality or case
  closure, whichever is later. Historical records keep their separate governing
  rules, and pseudonymous records can still be linkable.
- The approved local flow applies the existing shared profile/Auth deletion
  transaction at durable acceptance, after it has saved only the minimum
  provider-retry binding. A provider-pending receipt is therefore not account
  closure, but it cannot retain ordinary profile, contact, session, or Auth
  access through the seven-day maximum.
- Deletion does not waive a review or appeal. The existing full 48-hour notice
  and 72-hour filing/resolution windows remain unchanged. The assigned
  independent reviewer releases a review hold; the independent appeal decider
  releases an appeal hold. Review unresolved holds every **thirty days** without
  silently cancelling the right. Ordinary account access ends at durable
  acceptance; only narrow own-review, appeal and deletion-status access remains.
- Keep the deletion-status receipt for **ninety days** after all required steps
  and cases finish. Exact duplicates recover the saved outcome instead of
  repeating effects. Keep the deleted-account marker while historical references
  need it, expire only this receipt (not project-wide requests), report retained
  records separately from account closure, and never claim backups are erased
  without verification.

## Scoped deletion workflow

1. Inventory the exact environment, actor references, affected record classes,
   active agreements/reviews and retention holds. Produce a restricted dry-run
   count/class report; export no raw Health or token-bearing requests.
2. Review the approved policy and hold decisions. Revoke affected active sessions
   and sharing authority through supported controls; preserve safe own access and
   settle or retain unsettled receipts as required. Verify stale tokens and in-flight
   responses cannot disclose data across account changes.
3. Implement a forward, versioned, idempotent deidentification/deletion operation
   with a bounded request identity and minimum completion audit. Scope each class;
   do not cascade through historical agreements or erase audit to satisfy a request.
   Approval of a policy is not approval of an arbitrary destructive execution.
4. Test dry-run versus execution, exact retries, interruption/concurrency with
   admissions/review, protected phone recovery files, historic digests, restored
   backups and revocation replay on an owned disposable environment.
5. Obtain authorization for the exact real environment/action, then execute only
   its reviewed scope. Verify completion and remaining holds before communicating
   the actual result through the authorized route. Record any retained purpose
   accurately; never silently claim all copies are gone.

P10 executes none of these deletion steps against user data. Actual legal policy
review, human comprehension, physical accessibility, monitored support delivery
and operator coverage remain explicit acceptance dependencies.
