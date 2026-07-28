# M8.1 staging acceptance

M8.1 is an internal staging alpha. Repository implementation and fixture proof
do not complete this gate: completion requires two Apple-authenticated users
against the staging project and the observations below.

## External prerequisites

- an eligible Apple Developer Program or Enterprise Program team;
- a unique product App ID with Sign in with Apple enabled;
- matching target signing and Supabase Apple provider configuration;
- the M8.1 migration applied to staging;
- a current staging Supabase URL and publishable key in the gitignored product
  app configuration;
- at least one active, staging-only charity row; and
- two test users controlled by the team.

No service-role key, Apple private key, or provider secret belongs in the app.
If provisioning is unavailable, record the slice as implemented with staging
proof open, not complete.

## Evidence record

Record the date, app commit, Xcode version, iOS version, device models, staging
project reference, both pseudonymous test handles, and the contest/request UUIDs.
Do not record Apple IDs, access tokens, publishable keys, or private profile
data.

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

## Two-account flow

Use User A and User B on separate devices, or erase all app/session state before
switching accounts. After every successful mutation, force-quit and relaunch
the affected app before continuing.

1. Sign in with Apple as User A. Confirm a cryptographic nonce is exchanged,
   finish onboarding, and verify Apple’s first-sign-in name is only an editable
   prefill. Record A’s handle.
2. Repeat for User B and record B’s handle.
3. As A, submit B’s complete handle. Confirm there are no fuzzy results, send
   the friend request, force-quit, relaunch, and verify it reloads as outgoing.
4. As B, relaunch, verify the request is incoming, accept it, force-quit, and
   relaunch. Relaunch A as well; both users must see the accepted relationship.
5. As A, create a challenge for B using one of the four backend metrics, daily
   or cumulative cadence, future dates, a valid target, staging pledge,
   charity, and tie-break. Confirm the review screen presents B and every
   immutable term before submission.
6. Simulate a lost response after the server commits the creation request.
   To make this deterministic, set an Xcode breakpoint on
   `SupabaseContestsClient.createChallenge` immediately after the awaited RPC
   returns its `contestID` and before the method returns it to `AppModel`.
   Submit once;
   when the breakpoint proves the server response arrived, stop the process in
   Xcode without continuing. Relaunch A, confirm the app shows a saved request
   and did not retry automatically, then open its immutable review. Verify the
   visible request UUID and every term match the first attempt. Tap Submit
   manually once more. Confirm the response returns the original contest and
   staging contains exactly one contest, two participant rows, and one private
   idempotency record for that actor/request.
7. Force-quit and relaunch A. Confirm the pending contest reloads and the local
   saved-retry card is gone after the confirmed response.
8. Relaunch B. Confirm the invitation and identical immutable terms reload,
   choose B’s charity, and accept.
9. Force-quit and relaunch both apps. Confirm both users see the same pending
   contest UUID and roster state, with no duplicate contest.

M8.3a's repository tests additionally select two friends, verify the complete
three-person review, and prove that both invitations travel through one atomic
RPC. This two-account staging gate does not claim a live multi-friend
observation.

## Required failure observations

- A missing or malformed URL/key blocks launch configuration.
- A secret/service-role key is rejected.
- Offline refresh preserves an explicit retryable state.
- Cancelling Apple authorization or an in-flight task produces no error alert.
- Release cannot create or accept a contest.
- Live builds expose no account deletion, group feed, sensor permission,
  finalization, settlement, or dispute actions.

## Result

| Gate | Status | Evidence |
| --- | --- | --- |
| Repository implementation and automated tests | Implemented | Record CI URL and commit |
| Restart-safe same-request recovery | Implemented locally | Record force-quit retry UUID and staging observation |
| Apple product App ID and eligible signing team | Verified for one development device | 2026-07-27 observation above |
| Single-user native auth/onboarding/relaunch | Partial | Install, Apple identity, profile, live shell, and relaunch passed; Apple-name prefill remains open |
| Two-user force-quit/reload loop | Open | Record dated observation |
| Same-request duplicate proof in staging | Open | Record contest/request UUIDs and bounded database observation |
| Live multi-friend challenge | Open beyond M8.1 | Record a separate three-account observation before making a live multi-select claim |

M8.1 is complete only when every row is closed. Full M8 remains in progress
until sensors, App Attest, durable inbox/APNs, finalization, settlement,
disputes, accessibility hardening, and privacy disclosures are delivered.
