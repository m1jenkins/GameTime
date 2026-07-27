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
5. As A, create a one-to-one duel using one of the four backend metrics,
   daily or cumulative cadence, future dates, a valid target, staging pledge,
   charity, and tie-break. Confirm the review screen presents immutable terms
   before submission.
6. Simulate a lost response after the server commits the creation request.
   To make this deterministic, set an Xcode breakpoint on
   `SupabaseContestsClient.createDuel` immediately after the awaited RPC returns
   its `contestID` and before the method returns it to `AppModel`. Submit once;
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
| Apple product App ID and eligible signing team | Open | Record team-owned verification |
| Two-user force-quit/reload loop | Open | Record dated observation |
| Same-request duplicate proof in staging | Open | Record contest/request UUIDs and bounded database observation |

M8.1 is complete only when every row is closed. Full M8 remains in progress
until sensors, App Attest, durable inbox/APNs, finalization, settlement,
disputes, accessibility hardening, and privacy disclosures are delivered.
