# Bounded profile-creation retry correction — September 18, 2026

Implemented locally on `codex/profile-creation-retry`, starting from current
`main` at `4f5b528`. No merge, push, deployment or hosted configuration change.

## Behavior

`SupabaseProfileClient.createProfile` recovers a PostgreSQL `23505` error naming
the `profiles_pkey` constraint by reading the requested actor's profile by ID.
It returns only a row whose ID matches that actor. The existing AppModel
authentication-generation checks still reject late completion after sign-out
or account switching. Recovery returns saved values without updating the row.

Username constraint conflicts still fail with the existing inline copy. Missing
or wrong-actor recovery, unrelated constraints, and network/permission errors
remain errors. Generic duplicate-key failures no longer map to an unavailable
username. INSERT still omits RETURNING; database uniqueness and RLS are unchanged.

The historical accessibility commit
`8e2e267d2c853175ec4bf63cd5555419b639c983` was inspected directly through existing
Git objects, including its constraint-classification and profile retry/actor
regressions. No old branch, onboarding design or controller implementation was
merged. Health/P7 and hosted settings were untouched.

## Actual verification

Final focused Xcode run: **63 tests passed, zero failures**, on the iPhone 17 Pro
iOS 27.0 Simulator, Debug, signing disabled:

- `SupabaseProfileClientTests`: 9 tests, including normal creation, lost insert
  response, lost follow-up read, true username conflict, no/wrong-actor profile,
  network and permission errors, and constraint/error-mapping boundaries.
- `AppModelAndRoutingTests`: 34 tests, including the new delayed profile recovery
  check across sign-out and actor replacement and existing onboarding assertions.
- `DomainAndConfigurationTests`: 20 tests.
- `git diff --check`: passed.

```sh
xcodebuild test -project ios/GameTime/GameTime.xcodeproj -scheme GameTime \
  -destination 'platform=iOS Simulator,id=B3E5DFC7-ED3F-4620-B86A-4F20B2AEAA2A' \
  -only-testing:GameTimeTests/SupabaseProfileClientTests \
  -only-testing:GameTimeTests/AppModelAndRoutingTests \
  -only-testing:GameTimeTests/DomainAndConfigurationTests \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -resultBundlePath /tmp/gametime-profile-retry-final.xcresult \
  CODE_SIGNING_ALLOWED=NO
```

Local log: `/tmp/gametime-profile-retry-final.log`. The result bundle and log are
temporary local artifacts, not committed evidence files.

The first run executed 62 tests with four failure assertions in two new transport
tests (one unexpected thrown error). Their scripted responses omitted the pinned
SDK's three automatic GET retries. The fixture scripts were corrected to sustain
network failures across all four attempts; production retry policy was unchanged.
The actor-switch regression was included in the final run. The initial log is
`/tmp/gametime-profile-retry-first.log`. Its optional simulator diagnostic collector
was stopped after test completion; Xcode exited 65. The final run completed
normally with exit 0 and its result bundle intact.

## Limits

Transport tests exercise the real Supabase Swift request/response path through
an intercepted URLSession with fictional responses and empty Auth storage. They
verify actor-ID filters and returned IDs, but do not establish server commits,
real authentication or RLS behavior. No database integration, hosted request,
physical-device, UI/accessibility or full release gate was run. Unrecognized
constraint responses fail closed rather than attempting recovery.
