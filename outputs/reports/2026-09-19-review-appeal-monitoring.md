# Local review and appeal monitoring — September 19, 2026 UTC

Branch: `codex/review-appeal-monitoring`, based on committed main
`70584f16959885b4610cd635d3e8b81e70f85f4f`. Worktree:
`/Users/user/.codex/worktrees/review-appeal-monitoring/GameTime`.
The original checkout's uncommitted iOS work was excluded.

## Projection contract

The forward [migration](../../supabase/migrations/20260919023551_challenge_local_review_status_v1.sql)
adds only `public.challenge_local_review_status_v1()`. It uses the existing
service guard, account-availability helper, domain clock and sanitized local
worker status. Explicit execute grants allow only service access; the existing
internal service guard also rejects an accidentally widened execute grant.
A fixed empty search path protects the definer needed to read private relations.
No raw-table access or private-helper grant is added.

The eleven output fields are counts, timestamps and one monitoring state.
[Sample HTTP output](review-appeal-monitoring-20260919/sample.json) is fictional:
three outstanding reviews, one without an eligible independent operator, and
two pending appeals with an eligible independent support operator. Its future
`evaluated_at` is the fixture clock; `server_time` is the actual observation time.
Neither count establishes staffed support.

- Outstanding reviews have neither a saved resolution nor a final challenge
  result. The projection preserves elapsed resolution windows until finality;
  at `now >= resolve_by`, no operator can make a fresh resolution. It reports
  the earliest existing `resolve_by`, without creating another deadline.
- Review authorization requires a current `review` grant for that challenge,
  strict `expires_at > evaluated_at`, an available account and at least one
  live Auth session. Any membership, including exited or unselected membership,
  disqualifies a reviewer. Moderator grants and grants for other challenges do
  not count. Revocation already shortens expiry; no new revocation model exists.
- Pending appeals have no saved appeal decision. Eligibility requires a current
  support grant, account and session, the still-active matching suspension, and
  a decider different from both appellant and original suspender. An unmatched
  or inactive suspension leaves its undecided appeal visible with no eligible
  decider. The output gives the oldest filing time, not an invented response due date.
- Account availability uses the existing helper, including deleted/missing Auth
  principals, profile bindings, accepted deletion and suspension. Session expiry
  uses actual server time, as the human RPC does. A live session does not prove
  a particular JWT is valid, that the person is online, or that anyone is staffed.
  Every subsequent human action still performs its own current authorization.
- Grant expiration timestamps are the earliest **currently eligible** grants for
  outstanding cases. They are null when no such grant exists. One grant expiring
  is not necessarily a loss of all independent authorization.
- Counts span saved cases even with an empty worker actor allowlist or disabled
  fixtures. `monitoring_state` is `available`, `paused`, `disabled` or
  `unavailable`; it never says healthy. Missing runtime also yields null
  eligibility counts. `available` means the local projection is enabled, not
  staffed support or worker health. RPC/transport errors remain errors.

Continue consuming `challenge_local_worker_status_v1` for worker failure,
heartbeat and pause monitoring and the existing restricted
`challenge_operations_status_v1` for overdue monitoring. Their definitions and
outputs are unchanged. The new projection does not return actor/challenge IDs,
Health facts, tokens, case text, community membership totals or restricted
failed-work JSON. It adds no case store, assignment state, queue transition,
worker, scheduler, alert, grant mutation API or CLI command.

## Performed checks

[Sanitized verification](review-appeal-monitoring-20260919/verification.json)
records exact TAP counts and log hashes. Accepted SQL output was checked for
contiguous assertion numbers, matching plans and no failures/skips/TODOs.

| Final-source check | Result |
| --- | --- |
| New 515 projection suite | 70 assertions passed |
| Actual local Auth/PostgREST authorization | 18 checks passed |
| Populated forward upgrade and read-only projection checks | 426 assertions passed |
| Existing 497 operations / overdue suite | 19 assertions passed |
| Existing 509 local worker recovery | 43 assertions passed |
| Existing 512 / 513 / 514 deletion, restore, preservation | 32 / 21 / 19 assertions passed |
| Historical 440 Personal snapshot v2 | 37 assertions passed |
| Explicit-loopback security advisor | Exit 0, “No issues found” |

Total accepted SQL: **667 assertions**. The upgrade populated historical two-
and five-person weekly agreements and consents, Personal terms, new-domain
agreements/receipts, reviews, appeals and grants before applying the migration.
It compared every existing `app`/`public` table's ordered row digest and every
prior function's definition, ACL and search path. Monitoring reads left those
rows unchanged; old own reads and saved-request replay still succeeded.

The unchanged **506 community suite is not passing**: after 50 completed
assertions it aborts with `challenge_session_required` at its suspended actor's
`challenge_access_status_v1` call (line 128). This occurred identically on a fresh
committed-main schema **before** installing the projection and on the candidate.
No existing assertion or session guard was changed to hide this failure.

Intermediate failures were test/environment issues: Docker's default network
allocation required selecting an unused subnet; subnet discovery needed to
handle networks without IPAM configuration; the HTTP helper initially shadowed
its imported module, assumed 200 instead of the existing void RPC's 204, and
passed a fictional clock when disabling fixtures (the existing API requires
null). The SQL counterfactual ACL savepoint needed a subsequent restoration
assertion so pgTAP's final plan reflected all checks. Each was corrected before
the final passes. No projection SQL behavior failure was observed.

Supabase CLI 2.109.1 created the migration file. The initial advisor attempt
could not connect with its default SSL negotiation; an explicit loopback URL
with `sslmode=disable` succeeded. The explicit-target migration list also
completed. These stacks replayed exact files with `psql -v ON_ERROR_STOP=1`,
not fabricated migration-history entries, so the list has no applied-history
rows. Catalog, behavior and populated upgrade checks establish local application.
The [Supabase changelog](https://supabase.com/changelog.md),
[explicit API grants change](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically)
and official database testing/security documentation were consulted.

## Reproduction and owned resources

Use a newly owned disposable Supabase PostgreSQL/Auth/PostgREST stack with
loopback-only bindings and cron execution disabled **from first start**. Do not
run these committed fixtures on a retained or hosted project. First initialize
Auth and replay main's full migration chain, install test-only pgTAP/dblink using
the existing test harness extension statements, then:

```sh
# Populated upgrade: begin with main's schema, before the new migration.
psql "$MONITOR_DB_URL" -X -v ON_ERROR_STOP=1 -c 'set search_path=public,extensions' \
  -f supabase/tests/fixtures/review-monitor-upgrade-before.inc
psql "$MONITOR_DB_URL" -X -1 -v ON_ERROR_STOP=1 \
  -f supabase/migrations/20260919023551_challenge_local_review_status_v1.sql
psql "$MONITOR_DB_URL" -X -v ON_ERROR_STOP=1 -c 'set search_path=public,extensions' \
  -f supabase/tests/fixtures/review-monitor-upgrade-after.inc
python3 scripts/beta-review-monitor-smoke.py \
  --connection-file "$MONITOR_PRIVATE_CONNECTION" --sample-output "$MONITOR_SAMPLE"

# Separately, use an empty owned database with the complete final migration chain.
psql "$MONITOR_CLEAN_DB_URL" -X -v ON_ERROR_STOP=1 -c 'set search_path=public,extensions' \
  -f supabase/tests/515_challenge_local_review_status.test.sql
```

A zero `psql` exit is insufficient: verify complete TAP plans and assertions as
above. The HTTP script documents its private connection fields and verifies
owner labels and exact loopback publishes before doing any fixture work.

Three new resource prefixes were used: `gametime-review-monitor-86b5087001`
(initial upgrade and harness iterations), `gametime-review-monitor-f5b4050019`
(final SQL, populated upgrade and HTTP), and `gametime-review-monitor-d21fa98c5e`
(baseline community comparison and remaining regressions). Each has its own
`-db`, `-auth`, `-rest`, `-network` and `-data` resources. Images were cached
PostgreSQL `17.6.1.147`, GoTrue `v2.195.0` and PostgREST `v14.14`. No retained dump,
credential, project or volume supplied the baseline. Private logs remain in the
matching `/tmp/<prefix>/` directories; committed evidence contains no credentials.

[Disposition](review-appeal-monitoring-20260919/disposition.json) confirms all three
stacks were closed and removed after ownership and loopback-binding checks.
Before disposal, each had closed runtime gates, zero Auth sessions, zero active
cron registrations, **zero executed jobs**, and `cron.launch_active_jobs=off`.
Only this task's labeled containers, volumes and networks were removed. The
original main checkout still has its original uncommitted paths; the review
worktree is retained with the branch for inspection.

This work does not activate schedules, send external alerts, change hosted
resources, merge a branch or establish staffing or release acceptance. Grant
mutation recovery and operator CLI work remain separate.
