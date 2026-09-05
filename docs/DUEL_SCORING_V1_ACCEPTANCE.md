# Phase 2(a) — pure simulated official-result evaluator

September 4, 2026. Phase 1A and Phase 1B's local acceptance records satisfy the
dependency for starting Phase 2. This completes **slice (a) only**, the pure
evaluator and fictional fixture matrix. Phase 2 as a whole remains in progress.

## Delivered

- [Evaluator](../supabase/functions/_shared/duel_scoring.ts), version
  `duel-fixture-official-5k-v1`, accepts only the existing
  `duel-fixture-5k-v1` agreement and its exact immutable policy specification.
- [Fictional fixture corpus](../supabase/functions/_test/duel_scoring_fixtures.ts)
  uses the [captured Phase 1B agreement](../ios/GameTime/GameTimeTests/Fixtures/duel-agreement-v1.json).
  This tests the actual RPC terms, microsecond timestamps and consent bindings,
  rather than a separately invented agreement format.
- [Deno tests](../supabase/functions/_shared/duel_scoring.test.ts) cover the rule
  matrix, invalid snapshots, privacy of returned fields, deterministic replay,
  input ordering, DST/leap dates, corrections and exact deadline boundaries.

The evaluator has no imports, I/O, ambient clock or financial command. It does
not call the legacy charity scorer. No database migration, RPC, handler,
operator grant, scheduler, notification dispatch or native screen was added.
Existing agreements and pre-existing working-tree changes were preserved.
Hosted admission, Release routing and live money remain closed.

## Input and result contract

`evaluateDuel(input)` consumes one complete private snapshot: the agreement and
both matching consents, an explicit clock, the full proof revision chain,
durable notices, review cases, an optional authorized closure, and an optional
persisted final result. Empty ledgers and absent closure/final result must be
explicit. The database terms digest is carried verbatim and checked against
both consents; JavaScript does not recompute PostgreSQL's JSONB digest.

The future caller must obtain these records under the database's authorization
and consistency rules. Reviewer IDs, confirmed identity, source references and
receipt times in an ordinary request body confer no authority. This pure module
can reject inconsistent facts and self-review; it cannot verify a reviewer's
role, authenticate an organizer source, enforce append-only storage or prove
that the caller supplied the complete history. Those are Phase 2(b/c) gates.

Each numbered proof revision replaces the **complete pair's snapshot**, with
exactly one record per named runner and an explicit missing/ambiguous state
where appropriate. Revisions form one contiguous predecessor chain and carry
server receipt times plus an independent reviewer's identity. A correction must
not discard the other runner's proof or silently fall back to older valid data.
Source reference and bib mapping remain private inputs.

The decision contains only its implementation version, agreement ID/digest,
proof revision number, phase, outcome, deadlines and a support-correction flag.
It returns no bib, organizer reference, reviewer identity, raw timing record or
payment field. A future participant RPC must still authorize and project these
fields; the pure function is not an access-control boundary.

`ready_to_finalize` is a decision for a future worker. It neither persists a
result nor releases a participation slot. A final result must be appended
separately from any nonredeemable simulated settlement event. There is no
balance, payout, fee assessment or value-conservation ledger in this slice.

## Rules implemented

| Facts | Decision |
| --- | --- |
| Matching accepted pair before start / during event | Scheduled / active; no outcome |
| Two independently reviewed valid finishes | Lower published whole-second chip time wins; exact equality ties |
| One finish and independently confirmed DNS, DNF or disqualification | Finisher is the provisional winner, subject to notices and review |
| Two confirmed nonfinishes | Provisional void, no winner |
| Missing/ambiguous identity, wrong/duplicate bib, event/course/wave mismatch, incompatible source/distance/timing/precision | Await proof through the cutoff; unresolved proof becomes a void candidate, never a loss |
| Fractional, zero, negative, nonnumeric, unsafe or event-window-exceeding chip time | Unresolved proof; no rounding or alternate timing basis |
| Accepted runner withdraws before start / at or after start | Zero-consequence void / `withdrawn_no_contest` |
| Injury, event cancellation or participant deletion before the cap | Zero-consequence void; no medical input |
| Independent review voids the contest or misses its deadline | Void; ordinary finalization still waits for the dispute deadline |
| Corrected proof before finality | New provisional evaluation; both runners need new durable notices |
| Seven full days or an open review cannot finish by the cap | Void at the cap; no shortened correction window |
| Persisted final result plus later correction | Return the original final outcome and flag an audited support case |

Decline, invitation expiry and cancellation of an unaccepted invitation remain
Phase 1A operations. The evaluator requires two consents and does not reinterpret
those histories. Blocking alone is not an outcome event. Access revocation,
deletion races, review-role grants and contact suppression still need their
Phase 2 database/native integration.

### Exact time and revision conventions

These are local implementation choices within the frozen simulated policy;
they do not approve a human-organizer source or funded contract.

- Initial proof must be received strictly before event end + 72 elapsed hours.
  Equality is late. A correction requires an initial snapshot admitted before
  that cutoff and must arrive strictly before end + 720 elapsed hours.
  Late initial proof cannot enter by labelling a later append a correction;
  it flags support without selecting a winner. Missing data may be represented
  explicitly in an admitted initial snapshot and corrected later.
- A revision becomes a provisional candidate after the event ends when its
  proof is complete, or at the proof cutoff if unresolved. Notice records bind
  to that revision. Revision zero denotes no admitted proof at the cutoff.
  Old notices cannot be newly issued after a correction.
- Both people receive a common dispute deadline anchored to the **later** of
  their durable in-app notices + 168 elapsed hours. Missing either notice
  prevents ordinary finalization. Push delivery status is not an input.
- A runner can file after their own notice, strictly before the dispute
  deadline and the hard cap. A case must resolve strictly before filing + 168
  hours and the cap. Equality triggers timeout. Early resolution never shortens
  the filing window. Cases against earlier revisions remain in the ledger and
  can still pause or void a corrected result.
- At the cap, an otherwise completed review window permits the existing
  outcome; unresolved windows void. A post-cap withdrawal cannot change the
  result merely because the worker was delayed. A previously persisted final
  result always takes precedence over subsequent proof or exits.
- Arithmetic retains all six PostgreSQL fractional-second digits. Timezone
  offsets identify instants; DST, local display zones and leap days never turn
  168 elapsed hours into a calendar-week shortcut.

## Verification

Run from `supabase/functions`:

```sh
deno test _shared/duel_scoring.test.ts
deno fmt --check
deno lint
deno check .
deno test --allow-env
```

| Check | Current result |
| --- | --- |
| Focused pure evaluator tests (no runtime permissions) | 159 passed, 0 failed |
| Entire functions format / lint / type check | Passed |
| Full Deno regression suite | 563 passed, 0 failed |
| `git diff --check` and updated local Markdown links | Passed |

The existing CI Deno job discovers this suite automatically. No dependencies
or lockfile changes were needed. The Supabase changelog and current
[pure-function testing guidance](https://supabase.com/docs/guides/functions/unit-test)
were checked; no platform/API change applies to this import-free evaluator.

No pgTAP/reset, database advisor or Xcode run was needed for this isolated
TypeScript slice: it changes no schema, permissions, service entry point or
native source. The Phase 2 full portable integration gate, SQL concurrency/RLS,
simulated-value conservation and native result/review/rematch verification
remain required when those components exist. Prior phase counts remain prior
evidence, not checks rerun here. No hosted, physical-device or real-race proof
is claimed.

## Next slice: Phase 2(b)

Follow-up, September 5: [Phase 2(b) is now accepted locally](DUEL_PROOF_V1_ACCEPTANCE.md).
The original handoff below is preserved; the next implementation is Phase 2(c).

Add private append-only proof/review records and an audited narrow operator
boundary using forward migrations. Authenticate and authorize operators from
server-owned records, forbid either participant from reviewing the duel,
validate source identity/bib mapping, and persist server receipt/retrieval
metadata. The normalized corpus above is the scoring contract; private raw
source material and operator audit metadata need their own storage design.

Use explicit RLS/grants and participant-only redacted reads. Preserve exact
request identity, active-actor checks and Phase 1A's stable actor-lock ordering.
Serialize proof/cutoff/correction/review/deletion races and make append-only
revision selection authoritative. Test role revocation and concurrent revisions.
Keep admission default-off and use fictional local actors/events only.

Phase 2(c) then supplies activation/expiry, durable provisional notices, cases,
the clock-injected worker and separately appended final/simulated events. The
worker must lock and verify that the evaluated snapshot is still current before
committing. Slices (d/e) add native progress/results/review, explicit rematch
consents and target-bound expiring links. No hosted schedule is authorized.
Organizer permission, an independent human reviewer and support operations
are prerequisites for the later human pilot, not for these local fixtures.
