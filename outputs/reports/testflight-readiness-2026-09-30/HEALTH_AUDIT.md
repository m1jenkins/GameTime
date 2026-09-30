# Health upload readiness audit — September 30, 2026

The server recovery fix is already deployed and matches current source. The
hosted save acceptance gate still fails: no post-cutover saved facts, and all
34 observed ingest requests returned HTTP 422. Updating the owner's phone is
a separate approval; its installed source version has not been inspected by
this audit.

## Scope and source identity

- Reviewed the required repository context, P8/P9 Health contracts, the
  September 27 refused-upload receipt, September 28 Round 12 receipt and
  September 29 release-prep receipt.
- Local source identity: `f1dd690f4db5125b69407e7d8beaf4925e357c0b`, before
  the current readiness task's documentation changes. `git merge-base
  --is-ancestor dff4be9 HEAD` and the same check against `b16685b` both exited
  0. The fix is included in current source and the existing archive's source.
- Hosted checks used Supabase read tools for deployed code and metadata,
  fixed-window aggregate logs, and the runbook's read-only save aggregate.
  No raw log rows, request bodies, activity values, tokens, actor identifiers,
  challenge identifiers or session identifiers were retrieved or retained.
- No hosted mutation, deployment, credential change, device install/launch,
  physical Health read, agreement change or goal mutation occurred.
- Logs were queried through **2026-09-30 20:56:13 UTC**. That timestamp is
  the audit cutoff, not a claim about subsequent requests.

## Deployed fix independently verified

`list_edge_functions` and `get_edge_function` report
`ingest-challenge-health` as **ACTIVE**, version **9**, updated
**2026-09-27 22:23:14.770 UTC**, with `verify_jwt` false.

The dated [September 27 receipt](../2026-09-27-health-refused-upload.md#hosted-state-september-27)
calls the deployed function version 8. The current metadata says 9, while its
entrypoint's deployment-directory suffix is 8. This audit records that
discrepancy; it does not infer another deployment from the numbering. The
update timestamp matches the receipt.

All **12** returned deployed files match current local source exactly. The
comparison decoded each local `Path.read_bytes()` result as UTF-8, preserving
line endings, and compared it to the tool's decoded file-content string using
strict equality. All files were valid UTF-8. No deployed source was printed or
saved as an extra artifact. SHA-256 hashes below identify the matching local
bytes; equality with deployed content was checked separately.

| Source beneath `supabase/` | Identical | SHA-256 |
| --- | --- | --- |
| `functions/ingest-challenge-health/index.ts` | Yes | `eae7e04902bd392810ff2185128ad490fcca5c1e8bc9c9960084e671d9ce99e6` |
| `functions/_shared/database.ts` | Yes | `f257e36b31ec6f3ed2bd56a1d93764de53412a8ad27bf3aadba8f395c7bfbc39` |
| `functions/_shared/bytes.ts` | Yes | `6c92b2401d65b43448df1ebc52bc523612385f1909b96b526d5cbbc2645ba13e` |
| `functions/_shared/http.ts` | Yes | `11f0d79589e11b7f0ce1f41acd2ef4ea91bc01b9c4d88ac767717db83ee7fe2b` |
| `functions/_shared/env.ts` | Yes | `9c6e5370c8d89ecc8986228e8824b46e65d6941b54c19eeb189e6b5bcd2705d3` |
| `functions/_shared/jwt.ts` | Yes | `93a3452efa77425f8d40f5680396110b60d181cbfcc429fc1cbacac5a1a85c72` |
| `functions/ingest-challenge-health/database.ts` | Yes | `e9f53c98804b5e16b1b15408e89985039b42af79970da541f53ab17321a449c7` |
| `functions/ingest-challenge-health/handler.ts` | Yes | `1129299ed51782fc55eb37f6e65b55f72655f8dd430dd949eae6b4440a444d1d` |
| `functions/_shared/appattest.ts` | Yes | `83ef029bd0db31a5e6e0eebcd369458e02c17e74a4934c29475a043cf16fc0a4` |
| `functions/_shared/cbor.ts` | Yes | `4c8e9e756d91c1302ecc63149dd1bd2f06c5ae094a5e2b8f181fa803fea4510e` |
| `functions/_shared/ecdsa_verify.ts` | Yes | `3a4b5fa379eba8de4b4b76a57645f5aed4cdef28f14a4dc39fe4dde5051bf8ff` |
| `functions/deno.json` | Yes | `eb4446f6df43d036df1723bb53dd8b492363fcc0b9a64d6657407bfeab0a5a4d` |

## Current hosted saves and refusals

The cutover was **2026-09-28 22:27:11 UTC**, the recorded last write in Phase
5 steps 1–4. The following runbook Step 7 query ran inside `begin read only`
and `rollback`:

```sql
select l.policy, count(*) as saves, max(f.recorded_at) as latest,
       jsonb_agg(distinct r.verification_mode) as modes,
       jsonb_agg(distinct f.state) as states
from app.challenge_real_health_facts_v1 f
join app.challenge_lobbies_v1 l on l.id = f.challenge_id
join app.challenge_real_health_requests_v1 r on r.request_id = f.request_id
where f.recorded_at > '2026-09-28T22:27:11Z'::timestamptz
group by l.policy order by l.policy;
```

**Result: `[]`.** No policy has a saved fact after cutover. There are no modes
or states to report. This does not expose or make a statement about the
person's underlying activity.

The log tool caps a window at 24 hours. The final request audit used two
adjacent fixed windows; retained results were available for both. Each query
selected status, count and first/latest timestamps from `function_edge_logs`,
filtered by the ingest function identifier resolved from deployment metadata.
No identifiers were selected.

| UTC window | HTTP 422 requests | HTTP 200 requests | First HTTP 422 | Latest HTTP 422 |
| --- | --- | --- | --- | --- |
| Sep 28 22:27:11 → Sep 29 22:27:11 | 17 | 0 | Sep 28 23:18:21.950 | Sep 29 21:50:11.753 |
| Sep 29 22:27:11 → Sep 30 20:56:13 | 17 | 0 | Sep 29 22:50:13.733 | Sep 30 20:33:17.030 |
| Combined nonoverlapping results | **34** | **0** | Sep 28 23:18:21.950 | Sep 30 20:33:17.030 |

No other status appeared. An initial overlapping 24-hour query, Sep 29
20:56:13 → Sep 30 20:56:13, returned 18 HTTP 422s and no other status. It is
a cross-check and is **not added** to the 34.

Each status query used the tool's explicit start/end parameters from the
table. SQL below is the exact query shape with the deployment identifier
replaced by a placeholder; resolve it from the function metadata when
reproducing the audit.

```sql
select log_attributes['response.status_code'] as http_status,
       count(*) as requests, min(timestamp) as first_at,
       max(timestamp) as latest_at
from logs
where source = 'function_edge_logs'
  and log_attributes['function_id'] = '<INGEST_FUNCTION_ID_FROM_METADATA>'
group by http_status order by http_status;
```

Reason counts were aggregate string matches against the three fixed refusal
names. PostgreSQL rows were scoped by `parsed.context` containing
`challenge_real_health_ingest_v1`; function logs were scoped to this ingest
function. Only counts and the latest matching timestamp were selected.

| UTC window | Binding-invalid log occurrences | Revision-refusal occurrences | Request-conflict occurrences | Latest binding refusal |
| --- | --- | --- | --- | --- |
| Sep 28 22:27:11 → Sep 29 22:27:11 | 21 | 0 | 0 | Sep 29 21:50:11.704 |
| Sep 29 22:27:11 → Sep 30 20:56:13 | 22 | 0 | 0 | Sep 30 20:33:16.965 |

Those 43 matching occurrences are PostgreSQL logs, not 43 distinct HTTP
requests. Logging may duplicate an error, so this audit does not equate the
counts. The scoped function logs have zero matches for the three names; the
deployed handler deliberately limits its automatic error logging. A zero-match
`maxIf` returned its epoch default, which is not a real refusal timestamp and
is omitted here.

The scoped reason query used the same two adjacent windows:

```sql
select source,
       countIf(position(event_message, 'challenge_real_health_binding_invalid') > 0)
         as binding_invalid_occurrences,
       countIf(position(event_message, 'challenge_invalid_real_health_revision') > 0)
         as revision_refusal_occurrences,
       countIf(position(event_message, 'challenge_request_conflict') > 0)
         as request_conflict_occurrences,
       maxIf(timestamp, position(event_message, 'challenge_real_health_binding_invalid') > 0)
         as latest_binding_invalid_at
from logs
where (source = 'function_logs'
       and log_attributes['function_id'] = '<INGEST_FUNCTION_ID_FROM_METADATA>')
   or (source = 'postgres_logs'
       and position(log_attributes['parsed.context'], 'challenge_real_health_ingest_v1') > 0)
group by source order by source;
```

An initial attempt to aggregate a `body` log column returned a backend error.
Using `event_message` for bounded string matching succeeded. No raw message
was selected. An initial unscoped reason-count cross-check was superseded by
the scoped adjacent-window queries above.

**Inference:** current failures are consistent with an older installed app
repeatedly retrying a closed binding. The server maps binding-invalid to
`challenge_closed`, and current source retires that account-mode request.
The aggregate evidence does not establish the installed version or the exact
rejected agreement. A terms or membership mismatch can also produce
binding-invalid. Treat a phone update as conditional until its source version
is inspected.

## Recovery code already present

| Evidence | Meaning |
| --- | --- |
| `ChallengeHealthUploadClient.swift:20–26` | Only HTTP 422 with one of three known reasons is classified as permanent. Unknown refusals remain retryable. |
| `supabase/functions/ingest-challenge-health/database.ts:17–21` | Maps binding-invalid, revision refusal and request conflict to the fixed retirement reasons. |
| `ChallengeHealthUploadClient.swift:247–267` | Account-mode permanent refusal is retired with exact bytes preserved; session/epoch checks fence the write. |
| `ChallengeHealthTransportCoordinator.swift:168–178` | A refused account-mode record does not block another challenge or readiness. Device-signed recovery retains counter order. |
| `ChallengeHealthFlowStore.swift:343–359` | A challenge's own waiting request precedes new reads; other challenges proceed. Closed windows retire local work and show the saved-update state. |
| `ChallengeHealthFlowStore.swift:383–421` | Rechecks authoritative terms and revision after the Health query; a permanent refusal schedules one bounded replacement pass. |
| `ChallengeHealthFlowStoreTests.swift:409–539` | Existing tests cover independent challenges/readiness, closed-window retirement, another install taking a revision and a race during submission. |

No additional local 422 recovery defect was identified. This audit did not
change recovery behavior or redeploy the already matching function.

## Why a second uploading installation can lower a score

- Staging uses `com.mjenkins.gametime.staging`; TestFlight uses
  `com.mjenkins.gametime` (`project.pbxproj:610,684`). Both use the same p11b
  backend and account-mode upload path (`Configuration/Staging.xcconfig:7,18`;
  `Configuration/TestFlight.xcconfig:9,17`).
- Each app creates its own Application Support upload journal and comparison
  cache (`ChallengeHealthUploadClient.swift:37–47`;
  `ChallengeHealthComparisonCache.swift:13–27`). The coordinator's delivery
  lease is in-process; it does not elect a writer across two app bundles.
- Each connected app can refresh in the foreground or receive native Health,
  unlock or network opportunities (`ChallengeHealthFlowStore.swift:269–297`;
  `ChallengeHealthPermissionService.swift:53–82`). Merely avoiding manual
  Refresh is insufficient to guarantee a second installation stays quiet.
- A refresh takes that installation's current Health view, then fetches the
  latest server revision and submits its normalized replacement
  (`ChallengeHealthFlowStore.swift:368–401`). A later observation can contain
  less visible activity, a legitimate correction or unresolved data.
- Server ingestion validates the next revision, parent and nondecreasing
  observation/query timestamps. It does **not** require the activity value to
  increase (`20260920010824_challenge_real_health_ingest_v1.sql:659–685`).
  pgTAP `520_challenge_real_health_policy_matrix.test.sql:197` explicitly
  accepts a lower correction. P8's contract states that totals may decrease
  and values replace rather than take a maximum
  (`docs/P8_REAL_HEALTH_CONTRACT.md:56–89`).

**Conclusion:** the warning describes a real possibility, not an inevitable
decrease from every duplicate install. Revision-race recovery prevents a stuck
queue; it does not merge competing installations' views. Taking a maximum or
ignoring an unresolved replacement would violate legitimate corrections and
the existing missing-data policy. No source policy, result, stake or simulated
money behavior changed.

## Device boundary and next gate

This audit did not inspect the phone. The September 27/28 receipts describe a
build without the recovery fix, but that historical record cannot establish
what is installed today. A successful same-bundle update is also not, by
itself, evidence that current Steps and outdoor distance saved.

1. Inspect current Staging version/build without launching an extra uploader.
2. If its source predates `dff4be9`, obtain device approval for an in-place
   update of **the same Staging bundle**, preserving its app data, account,
   durable retry journal and active goal. Do not uninstall it or substitute
   the Debug app. This is an operational recommendation, not proof of a
   completed update.
3. With only that installation uploading for this account, verify the runbook
   Step 7 save aggregate and bounded ingest status/reason counts again. Steps
   and outdoor distance each need a post-cutover save in `private_account`
   mode, with no new binding-invalid refusals.
4. Existing Outdoor runs September 24–October 1 accepts corrections only
   through **October 3, 05:00 UTC** (October 3, midnight in America/Chicago).
   After that deadline, use a newly agreed outdoor-distance goal for this
   gate; do not reopen or reinterpret the existing agreement.
5. Keep this account's TestFlight installation deferred until active Staging
   goals are final, as selected in friends-plan Phase 6. Approximate settlement
   dates are scheduling guidance; verify final state before a cutover. Then
   stop the old uploader before connecting the new one, through separately
   approved device actions.

## Local tests actually run

Working directory:
`/Users/user/Documents/GitHub/GameTime/supabase/functions`.

```sh
deno test --allow-env _shared/http.test.ts ingest-challenge-health/database.test.ts ingest-challenge-health/handler.test.ts
```

**Exit 0; 77 passed, 0 failed.** Database adapter 21, ingest handler 53,
shared HTTP 3. Tests stub network calls; they do not send an activity update
or mutate hosted data. They include the permanent-refusal reason response,
unknown-reason retryability, paired-null account proof and exact-body recovery.

The original Deno output was delivered through execution session `23600`
(completion chunk `eaf79d`), not redirected to a file. A clearly labeled
excerpt transcribed from that completed output is retained at
`tmp/testflight-readiness-2026-09-30/health-audit-deno-session-excerpt.log`.
That generated log is ignored; this report is the durable checked-in receipt.
The tests were not rerun merely to create a log.

This Health agent did not run native device tests or pgTAP in this audit. The
existing source tests and dated receipts are evidence for their own runs;
current native/build verification belongs to the parent readiness receipt.
