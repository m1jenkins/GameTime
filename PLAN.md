# Get GameTime to a functional two-user alpha

GameTime reaches functional alpha when two real people can sign in, become friends, create and accept a challenge, sync steps from physical iPhones, see trustworthy standings, and finish the challenge without duplicate requests or exposed health data. This file lists only the work required to reach that result.

`README.md` records what is built. `DECISIONS.md` records why. The dated implementation audit and the previous milestone plan are archived under `docs/archive/`.

## What functional means

The alpha must let two real users:

- Sign in with Apple and restore the same account after relaunch
- Find each other by exact handle and accept a friendship
- Create, review, accept, and reload one immutable steps challenge
- Let the hosted scheduler activate the challenge at its start time
- Manually sync completed step intervals from each physical iPhone
- Register and use product App Attest without `ATTEST_DEV_BYPASS`
- Retry a lost challenge or metric response with the same request bytes and no duplicate rows
- See participant-only live standings and one frozen final result
- Keep health values, request bodies, assertions, tokens, and rival integrity details out of logs and unauthorized reads

The alpha does not move money. Every build must retain the staging message that no real pledge is collected or enforced.

## Clean alpha candidate

The candidate and its supporting foundations are consolidated on current
`main`. It contains the App Attest ECDSA fallback and current staging App IDs,
so no runtime fix needed to be ported. Consolidation also retains the locally
verified D76 deadline/escalation
foundation and M8.4 lead-loss push/reaction path. They do not expand the alpha
gate: operated adjudication, hosted D76 timer proof, APNs/device proof, a durable
action inbox, and settlement remain deferred.

The complete local database, Deno, Swift package, product, configuration, and
conformance matrix passes. Before deployment, the exact reviewed `main` commit
must also complete one green CI run.

Exit criteria:

- The functional-alpha commit remains independently reviewable in history
- Optional notification and review foundations do not become alpha requirements
- Database migrations, pgTAP, Deno checks, GameTimeCore tests, product tests, conformance tests, and Staging and Release builds pass
- `git diff --check` passes
- The reviewed commit is identical to the commit tested by CI

## Next step: prove the hosted challenge lifecycle

The backend must open and close a real challenge without test-only row changes.

1. Observe `gametime-activate-due-contests` activate one committed staging challenge.
2. Exercise friendship, invitation acceptance, metric ingest, and standings against that scheduler-activated challenge.
3. Connect the existing trusted assessment and first-result publisher to one authorized staging-only caller for clean challenges.
4. Publish a result only after ingest grace closes and the evidence digest is frozen.
5. Leave quarantined or failed assessments visibly under review and non-actionable. The implemented D76 deadlines may escalate and fail closed to `inconclusive`; do not enable an unstaffed hosted operator path for alpha.
6. Record bounded IDs, counts, job results, and failure recovery. Do not record health values or credentials.

Exit criteria:

- A committed challenge activates through the hosted job
- A clean challenge receives one idempotent frozen result
- A retry does not create a second result
- A failed or quarantined assessment creates no actionable obligation
- Scheduler and finalizer failures are visible to the operator

## Run the physical two-user acceptance

Use `docs/M8_1_STAGING_ACCEPTANCE.md` as the runbook. The alpha remains incomplete until this record passes.

Prerequisites:

- Two unlocked, trusted, provisioned physical iPhones
- Two distinct Apple-authenticated staging accounts
- Sign in with Apple, HealthKit, and development App Attest on both provisioning profiles
- Read-only confirmation of the reviewed staging bundle IDs and secret names
- `ATTEST_DEV_BYPASS` absent
- One active staging charity and the hosted activation worker

Run:

1. Sign in and complete onboarding on both devices.
2. Add and accept the friendship, relaunch both apps, and confirm it persists.
3. Create and accept one steps challenge.
4. Deliberately lose the creator response, relaunch, retry the exact request, and confirm one challenge exists.
5. Let the hosted worker activate the challenge.
6. Complete the M6.5 conformance run on the first device, then register product App Attest and upload one accepted step batch from each account.
7. Lose one metric response, relaunch, replay the exact saved request, and confirm no duplicate observations.
8. Confirm account isolation, live standings, and the clean frozen result.
9. Inspect GameTime logs for raw health values, request bodies, assertions, tokens, or private profile data.

Exit criteria:

- Both users complete the full challenge loop on separate physical devices
- Apple authentication, friendship, challenge state, and pending retries survive force-quit and relaunch
- M6.5 conformance plus product App Attest registration, assertion, and exact replay pass without a bypass
- Both metric uploads are accepted once
- Both users see the same challenge and privacy-bounded standings
- The challenge reaches one clean final result
- The app logs expose no sensitive health or authentication data

If two devices or accounts are unavailable, stop after repository and hosted-lifecycle work. Do not add more product features to compensate for missing physical evidence.

## Finish essential alpha hardening

Complete only the safeguards required to test the core loop:

- Add bounded monitoring for activation, metric ingest, App Attest registration, and finalizer failures
- Add rate limits to exact-handle lookup, challenge creation, and signed ingest
- Keep clear loading, empty, offline, retry, and under-review states
- Keep Release fixture routes, activity sync, and challenge mutations disabled until release approval
- Verify sign-out clears account-bound caches and pending requests
- Document staging backup and rollback steps for the migrations used by the alpha

The functional alpha is complete when the repository, hosted lifecycle, and physical acceptance gates all pass. TestFlight, production deployment, and App Store submission require separate approval.

## Current implementation status

| Capability | Current state | Remaining alpha proof |
| --- | --- | --- |
| Apple sign-in and onboarding | Implemented; one-user signed-device proof exists | Two-user relaunch proof and Apple name-prefill observation |
| Friendship and challenge creation | Implemented with exact-handle lookup and atomic idempotent creation | Two-user physical acceptance |
| Restart-safe challenge retry | Implemented and tested locally | One lost-response device observation |
| Scheduled activation | Implemented and tested locally | Committed-row hosted observation |
| Manual steps sync | Implemented for Staging with exact-byte persistence | Two physical uploads, replay, and account isolation |
| Product App Attest | Client and verifier paths implemented | Physical registration, assertion, replay, and counter or receipt observation |
| Live standings | Implemented with participant-only redaction | Real two-user staging observation |
| Clean final result | Assessment and first-result foundations implemented | Authorized hosted caller and committed clean-result observation |
| D76 review deadlines | Local 72-hour peer and seven-day adjudication escalation foundation implemented | Excluded from alpha; hosted operation requires authorization, staffing, and proof |
| Notifications and reactions | Local lead-loss intent, APNs delivery, deep-link, and reaction path implemented | Excluded from alpha; hosted APNs and device proof remain open |
| Money settlement and disputes | Foundations and decisions exist | Excluded from functional alpha |

## Deferred until the core loop is validated

Do not schedule these items before the functional alpha passes:

- Real donation collection, receipt confirmation, defaults, disputes, and reliability scoring
- Full D76 adjudicator authorization, staffed queues, conflict handling, and service-level agreements
- Hosted APNs rollout and device proof, a durable action inbox, and remaining notification types
- Background HealthKit delivery
- Core Location, workout collection, and product check-in integration
- Additional group-challenge work beyond the existing atomic roster support
- Avatar storage, group feeds, reminders, and demo-mode polish
- User-facing account-deletion recovery and production-scale retention operations
- Production charity curation
- TestFlight, production deployment, App Store work, and marketing

## Verification rules

- Simulator and fixture tests prove code behavior, not physical Apple services
- Local database tests prove migrations and policies, not hosted scheduling
- A signed build proves signing inputs, not App Attest or HealthKit behavior
- One user does not prove friendship, challenge sharing, or account isolation
- Never expose a service-role key, Apple private key, access token, assertion, or raw health value
- Preserve exact request UUIDs and encoded bytes for every retried mutation
- Require explicit approval before push, merge, deployment, TestFlight, production configuration, or submission

## References

- `docs/M8_1_STAGING_ACCEPTANCE.md`: physical two-user alpha runbook
- `docs/M6_5_DEVICE_CONFORMANCE.md`: full metric and check-in conformance reference
- `docs/archive/2026-07-30_M7_ACCOUNT_DELETION_RETENTION.md`: retained account-deletion and data-lifecycle design
- `docs/archive/2026-07-30_IMPLEMENTATION_STATUS.md`: historical audit evidence
- `docs/archive/2026-07-30_IMPLEMENTATION_PLAN.md`: previous milestone plan
