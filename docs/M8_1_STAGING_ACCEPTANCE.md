# Prove the functional two-user alpha

This run proves the smallest useful GameTime loop on two physical iPhones. Both users must sign in, become friends, complete one steps challenge, sync activity through App Attest, and see the same final result.

Do not use this run to claim production readiness. It excludes real donations, disputes, push notifications, background HealthKit delivery, Core Location, workouts, TestFlight, and App Store release.

## Prerequisites

Do not start until every prerequisite is available:

- Two unlocked physical iPhones with Developer Mode enabled
- Both devices trusted by the Mac and registered to the paid Apple team
- Two distinct Apple-authenticated staging accounts
- Product provisioning profiles with Sign in with Apple, HealthKit, and development App Attest
- `com.mjenkins.gametime.staging` configured as the product App ID
- Read-only confirmation of the reviewed Supabase project, bundle IDs, function versions, and secret names
- `APP_ATTEST_ALLOW_DEVELOPMENT=true` in Staging
- `ATTEST_DEV_BYPASS` absent
- One active staging charity
- The hosted activation job and clean-result caller enabled for Staging
- A completed M6.5 conformance run on the first device

No service-role key, Apple private key, access token, or provider secret belongs in the app or this record.

## Record only bounded evidence

Record:

- Challenge, request, and metric-batch UUIDs
- Pass or fail
- Bounded row and retry counts
- Hosted job success or failure

Do not record:

- Apple IDs, handles, names, or profile details
- Access tokens, keys, assertions, receipts, or authorization headers
- Step values, source identifiers, device health metadata, or request bodies
- Exact timestamps or raw logs containing private data

## Run the account and friendship flow

1. Install the signed Staging build on both devices.
2. Start a GameTime-only log capture without request-body or authorization-header logging.
3. Sign in with Apple as Account A and finish onboarding.
4. Force-quit and relaunch A. Confirm the same account and four-tab shell return.
5. Repeat sign-in, onboarding, force-quit, and relaunch for Account B.
6. Record whether Apple provides an editable first-sign-in name prefill.
7. On A, find B by exact handle and send a friendship request.
8. Force-quit and relaunch both apps.
9. On B, accept the request.
10. Force-quit and relaunch both apps. Confirm both show the accepted friendship.

## Run challenge creation and exact retry

1. Choose a future whole-hour start and a short steps challenge window.
2. On A, review every immutable term and create the challenge for B.
3. Deliberately interrupt the creator after the server commits but before the app records the response.
4. Force-quit and relaunch A.
5. Confirm the pending request restores with the original request UUID and terms.
6. Retry the exact request.
7. Confirm the retry returns the original challenge UUID and the database contains one challenge.
8. On B, review the same terms and accept.
9. Force-quit and relaunch both apps. Confirm both show the same pending challenge and roster.

## Prove hosted activation

1. Wait for the named hosted job to activate the committed challenge.
2. Confirm both apps show the challenge as active after refresh or relaunch.
3. Record the bounded job result and one challenge status.
4. Do not force the row active with a test-only database update.

## Run App Attest and steps sync

1. On both devices, tap **Enable Activity** and allow Steps read access.
2. On A, tap **Sync Activity**.
3. Confirm product App Attest registration succeeds without a bypass.
4. Confirm one metric batch is accepted and its receipt matches the queued batch and observation count.
5. Repeat the first successful sync on B.
6. Create one retryable lost-response condition for a metric upload.
7. Force-quit and relaunch the affected app twice.
8. Confirm the same queued request bytes and batch UUID remain.
9. Tap **Sync Activity** and confirm the exact replay is accepted without duplicate observations.
10. Switch accounts only if the test devices support the controlled flow. Confirm one account cannot load or drain the other account's queue.

An empty HealthKit read does not prove permission denial. Record it as no readable data.

## Prove standings and the final result

1. Confirm both users see the same challenge and participant roster.
2. Confirm live standings show the caller's integrity detail but not the rival's private detail.
3. Let the challenge end and wait for ingest grace to close.
4. Confirm the authorized staging caller publishes one clean frozen result.
5. Retry the caller and confirm no second result appears.
6. Confirm both users see the same final ordering and rationale.
7. Confirm no pledge or donation becomes actionable.

If the assessment is quarantined or fails, the challenge must remain under review and non-actionable. Do not manually approve it for this run.

## Verify failure and privacy behavior

Confirm:

- Cancelled Apple authorization produces no duplicate request
- Offline challenge creation restores one pending request
- Offline metric sync retains one exact queued request
- Sign-out clears account-bound models and cached standings
- Release does not expose fixtures, activity sync, or challenge mutations
- GameTime logs contain no step values, request bodies, assertions, access tokens, source identifiers, or private profiles

Apple system logs may contain HealthKit diagnostics. Keep them outside the GameTime evidence record.

## Completion checklist

- [ ] Two physical devices and two Apple-authenticated accounts
- [ ] Sign-in, onboarding, force-quit, and relaunch on both devices
- [ ] Exact-handle friendship persists on both devices
- [ ] One immutable challenge exists after a lost-response retry
- [ ] Hosted activation changes the committed challenge to active
- [ ] M6.5 physical conformance passes without `ATTEST_DEV_BYPASS`
- [ ] Product App Attest registers and signs accepted metrics
- [ ] One accepted metric batch per account
- [ ] One exact metric replay with no duplicate observations
- [ ] Queue and model state remain account-isolated
- [ ] Both users see privacy-bounded live standings
- [ ] One idempotent clean final result appears
- [ ] No real pledge or donation becomes actionable
- [ ] GameTime logs expose no sensitive health or authentication data

GameTime reaches functional two-user alpha only when every box passes. If two devices or accounts are unavailable, stop and leave the checklist open.
