# Friends TestFlight Phase 3: native

September 22, 2026. This is Phase 3 of the
[friends TestFlight plan](../../docs/FRIENDS_TESTFLIGHT_PLAN.md) under
[D142](../../DECISIONS.md#d142-first-private-testflight-adds-friends-opens-apple-sign-up-and-ships-goals-first).
The work is native source, tests, build configuration and a checker, all local.
Nothing was applied to `gametime-p11b` or any other hosted project, nothing
was installed on a phone, and nothing was pushed or uploaded. The approved
[Phase 1 mocks](../../.lavish/gametime-friends-2026-09-22/README.md) are the
reference, and the [Phase 2 receipt](2026-09-22-friends-phase-2-server.md)
defines the server contract.

## What changed

| Area | Source |
| --- | --- |
| Friend commands and store | `FriendModels.swift`, `FriendsStore.swift`, friend RPCs on `SupabaseChallengeV1Client` |
| Friends under You | `FriendsViews.swift`, one row in `LiveRecordView` |
| Home action rows | `HomeActionRows.swift`, `LiveHomeView` |
| Invite step and saved lobby | `ChallengeCreationInviteView.swift`, `ChallengeCreationSuccess.swift` |
| Onboarding age step | `LiveOnboardingView`, `AppModel.saveOnboardingAgeConfirmation()` |
| Server-reported policies | `ChallengeV1Availability`, `ChallengeV1Store.availability`, `ChallengeCreationDraft(allowed:)` |
| Hidden controls | Link controls in the invite step, lobby and entry sheet; Earlier challenges after a failed load |
| TestFlight build | `TestFlight` configuration, `TestFlight.xcconfig`, `TestFlightAppInfo.plist`, `GameTime-TestFlight` scheme, `AppEnvironment.testflight` |
| Candidate check | `scripts/check-beta-candidate.sh --testflight` and its fixtures |

### Friends store

- `FriendsStore` follows `ChallengeV1Store`. Every await is fenced by an actor
  generation and a fresh auth check, and an account switch or sign-out drops
  in-flight results and clears the list.
- Each command is written to a per-account journal (`GameTime/FriendCommandsV1`)
  before it is sent. A lost response keeps it, and Retry resends the same
  request ID, which the server replays. A server refusal removes it and keeps
  its code, so the Add screen can turn `friend_incoming_request_exists` into
  inline Accept and Decline. Account deletion clears the journal.
- The journal also remembers dismissed "Accepted your request" rows. The row
  is derived on the phone from `you_asked` and `since`, within 7 days.
- A failed refresh keeps the last list in memory, marks it not fresh and
  disables changes. The list isn't written to disk.
- Known friend error codes map to COPY.md sentences in `FriendsCopy`. An
  unknown code shows as `Reference: <code>`.

### Screens

The screens follow the approved mocks, with their copy.

- **You › Friends:** requests for you with Accept and Decline, friends, and
  requests you sent with Cancel. Then Add a friend and Blocked people. Also
  empty, loading, offline and unavailable states.
- **Add a friend:** exact username, Find, the lookup outcomes from the mocks,
  and your username with Copy and a plain-text Share with no link.
- **Safety:** tapping a friend offers Remove, Block and Report. The
  confirmations say what changes. Report offers the three stored reasons and
  no free text, and afterwards offers Block. Unblock is in Blocked people.
- **Home rows:** awaiting agreement ("Before Oct 5, 12:00 AM"), incoming
  request, invitation, and accepted request, in that order. At most three
  show, then "Show N more". There are no counts or badges.
- **Invite step:** accepted friends as checkable rows, up to five others with
  lobby members counted, plus inline "Add a friend by username". Invites go
  one saved request at a time and stop at the first refusal. The footer reads
  "Invite N friends", "Done inviting" or "Skip for now".
- **Challenge saved.:** an open friend lobby now gets this screen instead of
  "Challenge locked in.". It shows who was invited, "Nobody has agreed yet",
  and the three steps. Personal goals keep "Challenge locked in.".
- **Onboarding:** "Before you start" comes first, with the Apple Watch
  requirement, simulated stakes and the 21+ toggle. "I'm under 21" explains
  and offers Sign out. The profile step follows and adds the username
  sentence. The confirmation is saved with `confirm_age` once the challenge
  service can accept it after the profile exists. If that fails, Add a friend
  offers the same confirmation inline.

### Server-reported policies

- The store reads `challenge_availability_v1` with the access status.
- Creation offers only the kinds and activities the server allows.
  `personalStepsOnly` and the `privateHealthAccountMode` coupling in the shell
  are gone.
- A server without the projection, which today means hosted `gametime-p11b`
  until Phase 5, falls back to the private trial's two pairs for the enrolled
  Staging build. Nothing else changes for it.
- Links show only when the projection reports them open, or reports that its
  runtime doesn't govern them (`null`, as on unconfigured local stacks). With
  no projection they stay hidden. An incoming link then gets a sentence
  instead of the paste field.
- When the server reports `verification_mode = private_account`, the
  agreement screens add the COPY.md sentence: "We don't run a separate check
  on the device."
- The account-mode transport itself stays a build setting. The TestFlight
  configuration turns it on, limited to the P11B host.

### TestFlight configuration

- **`TestFlight`** is a fourth configuration on every target.
  - Production bundle `com.mjenkins.gametime`.
  - `GAMETIME_ENV = testflight`, compiled without `DEBUG` or `STAGING`.
  - The P11B URL and publishable key.
  - Challenges on and account mode on.
  - `test_only` settlement with an empty Stripe return, so there is no
    payment provider.
- **`AppEnvironment.testflight`**
  - production App Attest
  - backend-scoped sign-in and retry storage, as Staging has
  - no legacy Personal creation or sandbox cancellation
  - Stripe sandbox rejected
- **Account mode** now allows `staging` or `testflight`, and only on
  `lyushhqoednheqwzsmxh.supabase.co`.
- **The build-phase check** accepts `testflight` and requires the production
  bundle for it.
- **`TestFlightAppInfo.plist`** matches `AppInfo.plist`, adds the account-mode
  key, and replaces the stale "step counts" Health description with: "GameTime
  reads the steps, Activity minutes and outdoor runs your Apple Watch records
  to Apple Health, for the goals and challenges you join." This is new
  user-facing text for owner review.

### Candidate check

- **`--testflight`** checks the TestFlight inputs. The default Release
  contract is unchanged, and its fixtures still pass.
- **New checks:**
  - `no-payment-provider`
  - `challenge-account-mode`
  - `testflight-backend`
  - `testflight-app-info`
- **Shared checks** name the selected configuration: bundle ID, iPhone only,
  icon, privacy manifest, version, Watch isolation, public client and secrets.

Run on this checkout, `--testflight` reports 18 passed and 3 blockers. The
three blockers are the open owner inputs: the privacy policy URL, the beta
terms URL and a monitored support inbox. The Release contract reports the
same three.

## Checks

All on the iPhone 17 Pro simulator, iOS 27.0.

- **Unit suite (`GameTimeTests`):** 617 tests on the final build: 606 passed, 10 skipped and 1 failed.
  - The 10 skipped tests are the controller-backed smoke journeys, which need
    a local stack.
  - The one failure is
    `testReceivedLeaderboardCreationAndHealthCopyAtLargeTextInLightAndDark`,
    at its Health readiness text check (line 64). WORKING_BASELINE records it
    failing the same way on clean `ca92d25`. It wasn't re-run on clean `main`
    in this session.
- **New unit tests:**
  - `FriendsStoreTests`: 13. They cover the transport shape, the command body,
    the rate-limit body, the closed configuration, accept, lost-response
    retry with the same request ID, refusal codes, an account switch
    mid-flight, sign-out, offline, accepted rows and their dismissal, lookup,
    and error copy.
  - One draft test for the server-allowed policies and the availability
    projection.
  - One invite-picker test for the five-person limit and stopping at the
    first refusal.
  - One TestFlight configuration test.
- **`LiveDesignUITests`:** 12 of 12 passed, all on the fictional design
  fixture. That includes four new friends tests:
  - the list, safety and report flow
  - Add a friend
  - Blocked people
  - the Home rows
  The picked-friends lobby, the saved screen and the onboarding age step are
  in the updated tests. Captures are attached to the result bundle.
- **TestFlight build:** built for the iOS Simulator without signing.
  - The built Info.plist has bundle `com.mjenkins.gametime`,
    `GAMETIME_ENV = testflight`, the P11B URL, and challenges and account mode
    set to `YES`.
  - Settlement is `test_only`, with an empty Stripe return.
- **Scripts:**
  - `scripts/tests/check-beta-candidate.test.sh`: passed, with new TestFlight
    passing and blocked fixtures.
  - `scripts/tests/check-iphone-product.test.py`: passed, 15 tests. It now
    expects four shared schemes.
  - `scripts/tests/beta-preview-config.test.py`: passed.
- **Test changes:**
  - Existing unit and UI tests that asserted "Challenge locked in." for a
    friend lobby, or the username field in the creation invite step, now
    assert the approved behavior.
  - The controller-backed `SignalCreationUITests` journey was updated the same
    way but not run.
  - The lobby's "Invite by username" module in the challenge detail is
    unchanged, and `ChallengeV1UITests` still uses it.
  - Design-fixture launches now keep saved requests and friend journals in a
    per-launch temporary folder, so one UI test can't inherit another's
    dismissed rows.

## Not done here

- **Phase 4 local verification:**
  - no run against a disposable local stack with the Phase 2 migrations
  - no controller-backed UI journeys
  - no VoiceOver, large-text or physical-device pass
  - no `scripts/weekly-local-verify.sh`
  The screens were exercised through the fictional design fixture.
- **Hosted:** no hosted setting, allowlist or migration change. Hosted
  `gametime-p11b` has neither the friend RPCs nor `challenge_availability_v1`
  until Phase 5.
- **Signing and upload:** no signing, archive or TestFlight upload. The Apple
  provider still needs the production bundle, per Phase 5.
- **Owner review:**
  - the new TestFlight Health usage description
  - the fallback to the trial's pairs when a server doesn't report
    availability
