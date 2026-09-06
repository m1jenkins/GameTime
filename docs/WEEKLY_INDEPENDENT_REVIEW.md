# Independent weekly implementation review

September 6, 2026. **No unresolved actionable finding remains in the reviewed
local implementation. This is not full-stage or launch acceptance.** The
source/metric implementation agent independently reviewed
the other agents' new weekly policy, database/lifecycle, native transport/store,
and the lead-authored reminder preview/reproduction script. The reviewer did
not author or edit those implementations. The lead separately reviewed the
reviewer's source/metric implementation, as recorded below.

Scope: source and terms isolation, authentication and privacy, concurrent
admission and finalization, explicit consent, exact recovery, full correction/
review windows, safe exits, legacy regressions and default-off behavior. This
review does not establish physical Health behavior, human accessibility,
provider/legal clearance, actual pilot participation or hosted operation.

## Findings and resolution evidence

“Code corrected” means the reviewer observed the change or the author reported
it, as stated. It is not equivalent to the required regression passing. A
finding closes only when its corrected path has applicable test evidence.

| ID / severity | Concrete finding | Fix and current state | Required regression proof |
| --- | --- | --- | --- |
| R1 / high | `weekly_session_v1` checked session expiry before runtime/agreement locks. A session expiring during a subsequent wait could still create/join/exit/review/upload progress. | **Closed for the local boundary.** Reviewer observed `weekly_require_session_v1` and rechecks after session, admission and agreement waits in `20260906053958_weekly_local_v1.sql`. | `481_weekly_concurrency.test.sql` passed 25 assertions in the final fresh replay, including a real agreement-lock wait beyond session expiry, required `42501` rejection and an actual-blocking assertion. Other scenarios exercise valid-session admission and concurrent account deletion. Reviewer inspected the original detailed race log and final fresh portable result. |
| R2 / high | SQL fixture ingestion accepted exact upload/correction cutoff equality while `evaluateWeeklyParticipant` admitted only strictly earlier receipts. An acknowledged downward correction could be ignored and leave a stale success. | **Closed for the local boundary.** Reviewer observed SQL `>=` rejection at both cutoffs to match the existing W1 pure policy. | Latest 480 suite passed before/equal/one-microsecond-after both cutoffs. Fresh persisted lifecycle smoke passed an actual SQL downward correction at the final eligible microsecond through W1A, invalidated the stale worker snapshot and created a new complete notice/review window. Logs: `/tmp/gametime-weekly-verify.7xAyHql8/portable.log` and `lifecycle.log`. |
| R3 / high | Native `WeeklyChallenge.validate` expected `finalized` and rejected backend `review`/`final`; `WeeklyQualification` lacked backend `refund`. Result, review and safe-exit history could fail decoding. | **Closed.** Native exact statuses and `refund` match the backend contract. | `WeeklyNativeSmokeTests` passed against real local Auth/PostgREST: actual persisted `review` state and notice/case decode, explicit worker transition through the full window to `final`/refund, normal final history and exact old review-request replay after gate shutdown. Reviewer inspected `tmp/weekly-native-61e411ce.log` and the actual test implementation. |
| R4 / medium | Pilot opt-out/deletion removed `weekly_pilot_events` but retained reconstructible event/phase/challenge payloads in `weekly_requests`. An initial plain-SHA256 tombstone remained dictionary-recoverable from the small event vocabulary and known challenge IDs. | **Closed for the local boundary.** Reviewer observed the payload replaced by only `{"op":"pilot_erased"}`, with explicit retired-request behavior and no digest. | Final 480 suite passed all 77 assertions, including both-table erasure after opt-out and account deletion, constant retirement marker and no recreation on retry. 481 passed a real revocation-versus-event race. Reviewer inspected code, detailed focused logs and the final fresh portable result. |
| R5 / high | An early lifecycle tick changed an incompletely accepted friend challenge from `invited` to `scheduled`, while native `canAccept` required `invited`, blocking the remaining consents. | **Closed.** The worker preserves invited status during `acceptance_open`; native acceptance supports invited/scheduled with own-consent and exact cutoff predicates. | Fresh persisted lifecycle smoke passed worker-before-last-accept flows at two/five participants, creator-only consent, cutoff-equality rejection and valid earlier remaining consents. Native unit and actual HTTP smoke both passed early-worker then two/five-person acceptance. |
| R6 / high | A request with ambiguous transport loss could remain `mayHaveCommitted` forever. If it never committed and subsequently expired, every definitive retry rejection retained it; the single pending slot blocked all other reviews/exits/support. | **Closed.** Actor-serialized `resolve_weekly_request_v1` recovers a committed receipt or permanently retires an absent key before native removal. | SQL retirement/recovery assertions and an actual retire-versus-create blocking race passed. Real native HTTP passed both committed response loss with identical request-body hashes and an intentionally uncommitted dropped request, gate-off rejection, explicit retirement and subsequent support/safe exit. Account-switch/late-response isolation also passed. |
| R7 / medium | `weekly-local-verify.sh` copied directories without excluding a conventional `supabase/functions/.env`, contradicting its no-credentials-inherited boundary. | **Closed.** Copying uses the tracked inventory and rejects symlinks/nonregular files. The reviewer independently checked the actual reproduction manifest and committed blobs. | At HEAD `121628a4b90f42bfa654a747d7ae8e7d8e6faa6e`, all 300 inputs exactly matched the tracked allowlisted inventory and all committed-source/destination SHA256 checks passed. Only `supabase/config.toml` changed for disposable identity/ports. No `.env`, runtime linkage or local build state was inherited. Fresh portable and persisted lifecycle checks passed; `stop.log` confirms container cleanup in `/tmp/gametime-weekly-verify.fL5v687w/`. |
| R8 / high | **Lead review finding:** invitee acceptance lacked the full named frozen roster and each person's target, although the creator preview displayed them. Consent therefore omitted material group terms. | **Closed.** Allowed friend names and all targets appear before consent; contact suppression hides them and blocks new acceptance. Community remains own/counts only. | Real two/five-person native HTTP passed complete roster/terms checks. Reviewer visually inspected normal and accessibility3 five-person PNGs: Alice/You/Carmen/Dev/Ellis and 7,000/7,700/8,400/9,100/9,800 steps precede consent. Corrected rendered OCR tests passed; unit/SQL block-redaction checks passed. |
| R9 / high | Lead and independent reviewer both observed consent copy promising 72 hours after filing while SQL resolves at the end of the full 48-hour filing window plus 72 hours. Early filers could otherwise expect a substantially earlier deadline than implemented. | **Closed.** Reviewer inspected rules stating 72 hours after the filing window closes, with saved notice deadlines rendered from server fields. | SQL and real persisted worker checks passed complete filing/resolution windows, including a replacement correction notice. Native HTTP decoded persisted notice/review history through finalization. Reviewer inspected the saved-notice deadline on the corrected result PNG. |
| R10 / medium | Confirmation text said the exit was already saved before consent/server success. Provisional unresolved notices reused final “this week did not count” wording even though correction/review could change the outcome. | **Closed.** Exit confirmation is prospective; saved receipts/results alone support saved/final claims. Provisional notices use a distinct unresolved-update label. | Unit labels and actual HTTP safe-exit/immutable refund history passed. Reviewer inspected the corrected PNG's separate provisional update, confirmed no-loss result, entry return and exact saved-request recovery controls; rendered tests passed. |
| R11 / medium | `weekly_create_at_v1` expanded and locked the caller-supplied participant array before enforcing the 2–5 roster bound. An oversized payload could lock unrelated profiles before eventual rejection. | **Closed for the local boundary.** Reviewer observed a 32-KiB terms bound, array/cardinality and UUID checks before referenced profile locks; complete terms/relationship validation remains. | The focused and fresh 480 suites passed direct oversized creation rejection, beyond the preview's existing one/six-person rejection tests. Reviewer inspected source ordering and execution logs. |
| R12 / low | Creation controls remained editable while an old draft's preview request was in flight, allowing an outdated preview to replace recently changed choices. Full terms still appeared before fresh consent, so this was not silent agreement mutation. | **Closed.** Controls are disabled during loading/sending; preview responses validate the submitted draft. Draft edits explicitly invalidate the request token and clear preview/consent; actor changes clear and dismiss creation. | `testChangedDraftRejectsDelayedPreviewBeforeConsent` passed in the final 18-test native suite. It holds the actual store preview continuation, verifies requests are blocked while pending, permits unchanged exact terms, rejects a delayed response after draft invalidation, refuses creation from that old response, and rejects a held response across actor change. Real native HTTP independently passed exact two/five-person preview/consent/recovery. |
| R13 / medium | **Lead review finding, independently confirmed:** freshness used wall-clock deltas and clamped negative elapsed time to zero. Moving the phone clock backward could extend the 60-second fresh-data window, including private following data. | **Closed for the local store boundary.** Reviewer observed freshness based on injectable monotonic `ProcessInfo.systemUptime`; account/background transitions clear following rows and offers. | Reviewer inspected the passing `testMonotonicFreshnessExpiresWithoutTrustingDeviceWallClock` in the final native log, covering exact 60 seconds, 60.001 seconds and negative/nonfinite deltas. Source inspection confirms device wall-clock time no longer participates in freshness. |
| R14 / high | Independent visual inspection found `five-person-invitation.png` was entirely black although the rendered test's PNG byte-count assertion passed. Blank renders cannot prove consent roster, copy or Dynamic Type behavior. | **Closed.** The harness attaches a foreground window scene, renders its layer and requires pixel variation plus OCR of required visible strings. Long canvases use overlapping native-pixel crops without dropping required strings. | Three corrected rendered tests passed in `/tmp/gametime-weekly-final-rendered-native.log`. Reviewer independently viewed all four PNGs, including accessibility3, and verified actual text/targets/consent/recovery/final-return distinctions. This is automated rendering and model inspection, not human accessibility acceptance. |
| R15 / high | **Actual native HTTP integration finding:** a new actor's `client_progress_only` projection sent `complete_day_count: 0` despite having no service observation basis. The strict native contract correctly rejected the inconsistent projection. | **Closed.** Additive `20260906070927_weekly_progress_absence_v1.sql` emits null for absence while retaining zero for an existing incomplete basis and seven for seven complete days. Native validation was not weakened. | Reviewer diffed the replacement projection: only the actor-bound completeness expression changed. Focused 480 passed 77 assertions, including creator/invitee absence, incomplete/complete distinction and other-actor isolation. Actual native HTTP then passed with the fix applied. |
| R16 / medium | **Lead review finding:** an unaccepted actor could still see a disabled invitation/consent section on a terminal challenge. | **Closed.** Invitation controls require invited/scheduled state; terminal invitations show explicit closed copy and retain private support. | `testUnacceptedFinalWeekShowsClosedInvitationAndSupport` passed with required closed/support text and forbidden invitation/acceptance text; open two/five-person acceptance still passed. Reviewer independently viewed the terminal PNG and confirmed no dead consent control. Evidence: `/tmp/gametime-weekly-closed-invitation-native.log`, repeated in the final full native suite. |
| S1 / high | **Lead review finding:** block/unblock or unfriend/re-friend could automatically revive a prior sharing grant. | **Closed for local authorization.** Reviewer observed permanent grant retirement on block/friendship deletion; renewed sharing uses a new offer and fresh acceptance. | The final 482 suite passed immediate block suppression, unblock/new friendship without revival and old-offer rejection. Real native HTTP passed the bilateral sharing path and gate-off unfollow. Native cached representations are separately bounded by S5; no instantaneous push revocation is claimed. |
| S2 / high | **Lead review finding:** owner sharing permission alone made a recipient follow without their consent or an unfollow path. | **Closed.** Reviewer observed pending offers, recipient accept/decline/unfollow and actor/offer binding. Decline/unfollow prevents repeated offers for the same agreement. | SQL 482 and actual native HTTP passed owner-offer-only invisibility, explicit recipient acceptance and gate-off unfollow. Reviewer inspected native offer controls and exact operation/offer bindings. No notification or unsolicited follow is enabled. |
| S3 / medium | **Lead review finding:** the shared-progress projection rendered absent data as a zero step count. | **Closed.** The uncoalesced sum yields null when no observations exist, with a separate optional update timestamp. Native preserves nil and uses missing-update text. | SQL 482 passed missing observation as JSON null and absence of qualification/financial/roster fields. Actual native HTTP asserted `observedSteps == nil` after following with no source basis. Reviewer inspected the distinct native missing-update branch. |
| S5 / high | Independent reviewer found that the new monotonic freshness helper applied only to own-row actions. `WeeklyFollowingSections` still rendered `sharedProgress` and offers indefinitely while foreground, even after remote owner revocation, block or session loss. | **Closed for the local cache boundary.** Reviewer observed private social reads batched until all complete, a less-than-60-second monotonic publication check, expiry task tied to the original read time, and clearing of all names/totals/offers/grants on expiry/failure/background/account change. Follow-up review also removed partial/late publication during a hung later request and stale friend names after timer cancellation. | The final 18-test native suite passed the 60-second expiry reducer, a held later response beyond expiry with no partial/late publication, and `testScheduledExpiryCallbackClearsPrivateSnapshotWithoutUserAction`. The last test verifies the armed callback requests a 60-second wait, advances the injected monotonic clock, releases the wait, and observes private cards/offers/grants disappear without a direct reducer call. Production still uses `Task.sleep`. This proves scheduled store behavior, not a real 60-second rendered UI or human accessibility exercise. |
| S6 / medium | Independent reviewer observed copy saying following ends with the chosen week, while `list_shared_weekly_progress_v1` did not filter the activity end and could return historical grants indefinitely. | **Closed for local authorization.** Reviewer inspected `20260906065002_weekly_sharing_expiry_v1.sql`: new owner offers, recipient accepts, pending offers and shared reads all require server time strictly before the week ends. Exact receipts and safe revoke/decline/unfollow survive expiry. | 482 expiry suite passed 41 assertions, including before/equal/one-microsecond-after checks for all four operations and denied client access to injected-clock helpers. Reviewer inspected `/tmp/gametime-weekly-482-expiry.log` and the corresponding native following copy/read path. Native cached data remains subject to S5's bounded privacy lifetime. |
| S7 / medium | Optional social enrichment fetched sharing grants serially for every accepted history row, and one late failure cleared already validated own challenges, cohorts and preferences. | **Closed in the current source.** Validated own content publishes before optional social enrichment. Sharing reads use four bounded partitions; any social failure clears the private social snapshot together without clearing own content or exact pending recovery. Mutations, retries, new refreshes and actor changes cancel in-flight enrichment, and generation/session/token checks fence every dispatch and response. | Three executable store regressions cover a failure on the fifteenth sharing read while own content and recovery remain available, a maximum of four simultaneous sharing calls, and held responses after account switch or supersession. These additions postdate and are not included in the recorded 18-test/367-test full native gate. |

### Final publication fence follow-up

Independent finding `weekly-social-final-auth-suspension-race` (high): a
superseded same-account refresh could resume its final authentication check
and restore a revoked private total, follow offer and friend name. The current
correction checks actor/generation first, then cancellation and refresh token
after that suspension; optional error cleanup uses the same predicate.

The actual store regression failed on unchanged `eacb1f0` with three stale-data
assertions, then passed with this minimal correction. All 24 focused native
tests passed on the corrected disposable copy, including scene lifecycle and
safety-action coverage. Evidence and the tracked-input manifest are under
`/tmp/gametime-weekly-auth-race-p4xs13m8/`; the new executable regression is
`WeeklySocialRefreshAuthRaceTests.testSupersededFinalAuthCheckCannotRestoreRevokedSocialData`.
This closes the reproduced local behavior on that tested copy; required checks
on the committed correction remain a pre-merge requirement. It establishes no
physical-source or human acceptance.

No additional blocking finding was identified in the inspected pure optional
reminder preview: it validates actor/category/access, expiry, duplicate events,
quiet hours and configured caps and always returns `deliveryEnabled: false`.
This is a bounded review of an unwired rehearsal, not delivery acceptance.

The reviewer also inspected lead commit `9debb28`, a six-line test-only fix in
the historical Personal snapshot suite. A materialized single captured instant
now supplies both `observed_at` and `query_through`, preserving the completed-
query ordering that two separate wall-clock reads could violate by a
microsecond. No Personal production behavior or acceptance assertion changed.
The lead reports the 37 focused assertions passed; final fresh regression is
recorded by the lead's integration acceptance.

The reviewer inspected the optional study-delivery isolation fence: queued
delivery checks the captured actor/generation, does not own the durable safety
request slot, and cannot publish a late old-account failure into the new
account. `testHeldOptionalStudyDeliveryLeavesSafetyActionsAvailable` passed
while holding the actual asynchronous delivery continuation and then switching
actors. No additional blocking finding was identified in that correction.

## Separate lead review of source and metric prototypes

The lead independently reviewed `WeeklySourceFeasibility.swift`, the unwired
`WeeklyHealthSourceProbe.swift`, and `weekly-metric-fixtures.ts`, and reported
no blocking issue in the inspected source/metric contracts. The lead confirmed
that qualification unavailability, unknown metadata, DST weeks and timed versus
cumulative distances remain separate and that the Health probe is default-off.
This was the lead's review, not the source author's independent review of their
own code.

The source author's executed evidence is recorded separately in
[WEEKLY_SOURCE_METRICS_ACCEPTANCE.md](WEEKLY_SOURCE_METRICS_ACCEPTANCE.md): 22 Deno
fixture tests, 10 portable Swift diagnostic tests, format/lint/type checks, a
Debug Simulator build, and one Simulator default-off probe test covering all
three metrics. The lead also independently reviewed the private native metric
notebook, with its 15 passing tests and four actual native-serialized terms
accepted by the sole TypeScript evaluator. The lead's capacity/safe-exit,
plain-language, strict-revision-time and account-field-clearing findings and
fixes are attributed there. No physical-source acceptance is claimed.

## Final executed integration evidence

The reviewer inspected the following actual lead-run outputs, rather than
treating author completion messages as test results:

- Fresh disposable replay at `121628a`: 72 SQL files / 3,576 assertions,
  833 Deno tests and 113 portable Swift tests passed. The persisted SQL-to-W1A
  worker smoke passed corrections, complete notice/review windows, conservation,
  two/five-person remaining consent after an early tick, exact cutoffs and
  immutable final replay. The reviewer independently verified all 300 manifest
  entries against committed blob SHA256 values and copied files. Own-stack
  shutdown succeeded. Logs: `/tmp/gametime-weekly-verify.fL5v687w/`.
- Final native suite: 367 tests, three explicit controller-gated skips and zero
  failures, including 18 weekly model/store tests, 15 metric notebook tests and
  four rendered tests. Logs: `/tmp/gametime-weekly-final-all-native-units.log`.
  The weekly controller-gated HTTP test was separately run and passed.
- Actual authenticated native HTTP passed after the preview/terminal-invitation
  guards: `tmp/weekly-native-c8d692d1.log`. Earlier detailed result inspection
  also covered `tmp/weekly-native-61e411ce.log`: two/five-person explicit consent,
  solo community joining, bilateral sharing, missing data, persisted review to
  final refund, exact response-loss recovery, retirement of an uncommitted
  request, actor/session isolation and gate-off safety actions. The subsequent
  scheduler-test seam preserves the same production `Task.sleep` behavior.
- All 50 legacy UI tests passed: 11 duel, 31 Personal and eight performance
  commitment tests in `/tmp/gametime-weekly-full-native.log`. Its earlier blank
  weekly render failure was corrected and independently retested, as R14
  records. Final Staging and Release builds report `BUILD SUCCEEDED` in
  `/tmp/gametime-weekly-final-{staging,release}-build.log`.

The reviewer inspected five actual nonblank PNGs: normal and accessibility3
five-person invitations, community common-target consent, provisional/final
refund plus request recovery, and a closed unaccepted invitation. Automated
OCR/pixel checks and model visual inspection do not replace human accessibility
or comprehension evidence.

The draft PR body was reviewed for scope: it identifies default-off fictional
implementation, preserves historical Personal/Solo/charity/fictional-5K
agreements and paused organizer work, and explicitly retains the 2–5-total
participant assumption and fixture-only numeric targets. Delivery and any
additional repository-required checks remain the lead's responsibility.

## Remaining acceptance gates

These are external or separately gated capabilities, not unresolved findings
in the reviewed local boundary. Follow the exact next actions in
[WEEKLY_LOCAL_ACCEPTANCE.md](WEEKLY_LOCAL_ACCEPTANCE.md) and
[WEEKLY_SOURCE_METRICS_ACCEPTANCE.md](WEEKLY_SOURCE_METRICS_ACCEPTANCE.md): run
authorized physical iPhone/Watch source experiments before admitting any real
qualifying source; conduct human accessibility/comprehension checks; obtain
authorization and actual two-round pilot evidence; and obtain the documented
provider/legal/platform clearances before a funded version. Exercise and
distance fixtures remain prototypes, and the native notebook does not score
or finalize real outcomes. Notifications, source admission and live money
remain disabled. No hosted, participant, device or human evidence was invented.
