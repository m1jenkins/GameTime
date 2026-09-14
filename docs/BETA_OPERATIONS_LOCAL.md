# Local Beta operator CLI

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
| `grant`, `revoke` | Administrator; `--actor`, `--challenge`, `--capability review\|moderate`; grant also needs `--expires` |
| `grant-support`, `revoke-support` | Administrator; `--actor`; grant also needs `--expires` |
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

Every human mutation also requires `--request-id <UUID>` and the global option
`--journal-dir <private-directory>`. Reasons are `username`, `unwanted_contact`,
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

Grant/revoke RPCs have **no request UUID or durable response-recovery contract**.
They remain separate administrator calls without automatic retry. After an
ambiguous administrator response, inspect the exact grant and immutable audit
in that owned database before deciding whether to reissue. Reissuing may add an
audit event; this CLI does not claim exactly-once administration. No direct grant,
result or audit edits are part of the human procedure. Existing worker and fixture
publication commands retain their server invocation/request identities.

CLI failures print only a bounded code or a fixed recovery instruction, not raw
server errors, headers, passwords or tokens. Do not put secrets in command-line
arguments. Case/report output is for its authorized operator and should not be
forwarded to external logs. No hosted service, staffing, deletion policy, external
message, device acceptance or readiness gate is completed by this local tool.

## Focused verification

`python3 scripts/tests/beta-operator.test.py` checks local recovery-file invariants.
`scripts/beta-operator-smoke.py` invokes the actual CLI against local Auth and
PostgREST, inspecting task ownership and loopback publishes before creating
fictional actors. It accepts a private `--connection-file`, a new `--work-dir`
and a new `--evidence-dir`; it never starts, resets or stops a Docker stack.
A loopback forwarding proxy drops selected committed responses, preserving
request-body hashes without storing credentials. Setup, exact commands, results,
failures and resource disposition for this slice are in the
[September 14 operator report](../outputs/reports/2026-09-14-p11a-operator.md).

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
