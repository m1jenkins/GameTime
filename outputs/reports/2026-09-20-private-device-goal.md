# Private iPhone personal steps trial

Installed September 20, 2026; phone acceptance is pending owner interaction.
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

The selected project now has 94 migrations. Only `attest-device` and
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
native button requests name only. Initial Apple account signup is temporarily
open behind the private-trial guard; new goal admission and ingestion remain
closed pending the owner's actual account enrollment.

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

## Focused checks performed

- Private-trial SQL: 12/12 assertions passed in a unique disposable local
  Supabase project. Its database, network and temporary copy were removed.
  The initial Docker default address-pool failure was resolved with a new
  task-owned explicit subnet; no other project's stack was reset or reused.
- Hosted dry run selected only the new guard migration, then application and
  history readback succeeded. Trial mode is enabled with zero enrolled accounts.
- Both newly deployed endpoints returned HTTP 401 to unauthenticated POSTs.
- A rolled-back hosted guard check refused unapproved admission. Catalog checks
  confirmed clients/Edge keys cannot enroll themselves, and neither anonymous
  nor authenticated clients can directly call the service-only ingest RPC.
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

## Remaining device acceptance and real-time checks

Apple sign-in, name/username setup, deliberate 21+ confirmation, owner enrollment,
device verification, minimal readiness acknowledgment and the owner's chosen
goal/consent are pending. The agent must not manufacture these confirmations.
After one saved agreement, relaunch and refresh must retain that same goal.
The last hosted setup readback had zero Auth users, profiles, 21+ confirmations,
registered devices and challenges. No real Health record or consent has been
created on the owner's behalf. The phone was installed in place; its container
was never removed. Neither launch attempt used fixture/investigation flags.

Resume on the phone: open GameTime Staging, use Apple sign-in, complete the
name/username form, then save the 21+ confirmation in Challenges. Verify that
actual Apple account before enrolling its UUID in the private account table.
Close additional Auth signup after that first owner account is established;
keep existing-account Apple sign-in. Only then enable the existing real
admission/ingestion controls and Edge ingestion flag. From Challenges choose
Create a challenge → Personal goal → Steps, choose a target/dates/simulated
amount, connect Apple Health, review the agreement, obtain a current accepted
readiness check and deliberately agree. Do not infer any of these choices.

Scheduled starts and real clocks are unchanged: starts are local midnight at
least two calendar days after creation. Activity counting cannot be accepted
before the selected start. Initial uploads close at end +24 hours, corrections
at end +48 hours; provisional publication is due by end +72 hours, review lasts
48 hours after the actual notice, and a filed review has its existing 72-hour
resolution period. Record exact selected instants after consent. Missing
activity remains unknown and cannot establish a loss.
The next real-time check is the chosen goal's first active window. If it is
created September 20 in America/Los_Angeles, the earliest possible start is
September 22 at 00:00 PDT (07:00 UTC). This is conditional guidance, not a saved
agreement or a scheduled reminder.

This private device slice is not wider Beta readiness. Four friend leaderboard
modes remain unavailable; the other source, operational, human and release
requirements remain unresolved. D140's distribution-scope decision is unchanged.
No friends, invitation domain, community, TestFlight, recruitment, payments or
public distribution were enabled. Every challenge amount is nonredeemable
simulation.
