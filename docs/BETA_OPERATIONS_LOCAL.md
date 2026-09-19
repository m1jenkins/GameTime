# Local Beta operator CLI

The September 19 [main consolidation](../outputs/reports/2026-09-19-main-consolidation.md)
includes v2 administrator recovery, suspended-account repair and service
review/appeal/snapshot monitoring. Its complete local operator checks pass;
hosted operation remains unaccepted. Historical v1
administrator calls still require manual reconciliation.

`scripts/beta-operator.py` is a fictional, local-only interface to the existing
RPC contracts. It connects only to literal `127.0.0.1`; there is no hostname,
HTTPS target or hosted authentication mode. Allocate and inspect owned resources
before admitting fictional actors. Do not use a retained stack for verification.
The [support worksheet](BETA_SUPPORT_RETENTION_PREPARATION.md) remains authority
for scope, independence, staffing and policy dependencies.

## Credentials and roles

Pass `--owned-project <gametime-project-name> --credentials-file <private-file>`.
The credential file must be an owned regular file with mode 0600. Its fields are:

| File | Required fields |
| --- | --- |
| Administrator | `project_id`, `api_port` (integer), `role: "administrator"`, `api_key` (that owned local service key) |
| Human | `project_id`, `api_port` (integer), `role: "human"`, `api_key` (that local public key), `actor_id` (UUID), `email` |

Human passwords are prompted without echo. Fictional test automation may add a
`password` field to its private human file. Keep that file separate from reports
and journals. Each human invocation signs in through the local Auth server,
checks the returned account against `actor_id`, and signs out only its own
session. A local password account does not implement hosted Apple operator auth.

Administrator commands additionally require `--administrator`; human commands
reject it. The CLI rejects a credential file with the wrong role. Administrator
files cannot contain human identity/password fields. Server RPC grants remain
the security boundary; a human session cannot grant itself authority.

This replaces the old implicit `/tmp/gametime-finish-b7-stack` lookup and
`--local-actor`/`--email` selection. Existing status, worker and fictional
publication operations remain available using an explicit administrator file.
No retained preview resource or credential file is read automatically.

## Commands and authority

| Command | Arguments / authority |
| --- | --- |
| `grant`, `revoke` | Administrator; `--actor`, `--challenge`, `--capability review\|moderate`, `--request-id`; grant also needs `--expires` |
| `grant-support`, `revoke-support` | Administrator; `--actor`, `--request-id`; grant also needs `--expires` |
| `cases`, `reports` | Human; `--challenge`; independent reviewer/moderator grant for that exact challenge |
| `resolve` | Human reviewer; `--challenge`, `--review`, `--decision upheld\|exclude` |
| `remove` | Human moderator; `--challenge`, `--subject`, `--reason` |
| `close-community` | Human moderator; `--challenge` |
| `support-reports` | Human with separate global support grant; optional paired `--before` and `--before-id` |
| `suspend` | Human global support; `--subject`, `--reason`; no challenge argument or moderator fallback |
| `support-appeals` | Human global support; pending queue |
| `resolve-appeal` | Human global support; `--appeal`, `--decision upheld\|reinstate`; decider differs from appellant and original suspender |
| `appeal`, `own-appeals` | Human account filing or reading its own suspension appeal |
| `status`, `run-once`, `publish-fixture` | Existing local administrator operations; see command `--help` |

Every human mutation and administrator grant/revoke requires `--request-id <UUID>`
and the global option `--journal-dir <private-directory>`. Reasons are `username`, `unwanted_contact`,
`unsafe_behavior`. Grant expiry is checked against server time and cannot exceed
seven days; equality and revocation deny fresh access. Grants do not bypass
independence, active-session or account checks. Removal is challenge-scoped;
reinstatement permits future admission and never restores ended membership or
consent. Missing activity alone never establishes a loss.

Reports are bounded to 100 rows by the server. For the next global-report page,
pass both the last row's `created_at` as `--before` and its `id` as `--before-id`.
The CLI rejects half a cursor before sign-in. Cases and appeals use the existing
bounded RPC queues; this slice adds no queue allocator or monitoring service.

## Result review

Choose `upheld` only when the normalized result matches the agreed rule. `exclude`
removes the disputed result, returns its simulated entry, and may void a leaderboard
or an undersized group. Do not infer missing physical-source facts. Case context
includes only the filer, their structured reason, agreed policy/window/digest,
optional goal, latest normalized fact and their provisional allocation. It excludes
other participants' histories, raw Health samples, source IDs and routes. Case and
report reads and operator actions are audited. No freeform sensitive review text
is collected. Deadline equality closes resolution; actual time is returned by status.

## Exact human recovery

Choose a request UUID once and retain the original command. For example:

```sh
python3 scripts/beta-operator.py \
  --owned-project gametime-your-owned-task \
  --credentials-file /private/human.json \
  --journal-dir /private/operator-requests \
  resolve --challenge <challenge-uuid> --review <review-uuid> \
  --decision upheld --request-id <request-uuid>
```

Before sign-in or dispatch, the CLI atomically saves and syncs the exact JSON
request, RPC, project/port and account UUID. The journal directory is mode 0700;
records are mode 0600 and contain no credentials or response/case data. Request
files remain after success. Keep journals in restricted local storage; identifiers
and decisions are still operational data, not public logs or a retention policy.

After a lost response, interrupted process, or sign-in failure, repeat the exact
command with the same journal and original account. The CLI compares all saved
fields and sends the same request bytes. It refuses changed decisions, scopes,
accounts or targets under that UUID. It does not automatically create a new
request or replay as another operator. The server returns the original receipt
without a second action/audit entry, including supported retries after grant
revocation. A saved receipt never authorizes a fresh action. A corrupt or missing
journal requires reconciliation; do not delete it just to bypass a conflict.

## Exact administrator recovery for new requests

Choose a UUID before the first dispatch and keep the same command and journal:

```sh
python3 scripts/beta-operator.py \
  --owned-project gametime-your-owned-task \
  --credentials-file /private/administrator.json --administrator \
  --journal-dir /private/operator-requests \
  grant --actor <account-uuid> --challenge <challenge-uuid> \
  --capability review --expires <original-expiry-with-timezone> \
  --request-id <request-uuid>
```

All four grant/revoke commands use `challenge_admin_request_v2(uuid,jsonb)`.
The payload has `version: "challenge_admin_request_v2"`, `operation`
(`grant_operator`, `revoke_operator`, `grant_support`, `revoke_support`) and
`actor_id`; scoped operations also require `challenge_id` and `capability`,
and grants require `expires_at`. Every value is a string; extra or missing fields
are rejected. The request UUID is shared across all four operations in that
database. The server compares the entire JSON payload, including the original
expiry string. JSON object key ordering is immaterial; changed values conflict.

Before HTTP, the CLI syncs a mode-0600 version-2 record containing the exact
project, loopback port, administrator authority, RPC and canonical request bytes
(including UUID). It contains no key, password, token or response. Human version-1
journals remain compatible. Reusing a journal UUID with a different environment,
authority, operation, account, scope or payload fails locally before dispatch.
Keep the directory at mode 0700 and retain completed records.

After response loss or process interruption, rerun the **exact original command**
with that journal and an administrator credential file for the same environment.
Do not update the expiry, switch the scope or choose a fresh UUID to recover.
The server stores a `challenge_admin_receipt_v2` response containing `request_id`,
the original `request` and `recorded_at` atomically with the v1 mutation and its
single audit action. Concurrent duplicates return the same receipt. A committed
UUID with a different payload fails with `22023` and adds no audit action.
An unsuccessful transaction saves neither receipt nor mutation/audit action.
There is no background or automatic retry.

A receipt records a past action, **not current access**. Replaying an old grant
after revocation or expiry never restores access; replaying an old revoke after a
new grant never revokes the new grant. Recovery remains service-only and does not
repeat current grant validation. Fresh requests still use the existing scope,
independence, active-account and seven-day expiry rules. Revoking an absent grant
retains the existing audited no-op behavior. Administrator credentials represent
service authority, not a named human administrator; grant audit identities remain
the subject account under the existing v1 convention.

## Historical administrator calls and missing journals

The four original `challenge_grant_operator_v1`, `challenge_revoke_operator_v1`,
`challenge_grant_support_v1` and `challenge_revoke_support_v1` RPCs keep their
signatures, permissions and behavior. They have **no request UUID or durable
response-recovery contract**. Existing historical audits are not backfilled into
receipts. After an ambiguous v1 response, inspect the exact grant and immutable
audit in that owned database before deciding whether to issue a new action.
Reissuing may change current authority and adds an audit event. Attaching a new
UUID afterward cannot recover a historical response.

For a missing or corrupt journal, retain the remaining files and reconcile the
original environment, UUID, server request/receipt (if any), grant and audit before
dispatch. Do not delete a conflicting journal or guess an earlier UUID/payload.
No direct grant, receipt, result or audit edits are part of recovery. Existing
worker and fixture publication commands retain their request identities.

CLI failures print only a bounded code or a fixed recovery instruction, not raw
server errors, headers, passwords or tokens. Do not put secrets in command-line
arguments. Case/report output is for its authorized operator and should not be
forwarded to external logs. No hosted service, staffing, deletion policy, external
message, device acceptance or readiness gate is completed by this local tool.

## Focused verification

`python3 scripts/tests/beta-operator.test.py` checks local recovery-file invariants.
`scripts/beta-operator-smoke.py --administration-only` runs the focused grant/revoke
matrix; omitting the flag retains the full historical human/operator matrix.
The runner invokes the actual CLI against local Auth and
PostgREST, inspecting task ownership and loopback publishes before creating
fictional actors. It accepts a private `--connection-file`, a new `--work-dir`
and a new `--evidence-dir`; it never starts, resets or stops a Docker stack.
A loopback forwarding proxy drops selected committed responses, preserving
request-body hashes without storing credentials. The v2 matrix adds administrator
receipt recovery, opposite-action replay, parallel duplicates/conflicts and
service-only denials. SQL `516_challenge_admin_requests_v2.test.sql` checks the
strict interface and private immutable receipt store. Setup, actual results,
upgrade checks and resource disposition are in the
[administrator recovery report](../outputs/reports/2026-09-18-admin-grant-recovery.md).
The [September 14 operator report](../outputs/reports/2026-09-14-p11a-operator.md)
preserves the original v1 limitation and its historical results.

## Historical executed drills and pending acceptance

The historical b7 version of `scripts/beta-operator-smoke.py` passed 11 authenticated local CLI checks, including
unauthorized rejection, scoped context, exact recovery across separate logins,
worker recovery, session isolation, report/suspension privacy and safe closure.
SQL 497 passed 19 assertions, including processing pause, delayed notice and
unanswered review producing a new full review window. The all-policy native run
also filed reviews and left active challenges with admission/processing paused.
These are fictional local evidence, not physical or hosted acceptance.

Before hosted use: obtain explicit authorization, accepted source policies,
monitored support and named operators; provision new-product hosted client wiring,
least-privilege credentials and an approved scheduler/alert destination; repeat
these drills there. Never run this CLI against an unowned stack or copy local fixture
credentials into a hosted environment. See the finish-line handoff for gates.
