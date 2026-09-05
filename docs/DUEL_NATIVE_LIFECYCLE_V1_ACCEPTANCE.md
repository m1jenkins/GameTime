# Phase 2(d) — native simulated duel progress and review

September 5, 2026. Implements the native slice from the
[Phase 2(c) handoff](DUEL_LIFECYCLE_V1_ACCEPTANCE.md#phase-2d-handoff).
Phase 2(d) is accepted locally. This remains an opt-in, local, nonredeemable simulation. No hosted migration,
schedule, push/email delivery, organizer/provider integration or live money was
enabled. Historical Personal, Solo, charity and duel consents retain their meaning.

## Implementation

- `DuelLifecycleModels.swift` decodes participant notices, own review receipts,
  closures, final results and separate simulated returns. It binds the result
  to the exact agreement ID/digest and validates the scorer version, permitted
  outcomes and actor-relative return amount. `DuelInstant` retains the original
  PostgreSQL timestamp and all six fractional digits with integer microseconds.
- `SupabaseDuelClient.swift` adds `get_duel_lifecycle_v1`, `file_duel_review_v1`
  and `exit_duel_v1`, with account checks on both sides of transport. Review
  filing returns a case UUID; the store navigates using the request's duel UUID
  and confirms that the returned case matches its revision and reason.
- The existing, separate `duel_request_v1` envelope gains review and exit
  operations. Existing encoded operations remain compatible. Actor, key,
  operation, revision, reason, exit kind and exact parameters cannot change.
  The uncertainty marker is persisted before transport. Refresh never replays
  writes; **Retry saved request** explicitly recovers the original request.
- `DuelStore.swift` clears lifecycle content, timestamps and errors synchronously
  on account changes. Request generations and per-duel read tokens discard late
  responses. Refresh failures remove result content so cached opponent results
  cannot outlive a block or revoked read. Reads never infer a final result from
  the historical agreement's `scheduled` status or a deadline passing.
- `DuelLifecycleViews.swift` shows progress, all saved notices, per-correction
  deadlines, own cases and decisions, confirmed results and separately recorded
  simulated returns. Review requires choosing a reason and explicitly sending.
  Withdrawal and injury require confirmation. Sheets/dialogs are owned by the
  stable detail form. Blocked contacts retain their own cases, exit receipt and
  simulated return without shared outcomes or opponent names.
- Server action hints and a server-clock estimate disable unavailable new
  requests. The database rechecks every write under locks and owns exclusive
  deadlines. Exact retries bypass new-action hints and recover committed
  requests with admission off. No device timer finalizes a duel.

The small forward migration
[20260905141000_duel_native_lifecycle_projection_v1.sql](../supabase/migrations/20260905141000_duel_native_lifecycle_projection_v1.sql)
adds `serverNow`, `canExit`, redacted `closure`, and per-notice `canFileReview`
to the participant read. This was needed to render a saved exit before the
worker runs and avoid offering another exit. It retains the Phase 2(c) lock
order, active-session check, grant boundary and contact suppression. An
opponent's closure is hidden when contact is suppressed; one's own receipt is
retained. No table, policy, mutation, scorer or immutable historical receipt is
rewritten. Existing clients can ignore the extra fields; this native slice
requires the forward migration on its selected local stack.

## Verification

| Check | Result |
| --- | --- |
| New rollback-only participant SQL | 27 assertions passed: gates off, deadlines, own receipts, blocked contacts, final/return separation, unrelated/revoked sessions and privileges |
| Actual PostgreSQL → Swift DTOs | Four captured documents decode and validate: own exit, blocked own receipt, final awaiting return, recorded return |
| Focused native tests | 27 passed, including 11 new lifecycle tests and 16 retained agreement tests |
| Full native unit suite | 283 passed, 0 failed, 1 skipped (the opt-in HTTP smoke, separately passed) |
| Fixture UI journeys | Creator recovery, acceptance/cancellation, gate-off decline, ordinary Personal, final awaiting return, corrected review recovery, blocked injury at Accessibility XXXL/Reduce Motion, recorded simulated return passed across focused runs |
| Authenticated native HTTP smoke | Passed with real local Auth sessions, production RPC adapter/store and durable files; details below |
| Full portable regression | Passed: 57 database files / 2,609 assertions; 568 Deno tests; 103 portable Swift tests |
| Debug / Staging / Release simulator builds | Passed without compiler warnings; compiled duel UI/fixture symbols present in Staging and absent in Release |
| Local migration history | New migration applied and recorded; all three gates verified off after cleanup |
| Local database lint/advisors | No schema errors or warning/error issues |
| Personal copy audit | Passed; existing Personal checks retained |

The first UI run found that presentations attached to an offscreen lazy form
section did not open. Moving their ownership to the stable detail form fixed
both review and safe-exit presentation. A separate test needed to scroll back
to the simulation banner before asserting its existence. All three focused
reruns passed. The initial SQL DTO capture used the owner role, which correctly
failed the active participant-session check; capture now runs as authenticated.
Those failed attempts are not passing acceptance.

The initial focused native run reported missing precompiled-module debug-info
paths from existing Xcode caches. It passed; the subsequent full native run
reported no warnings. No dependency or Xcode configuration was changed.

Evidence on iPhone 17e / iOS 26.5:

- Full native: `test_sim_2026-09-05T14-44-08-865Z_pid26002_35a14b11.xcresult`.
- Final three UI reruns: `test_sim_2026-09-05T14-40-06-157Z_pid26002_952fa58a.xcresult`.
- Final retained cancellation/Accessibility XXXL decline rerun:
  `test_sim_2026-09-05T14-53-00-478Z_pid26002_e0373032.xcresult` (2 passed).
- Initial UI run's five passing journeys:
  `test_sim_2026-09-05T14-30-40-182Z_pid26002_302c9452.xcresult` (the run overall failed).
- Authenticated smoke: `tmp/duel-native-e98046ef.xcresult` and
  `tmp/duel-native-smoke-report.json`.

The `test_sim_*` bundles are under
`~/Library/Developer/XcodeBuildMCP/workspaces/GameTime-7b9ccaa5aefb/result-bundles/`.
Passing screenshots were inspected: normal text wraps, correction history and
receipts are readable, and Accessibility XXXL remains scrollable through the
injury action and receipt. VoiceOver traversal and physical devices remain
unverified; Dynamic Type checks are not VoiceOver acceptance.

## Authenticated local HTTP exercise

The existing [local smoke runner](../scripts/duel-native-local-smoke.py) now also
creates a fictional historical accepted agreement and a recent durable
missing-result notice through private local test-time setup. This setup is
explicitly separate from the native Phase 1 consent exercise. Participant
review and exit calls use real current database time and authenticated HTTP.

Observed after the new native exercise:

- Review filing committed, its HTTP response was deliberately lost, and the
  actor recovered the identical file-backed request after switching accounts.
  The opponent saw no private review case. Three successful sends under one key
  produced one case; changing the reason under that key returned HTTP 400.
- With admission and lifecycle execution off, a blocked actor read their own
  case and submitted an injury exit. Its response was lost; refresh preserved
  the request and the saved closure, and explicit retry recovered it. Three
  successful sends used the same key and retained one closure.
- The manual loopback worker ran the unchanged scorer, finalized the injury
  outcome and separately recorded simulation. The blocked actor saw their own
  2,000-cent simulated return while the shared final outcome stayed hidden.
- Final cleanup retained three fictional agreements, eight agreement requests,
  six consents and one review case. Open slots, admission allowlist, sessions
  and refresh tokens were all zero; admission and lifecycle gates were off.
  The proof gate was never enabled by this native exercise.

Reproduce using the Phase 1B runner command in
[DUEL_NATIVE_V1_ACCEPTANCE.md](DUEL_NATIVE_V1_ACCEPTANCE.md#reproduce-the-authenticated-smoke).
Admission must initially be off with an empty allowlist, and lifecycle execution
must also be off. The runner owns
only its random fictional accounts and agreements; it refuses active admission,
uses only loopback endpoints and retains no credentials in its report. No email
is sent. The service key remains in the host controller, never the native app.

Fixture entry remains **You → Friend duels**, with `--fixture-mode --duels`.
Add `--fixture-duel-review`, `--fixture-duel-correction`, `--fixture-duel-final`,
`--fixture-duel-settlement` or `--fixture-duel-blocked`; combine with
`--fixture-duel-lost-response` and `--fixture-duel-gate-off` for recovery.
Fixtures do not run the scorer or establish human result accuracy.

Supabase's current changelog, official
[Swift RPC guidance](https://supabase.com/docs/reference/swift/rpc) and
[Apple task identity guidance](https://developer.apple.com/documentation/swiftui/view/task%28id%3Aname%3Apriority%3Afile%3Aline%3A_%3A%29)
were checked. No library upgrade was needed.

## Phase 2(e) handoff

Implemented locally in [Phase 2(e) acceptance](DUEL_REMATCH_LINK_V1_ACCEPTANCE.md).
The original handoff follows.

Add **Challenge again** with a new agreement, a newly available event/time and
fresh explicit consent from both runners. Never reuse old consent or interpret
an old simulated return as spendable funds. Add target-bound invitation links
with expiry/revocation, account-safe pending destinations, no private proof in
URLs and no acceptance merely from opening a link. Sharing must be initiated
by the person. Preserve the lifecycle reads, recovery and block suppression
accepted here.

Independent operator UI, real organizer proof, human reviewer operations,
retention policy, hosted rollout, scheduling, external delivery and live money
remain separate gates. Post-final corrections use the existing independent
support intake; this native participant slice does not grant operator access.
