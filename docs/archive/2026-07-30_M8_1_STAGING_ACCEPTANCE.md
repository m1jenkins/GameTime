# M8.1 staging acceptance

M8.1 is an internal staging alpha. The current working tree improves immutable
review and staging diagnostics, and it adds explicit steps-only HealthKit sync
for source-merged Apple-device totals, product App Attest, exact-byte retries,
and visible confirmed/retained values. Repository implementation and fixture
proof do not complete either gate. Completion requires two Apple-authenticated
accounts on physical devices against the staging project and the observations
below.

This run stays within the friend, challenge, and explicit steps-sync prototype.
It has no background HealthKit delivery, workouts, Core Location, settlement,
donations, disputes, Apple Push Notification service (APNs), or production
release work. Do not deploy, submit to TestFlight, or push this working tree as
part of the run.

## External prerequisites

- An eligible Apple Developer Program or Enterprise Program team
- The staging App ID `com.mjenkins.gametime.staging` with Sign in with Apple,
  HealthKit, and App Attest enabled
- Development provisioning profiles for both physical devices that contain
  those three capabilities
- Matching target signing and Supabase Apple provider configuration
- `APPLE_BUNDLE_ID=com.gametime.conformance` as the reviewed primary identity
  and `APPLE_ADDITIONAL_BUNDLE_IDS=com.mjenkins.gametime.staging` for product
  registration and metric assertions
- Development App Attest acceptance in Staging with
  `APP_ATTEST_ALLOW_DEVELOPMENT=true` and `ATTEST_DEV_BYPASS` absent
- The M8.1 migration and existing App Attest Edge Functions available in
  staging
- A current staging Supabase URL and publishable key in the gitignored product
  app configuration
- At least one active, staging-only charity row
- The named activation job operating so an accepted challenge can become
  active after its start time
- Two controlled test accounts, two provisioned physical devices, and readable
  step samples recorded inside the challenge window

No service-role key, Apple private key, or provider secret belongs in the app.
The working-tree verifier keeps the conformance App ID primary and accepts a
strict, maximum-three additional bundle list outside production for device
registration and metric assertions. It binds receipt verification to the exact
App ID that passed attestation. Check-in remains primary-only, and production
rejects the additional list. Do not overwrite the primary bundle ID. The
approved Staging rollout now has the reviewed product additional identity and
source-identical `attest-device` and `ingest-metrics` bundles. Hosted
fail-closed and authenticated rejection probes pass. Do not send real step
data until physical App Attest conformance passes on a provisioned device and
the two-account prerequisites below are present. No further hosted mutation is
authorized by this record.

## Evidence record

Record only challenge, request, and metric-batch UUIDs; pass/fail results; and
bounded counts. Do not record dates or timestamps, tool or device versions,
handles, Apple IDs, access tokens, keys, assertions, source bundle identifiers,
device health metadata, step values, or private profile data.

### 2026-07-27 single-user device observation

This is a bounded Phase 1 observation, not the two-user acceptance run.

| Field | Evidence |
| --- | --- |
| Product revision | `dca1309` on `codex/iphone-staging-live` |
| Toolchain and device | Xcode 26.2; iPhone 17 on iOS 27.0 |
| Staging identity | Project `jrkzdttophnmkxjoyioo`; bundle `com.mjenkins.gametime.staging`; paid team `87Z29RTC26` |
| Signing | Automatic Apple Development signing; generated provisioning profile contains the paid team, staging App ID, connected device, and Sign in with Apple entitlement |
| Local configuration | Staging environment, HTTPS project URL, and modern publishable key resolved in the signed app; values were checked without recording them and `Secrets.xcconfig` remained ignored |
| Native authentication | Pass: nonce-backed native Apple authorization created exactly one Apple identity in the previously empty staging baseline |
| Onboarding | Partial: one unique staging handle and one linked profile were created, but Apple returned no full name, so the tester entered the display name manually; the required editable Apple-name prefill observation remains open |
| Live shell | Pass: tester observed Today, Challenges, Friends, and You; the staging banner remained visible with no offline/error state; the app's live charity read returned 200 against two active staging rows |
| Relaunch | Pass: the installed process was force-quit and relaunched; the tester confirmed the same signed-in profile and four-tab shell reloaded without Apple authorization or onboarding |

The first installed build also exposed a configuration-plumbing defect: Xcode's
generated Info.plist omitted custom keys. Revision `dca1309` adds an explicit
template and verifies the populated values in both simulator and signed-device
products. The same observation found that an insert-with-returning profile
request conflicts with the restrictive active-actor policy during onboarding;
the client now inserts without a returned row and reads the profile in a second
authorized request, preserving the RLS boundary.

### 2026-07-29 device and hosted-readiness audit

This is readiness evidence only, not a physical acceptance run.

| Field | Evidence |
| --- | --- |
| Connected devices | One available physical iPhone was visible. On 2026-07-29 the tester deferred the two-friend run because a second friend/device was not available |
| Staging profile | A current Apple Development profile contains the paid team, staging App ID, the connected device, Sign in with Apple, HealthKit, and development App Attest |
| Device build | Pass on retry: Xcode built, signed, installed, and launched `GameTime-Staging` on the connected iPhone |
| Runtime launch | Pass: the tester confirmed the app was visibly open with the amber Test environment banner and supplied a screenshot of the live four-tab shell. Challenges loaded with no rows and correctly kept creation disabled until an accepted friendship exists |
| Signature evidence | The build log names the paid-team identity/profile and signs with the generated Staging `.xcent`; the CodeDirectory is version 20400 with nonzero legacy and DER entitlement slots. Host-side certificate-chain verification remains untrusted, so runtime HealthKit/App Attest observations are still required |
| Hosted schema/data readiness | All 19 local migrations are present in staging; active charity data and the named one-minute activation job exist |
| Historical hosted function/configuration state | Before the approved rollout, the three existing functions were active, the primary bundle remained the conformance target, development attestation was enabled for Staging, and `ATTEST_DEV_BYPASS` was absent; the product additional-ID secret and current working-tree function bundles were not yet deployed |
| Fail-closed probe | Unauthenticated registration-challenge and metric-ingest requests returned 401 |

### Approved hosted rollout and no-data probes

This is deployment and rejection evidence only, not physical App Attest or
HealthKit acceptance.

| Gate | Evidence |
| --- | --- |
| Required Staging configuration | Pass, 5/5 checks. The conformance primary identity, product additional identity, development-only setting, staging environment, and `ATTEST_DEV_BYPASS` absence match the reviewed configuration |
| Explicit deployment scope | Pass, 2/2 functions. Only `attest-device` and `ingest-metrics` were named in the deployment command |
| Deployed source verification | Pass, 34/34 returned files match the commit. `attest-device` is active at version 29, `ingest-metrics` at version 22, and the secret-propagated `ingest-checkin` version 21 remains source-identical |
| Fail-closed probes | Pass, 4/4 cases across the reviewed endpoints |
| Authenticated availability and rejection probes | Pass, 3/3 cases. The active challenge path responded, malformed registration was rejected, and a partial App Attest header pair was rejected before metric persistence |
| HealthKit and physical conformance traffic | Zero HealthKit uploads; physical App Attest conformance not run |

### Current physical-readiness stop

This is a blocked readiness observation, not an acceptance run.

| Gate | Evidence |
| --- | --- |
| Required physical devices | Blocked, 0/2 connected devices were available; the previously known device was disconnected |
| Two staging accounts | Not observed; no device session was opened and no account identifier was inspected |
| Physical App Attest | Not started; no key registration, assertion, replay, receipt, or counter observation was attempted |
| HealthKit | Not started; no permission request, read, or metric upload was attempted |
| Hosted read-only inventory | Partial: the connected staging project is healthy and 3/3 functions are active. The local CLI had no Management API authentication, so this check could not independently re-list secret names. The approved rollout above remains the latest evidence that `ATTEST_DEV_BYPASS` is absent |

## Two-account flow

Use Account A and Account B on separate physical devices. Install the signed
Staging build directly from Xcode. After each mutation, force-quit and relaunch
the affected app before continuing.

1. Start a Console or Xcode device-log capture filtered to the GameTime Staging
   process. Do not enable request-body or authorization-header logging.
2. Sign in with Apple as Account A. Confirm the nonce-backed exchange, finish
   onboarding, and verify Apple’s first-sign-in name is only an editable
   prefill. Record A’s exact handle.
3. Repeat for Account B and record B’s exact handle.
4. As A, submit B’s complete handle. Confirm there are no fuzzy results, send
   the request, force-quit, relaunch, and verify the outgoing state reloads.
5. As B, relaunch, verify the incoming request, accept it, force-quit, and
   relaunch. Relaunch A. Both accounts must show the accepted friendship.
6. In Xcode, add a symbolic breakpoint named
   `StagingAcceptanceDiagnostics.challengeCreationResponseReceived`.
7. Confirm both accounts use the same frozen IANA timezone for this repeatable
   run. As A, create a steps challenge for B. Set its start to a future exact
   local-hour boundary, with minutes and seconds at `00`, and set its end at
   least two full hours later. Leave enough time for B to accept before the
   start. On the review screen, record the request UUID and verify the friend,
   metric, cadence, target, start, end, timezone, test pledge, charity,
   tie-break, and two-person closed roster. If the stored start is not on the
   boundary, create a new acceptance challenge instead of using this one.
8. Submit once. When the symbolic breakpoint proves the server returned a
   challenge ID, stop the process without continuing. This creates the
   committed-but-unacknowledged response.
9. Relaunch A. Confirm the saved request appears without an automatic retry.
   Open its immutable review and compare every term and the request UUID with
   step 7.
10. Tap **Submit challenge and invitation** once. Confirm the original
    challenge returns. In a bounded private database check, confirm one
    challenge, two participant rows, and one actor/request idempotency record.
    Record IDs and counts only.
11. Force-quit and relaunch A. Confirm the saved-retry card is gone. Open
    **Staging acceptance** and record the challenge ID, challenge state, A’s
    roster state, and the two loaded roster members.
12. Relaunch B. Open the invitation and verify the same start, end, metric,
    cadence, target, test pledge, tie-break, full roster, and creator. Choose
    B’s charity and accept.
13. Force-quit and relaunch both apps. Confirm both show the same challenge ID,
    both roster members, and accepted roster states. Confirm no duplicate
    challenge exists.
14. Wait past the scheduled start and the named staging activation run. Refresh
    both apps until the same challenge becomes active. Do not force the state
    with an ad hoc database mutation.

The two-account gate does not claim a live three-account or multi-friend
observation.

## Explicit steps-sync flow

Run this section only after both accounts show the same active steps challenge.
The explicit action queries the immutable challenge interval `[start, end)`.

1. On A, tap **Enable Activity** and allow read access to Steps. A completed
   permission request does not prove HealthKit granted read access.
2. On B, repeat the permission flow. To observe a denial on a clean device,
   deny Steps and tap **Sync Activity** once. Expect a no-readable-data state
   and no queued upload, but do not label that result “denied” because HealthKit
   does not disclose read denial. Grant Steps in Settings before continuing.
3. Start the real-step run only after the scheduled local-hour boundary and the
   challenge activation. Record real steps on both devices during that first
   in-window local hour.
4. Wait until the entire local hour has ended on both devices. Confirm the
   Health app shows the steps. When an iPhone and Apple Watch both contributed,
   use Health's merged Apple-device total for comparison; do not add the two
   devices' raw sample totals. Do not tap **Sync Activity** during an unfinished
   hour because the client drops incomplete buckets.
5. Before A’s first sync, set a source breakpoint in
   `ActivitySyncCoordinator.deliver` on the call to
   `pendingUploads.acknowledge`. The breakpoint occurs only after the staging
   service accepts the metric response and before the local queue removes it.
6. On A, tap **Sync Activity** once. When the breakpoint stops execution, record
   the queued batch UUID in the debugger, then stop the process without
   continuing. Do not inspect or record the encoded body, assertion, step
   values, source identifiers, device metadata, or bucket timestamps.
7. Relaunch A. Confirm **Saved activity retry: 1** appears and no automatic
   upload occurs. Force-quit and relaunch once more to prove the same retry
   survives.
8. If the test setup supports controlled account switching on A’s device, sign
   in as B and confirm A’s saved count and batch are absent. Return to A and
   confirm the saved count is still one. If account switching is unavailable,
   keep physical account-isolation evidence open and rely only on the recorded
   automated result.
9. On A, tap **Sync Activity** once. Confirm the app sends the saved exact body
   and assertion rather than querying new samples, reports an accepted replay
   with the device-recorded step value confirmed from that saved activity, and
   clears the saved count. Record only whether the displayed value matches
   Health's merged completed-hour value, not the health value itself.
10. In a bounded private database check, confirm the batch UUID appears once and
   its retry did not duplicate the batch or observations. Record IDs, replay
   status, and counts only.
11. On B, record additional steps during another complete in-window local hour
    if needed. Wait until that hour ends, then tap **Sync
    Activity** once. Confirm an accepted first upload, a matching
    device-recorded confirmed total, and no saved retry.
12. Force-quit and relaunch both apps. Confirm the challenge ID and full roster
    still match and both saved-upload counts are zero.

Do not tap **Sync Activity** again after a confirmed first upload unless the
test explicitly targets a saved retry. A new explicit sync creates a new batch;
the duplicate-prevention proof is the replay of the saved batch UUID.

## Verify app logs contain no raw health data

Stop the GameTime process log capture after both syncs and review only messages
emitted by the app process:

1. Search for the metric batch UUIDs, `source_bundle_id`, `device_model`,
   `clientBatchId`, `observations`, `value`, and the known step totals.
2. Confirm the app emitted no encoded metric body, assertion, authorization
   header, sample timestamp, source identifier, device metadata, or step value.
3. Record pass/fail and a bounded count only. Do not record a log time range or
   attach raw HealthKit or request data to the evidence record.

Apple’s own HealthKit subsystem may emit system diagnostics. Keep those outside
the GameTime app-log evidence and never copy health values into this document.

## Required failure observations

- A missing or malformed URL/key blocks launch configuration.
- A secret/service-role key is rejected.
- Offline refresh preserves an explicit retryable state.
- Cancelling Apple authorization or an in-flight task produces no error alert.
- An empty HealthKit read makes no claim that permission was denied.
- A retryable metric transport failure retains one exact queued request across
  relaunch.
- The retained-status step total matches the values in the exact queued request,
  and the confirmed-status total matches the values acknowledged in that
  explicit sync.
- Overlapping iPhone/Apple Watch data is represented by HealthKit's merged
  Apple-device value rather than the arithmetic sum of raw samples. A
  controlled manual entry and any available third-party-only contribution are
  not presented as device-recorded steps.
- A different account cannot see or send the first account’s queued metric
  upload.
- Release cannot create or accept a challenge, expose fixture routing, request
  HealthKit permission, or sync activity.
- The staging activity flow exposes no background delivery, workout, location,
  settlement, donation, dispute, or APNs action.

## Result

| Gate | Status | Evidence |
| --- | --- | --- |
| Current working-tree automated verification | Passed locally and rerun after the hosted rollout | GameTimeCore 103/103; product unit 68/68; product UI 10/10; conformance 10/10; Deno 313/313 plus format/lint/check; Staging and Release builds passed; clean local database reset and 21-file/869-assertion pgTAP passed, followed by successful local-volume cleanup |
| Immutable creator/invitee review and staging diagnostics | Implemented locally; physical proof open | Record both reviews, same challenge ID, full roster, and breakpoint observation |
| Restart-safe challenge recovery | Implemented locally; physical proof open | Record request UUID, force-quit restore, original challenge ID, and bounded row counts |
| Eligible Apple team and prior Sign in with Apple provisioning | Prior partial evidence; current readiness blocked | The prior single-device launch observation passed. The current inventory had 0/2 connected devices available, so no fresh build, launch, or provisioning observation was attempted |
| Single-user native auth/onboarding/relaunch | Partial | Install, Apple identity, profile, live shell, and relaunch passed; Apple-name prefill remains open |
| Two-user force-quit/reload loop | Blocked before execution | Connect and unlock two provisioned devices and make two controlled Apple-authenticated staging accounts available |
| Same-request challenge duplicate proof | Open | Record challenge/request UUIDs and bounded database observation |
| Staging App ID HealthKit and App Attest provisioning | Partial | One signed install uses the intended HealthKit and development App Attest entitlement inputs; prove both capabilities at runtime and repeat on the second device |
| Physical App Attest registration/conformance | Blocked before execution | Complete the primary conformance-target registration, signed metric/check-in sends, exact replays, and bounded key/counter/receipt audit before sending real HealthKit data |
| Hosted App Attest identity strategy | Staging rollout and no-data probes passed; physical conformance open | The reviewed configuration is present, the two explicitly deployed bundles match the commit, 4/4 fail-closed and 3/3 authenticated availability/rejection cases pass, and no HealthKit data was sent |
| Two-account real step uploads | Blocked before execution | First complete physical App Attest conformance, then record one accepted batch UUID per account without raw health values |
| Merged Apple-device step accuracy | Unit-tested; physical proof open | For at least one completed hour with phone/watch overlap, record pass/fail against Health's merged value; separately confirm controlled manual and available third-party-only values are not labeled device-recorded |
| Lost metric response, relaunch, and exact replay | Unit-tested; physical proof open | Record one saved batch UUID, two relaunches, accepted replay, and zero duplicate rows |
| Metric queue account isolation | Unit-tested; physical proof open | Record the controlled account-switch observation |
| No raw health data in app logs | Static/unit checks pass; physical inspection open | Record pass/fail and a bounded count only |
| Release safety | Passed locally | Release build, configuration tests, UI gates, entitlement/plist separation, and scoped forbidden-API scans passed; signed distribution remains outside this record |
| Live multi-friend challenge | Open beyond M8.1 | Record a separate three-account observation before making a live multi-select claim |
| Background HealthKit delivery | Intentionally out of scope | Do not enable for this prototype |

Do not mark M8.1 or HealthKit complete until the physical two-account record
closes every applicable open row. Full M8 remains in progress after this gate.
The approved hosted configuration change and two-function deployment are
complete. This record authorizes no further hosted mutation, TestFlight
submission, production release, git push, settlement, donations, disputes,
APNs, or Core Location work.

## Current handoff

The reviewed Staging configuration and two explicitly deployed function
bundles are verified. No-data hosted rejection probes and the non-database
regression suite pass. After Docker recovery, the clean local database reset and
21-file/869-assertion pgTAP suite passed from a verified byte-identical
non-iCloud checkout, followed by successful local-volume cleanup.

The existing documentation commit is already on `origin/main`. This readiness
attempt stopped with 0/2 connected physical devices available. It did not open
an account session, launch either target, run App Attest, request HealthKit
permission, or send metric data. This blocked documentation note remains local
and uncommitted because the acceptance run did not complete.

Do not tap **Sync Activity** yet. Before resuming:

1. Connect two separate physical iPhones to the Mac, enable Developer Mode,
   trust the Mac, unlock both devices, and keep both screens awake until Xcode
   reports 2/2 devices available.
2. Register both devices with the eligible paid Apple team. Ensure the
   conformance target can use the explicit primary App ID on at least one
   device, and ensure both product provisioning profiles contain Sign in with
   Apple, HealthKit, and development App Attest.
3. Make two controlled, distinct Apple-authenticated staging accounts available,
   one per device, without sharing their identifiers in this record. At least
   one account must be eligible for the still-open first-sign-in editable-name
   prefill observation.
4. Restore read-only Supabase Management API access by signing the CLI in
   interactively or making an authenticated Dashboard secret-name view
   available. Do not paste a token into chat. Re-list names and confirm the
   reviewed primary identity, product additional identity, staging-only
   development acceptance, and `ATTEST_DEV_BYPASS` absence without changing
   any hosted value.
5. Provide the onboarded conformance Auth fixture on the first device. Run the
   physical App Attest registration/conformance sequence and its bounded
   database audit before opening the product HealthKit flow.
6. After conformance passes, install and launch the signed Staging product on
   both devices. Keep enough supervised time for a future exact local-hour
   start, challenge acceptance before that boundary, and two complete in-window
   hours. Generate real steps only after the challenge is active.
