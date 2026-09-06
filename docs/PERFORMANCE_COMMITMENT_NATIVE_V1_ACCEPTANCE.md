# Phase 3(f): first native commitment slice

Implemented locally September 5, 2026, following the
[Phase 3(e) acceptance and native handoff](PERFORMANCE_LIFECYCLE_V1_ACCEPTANCE.md).
This starts native integration with owner agreements and result/review history.
It does **not** complete the handoff across attempts, progress and following.

## Implemented flow

An explicit `--commitments` opt-in exposes **You → Running goals** on a
non-Release build configured for an explicit HTTP loopback host and port.
`--fixture-mode --commitments` selects a separate fictional client. Normal
Personal launches retain their navigation and disclosure. Release compiles
out the route/screens and disables the client even if constructed as enabled.

The owner chooses a strict 5K target, future start and 28–90 elapsed 24-hour
days. The editor initially shows 25:00, tomorrow and 56 days; these are editable
presentation defaults, not new agreement or launch policy. Server preview
returns exact terms and a digest before explicit consent. Editing or refreshing
invalidates that preview; a previous toggle cannot consent to changed input.
Review shows fictional organizer-only results, exact start/exclusive finish,
whole-second chip timing, proof/review/finality windows, safe exits, $20
nonredeemable simulation, $0 fee and no selected recipient. The editor explains
that native attempt entry is still being built.

History loads the original agreement **and** its separately authorized
lifecycle. `open` never proves that no final exists. Detail presents corrected
notices, saved timestamps and review windows, own cases/redacted decisions,
closure receipts, immutable finals, separately appended simulated returned/lost
amounts and redacted support receipts. Raw organizer sources, reviewer identity
and private support notes are absent. Missing results never imply a miss;
absent simulation stays pending even with a final result.

Fixed-reason reviews and explicit cancellation/withdrawal/injury actions use
server hints and an advancing server-clock estimate; the database remains
authoritative. Deadline-dependent controls update while sheets stay open. A
cap earlier than the full notice window is shown separately with the existing
zero-consequence protection. Opening a result never creates or restarts a notice.

## Requests and isolation

Distinct `PerformanceCommitment*` models, client, store and request namespace
preserve the other products. The existing integer-microsecond timestamp parser
preserves incoming wire values and pagination cursors. Typed decoding validates
the exact supported policy/source/consent and owner/result bindings. Missing
nullable final/closure fields and unknown outcomes fail closed.

Complete mutations are saved atomically to protected, backup-excluded,
actor-specific application-support storage. The uncertainty marker is saved
before sending. HTTP sends those exact bytes, performs no application-level
automatic mutation retry, rejects redirects and checks the in-memory session
before/after calls. Requests contain no session credential or service key.
Explicit recovery reuses original IDs/input; changed input needs a new request.
An initial definitive rejection can clear an uncommitted request; uncertainty
retains it across admission shutdown and relaunch.

Creation/closure UUIDs and review-case receipts have different types and checks.
Recovery re-reads agreement/lifecycle and binds the exact case/reason/time or
closure before removing the saved request. An action receipt never establishes
current permission or a final result.

Owner content/action hints clear on account changes, backgrounding and failed
reads. Prior actor/generation/read responses cannot repopulate it. Only requests
persist across relaunch; no owner result or shared-progress cache is added.
Deletion clears this product's local request and fences queued writes. No
follower access to results or result-sharing consent is introduced.

## Verification

Verification uses the booted iPhone 17e simulator on iOS 26.5 and Xcode 27.

| Check | Fresh result |
| --- | --- |
| Native Debug build | PASS |
| Native regression run | PASS: 322 unit tests plus six commitment UI flows, 328 total; controller-dependent HTTP suites run separately |
| Final focused native run | PASS: 36 commitment model/client/store/integration tests plus three UI checks, including default Personal navigation and the updated review/exit controls |
| Authenticated native HTTP acceptance | PASS: one comprehensive test through real local Supabase Auth sessions, the production native client and AppModel account switching |
| Native Release build | PASS; commitment routes/screens compile out and transport defaults disabled |
| UI scenarios | Seven distinct flows pass across the runs: preview consent reset, lost create recovery, corrected review recovery with admission off, final before simulation, appended simulation, injury at accessibility XXXL/reduced motion, and no default Personal entry |
| Local script and documentation checks | Python compilation, Deno format/lint/type checking, local Markdown links and whitespace pass |

Tests cover missing/unknown wire state, microsecond filing/cancellation bounds,
response loss, exact bytes after store reconstruction, storage failure before
send, changed preview input, actor A→B→A, replaced/revoked sessions, out-of-order
reads, backgrounding during success/rejection/detail responses, and immutable
final results despite an original `open` agreement. Five simulator screenshots
were exported; default-size result/pending views and the accessibility injury
receipt were visually inspected. VoiceOver traversal and physical devices are
not verified.

The authenticated test verifies preview/create, foreign-owner denial, held
responses across account switches, and revoked-session rejection. It deliberately
loses a committed create response, reconstructs the durable store and recovers
the same agreement with admission off. It similarly recovers a review case,
preserves the earlier notice timestamp and review case after correction, exercises injury closure,
and reads a final followed by simulation in separate transactions. Repeated
create/review request IDs must have identical body hashes. Historical fictional
proof and clock setup use private SQL fixture seams; final evaluation uses the
unchanged pure evaluator. This does not establish real organizer ingestion or
native attempt-entry acceptance.

The first UI attempt used the wrong fixture launch flag and stopped at sign-in.
After correcting it to `--fixture-mode`, all six scenarios passed, then passed
again in the broader run. Two initial HTTP attempts exposed fixture setup
mistakes: proof capture used an incorrect timestamp/column, then a backdated
correction clock preceded the real review filing. Correcting those fixture
clocks and fields produced the passing run; no app/schema change was needed
for those failures. Python's configured external cache required sandbox
permission before its compile check passed. Failed/blocked attempts are not
counted as passing evidence; overlapping test runs are not added together.

XcodeBuildMCP artifacts live under
`~/Library/Developer/XcodeBuildMCP/workspaces/GameTime-7b9ccaa5aefb/`:

- Broad result: `result-bundles/test_sim_2026-09-06T01-28-03-937Z_pid7449_27506871.xcresult`
- Focused result: `result-bundles/test_sim_2026-09-06T01-35-26-884Z_pid7449_1ecf2360.xcresult`
- Authenticated HTTP result: `result-bundles/test_sim_2026-09-06T02-00-34-136Z_pid7449_784336c3.xcresult`
- Final Release build: `logs/build_sim_2026-09-06T02-02-03-426Z_pid7449_2b4d709d.log`
- Exported screenshots: `/tmp/gametime-phase3f-native-screens/manifest.json`

Earlier Phase 3(e) portable/database counts are historical and are not claimed
as rerun for this native-only change. No earlier migration or scoring source
changed. The [Supabase changelog](https://supabase.com/changelog.md) and
[Swift RPC documentation](https://supabase.com/docs/reference/swift/rpc) were
checked; no SDK/schema/platform upgrade was needed.

## Reproducing authenticated local acceptance

Use a dedicated disposable stack, not the normal development database. This run
copied current `supabase/migrations`, `supabase/functions` and `supabase/seed.sql`
to `/tmp/gametime-phase3f-native/supabase`. The copied configuration uses project
ID `gametime-phase3f-native`, API port 57321, database 57322, shadow database
57320, Studio 57323, mail 57324, analytics 57327 and edge inspector 8085. The
pooler is disabled, leaving 57329 for the loopback response-loss controller.
Apple authentication is disabled only in this disposable configuration. Keep
admission, lifecycle and attempts off and the commitment allowlist empty before
starting the controller; it checks these conditions.

With that prepared directory (or its retained local backup), run:

```sh
supabase start --workdir /tmp/gametime-phase3f-native -x edge-runtime,studio,imgproxy,mailpit,storage-api
umask 077
supabase status --workdir /tmp/gametime-phase3f-native -o json > /tmp/gametime-phase3f-native-status.json
python3 scripts/performance-commitment-native-smoke.py --status-file /tmp/gametime-phase3f-native-status.json --simulator YOUR_SIMULATOR_UUID --derived-data /tmp/gametime-phase3f-native-derived
supabase stop --workdir /tmp/gametime-phase3f-native --project-id gametime-phase3f-native
rm /tmp/gametime-phase3f-native-status.json
```

The passing run used XcodeBuildMCP: omit `--simulator` to keep the controller
running, then run only
`GameTimeTests/PerformanceCommitmentNativeSmokeTests` in Debug with parallel
testing disabled, `SUPABASE_URL=http://127.0.0.1:57329` and the local publishable
key from the controller manifest. Stop the controller with Ctrl-C afterward.
The controller's `--simulator` option automates the equivalent xcodebuild test
and cleanup. Its manifest is temporary and contains fictional test credentials;
never commit it or the status file.

Cleanup verified admission/lifecycle/attempt gates off, empty allowlist, zero
open slots and zero fictional sessions/refresh tokens. Three fictional
agreements and one review case remain as closed history for the final run.
The sanitized report is `tmp/performance-commitment-native-smoke-report.json`.
The controller stopped, both credential files were removed, and only this
disposable stack was stopped with its backup retained. The normal database and
prior Phase 3(e) backup were untouched. A normal Debug build was reinstalled on
the simulator afterward, removing the temporary proxy build configuration.

## Remaining native handoff

**Planning supersession, September 6, 2026:** the list below preserves the
original format-specific handoff. Organizer catalog/nominations are paused as
the default next task after the owner dropped the mandatory fixed 5K. Use
[W1A and the weekly roadmap](WEEKLY_CHALLENGES_IMPLEMENTATION_PLAN.md#current-next-build-prompt)
for new work; adapt milestones and selected-following patterns when relevant.
No earlier acceptance result or existing agreement is changed by this note.

1. Add event catalog/nominations, redacted attempt receipts and explicit
   complete-set/no-attempt confirmation through Phase 3(b) APIs. Silence never
   establishes completeness or a miss.
2. Add private milestones, check-ins and append-only status changes with exact
   recovery and fixed-upper-sequence pagination. Owner-reported progress cannot
   become organizer proof or change a result.
3. Add owner sharing/named-friend acceptance, selected progress, revocation,
   retraction, reactions, personal reminders and private report/block flows.
   Apply the [Phase 3(d) cache handoff](PERFORMANCE_FOLLOWING_V1_ACCEPTANCE.md#native-and-phase-3e-handoff):
   no persisted shared content; current authorization before display; clear on
   failed reads/revocation/account changes; reject late responses.

Keep new operations explicit and preserve original agreement terms. Acceptance
of those remaining flows, VoiceOver traversal, physical devices, actual
organizers, real-data retention, staffed support/review, hosted rollout,
external delivery, true-mile formats and live money remain separate work.
