# Prompt 2: unchanged local scale baseline

The actual two-hour soak passed: **72,000 of 72,000 primary operations completed inside 7,200 seconds**, with no errors, drops, recovery attempts or historical postflight failure. **The overall Beta and long-term targets did not pass.** Worker contention missed one deadline by 4.388542 ms; the 250-person join storm had 14 disconnects; the 25,000-account higher-rate attempt aborted after 175.336636458 seconds with 15 primary failures and 10,039 planned arrivals unoffered. These are retained failed characterizations, not corrected passes.

All timed attempts, observers, exact-request reconciliation, tier audits and final gates-off checks are complete. No further load or optimization was performed to erase a failure. The source/release decision owners and Firstmate's integration/review gates remain separate from this report.

## Scope and immutable identities

The product parent is **7c34d52bc0250053819e35342a2b4fd9ed5d7382**. All 72 migration files and `supabase/config.toml` retain that commit's exact bytes and file set. This Prompt2 implementation changes no app, product SQL, shared tests, migration, CI, project configuration, controller or Health-contract source. The original preparation report against 9ce9ea6 remains historical evidence; Firstmate subsequently promoted this same task to implementation on the accepted 7c34d52 parent. The branch is `fm/gametime-beta-load-prep-e2`; no moving main, stale origin/main, integration, merge, push or deployment supplied a measurement input.

| Commit | Role |
| --- | --- |
| 072c27548ff7fc6d723520570f3a3ebb372636b5 | Initial harness checkpoint; stack-creation manifest source HEAD. The first fixture corpus and harness had review findings. |
| e982622f42a1efc9a419ae7152f62c44468d0453 | Corrected product routing/identity guards, literal agreement fixtures, arrival accounting and prerequisite oracles. |
| 69a3b99a407b2a85277dedae1922776fb867875e | Corrected isolated race and burst entry points; first corrected soak launch. |
| ad5df69d7bd9e749f5073469aa5e72cf838178d9 | Completed two-hour soak launch; corrected runtime/core/fixture bytes retained. |
| 686eedcf16c33ed544375edc801e7418311f37fb | Final reviewed reporter/test correction; 27 framework-free tests passed. All 17 Python hashes in subsequent profile specs match this commit. |
| 08c0a8eff5532967db1f2fac081a7c5cb43e38f4 | Documentation checkpoint before this final evidence publication; harness unchanged. |

The initialization manifest's 072c275 source field is an initialization record, not a claim that later measured commands ran that harness. Per-window specs, core-bound preflight receipts and driver records establish executed bytes. The completed soak spec is SHA256 `59cd22d4fdc99d0ccf7e4cbcc8216e6d9f5cace24b4cf0c77e36590d4b955e36`; 2k preflight is `b9ce6cba03be078b73e4d9d68bfb0e95f4e98741df7e3b063ffc0e4c5dfb1856`; final reporter is `d1c88225316ee437715b0da784a3def5996c74e47707a1aa5458b4f0d6108b34`. A later offline reporter does not change producer provenance. Burst summaries bind their entry-point hash and core preflight instead of a complete-file profile spec. Earlier smoke did not execute the final burst/scale implementation.

The sanitized evidence bundle is [run-20260909T2230-4132](../evidence/challenge-load/run-20260909T2230-4132/README.md). Its `artifact-index.json` binds exact copied bytes and retained event-stream hashes; `SHA256SUMS` covers the publication files. `driver-receipts.json` preserves driver arguments, exit codes and output hashes. Full command receipts and the six larger event streams remain under `/Users/user/firstmate-workspace/data/gametime-beta-load-prep-e2/evidence/run-20260909T2230-4132`; private credentials and raw SQL/log output are not published. Unless otherwise specified, artifact paths below are relative to that corrected run or its matching sanitized bundle.

## Resources and environment

| Resource | Corrected retained lab | Failed first retained lab |
| --- | --- | --- |
| Run | run-20260909T2230-4132 | run-20260909T2200-4232 |
| Project | challenge-load-945c3d54dd77 | challenge-load-19707ee467e1 |
| Service ports | 41320–41329 | 42320–42329 |
| DB / gateway | 363f30d49234 / 428e34cbc948 | abe29b3bd69e / 900e72357032 |
| Auth / REST | 5f05fe937d76 / 0b7c305f7f1e | e4001e434701 / 1bd39d042a21 |

Corrected namespace: `7afe14e0-12f1-4db8-b98e-72fad4717312`; PostgreSQL system identifier: `7683666906650140710`. Every final runtime gate is false on both labs: admission, fixtures, processing, discovery, ingestion, steps, exercise, distance, timed and analytics. Actor allowlists are empty and fictional clocks are null. See `final-gates-off-v2-01.json` and `retained-first-attempt/final-gates-off-v2-01.json`. Audits were taken before this final gate change and are not gates-off receipts.

All accounts, sessions, immutable ledgers, containers, volumes, failed corpora and evidence remain retained. Optional `cleanup-sessions` was not invoked. No retained stack was reset, restarted, stopped or deleted. Only identified owned load/observer processes were interrupted in earlier partial attempts; their receipts remain. Firstmate was notified after the final audits/reconciliation/gates-off that the native quiet window could end. Subsequent work was offline reporting apart from the separately authorized rollback-only join plan below; the native quiet window was not re-held.

The measured environment is local Docker on an ARM64 Mac, 10 logical host CPUs and 32 GiB RAM. Docker reports 10 CPUs and 8,321,515,520 bytes memory. PostgreSQL 17.6 has max_connections=100, shared_buffers=16,384 8-KiB blocks, work_mem=4096 KiB, read-committed isolation, JIT enabled, track_functions=none and track_io_timing=off. Supabase CLI was 2.109.1. This shared host also served other authorized work. No hosted, dedicated-hardware, native rendering, real sign-in, Health, payment or release capacity is claimed.

## Actual fixture shapes and audits

Accounts use deterministic UUIDv5 identities within the unique namespace. Batches of 1,000 insert synthetic Auth users/sessions and age/access/readiness/profile records. Locally signed JWTs bind actual synthetic sessions and exercise REST authorization; sign-in issuance/refresh is bypassed (`scripts/challenge-load/fixtures.py:15–35`). The 25k expansion executed 23 additional batches, each roughly 15–17 seconds, and compared the old 2k historical fingerprints before publishing new live metadata and `preflight-25000.json` (`scale.py`; `tier-history-comparison.json`). Both tier preflights passed 19 checks.

History contains 4,100 constrained challenge snapshots spanning all 13 policies: four personal goals, four friend goals, four friend leaderboards and community steps. Personal historical roster size is 1; friend rosters are 2, 5 and 6; community rosters are **2, 5, 6, 50 and 100**. Roster counts include membership records after exit, not only active participants. Historical members have 120 revisions per stream including decreases, deleted and unresolved facts; valid historical age-confirmation journals accompany those facts. Reviews, resolutions, exits, reports, blocks, revoked links/redemptions and scored/void finals are represented. Bulk constrained snapshots do not demonstrate complete historical public-RPC lifecycles (`fixtures.py:37–129`, `fixture-terms.sql`, `contracts.py`).

Independent literal contract calculations check all policy agreements/allocations, 25 reopened agreements, seven nonzero integer remainders and 614 tied leaderboard cases. Live fixtures add 100 personal commitments across four metrics, 50 friend pairs, a pending friend draft with 20 actual link redemptions, one community capped at 100, operator grants and 100 expired unfrozen drafts. The capture allowlist remains 100. The join storm fills the community to its real cap. Timed writes exercise ingestion-like corrections and reports; review-resolution and participant-exit contention were not timed.

| Exact audit result | After 2k windows | After 25k attempt and reconciliation |
| --- | ---: | ---: |
| Auth users / sessions | 2,000 / 2,000 | 25,000 / 25,000 |
| Accounts with memberships | 1,850 | 1,850 |
| Historical challenges | 4,100 | 4,100 |
| Rows across 24 challenge tables | 1,844,889 | 1,989,950 |
| Fact rows | 878,088 | 878,786 |
| Request journal rows | 878,312 | 879,010 |
| Database bytes | 475,270,291 | 522,841,235 |
| Worker receipts / processed entries | 5,477 / 109,540 | 6,175 / 123,500 |
| Distinct processed challenges | 100 | 100 |
| Cancelled challenges still due / without finals | 100 / 100 | 100 / 100 |

The million-row requirement is actual challenge-related rows, chiefly facts and journals, not one million challenges. The added 23,000 accounts remain sparse: this is not a dense per-account history expansion or a day of 5,000 active users. At 2k, facts occupy 215,023,616 total relation bytes and journals 196,157,440: together 91.6667% of the 448,561,152 challenge-table total. Heap and index bytes are independently recorded; PostgreSQL total relation size contains more than just their sum. Database size also includes other schemas. The audits issue separate queries, not a single transactional snapshot (`audit.py:8–22,29–42`). Exact policy groups, fact states, revision bounds and per-table heap/index/total bytes are in `audit-{2000,25000}-v2-01/audit.json`. Their postflights passed. Final audit counts include post-window reconciliation effects.

## Timed scenarios and strict dispositions

“Completed” counts finished primary attempts, including failures; it does not mean successful business effects. Percentiles below use nearest-rank distribution. HTTP latency is separate from scheduled-arrival-to-finish latency. Inflight limits, distinct actors, logical overlap, registered users and DAU are different quantities.

| Scenario | Planned / offered / completed | Actual generator or primary span | Primary failures / drops | Peak logical overlap | Result |
| --- | --- | --- | --- | ---: | --- |
| Smoke | 20 / 20 / 20 | 10s planned, all in-window | 0 / 0 | See final analysis | Pass |
| Two-hour soak v2-02, 10/s | 72,000 / 72,000 / 72,000 | 7200.008516958s generator | 0 / 0 | 14 | Pass: every primary finished inside 7200s |
| Ramp: 60s×5, 60s×10, 120s×25 | 3,900 / 3,900 / 3,900 | 240.004554041s generator | 0 / 0 | 24 | Pass: all inside 240s |
| Spike: 30s×5, 60s×25, 30s×5 | 1,800 / 1,800 / 1,800 | 120.005501292s generator | 0 / 0 | 18 | Pass: all inside 120s |
| Foreground: 100 sessions × six calls | 600 / 600 / 600 | Last primary finish 1.305626125s | 0 / 0 | 100 | Pass |
| Worker/client contention: 120s×25 | 3,000 / 3,000 / 3,000 | 120.006875667s generator | 0 / 0 | 27 | **Fail:** only 2,999 inside 120s |
| Join: 250 distinct actors | 250 / 250 / 250 | Last primary finish 0.511586s | 14 / 0 | 250 | **Fail:** 100 admissions, 136 capacity refusals, 14 disconnects |
| 25k: 60s×25, 60s×75, 120s×150 | 24,000 / 13,961 / 13,961 | 175.336636458s, aborted | 15 / 0 | 358 | **Fail:** four unknown-commit oracles; 10,039 unoffered |

The completed soak started 2026-09-09T23:16:28.894191Z, had zero requests completing in drain, and its historical postflight passed. The 0.008516958s generator overhead is not a late request. It offered 10 primary logical operations per second, used max-inflight 100 and recorded 101 actor ordinals including operator 1999; actual peak overlap was 14. The ramp/spike full mixed-window offer rates are 16.25/s and 15/s. They are short 25/s stages, not sustained 25/s for two hours or a discovered maximum rate.

Foreground used actors 0–99, each making action, active, upcoming, history, access and catalog calls sequentially. First-call and whole-session overlaps both reached 100; first-dispatch spread was 8.447041 ms. Summary elapsed 5.551112890s includes later verification/postflight and must not replace the 1.305626125s primary span. These are synthetic RPC sessions, not 100 devices.

Worker contention has 750 each action, active, worker batch and worker status calls. Despite the generic 100 read-cohort field, its selection formula records only 25 actor ordinals (`runner.py:130–131`). Event2998 (`worker_discovery`) was scheduled at119.920000s, dispatched119.929208167s, returned200 after75.123583ms, and finished at **120.004388542s**. The strict rule in `arrivals.py:45–51` makes this a failure; no tolerance was added. In-window completed rate is24.991666667/s; including drain24.998567651/s. This single deadline-edge miss is not proof of sustained saturation.

Join first-dispatch spread was32.892958ms. Of250 primary attempts,100 returned200 and136 returned409/SQLSTATE23505 expected capacity refusals;14 returned status0/RemoteDisconnected. The cap remained100,100 winner exact replays and100 journal receipts passed, but `exactly_150_capacity_refusals=false` and driver exit1 remain. The100 winner verification calls occur outside primary event recording (`bursts.py:47–77`); summary5.379981279s includes those checks. Do not count those as primary successes or claim250 admitted members.

| HTTP population (milliseconds) | p50 | p95 | p99 | Max |
| --- | ---: | ---: | ---: | ---: |
| Soak: 72,000 successes | 5.649 | 82.405 | 360.598 | 1783.110 |
| Ramp: 3,900 successes | 5.072 | 86.743 | 336.345 | 966.995 |
| Spike: 1,800 successes | 4.728 | 82.567 | 214.516 | 827.941 |
| Foreground: 600 successes | 115.821 | 537.555 | 791.496 | 1248.595 |
| Worker: 3,000 successes including late call | 21.057 | 107.778 | 752.390 | 1347.458 |
| Join: 100 accepted | 254.136 | 335.512 | 348.140 | 348.944 |
| Join: 136 expected refusals | 428.852 | 486.549 | 493.524 | 495.751 |
| Join: 14 transport failures | 55.082 | 62.629 | 62.629 | 62.629 |
| 25k: 13,946 successes | 38.492 | 1147.989 | 2462.225 | 5675.716 |

Exact per-operation success/failure/expected-refusal HTTP and arrival-to-finish distributions, dispatch lag, first-response bytes and additional recovery counts are in each `final-analysis-v3-686eedcf.json` and `final-calculations-v1.json`. They are not replaced by this aggregate table. For comparison, selected successful-operation HTTP p95 values are:

| Operation | 2k completed soak p95 ms | 25k aborted mixed window p95 ms |
| --- | ---: | ---: |
| section_action | 10.719 | 1221.000 |
| section_active | 12.743 | 1099.874 |
| section_upcoming | 10.428 | 1274.933 |
| section_history | 13.129 | 1191.743 |
| detail | 10.366 | 1074.603 |
| catalog | 12.714 | 1234.862 |
| revision_write | 24.532 | 1358.567 |
| link_exact_retry | 17.975 | 1091.132 |
| journal_exact_retry | 14.640 | 1019.212 |
| report_write | 11.417 | 1071.731 |
| operator_reports | 22.524 | 1108.303 |
| operator_cases | 16.634 | 1120.460 |
| worker_batch | 82.984 | 1365.908 |
| worker_discovery | 178.894 | 1499.275 |

These windows differ in rate, corpus age, receipts and host state. Their differences are measurements, not a controlled account-count scaling coefficient.

## Higher-rate failure and exact unknown-outcome reconciliation

`long-term-25000-v2-01` started2026-09-10T01:40:07.734738Z; planned end was01:44:07.734738Z. All17 Python spec hashes match686eedcf. The first60s scheduled/offered1,500 operations without errors; the next60s scheduled/offered4,500 without errors. Of18,000 planned offers in the150/s stage, only7,961 were dispatched before the configured unknown-commit oracle stopped new work. Last scheduled offset was173.066666667s; dispatch ended173.075517583s. Already dispatched work finished by175.336636458s. The unperformed10,039 arrivals and remaining portion of the240-second profile are an explicit evidence gap.

There were13,961 completed primaries:13,946 successes and15 failures, with four oracle failures already included in those15. There were eight additional recorded recovery HTTP attempts, making13,969 primary-plus-recovery attempts. Another12 exact reconciliation calls happened after the timed window. The summary's58.170833333 offered/completed-in-window rate divides by the planned240s; it is not observed150/s plateau goodput. Whole actual-window completed rate, including failures and completion after abort dispatch ended, is79.623975240/s. The source `drain_seconds=0` means none finished beyond the original240s deadline; it does not imply dispatch and completion ended simultaneously. Peak logical overlap was358, not the configured1,000; recorded actor ordinals were1,001 including operator1999. Hot detail/capture actors remain100.

The15 failed primaries occurred around172.906–173.710s:11 status0/RemoteDisconnected and four HTTP500 responses without a SQLSTATE. The500 bodies were46 bytes with the same hash. The exact failed event set and payload hashes are in `post-window-reconciliation.json`:

| Failed event(s) | Exact post-window disposition |
| --- | --- |
| 13937 worker batch | Journal already1 before reconciliation and1 after; two matching200 receipts. An in-window/recovery attempt committed, but the ledger alone cannot identify which one. |
| 13957 worker batch | Before0, after1; first post-window exact retry created the receipt/effect, second replayed it. |
| 13958 capture | Actor43, no fact for request before; latest revision51. After exact retry, one matching fact at52; second replay matched. Event's service actor ordinal0 is not the target account. |
| 13959 report | Reporter80/subject81; before journal/report0/0, after1/1; first post-window retry created the effect, second replay matched. |
| 13952 exact link,13955 exact age journal | Each canonical receipt existed before and remained one after; each received two matching200 replays. Age target actor32. |
| 13936,13956 worker status;13944 detail | Failed reads without a product-data write in effective source; no business command journal to recover. |
| 13940,13960 action;13942 upcoming;13950 history | Page creation/pruning may have occurred. A generated snapshot UUID was never returned, so individual page effects cannot be attributed. |
| 13953 operator reports;13954 operator cases | Read-audit insertion may have occurred. Generated audit UUID was not returned, so individual audit effects cannot be attributed. |

All12 post-window HTTP responses were200 with pairwise stable receipts, and immutable postflight passed. Three unknown business effects were created only during reconciliation; one worker receipt already existed. Do not say all four succeeded during load, that all possible read-side metadata effects were absent, or that later success repairs the15 failures/four oracles. The conservative stop behaved as designed; this investigation found no new harness correctness defect requiring looser rules.

Join reconciliation independently reconstructed all14 disconnected request identities. Each had zero journal and zero membership rows before and after two exact retries; all28 extra HTTP calls returned409/23505. Historical postflight passed. This supports no journal/membership effect for those14 requests, not absence of every possible counter/log effect. Original14 timed transport failures remain failures. See `join-2000-v2-01/post-window-reconciliation.json` and `reconciliation-postflight.json`.

Owned gateway logs provide direct local capacity evidence. Join had one contemporaneous warning at2026-09-10 01:28:25 UTC:512 worker_connections were insufficient and connections were being reused. For the25k failure window01:42:57.734738–01:43:06.734738Z, Kong container428e34cbc948 logged one such warning and **seven alerts that512 worker_connections were insufficient while connecting upstream**, covering section, operator report, worker, capture and report endpoints at01:43:00. This is measured local gateway connection-budget exhaustion, consistent with the four primary500 and three recovery500 responses. There are no per-request correlation IDs proving a one-to-one mapping. REST logs were empty; this window did not record PGRST003 or SQLSTATE57014. See both `transport-log-signatures.json` files; raw retained logs are hash-bound and private. No gateway tuning/restart or counterfactual run was performed, and these failures do not establish PostgreSQL's maximum throughput or a hosted ceiling.

## Source-backed bottleneck inventory and plans

| Finding | Evidence | Strength and limit |
| --- | --- | --- |
| Runtime singleton serializes unrelated authenticated challenges | Effective `supabase/migrations/20260909123228_challenge_session_lock_expiry_v1.sql:11–19` locks runtime FOR UPDATE before session FOR SHARE and rechecks wall-clock expiry after that wait. Isolated `lock-proof-v2-02/proofs.json` shows905→904→runtime holder903 across unrelated actors/challenges; release permits completion. | Source-proven scope plus measured causal contention. No maximum rate or ordinary hold duration follows. |
| Session revocation wait can block unrelated runtime users | Second isolated graph911→session waiter909→revoker908. After session expiry, waiter rejects42501 and canary succeeds. Owned session1200 was restored before load. | Measured causal coupling; engineered roughly0.2s waits are not representative latency. Preserve the final expiry check in any future lock redesign. |
| Worker batch retains singleton over a pass | `20260908062409_challenge_operations_v1.sql:38–55`: runtime lock precedes exact journal replay, discovery, every tick and receipt insert. Limit20 bounds items, not elapsed lock time. | Source-proven transaction scope, measured wrapper work below. Direct per-request lock hold duration was not measured. |
| Repeated cancelled-draft work | Work eligibility at operations:8–23 excludes final/void/finals, not cancelled. Tick at `20260908050701_challenge_community_entry_v1.sql:96–100` updates cancelled unfrozen draft revision again; `20260908115825_challenge_reopened_draft_lifecycle_v1.sql:7–13` preserves that path. Audits show123,500 entries over100 distinct cancelled challenges, all outcomes cancelled, zero failed items,100 still due. | Measured repeated terminal work across retained history. Not123,500 useful transitions; not proof that other work starved, or that this caused all contention. |
| Status repeats discovery and scans accumulated worker receipts | Operations:30–34 evaluates `app.challenge_work_v1()` four times. Status plans:71.347ms/41,986 hits at2k,241.581ms/145,116 hits at25k. | Measured local query work and a concrete later reduction candidate. Status does not itself acquire the authenticated session helper's runtime lock. |
| Section first page materializes all matching IDs | `20260908054225_challenge_home_sections_v1.sql:24–44` prunes actor pages, aggregates ordered IDs then projects details. Actor/created_at page index at:8. | Source-proven growth-sensitive shape; history wrapper11.220/11.934ms at the two points does not measure a dense-history slope. Reads may write pages. |
| Operator report reads aggregate scoped history | Operations:59–66 inserts read audit, joins membership scopes and orders report aggregation. Scope fragment0.290ms/54 hits then0.735ms/410 hits/96 rows. | Potential growth risk with measured points, not evidence that report reads are presently the bottleneck. |
| Exact lookup indexes serve sampled requests | Session, request journal and link fragments use existing indexed paths; sampled timings below. Capture lookup/new revision rules at `20260908043438_challenge_steps_lifecycle_v1.sql:20–39`. | No evidence for speculative new indexes. Exact request tuple mismatch remains a conflict; a new capture request is a new revision. |
| Community and capture capability bounds | `20260908050701_challenge_community_entry_v1.sql:12–13,55` caps community publication/admission at100; steps lifecycle:6–10 caps capture actor allowlist at100. | Implemented contract limits, not measured slowness.250/10,000 admitted communities cannot be characterized unchanged. |
| Local gateway connection exhaustion | Timestamped512-worker-connection alerts,500s/disconnects and aborted25k window, as above. | Measured local transport/resource failure; no proved hosted or PostgreSQL ceiling. |

All21 corrected2k `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` captures succeeded. After the community filled,20 of21 original25k plans succeeded; join failed with `challenge_capacity`, psql exit3 and driver exit1. That failure is retained. Firstmate013 subsequently authorized the single rollback-only `join-plan-25000-v2-02`, which successfully closes the missing25k join-plan characterization. No participant was removed or capacity widened. The table records execution milliseconds and root shared hits/reads from exact JSON:

| Query | 2k ms; hits/reads | 25k ms; hits/reads |
| --- | --- | --- |
| catalog | 2.563; 1,830/0 | 2.684; 1,840/0 |
| detail_friend | 3.069; 2,211/0 | 8.863; 2,211/0 |
| detail_history | 2.964; 2,123/0 | 3.077; 2,123/0 |
| home_action | 23.481; 2,277/5 | 9.939; 2,258/1 |
| home_active | 17.381; 3,206/2 | 8.805; 3,183/5 |
| home_history_hot | 11.220; 5,484/0 | 11.934; 5,458/3 |
| home_upcoming | 4.930; 3,136/0 | 7.719; 2,950/2 |
| join | 7.464; 2,119/21 | 14.537; 1,057/27 (separate rollback fixture); original full-fixture capture failed |
| journal_exact | 0.035; 4/0 | 0.624; 2/2 |
| link_issue | 3.500; 1,611/7 | 11.332; 1,603/17 |
| link_lookup | 0.026; 4/0 | 0.028; 4/0 |
| member_latest_fact | 0.043; 8/0 | 0.051; 8/0 |
| operator_cases | 3.210; 2,120/0 | 3.892; 2,122/1 |
| operator_reports | 4.137; 1,605/42 | 7.549; 1,884/122 |
| report_scope | 0.290; 54/0 | 0.735; 410/0 |
| report_write | 2.618; 1,386/2 | 3.858; 1,386/4 |
| revision_write | 5.147; 1,119/5 | 7.251; 1,110/12 |
| session_lookup | 0.032; 5/0 | 0.062; 5/0 |
| worker_batch | 22.206; 13,752/1 | 93.013; 36,765/5 |
| worker_discovery | 17.879; 11,621/0 | 50.567; 34,690/0 |
| worker_status | 71.347; 41,986/24 | 241.581; 145,116/1,498 |

The separate25k join plan uses the unchanged100 cap, minimum2 and real frozen terms. The publisher permits only one nonterminal community (`20260908050701_challenge_community_entry_v1.sql:17`), so the single transaction temporarily marks only the existing full synthetic community cancelled, enables synthetic gates transactionally, publishes a new community through the real service RPC, and measures actor400 through the real authenticated join RPC. It verifies exactly one member, consent, slot and journal before **ROLLBACK**. No trigger is disabled. Pre/post live community row, member/consent/slot/agreement hashes, counts, namespace, cluster and full runtime JSON are identical; the new lobby/agreement/member/request rows are absent afterward; historical postflight passes and gates remain off. The driver exited0. This measures an empty available community join at25k accounts, not another storm or admission to the full community. `join-plan-25000-v2-02/plan.sql`, `driver.py`, `before.json`, `inside-transaction.json`, `join.json`, `after.json`, `rolled-back-absence.json`, `postflight.json`, `result.json` and command receipts preserve the exact bounded method. Its own window follows the completed audits; the original failure and all timed results remain unchanged.

Plans followed bulk seeding/preflight scans and were not controlled cold-cache trials. The25k plans also follow prior traffic/receipt growth and a filled community; their change is not an account-only slope. RPC wrappers expose one JSON result (`Actual Rows=1`), hiding internal PL/pgSQL plan trees; that is not a one-participant workload. Six inner fragments expose selected operators, including latest-fact, session, scope, discovery, journal and link lookups. Buffer hits count accesses rather than unique pages. No planner settings, indexes or product SQL were optimized.

## Observer coverage and attribution limits

| Timed primary window | Sample starts inside it | DB CPU median / max | Sampled Lock waiters max |
| --- | ---: | --- | ---: |
| soak-2000-v2-02 | 240 | 7.66% / 34.85% | 0 |
| ramp-2000-v2-01 | 8 | 12.56% / 23.61% | 0 |
| spike-2000-v2-01 | 4 | 1.77% / 26.89% | 0 |
| foreground-2000-v2-01 | 0 | Unmeasured | Unmeasured |
| worker-contention-2000-v2-01 | 4 | 62.63% / 66.10% | 0 |
| join-2000-v2-01 | 0 | Unmeasured | Unmeasured |
| long-term-25000-v2-01 | 6 | 43.06% / 283.91% | 6 |

Docker CPU is core-relative and can exceed100%. These are sparse sample starts, not continuous traces or per-request CPU attribution (`observe.py`; `observer-window-coverage-v1.json`). The completed soak observer has242 valid samples, no errors/Docker failures, driver duration7240.004975333s and sample span7231.426203966s;240 starts fall inside primary traffic. Whole observer host one-minute load median10.646, max90.694. Sampled PostgREST transaction age during soak peaks0.126687s; it is not lock hold time.

The Beta observer has20 valid samples, no errors, driver601.431459s and sample span570.096022s (01:18:22.313274–01:27:52.409296Z). It brackets the foreground burst but its30s cadence misses every primary. **Join starts32.760487s after the final sample: there is no join observer coverage.** No join CPU/locks may be inferred from the Beta observer. Its overall host load median9.350/max12.115 and10,194 commit/zero added rollback/zero deadlock deltas, including1,059,389,440 temporary bytes in32 files, describe the earlier observed phases plus diagnostics, not join.

The25k observer completed10 samples without errors over a300s request; six sample starts fall inside the actual aborted primary window. Those samples show DB CPU max283.91%, up to six Lock waiters and PostgREST transaction age max0.333277s. Overall host load median12.105/max15.646 includes samples before/after traffic. Four other samples and whole-observer database deltas cannot be attributed solely to the failed run. Zero sampled waiters elsewhere cannot rule out transient contention. Account/table estimates in samples do not replace exact audits.

## Retained failed attempts and harness review

| Earlier attempt | Failure classification and retained outcome |
| --- | --- |
| Original4232x `soak-2000-01` | Stopped for fixture/harness review after710.160487890s;7,102 records and163 failures:2 SQLSTATE57014,8 PGRST003 and153 RemoteDisconnected. Wrong frozen leaderboard/community terms and deliberately overlapping lock probes make this unsuitable for corrected capacity acceptance. Corpus, partial-result and owned-client-stop evidence remain. |
| Corrected4132x `soak-2000-v2-01` | Configured unknown-commit abort at1689.021404917s:16,882 offers,16,829 finished primaries,136 failures (133 PGRST003,3 SQLSTATE57014),53 drops,55,118 unoffered. Postflight passed. It is not a two-hour pass. |
| `lock-proof-v2-01` | Harness restore statement lacked a SQL terminator. Separate guarded restore repaired the owned session; failed artifact retained. Corrected v2-02 passed both causal graphs. |
| Earlier reporter/fixture/guard findings | Independent review H1–H8 required routing/identity/committed-input checks, correct literal terms, arrival/retry/oracle accounting, guarded tier publication and captured-byte/final-disposition reporting. Corrected locally within harness ownership, with failed evidence preserved. |

The failed corrected soak's worker event16617 returned initial504 then recovery504/200, triggering the conservative oracle. Post-stop exact UUID33e2c6a9-535e-5cf8-9cf2-3a213fa48b0a had one journal before/after two matching200 receipts. That reconciliation does not repair the failed timed operation or aborted duration. Its62-sample observer was interrupted only after runner exit and exact owned PID47591 verification; child exit-2/wrapper1 are retained. The observer sampled host load max765.367. An independent operational report, `/Users/user/firstmate-workspace/data/gametime-beta-candidate-review-d9/host-contention-20260909.md`, found contributing native work on a heavily compressed/swapped shared host; it did not establish a sole owner or sole cause for every failure. Firstmate coordinated the later native quiet window without deleting retained resources.

Final harness regression command was `python3 -m unittest discover -s scripts/challenge-load -p 'test_*.py' -v`:27 passed at686eedcf. Later edits are documentation/evidence only. Independent reports `prompt2-harness-review-round1.md`, `prompt2-harness-review-round2.md`, `prompt2-final-code-review.md` and `prompt2-h7-h8-review.md` under `gametime-beta-candidate-review-d9` retain findings and H1–H8 closure at686eedcf. The completed `prompt2-beta-scenarios-review.md` independently reconciled the five Beta scenarios/audit/observer, preserved worker/join failures and confirmed the observer gap and repeated cancelled work. The subsequent complete `prompt2-final-25k-review.md` independently reconciled25k accounting, expansion, all15 failures/recovery, audits and gates-off; it found the missing successful join plan, now addressed only by the separately named rollback plan above. The final candidate/export and this narrow follow-up remain subject to independent acceptance. Review of evidence is not another runtime measurement or overall capacity acceptance.

## Correctness, failure stops and retention

Nineteen prerequisite checks cover actor/session binding, agreement/consent digests, slots, bounded contiguous revisions, final field types/conservation, source gates, privacy for pending/blocked/departed actors, cross-actor denial, actor-bound cursor snapshots, exact replay, changed-payload conflict and simulated lost-receipt recovery. Ten historical groups (lobbies, members, agreements, consents, facts, notices, reviews, resolutions, exits, finals) remain fingerprint-bound; request journals are outside that immutable set. Every corrected scenario and final reconciliation/audit postflight passed those historical checks. This is scoped evidence, not universal schema/privacy verification of every HTTP200 operation.

A missing/stale preflight, source/cluster/namespace mismatch, response/structural invariant failure or unreconciled unknown mutation stops dependent work. Open arrivals expose inflight saturation/scheduler lag as drops and retain unoffered arrivals after abort. Capacity requires every planned arrival offered and finished in-window, no errors/drops/abort and passed postflight (`arrivals.py:45–51`). An operational stop also applies above50% errors after100 completions. Transport has bounded timeouts and no transparent mutation retry; two explicit exact recovery attempts are recorded. Neither later reconciliation nor successful offline report generation changes a failed source disposition (`runner.py`, `summarize.py`). There is no invented latency SLO.

The two new run roots were create-exclusive, ports were probed before binding, and namespaces/containers/PostgreSQL IDs are rechecked before operations (`lab.py:14–42,104–226`). Each SQL connection strips inherited libpq routing, supplies explicit loopback parameters and checks the owned database system identifier on that same connection. HTTP has an independent actor/session canary. Any later fresh run needs a new Firstmate allocation and new project/UUID/evidence names;4132x and4232x remain occupied. Existing Snapshot/xcresult/device resources were not used. No teardown is offered; optional scoped page/session cleanup retains accounts/history/volumes and was not run here.

## Exact file ownership and later coordination

All implementation paths are new within `scripts/challenge-load/`: `lab.py`, `fixtures.py`, `fixture-terms.sql`, `contracts.py`, `live.py`, `oracles.py`, `arrivals.py`, `runner.py`, `bursts.py`, `races.py`, `plans.py`, `scale.py`, `observe.py`, `audit.py`, `summarize.py`, `test_harness.py`, `test_bursts.py`, and `test_scale_reporting.py`. Documentation owns `docs/load/README.md` and this `capacity-report.md`; sanitized results own only `docs/evidence/challenge-load/run-20260909T2230-4132/**`. No existing source/shared-test/fixture/CI file required edits. Framework-free Health contract work has no file or semantic ownership overlap.

The narrow coordination seams are accepted product parent and exact schema/RPC payloads; unchanged agreement/replay/revocation semantics; resource port/project/namespace allocations; and scheduling measurements around shared-host native work. Local driver/fixture behavior stays in this subtree. Any future product optimization belongs to a separately reviewed product owner, not a silent harness workaround. Firstmate inbox014 now assigns exact reviewed Prompt1 HEAD64c3a8bd3640127cdb1bf5233f1f0db25dcabf56 for a normal local merge after the clean Prompt2 candidate. Measurement provenance remains7c34d52. No rebase/reset/history rewrite or runtime full gate is authorized; exact merged parents and offline verification are recorded in the task handoff.

The smallest evidence-backed follow-ups are proposals only: (1) isolate a fresh local gateway connection-budget experiment while recording the same traffic/host metrics; (2) make terminal-draft eligibility/repeated status discovery an explicit worker/query redesign candidate; (3) evaluate narrower runtime locking while preserving session revocation ordering, final expiry checks, stable actor-bound cursors, exact request receipts and frozen allocation contracts. Review source changes before comparable before/after measurements. Do not infer new indexes from the small indexed lookup plans, widen community terms, delete filled participants, or repeat a two-hour run to hide this baseline's failures. No follow-up task was created by this worker.

## Unperformed checks and handoff

The full240s25k profile, remaining150/s-stage duration and10,039 planned arrivals were genuinely unperformed after the required stop. The sample set has no join CPU/lock coverage and no sample during the foreground burst. There is no actual1,000-request peak (observed358), no day-long250/5,000-DAU test, no dense25k historical workload, and no250- or10,000-admitted-person community because the product caps it at100. Timed exit/review-resolution races, real sign-in/refresh, per-request lock-hold/CPU attribution, cold-cache scaling, native UI/Health/device, hosted capacity and release gates were not performed. No skipped characterization is a pass.

Prompt2 delivers the reusable harness and truthful unchanged local baseline, including failed required scenarios. It does not certify that Beta or long-term capacity targets passed. All owned resources remain retained with gates off. No product optimization, physical access, main landing, push, deployment or downstream implementation occurred. Only the explicitly assigned isolated branch integration is authorized after publication of this Prompt2 candidate. Firstmate owns final review, any explicitly steered integration, the fresh combined gate and guarded local landing. Existing unresolved source/physical choices remain with `gametime-beta-source-acceptance-b7`; release/legal/support/retention/publication choices remain with `gametime-beta-release-readiness-b7`. These results introduce no new captain policy choice and do not close either owner.
