# W1A — fictional weekly steps qualification

September 6, 2026. **Implemented and verified as a pure fictional policy slice.**
This record does not accept a playable weekly mode, Apple source, database
lifecycle, native journey, pilot or real-money product. The owner's broader
W1–W4 execution request permits dependent local development; its external
acceptance requirements remain in force.

## Delivered contract

- [Policy and evaluator](../supabase/functions/_shared/weekly-steps.ts):
  `weekly-friend-steps-fixture-v1`, implementation
  `weekly-steps-qualification-v1`, source `fixture_weekly_steps_v1`.
- [Colocated fictional fixtures and tests](../supabase/functions/_shared/weekly-steps.test.ts)
  follow the existing `_shared/*.test.ts` discovery convention.
- `evaluateWeeklySteps` requires the agreement, every matching explicit
  consent, complete revision ledgers and an injected clock. It returns
  participant `pending`, `met`, `confirmed_miss` or `unresolved`, aggregate
  group qualification and **`final: false` in every case**. No notice,
  published result, review decision or allocation is created here.
- `evaluateWeeklyParticipant` shares the exact daily qualification primitive
  with a separately validated community contract. It validates participant,
  agreement/digest/policy/source bindings, dates, values, revision chains and
  cutoff rules; the community caller must separately validate its immutable
  calendar, roster, common target and every consent. The friend entry point
  still rejects any roster outside 2–5.

The evaluator imports no old evaluator or platform dependency and has no I/O,
ambient clock, mutation, health-client API or financial command. Existing
Personal, Solo, charity and official-5K policies and tests are unchanged.

## Frozen terms and trust boundary

The frozen roster includes the creator and each participant's positive whole
step target. **Two to five total, including the creator, remains the explicit
unconfirmed interpretation of D132.** Different individual friend targets are
a provisional policy; no participant has to exercise daily or run 5K.

Seven consecutive Monday-through-Sunday dates bind exact local-midnight start
and exclusive-end instants in one named IANA zone. The evaluator validates
those boundaries against the supplied zone, permits DST's 167/169-hour weeks,
and rejects travel changing that calendar. Unusual transitions outside
22–26-hour local days are conservatively unsupported by this fixture version.
Timestamps retain all six PostgreSQL fractional digits, including consent and
revision receipts. Equivalent explicit UTC offsets compare as the same instant.

Every consent binds agreement ID, participant ID, policy version, digest and
the full canonical terms string from `weeklyStepsConsentBinding`. That string
detects a changed roster/target/window even if a caller leaves the digest stale.
It is a deterministic key-sorted JSON serialization, **not a signature or
authentication token**. JSONB text with spaces is not the same serialization.
Database callers must produce the specified binding and establish actor,
consent, immutable terms and snapshot authority independently.

The full terms also bind the W1B fictional lifecycle handoff: initial uploads
strictly before end +24 elapsed hours; corrections strictly before end +48;
notice by end +72; a full 48-hour filing and 72-hour resolution window; and
finality cap at end +216 hours. These are coordinated reversible fixture
defaults, selected for weekly development. They do not inherit organizer
timelines or approve launch deadlines. The evaluator validates these terms but
does not establish that any required notice/review actually happened.

The fixture uses 2,000 nonredeemable example cents each and zero fee. Safe exits
and unresolved friend proof bind no-loss group-void rules. The combined
`void_friend_refund_community_v1` handoff and private fictional retention label
are versioned local simulation rules, not selected live recipients or a
real-data retention period. W1B owns their operational implementation.

Targets accept 1–1,000,000 whole steps; daily values accept 0–1,000,000 whole
steps; each person/date accepts at most 128 numbered revisions. These are
**fixture validation bounds, not health advice or recommended targets**.
The largest weekly aggregate remains a safe integer. No numeric community
launch target is selected by these tests.

## Observation and qualification rules

Each participant/date has a contiguous revision chain starting at one, with
an explicit predecessor and nondecreasing receipt instants. Input row order
does not affect the result. A latest downward or revoked revision replaces the
previous observation; older successful totals are never permanently retained.

| Current facts | Qualification |
| --- | --- |
| Complete daily observations already sum to at least the agreed cumulative target | Provisional `met`, even if other dates lack observations |
| Below target while initial uploads remain open | `pending` |
| Below target at/after upload cutoff with all seven latest observations complete | Provisional `confirmed_miss`, still requiring operational correction/review |
| Below target with any absent, incomplete, revoked or failed-query date after cutoff | `unresolved`, never a miss |
| Incomplete observation with a numeric total | Display-only progress; never qualifying proof or proof of a miss |
| Explicit complete zero after that day's end | Usable zero; distinguish from a missing observation |
| A complete observation before the entire day ends | Invalid snapshot |
| Initial revision received exactly at/after upload cutoff | Excluded and counted as late |
| A later revision of a late initial snapshot | Also excluded; cannot launder late initial proof into a correction |
| Correction exactly at/after correction cutoff | Excluded and counted as late; prior admitted snapshot remains the candidate |

A partial known total below target never implies failure. `complete` is an
authoritative assertion **only within fictional fixtures or an independently
authorized fictional server source**. A permission prompt, successful empty
query, device claim or user-supplied boolean cannot grant it. The pure function
does not authenticate a source or prove the caller supplied the entire ledger.

Group qualification is `all_met`, `some_met` or `none_met` only when every
participant is individually resolved; otherwise it remains `pending` or
`unresolved`. These group decisions contain no simulated allocation. Privacy
projection and participant access remain the caller's responsibility: the
private decision includes individual totals and must not become public or
cohort-wide merely because evaluation succeeded.

## Verification actually run

From `supabase/functions` in the isolated integration checkout:

```sh
deno fmt --check _shared/weekly-steps.ts _shared/weekly-steps.test.ts
deno lint _shared/weekly-steps.ts _shared/weekly-steps.test.ts
deno check _shared/weekly-steps.ts _shared/weekly-steps.test.ts
deno test _shared/weekly-steps.test.ts
deno test --allow-env
git diff --check
```

| Check | Result on September 6 |
| --- | --- |
| W1A pure tests, no runtime permissions | 162 passed, 0 failed |
| Focused formatting, lint and type check | Passed |
| Full Deno regression suite at W1A handoff | 775 passed, 0 failed, including unchanged existing scorer/Personal handler suites |
| Diff whitespace check | Passed |

The matrix covers all 60 possible success subsets across roster sizes 2, 3,
4 and 5, including every sole success, multiple successes, everyone met and
everyone missed. It also covers capacity violations, changed/duplicate rosters,
unequal and boundary targets, missing/stale/duplicate/wrong consents, upward and
downward corrections, missing/incomplete/revoked/failed/zero observations,
microsecond cutoff equality, DST, travel, malformed dates/units/values/ledgers,
replay/input immutability, protected outputs and separate community-helper
bindings. The helper never admits a six-person friend agreement.

Current [Supabase pure-function testing guidance](https://supabase.com/docs/guides/functions/unit-test)
and the [changelog](https://supabase.com/changelog.md) were checked. This
import-free policy adds no Supabase API or dependency whose behavior changes.

No database reset, pgTAP, native build, human accessibility traversal, physical
device test or pilot was performed **for W1A**; those checks do not follow from
these TypeScript results. Later integrated runs may have larger suite counts
and are recorded with their own slice evidence.

## W1B handoff and remaining gates

Persist immutable weekly agreements and canonical consents with new private
request/participant/observation/lifecycle boundaries. Require active actors,
exact retries, accepted friendships, actor-ordered locking and default-off
local admission. Server fictional observation authority must be independent
of client `complete` claims. Snapshot all relevant ledgers consistently before
evaluating; compare that exact snapshot before committing a candidate result.

Preserve the full filing/resolution windows even when notices are delayed,
corrections arrive, week two starts, or the cap is reached. An incomplete
window or unresolved case cannot produce a miss. W1B must append immutable
final results and a separate idempotent simulation, and implement retained
history/reviews/safe exits while admission is off or paused. W1C must verify
two- and five-participant native journeys and account/privacy recovery.

Keep an actual step source disabled until physical iPhone/Watch testing records
manual entries, third-party writers, overlap/deduplication, deletion/downward
edits, late sync, locked/offline queries, permission loss and travel, with an
explicit account of what could establish a miss. Missing that evidence blocks
real-source admission, not independent fictional implementation. Human
accessibility, comprehension, pilot evidence, hosted rollout and provider/legal
clearance remain distinct unperformed gates.
