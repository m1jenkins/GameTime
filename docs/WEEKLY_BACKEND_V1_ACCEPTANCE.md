# Weekly local backend v1 — implementation and acceptance

September 6, 2026. Local fictional implementation is verified as detailed below; real-source and stage-wide acceptance remain open.
All values are fictional nonredeemable fixtures. Physical source validation,
human accessibility, provider/legal clearance and pilot evidence remain missing.
The working 2–5 total friend-participant interpretation is an assumption.

## Native RPC contract

Every mutation uses an actor-bound UUID `p_request_id`; exact committed retries
recover after gate closure, pause, block or activity cutoff. Changed payloads
fail. An active current Auth session is required, including reads and recovery.
All public participant RPCs use the database wall clock; test-time seams are
private and ungranted. All new tables are private/RLS with no direct API grants.

| RPC | Arguments / result |
| --- | --- |
| `preview_weekly_friend_v1` | `p_participants` JSON `[{actor_id: UUID,target_steps: integer}]`, `p_week_start` Monday date, `p_timezone` IANA zone → `{terms,terms_digest}` |
| `create_weekly_friend_v1` | `p_request_id`, exact preview `p_terms`, `p_expected_terms_digest`, `p_consent: true` → UUID |
| `accept_weekly_v1` | `p_request_id,p_challenge_id,p_expected_terms_digest,p_consent: true` → UUID |
| `join_weekly_cohort_v1` | Same arguments as accept → UUID |
| `exit_weekly_v1` | `p_request_id,p_challenge_id,p_kind` (`decline`, `cancel`, `withdrawal`, `injury`) → UUID |
| `get_weekly_v1` | `p_challenge_id` → projection below |
| `list_my_weekly_v1` | No arguments → latest 50 own projections |
| `list_weekly_cohorts_v1` | No arguments → up to 10 currently joinable official local cohorts, common immutable terms and counts only |
| `file_weekly_review_v1` | `p_request_id,p_challenge_id,p_notice_revision,p_reason` (`wrong_total`,`source_problem`,`wrong_result`) → UUID |
| `submit_weekly_support_v1` | `p_request_id,p_challenge_id,p_reason` (`correction`,`privacy`,`unwanted_contact`,`exit_help`) → UUID |
| `set_weekly_entry_pause_v1` | `p_request_id,p_paused` → request UUID |

Projection fields: `id`, `mode` (`friend` or `community`), `status`, `terms`,
`terms_digest`, `server_now`, `participant_count`, `accepted_count`, `own`,
`roster`, `notices`, `cases`, `exits`, `support`, `result`, `allocation`.
`own` contains `actor_id,target_steps,accepted_at,declined_at,exited_at`.
`roster` is an array of friend participant receipts only; it is empty for
community and if any friend contact is blocked/deleted. Redacted `terms` retains
own target and timing/rules but replaces participants with own-only data.
`notices` contains `revision,recorded_at,file_by,resolve_by,qualification` for own
qualification only. `cases` contains own `id,notice_revision,reason,recorded_at,
resolution` (null or `upheld`/`void`). `exits` and `support` are own receipts.
`result` is null or `{recorded_at,qualification,reason}`. `allocation` is null or
`{recorded_at,returned_cents,bonus_cents,mode:"fictional_nonredeemable",redeemable:false}`.
No participant RPC publishes another person's raw source, forfeiture, review,
financial amount or community identity. Full frozen terms remain private for audit.

Fixture bounds: 2,000 example cents per accepted entry, zero fee, at most three
unsettled weekly enrollments / 6,000 example cents per actor, a single overlapping
activity week across friend/community. Prior-week review does not prohibit fresh
explicit nonoverlapping next-week consent. Limits are implementation fixtures,
not launch pricing/health/financial recommendations. Entry pause affects only new
weekly entries and never cancels existing agreements or blocks review/exit/support.

## Implemented boundaries

`20260906053958_weekly_local_v1.sql` adds only the new `app.weekly_*` domain and
its purpose-limited public RPCs plus an additive profile-deletion hook. It does
not rewrite Personal, Solo, charity, fixed-5K or performance-commitment terms,
slots, snapshots, results or settlement. Three independently controlled local
runtime switches default off: admission, fictional-source capture and worker.
There is no real-source admission switch because real-source acceptance is absent.

The service curates immutable community cohorts with a chosen local fixture target
and capacity 2–30; participants cannot curate or override a common target. Friend
terms freeze 2–5 total including creator, individual targets, exact full roster,
Monday-to-Monday IANA-calendar dates and all consents. Before taking referenced
profile locks, creation bounds its input to five actors and 32 KiB. Accepted
friendship with creator and no pairwise blocks are checked under profile locks.
The SQL calendar and exact JSON policy match W1A, including 167/169-hour DST weeks.

Upload and correction deadlines are exclusive: initial receipts must arrive
strictly before end + 24 elapsed hours; revisions strictly before end + 48 hours.
Equality is rejected consistently by SQL and W1A. Private injected-clock seams
retain all six PostgreSQL fractional digits and are ungranted to API roles.
Source fixtures assert completeness only through service RPCs. Ordinary client
refreshes enter a separate bounded progress ledger and never enter qualification.
Every corrected daily chain is append-only and can decrease totals.

A manual clock-injected worker saves provisional notices after the upload window;
any subsequently eligible source correction creates a new durable notice. Each
notice grants 48 complete elapsed hours to file and 72 further hours for an
independent resolution. Filing and resolution cutoff equality are closed. The
last notice must be saved by end + 72 hours; an absent late notice safely refunds
rather than shortening its windows. The frozen end + 216-hour cap accommodates
every permitted full window. Open cases postpone finalization, then safely refund
at timeout. Resolution is an explicit service-only fictional operation; the local
prototype does not supply a human reviewer console or real operating program.

Friend uncertainty/exit refunds all accepted entries. Community uncertainty,
withdrawal and void review refund the affected entrant before calculating the
confirmed forfeiture pool. The minimum applies to active consent at join cutoff;
after-cutoff safe withdrawal does not retroactively change the minimum. All met
returns own entries; some met adds equal integer bonuses; none met and integer
remainders remain unallocated with no recipient. Only an immutable final record
can receive one separately appended, conserved, nonredeemable allocation.
A full snapshot/version comparison rejects stale worker decisions across source,
consent, exit, deletion, notice, case, resolution or final-result changes. Clock
boundary crossing during evaluation requests fresh input. Final/settlement
interruption recovers without changing final results or duplicating allocation.

All participant operations require a current active Auth session. Profile,
session, runtime and agreement locks coordinate with existing friendship/block
and deletion boundaries. The session is revalidated after downstream blocking
locks so expiry during a wait cannot authorize a late mutation. Safe exits,
reviews, private support and exact recovery remain usable when entry closes or
pauses. Contact blocks/deletion hide other-person terms/name/roster content at
read time and retain private own history. Source documents, peer health, peer
review and peer financial returns are never in participant projections.

## Recovery, display and optional research additions

`resolve_weekly_request_v1(p_request_id)` returns either
`{state:"committed",receipt_id:UUID}` or `{state:"cancelled",receipt_id:null}`.
Under the same actor lock, an absent request key receives a durable retirement
marker. A delayed original call can no longer commit that key. This lets the
native client safely resolve uncertainty instead of trapping reviews and exits
behind an indefinitely retrying draft. Existing committed receipts are retained.

`get_weekly_preferences_v1()` returns `{entry_paused,pilot_consent}`.
`record_weekly_progress_v1(p_request_id,p_challenge_id,p_day,p_steps)` records
nonauthoritative display progress only. `own_progress` reports `observed_steps`,
`qualifying_steps`, `complete_day_count`, `updated_at` and `status`. Qualification
is present only from service fixtures (`fixture_only`); ordinary refresh totals
are `client_progress_only`. Neither is a final result. Authorized friend roster
rows also include `display_name`; community and suppressed contacts expose none.

Optional research collection defaults off and requires an explicit separate
`set_weekly_pilot_consent_v1(p_request_id,p_enabled)` request. Its event RPC accepts
only the fixed event categories (`rule_preview`, `consent`, `invitation`,
`cohort_join`, `progress_refresh`, `result_view`, `review`, `withdrawal`,
`next_week`, `sharing`) and phase (`intent`, `exposure`, `outcome`). No free text,
health value, amount, arbitrary metadata or notification is accepted. These are
local support for future descriptive research, not recruited participants or
pilot evidence. Revocation/deletion erases event rows and replaces reconstructible
retry payloads with a constant retirement marker containing no event, phase,
challenge or hash. An erased event key returns `weekly_request_retired`, never
recreates optional data. Other non-research exact requests retain their history.

## Verification actually run

| Check | Recorded result |
| --- | --- |
| Focused SQL roles/consent/2–5/calendar/overlap/privacy/recovery | 72 pgTAP assertions passed on disposable port 56322 |
| Pure lifecycle scenarios and bounded worker recovery | 18 Deno tests passed |
| Persisted SQL → real W1A/helper → worker → final/allocation | Passed rollback-only smoke: corrected notices and microseconds, full review timeout, 2/3/4/5 groups, community partial success/unknown/remainder, 0/1 minimum, final retry and delayed-worker refund |
| Deno lifecycle/runner format, lint and typecheck | Passed |
| Real independent-session concurrency | 25 assertions passed, including 12 races proven blocked with `pg_blocking_pids` and selected-sharing revoke/read |
| Explicit selected-friend sharing | 41 pgTAP assertions passed: bilateral consent, fresh offer binding, revoke/decline/unfollow, no block/refriend revival, missing versus zero, exact selected-week expiry before/at/after the microsecond cutoff, preserved receipts/safe revocation, private-only clock seams and no enrollment/qualification/financial projection |
| Full fresh-migration regression/advisors/native integration | Lead integration owns final evidence; integrated Deno 833 tests passed before final fresh replay/native verification |

Reproduce in a disposable local stack, preserving the normal developer stack:

```sh
psql "$WEEKLY_DISPOSABLE_DB_URL" -X -v ON_ERROR_STOP=1 \
  -f supabase/tests/480_weekly_backend.test.sql \
  -f supabase/tests/481_weekly_concurrency.test.sql
deno test --config supabase/functions/deno.json \
  supabase/functions/_shared/weekly-lifecycle.test.ts
deno run --config supabase/functions/deno.json --allow-run=psql \
  --allow-read=supabase/tests/fixtures scripts/weekly-lifecycle-local-smoke.ts 56322
```

The operational runner is explicit-ID and loopback-only, performs no discovery
scan or scheduling, rejects redirects and never prints its service key:

```sh
deno run --config supabase/functions/deno.json \
  --allow-env=WEEKLY_LOCAL_URL,WEEKLY_LOCAL_SERVICE_ROLE_KEY \
  --allow-net=127.0.0.1:56321 scripts/weekly-lifecycle-local-worker.ts <weekly-uuid>
```

`WEEKLY_LOCAL_URL` defaults to `http://127.0.0.1:56321`; intentionally enable only
the required local gates, provide the disposable local service key, then close
gates after the exercise. No external delivery, hosted mutation, recruitment,
payment provider, live funds or notification has been enabled.

## Remaining acceptance gates

W1B and W2 are **not fully accepted**. Physical iPhone/Watch source evidence,
actual source completeness/confirmed-miss suitability, human accessibility and
comprehension, human review/support operations, live retention clearance and the
separately authorized pilot are unperformed. The common launch target is open;
63000/70000 and all simulated amounts/caps in tests are explicit fixtures. Live
fees, recipient, financial limits, jurisdiction and provider/legal clearance
remain unselected. Keep real-source admission, distribution, hosted workers,
notifications and money disabled until their respective evidence is completed.


## Selected display progress: separately consented local adaptation

The additional `20260906062952_weekly_display_sharing_v1.sql` implements a
bounded `weekly-display-sharing-v1` permission for either weekly format. An
owner deliberately offers display-only progress to a named accepted friend;
the recipient explicitly accepts before anything appears in their followed
progress. Pending requests are a separate private inbox. No view enrolls,
accepts a challenge, reveals the community roster or exposes raw source,
qualification, result, simulated amounts or review data.

`set_weekly_sharing_v1(p_request_id,p_challenge_id,p_friend_id,p_enabled)`
creates a fresh pending `offer_id` or safely disables the owner's grant.
`list_weekly_sharing_v1(p_challenge_id)` lists permitted recipients and current
state for the owner. `list_weekly_follow_requests_v1()` lists the recipient's
pending offers. `respond_weekly_follow_v1(p_request_id,p_challenge_id,p_owner_id,
p_offer_id,p_decision)` accepts, declines or unfollows one exact offer.
`list_shared_weekly_progress_v1()` returns only currently accepted bilateral
sharing with `offer_id`, owner name, target/window and ordinary display progress.
Absent observations are null, never inferred zero. No fixture qualification is
reused as follower display progress.

At most five recipients can be enabled for one owner/agreement. Decline/unfollow
prevents repeated offers for that same agreement. Either person can end sharing
while entry is closed. Blocking, unfriending or deleting either actor permanently
ends the old grant. Unblocking or refriending does not revive it: a fresh owner
offer and fresh recipient acceptance are required. Current friendship, blocks,
active accounts and Auth session are checked on every read. Bilateral profile
locks serialize consent/revocation with reads and the social/deletion hooks.

The native fixture-history helper `scripts/weekly-native-lifecycle-seed.ts`
accepts two existing disposable actor UUIDs and creates three prior-week
agreements using temporary fixture sessions. It drives the real evaluator and
worker through notices and a saved review/full timeout, appends final simulated
returns, restores the caller's gate settings and revokes its temporary sessions.
It returns IDs for native authenticated HTTP history decoding and an exact saved
review-request replay. The initial invocation deliberately leaves `reviewID` in persisted `review`
status after the real worker, allowing a native HTTP review-state read. The
controller then appends `finalize <reviewID> <reviewRequestID>` to the same
actor-scoped command. That second phase validates the exact actors and saved
case, then drives the real worker after the maximum stored correction/review
window. It restores pending-entry capacity before the native two/five/community
flow. This phased helper is format/type checked; native HTTP execution evidence
is owned by the native acceptance record.

The shared rollback fixture is canonical at `supabase/tests/fixtures/weekly-fixture.inc`.
Both pgTAP includes and the persisted Deno smoke read that one file. Its non-test
extension prevents pg_prove from treating setup as a separate test, and keeping it
inside the test tree makes it available to the Supabase CLI database test runner.

The additive `20260906065002_weekly_sharing_expiry_v1.sql` enforces the selected
week's exclusive end using the server clock. New offers and acceptances fail at
`endsAt`; pending offers and accepted display progress disappear at that same
instant, and the owner list reports an ended grant. Exact committed recovery,
owner revocation, and recipient decline/unfollow remain safe after expiry.
Private injected-time functions have no client/service grants. Focused 482
passed 41 assertions in `/tmp/gametime-weekly-482-expiry.log`, including final
eligible microsecond, exact end and one microsecond after for all four paths.
