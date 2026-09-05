# Reviewed checkpoint before Phase 3(d)

September 5, 2026. This review checkpoints the existing local implementation
through Phase 3(c). It does not implement following, reactions, reminders,
report/support flows or any other Phase 3(d) feature.

## Inventory and scope

The initial recheck found **35 modified tracked files and 333 untracked files**,
with no staged changes. The prior head was `c403b88` (September 3, 2026).
The counts matched the earlier assessment; they were freshly measured.

| Initial changes | Files | Disposition |
| --- | ---: | --- |
| Product implementation and native configuration | 35 | Reviewed checkpoint |
| Tests and intentional fictional fixtures | 29 | Reviewed checkpoint |
| Documentation and project guidance | 37 | Reviewed checkpoint |
| Local test runners and SQL examples | 14 | Required verification support; checkpoint |
| Installed skills and `skills-lock.json` | 118 | Preserve, leave uncommitted |
| `.ua/.trash-1788470932/` generated analysis/trash | 135 | Preserve, leave uncommitted |

The native JSON fixtures are deliberate DTO/evaluator inputs. They are not
accidental output. Generated analysis, installed skills and their lockfile
are unrelated to the product checkpoint. No untracked file was deleted.
The prior plan remains verbatim beneath its archive header. Existing migration
files were preserved; fixes use a new forward migration. Ten retained database
test files received only the connection portability correction described below.

Four read-only review roles examined intent/regressions, security/privacy,
reliability, and contracts/coverage. The primary review checked the findings,
fixed narrow defects, ran verification and inspected the staged content.

## Findings and fixes

1. **Rematch/link session expiry during waits.** The original Phase 2(e) methods
   checked the session before potentially blocking admission/agreement locks.
   A wait could outlast session expiry. The forward checkpoint migration locks
   the matching session after sorted pair locks and rechecks expiry after later
   waits. Reads, new writes and exact recovery retain their existing actor and
   recipient boundaries. Observed transaction races cover rematch expiry, link
   expiry, commit versus session revocation, and denied recovery after revocation.
2. **Performance source/evaluator mismatch.** Capture accepted PostgreSQL-only
   timestamp spellings, absent offsets, excess fractional precision and numeric
   JSON bibs that the strict evaluator could not consume consistently. New
   sources now require the evaluator's timestamp spelling/precision and bib
   types. Existing exact source recovery stays before validation and original
   documents remain immutable. A correction must append a new source/revision.
   SQL regressions reject malformed input, retain old exact replay and accept
   explicit UTC offsets with microseconds. The persisted smoke evaluates that
   accepted offset representation through actual capture, retrieval and review.
3. **Unused evaluator history maps.** Per-revision copies of the latest-attempt
   map were retained only to count admitted revisions. A counter and the current
   map preserve behavior and avoid unnecessary history allocation. No shared
   scoring framework or policy rewrite was introduced.
4. **Test connections assumed one container.** Dblink connections now derive
   their host from `host(inet_server_addr())`, preserving password authentication
   and targeting the executing stack. Rollback-only SQL examples and four Deno
   smoke runners accept a validated optional local database port; their host
   stays loopback. This permits verification without resetting other work.
5. **Stale current-state summaries.** README, PLAN, business-model/copy summaries
   and the affected acceptance follow-ups now distinguish the implemented local
   slices from their historical planning baseline. Original acceptance counts
   remain historical evidence.

## Reviewed boundaries and remaining limitations

- Commitment agreement, attempt and progress APIs require the active owner and
  a matching unexpired session. Reviewer grants/revocations are server-owned;
  private sources require independent authorization and audited retrieval.
- Sorted actor locking, session checks after waits, immutable consent, exact
  request identity, separate open slots and retained closure/deletion behavior
  remain intact. Manual progress uses bounded sequence pages with milestone
  states frozen at the same upper sequence.
- Progress stays owner-only and absent from organizer proof and scoring input.
  A claimed time, completion or reaction cannot qualify an attempt or confirm
  completeness. No friend or future follower gains raw notes, request payloads,
  proof or financial details through the existing owner projection.
- Existing friendships/blocks and tombstoned identities are reusable patterns,
  not an implemented following permission. Phase 3(d) must explicitly select
  shareable fields and serialize grants/revocation, reads, blocks and deletion;
  cache invalidation must also cover account changes and failed authorization.
- **Retained Phase 1 limitation:** original duel agreement create/respond/read
  APIs and agreement RLS check the active profile, not a current Auth session.
  A revoked session's unexpired JWT can still access that original agreement
  boundary. Earlier acceptance explicitly retained this behavior. This review
  does not broaden that old contract; do not copy it into Phase 3(d). Tighten it
  in a separate forward change before hosted duel operation.
- Native duel history currently reloads accumulated lifecycle rows serially;
  the event catalog takes an unordered first 100 immutable rows. These local
  scale limitations remain follow-up work before a growing hosted catalog.
- Product-specific attempt/progress retention holds preserve local fictional
  records after closure/deletion. Real-note/proof retention durations, release,
  purge and post-closure support access are not approved or implemented.
- Personal/Solo/charity terms and behavior remain covered by regression tests.
  Default-off gates, Release route exclusion and nonredeemable simulation remain
  required. No hosted mutation, external message, provider operation or money
  was enabled.

## Fresh verification

The normal development database was inspected read-only and preserved. All
reset-based work used `/tmp/gametime-phase3d-checkpoint`, a source snapshot with
only its Supabase project identity, ports (`5532x`) and unused Apple provider
configuration changed. Reviewed portable source files were hash-compared with
that snapshot. No verification reset targeted the normal stack.

| Check | Fresh result |
| --- | --- |
| `scripts/test-all.sh` in isolated stack | PASS: 65 SQL files / 3,005 assertions; Deno install/format/lint/check and 613 tests; Swift build and 103 tests |
| Focused link concurrency | PASS: 15 assertions, including seven observed waits |
| Source regression before fix | Four malformed-source checks failed as expected; retained row counts consequently also failed |
| Source regression after fix | PASS within full suite: 75 assertions |
| Local schema lint | PASS, no errors/warnings (`--fail-on warning`) |
| Security/performance advisors | PASS, no warning/error issues (`--fail-on warn`) |
| Persisted SQL smokes | PASS: duel proof, lifecycle/scorer/worker, commitment attempts, manual-progress isolation |
| Agreement examples | PASS: duel and performance commitment, including gate-off recovery; rolled back |
| Changed smoke scripts | Format/lint/type checks and shell syntax passed |
| Beta preflight fixtures and Personal copy audit | PASS |
| Native product Debug unit/UI | PASS: 331 passed, zero failed, one skipped; includes 290 unit and 41 UI passes |
| Staging / Release simulator builds | PASS: both configurations; compiled Staging registers `gametime-duel`, Release does not and contains neither duel home nor invitation view symbols |
| Conformance simulator tests | PASS: 10 passed, zero failed/skipped |

Native tests used **Xcode 27.0 (27A5237l)** and iPhone 17e / **iOS 26.5**.
The pinned CI Xcode 26.2 / iOS 26.2 matrix was unavailable and was not reproduced.
The one skipped test is the opt-in authenticated native HTTP smoke: its fixed
API/controller ports target the preserved normal stack. Previous HTTP evidence
remains historical; this checkpoint does not claim a fresh HTTP run. VoiceOver,
physical devices, real organizers and months of operation remain unverified.

The product result bundle reports eight SwiftUI runtime warnings about invalid
frame dimensions, with zero test failures. Their cause is unresolved; they are
not counted as clean runtime-warning evidence. The native tool timed out at
300 seconds while Xcode continued; the completed `.xcresult` independently
reports `Passed`, and the log ends with `TEST EXECUTE SUCCEEDED`.

The first isolated full run failed because a loopback dblink connection bypassed
password authentication and the scorer had been formatted without its Deno
configuration. An intermediate address needed its network-mask suffix removed.
Those harness defects were corrected before the passing full run above. No
failed run is counted as passing evidence.

Logs: `/tmp/gametime-phase3d-{portable,link-races,regression-before,lint,advisors}.log`
and `/tmp/gametime-phase3d-{proof,lifecycle,attempt,progress}-smoke.log`.
Product native result:
`~/Library/Developer/XcodeBuildMCP/workspaces/GameTime-7b9ccaa5aefb/result-bundles/test_sim_2026-09-05T21-47-57-225Z_pid76321_544d48df.xcresult`.
Conformance result in the same directory:
`test_sim_2026-09-05T22-31-44-237Z_pid76321_68d21a29.xcresult`.
Staging and Release build logs in that workspace's `logs` directory:
`build_sim_2026-09-05T22-29-44-883Z_pid76321_a035f066.log` and
`build_sim_2026-09-05T22-34-42-768Z_pid76321_1641a81f.log`.
The disposable database finished with all six new-product gates off, zero open
duel/commitment slots, zero sessions, zero attempt sources and zero progress
entries. The forward fix is verified there; it was not applied to the preserved
normal development database. Only the disposable checkpoint stack was then
stopped and its test data volumes removed.

Official [function permissions](https://supabase.com/docs/guides/database/functions),
[RLS guidance](https://supabase.com/docs/guides/database/postgres/row-level-security),
[Supabase changelog](https://supabase.com/changelog.md),
[dblink authentication](https://www.postgresql.org/docs/current/contrib-dblink-connect.html)
and [network address functions](https://www.postgresql.org/docs/current/functions-net.html)
were consulted. No dependency or platform upgrade was required.

## Handoff

Phase 3(d) can begin as local, default-off implementation after selecting a
local stack with the checkpoint migration applied. Its existing handoff in
[progress acceptance](PERFORMANCE_PROGRESS_V1_ACCEPTANCE.md#phase-3d-handoff)
remains the scope: explicit opt-in following, selected-progress projections,
revocation and the planned interaction/report/block/support boundaries.
Define that sharing contract before exposing data. Native commitment screens,
Phase 3(e) result/review persistence, real retention/organizer operations and
hosted/live-money clearance remain separate work. Phase 3(d) was not started.
