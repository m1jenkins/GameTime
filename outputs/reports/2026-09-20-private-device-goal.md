# Private iPhone personal steps trial

Installed September 20, 2026; owner Apple account and device verification accepted.
The owner subsequently chose to keep Apple sign-in and skip device verification
for this private trial. That narrower account-only mode is now enabled.
This receipt records performed work separately from the owner actions and
real-time checks still required below.

## Scope and source

- Started from clean local `main` at reviewed `483d2c6`, on
  `codex/private-device-goal`. No push, purchase, plan upgrade, historical-backend
  mutation, container deletion, P7 restart or broad release exercise.
- Authorized target: `gametime-p11b` / `lyushhqoednheqwzsmxh`, Better Bet,
  `us-west-1`, existing Free plan and $20 ceiling.
- Internal iPhone identity: team `87Z29RTC26`, bundle
  `com.mjenkins.gametime.staging`, development App Attest. The existing profile
  expires August 11, 2027 and permits Apple sign-in, Health and App Attest.

## Implemented and installed

Staging overrides the historical public client with the selected HTTPS backend
and its active publishable key. Ordinary Signal challenge transport is enabled
in Staging. Debug and Release retain their previous configuration. Staging's
Auth Keychain and App Attest state are separated by backend; legacy key names,
owner-scoped pending requests and old data are preserved.

Migration `20260920160248_private_device_trial_v1` adds a project-local, normally
disabled private-trial guard. Its private, RLS-enabled account list is writable
only through database administration, not participant or Edge service API roles.
In trial mode, unapproved accounts cannot register a device, admit a real
challenge, save readiness or submit new activity. Approved accounts are limited
to `personal_steps_goal_v1` with `apple_watch_steps_v1`. Historical fixture
admission remains off. Saved matching request recovery and existing reads/exits
remain available. An authenticated active account can request an App Attest
nonce; that alone does not authorize registration or Health data.

The selected project now has 95 migrations. Only `attest-device` and
`ingest-challenge-health` were added to its three existing machine endpoints.
Both validate user JWTs against the platform-injected ES256 JWKS; gateway
`verify_jwt=false` delegates verification to these existing handlers. The
configured Apple identity is exact, development attestations are accepted,
Apple public root fingerprints were checked, and verification bypass is false.
Only the missing challenge HMAC credential was created, using existing owner
Vault/Edge custody. No secret was printed or committed; existing machine
credentials were preserved.

Native Apple sign-in is configured for the Staging bundle only. Native ID-token
exchange needs no web OAuth signing secret. Email, phone, anonymous providers
and manual linking remain disabled. Email is optional because the existing
native button requests name only. The owner completed Apple sign-in, profile
setup and deliberate 21+ confirmation through ordinary Signal. Hosted readback
found exactly one Apple account with an active session and its age confirmation.
Additional signup was then closed while existing-account Apple sign-in remains
enabled. Only that actual account was enrolled in the private list at
16:30:05 UTC. Real admission, ingestion and the Edge ingestion flag are enabled;
existing real processing remains enabled and all fixture gates remain off.

Two signed Staging device builds passed, including the final incremental build.
The built backend, public key type, bundle/team, entitlements, provisioning and
code signature were checked. The installed executable SHA-256 is
`6ce6afffe06f0f5bf7e46c7f214153fb574c786b2be1eed1e11c2d2f3323274e`. `scripts/check-iphone-product.py` passed with no
Watch app or WatchConnectivity payload. The app was installed over the existing
Staging app on Mason's iPhone (iOS 27.2). Launch initially failed because the
phone was locked. After the owner unlocked it, a fresh Staging build from local
main `1752009` passed, was installed in place, and launched successfully with no
arguments (process 4694). The rebuilt installed executable SHA-256 is
`e562ffa3c086f4715174d699987b673baf5337aa157e9ddf2d0a48a3befb38a8`.

## Owner-authorized account-only trial

The owner's explicit follow-up was “Keep Apple sign-in; skip device
verification.” Migration `20260920164443_private_account_health_v1` adds a
normally-required device-proof setting. Only this selected project's enabled
private trial sets it false, with exactly one enrolled account. New readiness
and activity writes may omit device proof only for that account. Authentication,
actor/session binding, Health consent, agreement consent, source rules, real
clocks, payload digests and idempotency remain enforced. Unsigned requests carry
an explicit `private_account` provenance; no fake key, receipt or counter is
recorded. Invalid or partial signed proof never falls back to the unsigned path.

`GAMETIME_PRIVATE_HEALTH_ACCOUNT_MODE` is enabled only in the selected Staging
build and additionally checks the exact backend host. Debug, Release and other
backends remain unchanged. New account-only requests preserve their exact bytes
for retries. Existing signed requests retain their original bytes and storage.
The existing development device registration remains valid historical evidence;
the account-only path does not claim device verification.

The migration dry run selected only this new migration, application succeeded,
and readback confirmed 95 migrations, one approved account, private mode enabled
and all three real runtime gates enabled. Signup remains closed. Only
`ingest-challenge-health` was redeployed for this change (version 4, then version 5
to align the final source formatting).
Both Health endpoints again refused unauthenticated POSTs with HTTP 401; the
private-account helper refused an unapproved actor. The Free plan, $20 ceiling,
machine credentials, schedules and historical backend were unchanged.

Focused verification: 14/14 SQL assertions on a unique disposable local backend,
64/64 Edge handler/database tests, 13/13 Core request/journal tests and 21/21 native
configuration, transport, account-fence and retry tests passed. The native result
is `/private/tmp/gametime-private-device/native-private-account.xcresult`.
The signed device build passed, installed in place, and launched ordinary Signal
with no arguments (process 4953). That executable's SHA-256 is
`b8badf5a6f739208b0fbef02b752e7134204d05c126ce6dc098e1721832688a5`.

## Focused checks performed

- Private-trial SQL: 12/12 assertions passed in a unique disposable local
  Supabase project. Its database, network and temporary copy were removed.
  The initial Docker default address-pool failure was resolved with a new
  task-owned explicit subnet; no other project's stack was reset or reused.
- Hosted dry run selected only the new guard migration, then application and
  history readback succeeded. Trial mode was first enabled with zero enrolled
  accounts; owner enrollment later raised the list to exactly one.
- Both newly deployed endpoints returned HTTP 401 to unauthenticated POSTs.
- A rolled-back hosted guard check refused unapproved admission. Catalog checks
  confirmed clients/Edge keys cannot enroll themselves, and neither anonymous
  nor authenticated clients can directly call the service-only ingest RPC.
- After real admission/ingestion were enabled, another rolled-back check refused
  both an unapproved actor and a null actor with the private-account guard.
  Both endpoints still returned HTTP 401 to unauthenticated requests.
- The real device registered with development App Attest at 16:31:11 UTC, and
  independent receipt verification succeeded. No verification bypass was used.
- Security advisors reported intentionally closed private tables without RLS
  policies ([INFO](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy))
  and existing authenticated SECURITY DEFINER interfaces
  ([WARN](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)).
  The new helpers are private and explicitly revoked. This was not a broader
  legacy API audit; no historical grants were rewritten.
- Focused native regressions: 2 passed, 0 failed, 0 skipped on a task-owned
  iPhone 16 Pro / iOS 18.6 simulator. They check the exact original App Attest
  storage key, backend isolation, and both new actionable guard messages.
  The simulator was deleted after the run. Log and result bundle remain at
  `/private/tmp/gametime-private-device/native-config-focused.log` and
  `/private/tmp/gametime-private-device/native-config-focused.xcresult`.

## Defect found on the actual phone

The initial activity check incorrectly asked the owner to unlock an already
unlocked phone. Registration and receipt verification had succeeded, but signed
readiness returned HTTP 401 before database ingestion. A read-only copy of only
the pending minimal readiness request was checked privately against the
registered public key. Its real signature verified using the existing nonce
construction; the parser instead misread flags `0xc0` as a credential block.
This device supplied the 37-byte assertion prefix followed by one map containing
`apple_bundle_version_01` and `apple_validation_category_01`.

The parser now accepts that exact, strictly validated map only in assertion
context. Original signed bytes, App ID, key, session and replay checks are
unchanged. Credential blocks, malformed/extra maps, tampered payloads and wrong
keys/apps remain refused. Synthetic regressions contain no owner's identity,
request, signature or Health data. The corrected `ingest-challenge-health`
endpoint was deployed only to the selected project; no other hosted endpoint
was redeployed for this fix.

Readiness failures now distinguish storage, delivery, connection, session and
busy conditions. Generic failures no longer instruct the person to unlock the
phone; only storage failures retain that recovery action. Saved requests remain
pending for normal exact retry. The focused server tests passed 94/94, and the
native error/recovery regression passed 1/1 with no failures or skips. Its result
is `/private/tmp/gametime-private-device/native-readiness.xcresult`. Its disposable
simulator was removed. The corrected Staging device build also passed.

The next real attempt reached the database and returned HTTP 403. Status-only
function logs and named database error messages identified
`challenge_private_trial_personal_steps_only`: the original saved readiness
request was for outdoor running distance. That out-of-scope signed request was
blocking every later check. Account-only delivery now defers the old signed queue
without deleting or rewriting it; account-only requests consume no device counter.
An attempt to reuse a signed request ID in this mode is refused, never falsely
acknowledged or converted. Default signed recovery keeps its counter ordering.
The private build's creation form now opens directly to Personal Steps and does
not offer unsupported Who/Activity choices. Review validates the entered target,
shows errors beside the button, and scrolls to the complete agreement.

The final transport/configuration/error regression run passed 22/22, with no
failures or skips, including preserved signed journals and independent exact
account-only retries. The new scrolling render check passed 1/1 after correcting
the test's case-sensitive expectations against its lowercase OCR transcript;
its initial failure was a test assertion error. Result bundles:
`native-private-account-recovery.xcresult` and `native-private-steps-ui-retry.xcresult`
under `/private/tmp/gametime-private-device`. The existing broader HTTP-backed UI
test was updated but not run; no P12 matrix or broad acceptance was repeated.
The final signed Staging build passed and installed over the same app container,
then launched with no arguments (process 5056). Its executable SHA-256 is
`8c7439d126560f2030053f7ea302a79b1a4d7041a041ebdbf8f2bc866de56cc8`.
The active iPhone product guard passed again.
The task-owned simulator was deleted after the focused checks. Temporary private
debug copies were removed; no original on-phone journal was
deleted or rewritten. A later read-only copy of that specific protected file was
refused by the device, so the post-fix preservation check relies on the focused
exact-journal regression rather than a successful second file readback.

The old signed distance request remains outside this steps-only trial. Legacy
signed sync callers retain their original recovery behavior and may still meet
that refusal; they were not reconfigured or accepted in this bounded milestone.
They do not block the accepted account-only steps path.

## Real device acceptance

The owner reported the corrected flow worked. Hosted readback confirmed real
`apple_watch_steps_v1` readiness in `private_account` mode, first accepted at
17:06:16 UTC. One `personal_steps_goal_v1` was created and consented at
17:06:20 UTC, with status `scheduled`. Its chosen target is **4,703 total steps**
over seven days, with **$20 in nonredeemable simulation**. The consent's digest
and version match the saved agreement. SQL checks confirmed local-midnight start
and at least two calendar days between creation and start.

The exact saved consent request was replayed twice under the actual account's
authenticated session claims in a rolled-back transaction. Both responses matched
the original receipt; counts remained one goal, one consent and one personal
commit request. No new goal or consent was manufactured. The app was stopped and
relaunched normally (process 5068). Subsequent on-device detail requests returned
HTTP 200 and hosted readback still had one goal and one consent; explicit owner
confirmation of the refreshed visual is pending. No raw Apple Health history was uploaded or added to
this repository. At this check there were zero challenge activity facts, as the
window has not begun. The app container was never removed and no launch used
fixture/investigation flags.

## Real-time checks still pending

Scheduled starts and real clocks are unchanged: starts are local midnight at
least two calendar days after creation. Activity counting cannot be accepted
before the selected start. Initial uploads close at end +24 hours, corrections
at end +48 hours; provisional publication is due by end +72 hours, review lasts
48 hours after the actual notice, and a filed review has its existing 72-hour
resolution period. Missing
activity remains unknown and cannot establish a loss.

The saved agreement uses America/Los_Angeles. Its actual deadlines are:

| Check | Pacific time (PDT) | UTC |
| --- | --- | --- |
| First active window; verify actual Watch steps begin counting | September 22, 00:00 | September 22, 07:00 |
| Seven-day activity window ends | September 29, 00:00 | September 29, 07:00 |
| Initial activity updates close | September 30, 00:00 | September 30, 07:00 |
| Corrections close | October 1, 00:00 | October 1, 07:00 |
| Provisional notice due | October 2, 00:00 | October 2, 07:00 |

The review deadline remains 48 hours after the actual notice, and a filed review
has 72 hours for resolution. Neither deadline is invented before its event.
These future checks are unperformed; no clock was advanced and no reminder or
monitoring automation was created.

This private device slice is not wider Beta readiness. Four friend leaderboard
modes remain unavailable; the other source, operational, human and release
requirements remain unresolved. D140's distribution-scope decision is unchanged.
No friends, invitation domain, community, TestFlight, recruitment, payments or
public distribution were enabled. Every challenge amount is nonredeemable
simulation.
