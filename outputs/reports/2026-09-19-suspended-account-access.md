# Suspended-account access correction — September 19, 2026 UTC

Review branch: **`codex/suspended-account-access`**, based on current committed
main **`9f116ac4954594a8d64467f78a6dca55d3cc2ce4`**. Work used the isolated
`/private/tmp/gametime-suspended-account-access` worktree. No merge, push, hosted
action, P7 change, native change or readiness change is part of this delivery.

Read the administrator-recovery report at delivered branch tip
`c547471e508c30346ee43e2738300af340f96c68` and the review-monitoring report at
`3f62ff88d2638b4569ac9d8b36d3b4a33a78879b`. Their failures remain historical
failures. Those branches were inspected, not merged into this correction.

## Correction and affected callers

The account-deletion migration replaced the session helper's active-identity
predicate with `challenge_actor_unavailable_v1`, which additionally rejects
suspension. That made a valid suspended session fail before the operation could
apply its own contract. The forward
[migration](../../supabase/migrations/20260919045754_challenge_suspended_account_access_v1.sql)
changes only `app.challenge_session_v1()` back to the active-identity predicate
at both checks, before and after its existing session SHARE lock.

The current `is_active_actor` predicate already rejects accepted deletion
tombstones, deleted/missing profiles, missing profile/Auth bindings and missing
Auth principals. The actor-bound session lookup, current-clock expiry checks,
post-wait identity check, invoker mode, empty search path and privileges remain.
No historical migration or shared suspension-availability predicate was edited.

The audit used the fully migrated function definitions, including renamed
unmetered helpers and dispatcher paths:

| Caller family | Preserved behavior |
| --- | --- |
| Access status, own appeals | Authenticated suspended callers can see suspension, file an appeal and read their own decisions. Filing still binds the current suspension. |
| Detail, list, sections and history | Existing membership checks and private projection remain. `challenge_actor_unavailable_v1` still hides peer members, Health facts, result maps and friend roster terms. Community disclosure rules are unchanged. |
| Mutate/command and personal commit | New creation, configuration, invitations, targets, selection, freeze/reopen, consent and personal admission retain `challenge_admit_v1`, including rechecks after profile locks. Leave, cancel and review retain their separate ownership, state and deadline rules. |
| Invitation issue/redeem/revoke | Issue retains admission checks. Redemption retains explicit issuer/caller suspension checks; a known valid token cannot admit a suspended caller. Revoke remains an allowed safe action. Existing-account redemption replay creates no new membership. |
| Community catalog/join | Discovery eligibility still uses the unchanged unavailable predicate; join still requires admission before and after locking. |
| Reports, blocks, abandon/stop | Safe actions remain available within their existing scope. Stop still fences an uncommitted request and preserves committed responses. |
| Reviewer/moderator cases, reports, resolve/remove/close | Unchanged capability, expiry, membership/independence and suspension checks deny fresh privileged access, even with live grants. |
| Support reports, appeals, suspend and resolve appeal | `challenge_require_support_v1` still rejects unavailable operators. Appeal decisions still require an active independent operator different from appellant and original suspender. Reinstatement cannot revive ended membership. |
| Administrator grants and service/worker operations | Existing service guards and unavailable-subject checks are unchanged. No new authority or execute grant is introduced. |
| Confirm age and policy previews | Identity-only acknowledgement or computed terms remain available; they do not grant admission or discover another account. |
| Exact receipt recovery | Authentication precedes lookup. Suspended callers may recover their existing receipts, including an operator receipt, without rerunning the action. Changed payloads conflict. Deleted, revoked or expired callers cannot reach receipt lookup. |

## Actual verification

On the uncorrected 81-migration committed-main schema, SQL 494 aborted after
13 passing assertions, 506 after 50 and 507 after 13, all with
`challenge_session_required` and no complete TAP plan. The unmodified default
operator HTTP smoke stopped after 79 checks at suspended appeal response recovery.

The same owned stack then received the forward correction. Accepted SQL logs
were checked for contiguous assertion numbers, complete matching TAP plans,
exit zero, no failed assertions, skips, TODOs or SQL errors. See
[sanitized verification and source hashes](suspended-account-access-20260919/verification.json).

| Final check | Actual result |
| --- | --- |
| SQL 494 safety | **22/22** |
| SQL 506 private community | **67/67** |
| SQL 507 community guards | **18/18** |
| SQL 512 deletion | **32/32** |
| SQL 513 deletion restore | **21/21** |
| SQL 514 deletion preservation | **19/19** |
| New SQL 517 suspended access matrix | **71/71** |
| SQL 493 entry / 497 operations / 501 privacy / 502 sessions | **42 / 19 / 14 / 13**, all complete |
| Full default operator CLI/Auth/PostgREST smoke | **154/154**, original 131 checks retained plus 23 suspension/session checks |
| Operator unit suite | **8/8** |
| Actual suspended-session lock-wait cases | **12/12** |
| Populated forward-upgrade preservation | **5/5** |
| Security advisors, explicit loopback target | Exit 0; no warning/error issues |
| Python syntax and diff whitespace | Passed |

SQL total: **338 assertions in 11 suites**, plus five upgrade assertions.
The new suite explicitly covers permitted status, appeal, own history, safe
report/block/exit/review and exact receipts; forbidden friend/personal/community
admission, valid invitation redemption, discovery and fresh privileged actions;
private peer data, independent appeal decisions and no restored membership.
It also tests an accepted tombstone while the old Auth principal, undeleted
profile and session still exist, plus ordinary account deletion, revoked and
expired sessions, missing JWT session binding and another actor's session.

The full default HTTP run uses actual Auth tokens and PostgREST. It retains the
original committed-response-loss recovery cases for review, moderation,
suspension and independent appeals, and tests both upheld and reinstated
decisions. Added checks compare active versus suspended discovery of the same
published fixture, reject join with its valid digest, and deny suspended
operators with live grants. Actual Auth logout and server-side session expiry
reject still-signed, unexpired JWTs on otherwise permitted own reads.

The session harness used a suspended fictional actor and real PostgreSQL lock
waits for detail and exact recovery: live, already expired, expiry while waiting,
still live after waiting, session deletion winning the wait, and missing session.
The elapsed-expiry cases released unchanged locked rows; expiry was observed
before release. The upgrade harness temporarily restored the baseline helper
inside a rollback-only transaction, then applied the candidate body to populated
fictional data: all **207 existing app/public tables (329 rows)**, all other
function definitions, and all function ACLs/configuration were unchanged.

**Remaining failures:** none in final requested or added checks. Earlier
baseline failures remain recorded. Local harness preparation had a Python
quoting error before SQL dispatch; it was corrected before the five upgrade
checks. Python compilation initially hit the host cache sandbox; directing its
cache to the private lab passed. These were not product-test assertion failures.

## Reproduction and resources

Private local evidence and helper sources are retained at
`/private/tmp/gametime-suspension-lab-20260919` (mode 0700). The baseline/final
HTTP logs and results, every SQL attempt, strict summary, upgrade SQL/log,
suspended session-wait helper/report and source manifest remain there. Generated
credential/environment files are removed at disposal. Committed evidence contains
no credentials, JWTs, invitation tokens or case content.

Use a fresh owned loopback PostgreSQL/Auth/PostgREST stack with cron launching
disabled from first start; apply main's complete migration chain to reproduce
the three SQL/default HTTP failures, then apply this migration. Install test-only
pgTAP as in `scripts/db-test.sh`, without invoking that reset-owning script on
another checkout's stack. Run SQL and HTTP suites sequentially:

```sh
python3 /private/tmp/gametime-suspension-lab-20260919/sql-tests.py \
  494 506 507 512 513 514 517
python3 /private/tmp/gametime-suspension-lab-20260919/sql-tests.py 493 497 501 502
python3 scripts/beta-operator-smoke.py \
  --connection-file "$PRIVATE_CONNECTION_FILE" \
  --work-dir "$NEW_PRIVATE_WORK_DIR" --evidence-dir "$NEW_PRIVATE_EVIDENCE_DIR"
python3 scripts/tests/beta-operator.test.py
```

The retained setup helper documents fresh bootstrap from cached images and
checks free ports and subnet allocation. Allocate a fresh owner and credentials
for a new run; the recorded connection file/stack are intentionally removed.
The local SQL helper expands repository fixture includes and runs container-local
`psql -v ON_ERROR_STOP=1`; every suite rolls back. A zero psql exit alone is not
acceptance: verify complete TAP output as above.

Owner: `gametime-p11a-operator-suspension-20260919`. DB/Auth/REST bound only to
`127.0.0.1:65432/65433/65434`; the owned HTTP proxy used `:65431`. Images were
cached PostgreSQL `17.6.1.143`, GoTrue `v2.192.0` and PostgREST `v14.14`.
No retained stack, credential or volume supplied fixtures. The smoke verified
owner labels and loopback-only bindings before creating fictional accounts.
[Disposition](suspended-account-access-20260919/disposition.json) records removal
of the three owned containers, data volume and network, closed ports, disabled
runtime, zero sessions, cron launching off and zero executed jobs.
The final read-only comparison found 207 pre-existing containers unchanged and
two retained account-deletion containers with concurrent metadata changes.
Neither was a cleanup target; no machine-wide unchanged-state claim is made.

This delivery changes no readiness value, source policy, P7 state, legacy
Personal/Solo/charity agreement, hosted resource, payment or schedule. Full native,
physical, human, hosted and release acceptance remain unperformed.
