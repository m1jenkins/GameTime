# Friends TestFlight Phase 4: local verification

September 22, 2026. This is Phase 4 of the
[friends TestFlight plan](../../docs/FRIENDS_TESTFLIGHT_PLAN.md) under
[D142](../../DECISIONS.md#d142-first-private-testflight-adds-friends-opens-apple-sign-up-and-ships-goals-first).
It checks the [Phase 2 server](2026-09-22-friends-phase-2-server.md) and the
[Phase 3 app](2026-09-22-friends-phase-3-native.md) against disposable local
stacks set up the way Phase 5 proposes to set up hosted `gametime-p11b`.
Everything ran locally with fictional accounts. Nothing was applied to hosted,
installed on a phone, signed, uploaded or pushed.

## Summary

- **The server does what the plan asks, with two fixes.** All four friend goals
  ran at 2 and 6 people from creation to a final result, along with Personal
  Steps and Outdoor runs, the membership limits, cancellation, voids,
  corrections, and the friendship matrix. Links and community stay closed.
- **Fixed: a failed freeze told the creator about someone else's limit.** When
  another member was at a limit, the creator saw "You already have a friend
  challenge for this activity during these dates". That sentence is wrong for
  the creator and hints at the other person's challenges. Migration
  `20260922230000` now gives one neutral answer, and the app says: "Someone you
  picked can't join this challenge. Change who's in, then try again."
- **Fixed: the community list ignored the closed setting.** Migration
  `20260922230100` empties it while community is off the allowlist.
- **Found, not fixed: most screens ignore the text-size setting.** The
  screens from the September 22 native rewrite set fixed point sizes: Home,
  goal detail and rules, You, Settings, sign-in and onboarding, the tab bar,
  and every friends screen. The creation flow does scale, apart from the friend
  rows in its invite step. Fixing this needs an owner decision (see Open items).
- **Found, not fixed: nobody can fall short.** A real Apple Health total below
  the goal counts as incomplete, so the person is excluded and their simulated
  entry returns. The app shows "Didn't count". This is the existing
  real-activity rule, but the first TestFlight cycle will never show "Goal
  missed".

## What ran

| Check | Result |
| --- | --- |
| `scripts/friends-local-verify.sh` at `f83a03c`, fresh stack | 139 of 139 checks passed |
| `scripts/weekly-local-verify.sh` at `3f29398`, fresh stack | Passed: 116 pgTAP files and 5,218 assertions, 923 Deno tests, 184 Swift core tests in 20 suites, and the persisted weekly lifecycle smoke. Later commits change only app code, tests and scripts this gate doesn't run |
| New pgTAP `532` and `533` | 9 and 4 assertions, passing inside the weekly gate |
| `LiveDesignUITests`, iPhone 17 Pro, iOS 27.0 | 13 of 13 passed at `f83a03c`, including the new audit |
| System accessibility audit of the friends screens | Passes apart from text size and the reports listed under Native checks |
| `GameTimeTests` unit suite | 619 tests: 607 passed, 11 skipped, 1 known failure |
| `FriendsNativeSmokeTests` against a local stack | Passed |

Every disposable stack had its own project ID, ports and Docker network, and
the one-shot runs removed their stack and network afterwards. The working stack
`gametime-friends-dev` was stopped at the end. No other checkout's stack was
reset or reused. The native runs used a dedicated
simulator created for this task.

## The HTTP verification

`scripts/friends-local-verify.sh` copies the tracked `supabase/` and `scripts/`
inputs into a temporary folder, starts a fresh stack on ports 57540–57549 and
runs `scripts/friends-local-http.ts`. The recorded run used project
`gametime-friends-verify.bvglinhx` on `10.253.1.0/24` at `f83a03c`. An
earlier run at `3f29398`, before the settings moved into a shared file, also
passed all 139 checks.

### How it is set up

- **Settings.** `scripts/fixtures/friends-build1-settings.sql` holds the values
  the Phase 2 receipt proposes for hosted: `commands_only`,
  `allowlist_enforced` and `account_mode` on, `links_enabled` off, and the four
  friend goals added to the allowlist. The real-activity runtime is on for
  admission, uploads and processing. The private trial and the fictional
  fixture runtime stay off.
- **Accounts.** Fictional accounts are created through the local Auth admin
  API. The disposable copy of `supabase/config.toml` turns on password sign-in
  for them; hosted build 1 stays Apple sign-in only. Profiles are saved through
  the app's own insert, and 21+ through `confirm_age`.
- **Requests.** Friend commands use the exact body `FriendCommand` sends.
  Uploads go through the actual `ingest-challenge-health` handler, run in the
  driver, with no device key or signature headers. That is account mode.
- **Clock.** `app.challenge_real_health_now_v1` is replaced in the disposable
  database only and restored at the end. The run covers November 2 (setup),
  November 4 (the window), November 5 (corrections), November 7 (provisional
  results), November 9 (final) and November 12 (the reviewed challenge).
- **Processing.** The driver calls `challenge_process_v1` for every row the
  work inventory reports, without naming challenges. The Cron-to-Edge worker
  path was not used; the P11 checks cover it.

### What it checked

- **Availability.** The server reports itself restricted, offers exactly the
  four friend goals plus Personal Steps and Outdoor runs, reports links and
  community closed, and reports account mode.
- **Friendship matrix.**
  - Lookup matches an exact username, ignores letter case, never matches a
    prefix and answers `self` for yourself.
  - A request retried with the same ID returns the saved answer. The same ID
    for another person is refused.
  - A crossed request gets `friend_incoming_request_exists`. A stale cancel
    after acceptance gets `friend_state_changed`.
  - Decline is silent: the sender's list simply loses the request, and they can
    ask again.
  - Direct inserts and deletes on `friendships` are refused with
    `friend_command_required`.
  - Block hides both people from each other's lookups, ends the friendship and
    shows only in the blocker's list. A repeated block and an unblock by the
    blocked person are refused. Unblock doesn't restore the friendship.
  - Report takes only the three stored reasons and works without a shared
    challenge. It reaches the support queue, which shows who was reported and
    why, but not who reported.
  - Accounts that never confirmed 21+, or that are suspended, aren't found and
    can't send requests.
  - The 31st lookup in a minute and the 21st request in a day are refused.
- **Invites.** Only a friend can be invited. Removing a friend after inviting
  them leaves the lobby as it was, as the plan records.
- **Friend goals.** Steps, Activity minutes, Running distance and Timed run, at
  2 and at 6 people:
  - the agreement names the source, every person and simulated stakes
  - it is scheduled once everyone agrees, and active in its window
  - every upload saves without a device check and records `private_account`
  - a correction after the window saves as a new revision
  - each reaches a provisional result on November 7 and a final one on
    November 9
  - a review holds its challenge until the review closes
  - each final result matches the saved activity and corrections, the entry
    total is 100 times the group size, nothing is left unallocated, and a
    participant can read it
- **Membership and limits.**
  - Selecting a seventh person is refused with `challenge_capacity`.
  - A friend in a same-activity challenge on the same dates, or with three
    unsettled challenges, fails the freeze with `challenge_member_unavailable`.
    The lobby stays open. A creator at their own limit still gets the specific
    reason.
  - Reopening, changing a goal and dropping a member makes new terms. Agreement
    to the old terms is refused, the earlier agreement doesn't count, and
    everyone agrees again.
- **Outcomes.**
  - A challenge without everyone's agreement is cancelled at its start, and
    every simulated entry returns.
  - A leave, or a block between the only two people, voids the challenge, and
    every entry returns.
- **Personal goals.**
  - Personal Steps and Outdoor runs save after one agreement.
  - A met Personal goal is final and returns its stake.
  - A total below the goal, and no activity at all, both leave the goal void
    with the stake returned, which keeps the Personal promise.
  - Personal timed and Activity minutes goals are refused
    (`challenge_policy_unavailable`). Readiness for those sources still saves,
    because friend goals use them.
- **Closed features.**
  - Friend leaderboards are refused.
  - Issuing a link for an open lobby is refused, and so is redeeming one.
  - A community published before enforcement no longer appears in the list,
    and joining it is refused (`challenge_join_closed`).

### Results in each friend goal

Each goal used the same plan. The creator meets the goal. The first friend
misses and then corrects up to a met total. In the groups of six, one more
friend meets, one misses, one never uploads, and one meets and then corrects
down to a miss.

| Person | Final status | Simulated entry |
| --- | --- | --- |
| Met, or corrected up to met | `met` | returned |
| Below the goal, no upload, or corrected down | `excluded` | returned |

Timed run uses "faster than", so its met and missed values are times.

## Findings

### Fixed here

1. **A failed freeze named another member's reason.** Freeze checks every
   selected member, and the first one at a limit failed the whole freeze with
   their own reason. The creator saw "You already have a friend challenge for
   this activity during these dates" or "Three challenges still need a final
   result". Both are wrong for the creator and hint at the other person's
   challenges.
   - Migration `20260922230000_challenge_freeze_member_privacy_v1` checks the
     creator first, keeps the creator's own reasons, and turns another
     member's admission, suspension, overlap or unsettled-limit reason into
     `challenge_member_unavailable`. Lock and serialization errors pass
     through unchanged.
   - The app maps the code to "Someone you picked can't join this challenge.
     Change who's in, then try again." `docs/COPY.md` has the row.
     `testLockingTheRosterNeverExplainsAnotherPersonsLimit` checks the
     sentence says nothing about why.
   - pgTAP `532` covers another member's overlap, unsettled limit and
     suspension, the creator's own overlap and limit, a creator and a member
     both at a limit, and a clear roster.
2. **The community list ignored the closed setting.** With community off the
   allowlist, `challenge_availability_v1` said community was closed and joining
   was refused, but `challenge_community_catalog_v1` still listed a community
   published earlier. The app shows whatever the list returns. Migration
   `20260922230100_challenge_community_catalog_closed_v1` returns an empty list
   in that case, and pgTAP `533` covers it. Hosted has no community today, so
   this was latent.
3. **Two small tap targets.** The Home row's Dismiss button and the onboarding
   "I'm under 21" button drew a 44-point frame their tappable shape didn't
   reach. Both now use the full frame.

### Found, not changed

4. **Most screens ignore the text-size setting.** The audit reports fixed type
   on every friends screen and on the shared tab bar. The screens from the
   September 22 native rewrite set point sizes directly: `LiveGoalDetail`,
   `FriendsViews`, `LiveChallengeShell`, `LiveAccountEntryViews`,
   `ChallengeV1EntryViews`, `LiveRecordView` and smaller amounts elsewhere.
   The creation flow uses text styles and does scale, apart from the friend
   rows in its invite step. So this belongs to the rewrite as a whole rather
   than to friends. At the largest size the text stays the same while some
   layouts still switch to their stacked form, which leaves Friends' chevrons
   on their own line. Fixing it touches most of the locked design.
5. **Nobody can fall short in a real-activity goal.** A miss needs a complete
   total, and an Apple Health total is never complete, so a total below the
   goal is `excluded` and the simulated entry returns. The app shows "Didn't
   count" and "Your entry returns". This is the existing real-activity rule,
   and it keeps the missing-data promise. In the first TestFlight cycle,
   though, a friend who falls short won't see "Goal missed".
6. **Links can't open for real-activity lobbies.** `challenge_issue_link_v1`
   admits the caller without the real-activity marker, so the enforced
   allowlist refuses it with `challenge_policy_unavailable`, even with
   `links_enabled` on. Links stay off in build 1 and the app hides them.
   Fix this before turning links on.
7. **Support grants last at most 7 days.** `challenge_grant_support_v1` refuses
   a longer grant. Phase 5's "grant global support to the owner" needs a
   weekly renewal for the owner to keep reading the report queue.
8. **The lookup limit answers with HTTP 429.** The body carries
   `friend_lookup_rate_limited`, and the app maps it to "Too many searches.
   Wait a minute and try again."

## Native checks

All native runs used a simulator created for this task (iPhone 17 Pro,
iOS 27.0) and a derived-data folder in the session scratch directory. The
simulator was deleted afterwards.

### The app's friends code against a server

`FriendsNativeSmokeTests` runs the production `FriendsStore` and
`SupabaseChallengeV1Client` against a disposable stack with the build 1
settings. It signs in through the Supabase SDK. `scripts/friends-native-smoke.py`
creates four fictional 21+ accounts, one with a mixed-case username, writes a
mode-0600 manifest, runs the test, then removes the manifest and signs the
accounts out. It ran against `gametime-friends-dev`, the disposable working
stack used while writing the driver, on ports 57560–57569, and passed.

It checks the things fixtures couldn't:

- the app decodes the real availability reply: restricted, account mode,
  links and community closed, and the six allowed goals
- a request, and a crossed request answered with "<username> already sent you
  a request. Accept it to become friends."
- accept, the sender's "Accepted your request" row, and no row for the person
  who accepted
- a silent decline, block, unblock (no friendship restored) and report
- a stale cancel answered with `friend_state_changed` and a refreshed list
- the lookup limit's HTTP 429 reply shown as "Too many searches. Wait a minute
  and try again."

Afterwards the server's command journal held exactly the seven saved commands
and none of the test's sessions remained.

### Accessibility audit

`testFriendsScreensPassTheSystemAccessibilityAuditApartFromTextSize` runs the
system audit on Friends, friend actions, Add a friend, Blocked people, the Home
rows, the invite picker and "Before you start", at the default size and at
the largest accessibility size. Each screen gets 1.5 seconds to settle first.
The first run, without that wait, also reported problems caused by a sheet
still moving.

It fails on any report except the ones below, which it records as
attachments instead:

| Report | Where | Why it isn't failed here |
| --- | --- | --- |
| Fixed type size | Every friends screen and the tab bar | Shared by the September 22 screens; see finding 4 |
| Small hit area: "You" | Friends, Blocked people, Home | The shared tab bar |
| Small hit area: "3 friends ↗" | Home | The Home goal card, not a friends control |
| Small hit area: "Step 1 of 2" | Before you start | Progress dots, not a control |
| Small hit area, unnamed | Invite picker | The audit didn't name it, and it doesn't match any friends control on that screen |
| Unnamed "potentially inaccessible" text | Several screens | The audit can't point to the element |
| Contrast: "Add a friend" | Friends | The icon-only header button, black on near-white |
| Contrast and clipped text | Friend actions | The captures show the sheet fully drawn and legible |

The sheet reports and the icon contrast may be audit false positives. A person
should check them with VoiceOver and larger text.

The Home row's Dismiss button and onboarding's "I'm under 21" failed the
hit-area check at first. Both are fixed, and the audit now passes on them.

### Other runs

- **`LiveDesignUITests`.** 13 of 13 passed at `f83a03c`, with nothing else
  running. In an earlier run, while a disposable stack was starting,
  `testAddAFriendUsesAnExactUsernameAndPlainShareText` failed once at its
  second lookup. It passed when run alone and in the final run.
- **`GameTimeTests`.** 619 tests: 607 passed, 11 skipped and 1 failed.
  - The skips are the 10 controller-backed smoke journeys and
    `FriendsNativeSmokeTests` without its manifest.
  - The failure is
    `testReceivedLeaderboardCreationAndHealthCopyAtLargeTextInLightAndDark` at
    line 64, the same existing failure WORKING_BASELINE records on clean
    `ca92d25`.
  - The new `testLockingTheRosterNeverExplainsAnotherPersonsLimit` passed.

## Not done here

- **A person using VoiceOver.** The system audit checks labels, hit areas,
  contrast and clipping. It can't judge whether the screens make sense spoken
  aloud. That needs a person, ideally on a phone.
- **Physical devices, Apple sign-in, hosted and TestFlight.** None were used.
  Hosted `gametime-p11b` still has none of the Phase 2 or Phase 4 migrations.
- **The Signal creation journeys.** `SignalCreationUITests` needs the P8/P9
  owned-stack controller, which is tied to older baselines, and its journeys
  create leaderboards that build 1 refuses. It was not run.
- **The older controller-backed journeys.** `scripts/beta-native-smoke.py`
  uses the fictional fixture path, which the enforced allowlist closes. It was
  not run.

## Open items

- **Text size.** Decide whether the friends TestFlight waits for the app to
  support larger text, or ships with fixed text as a known limit for the
  first cohort.
- **Falling short.** Decide whether "Didn't count" is acceptable for the first
  cycle, or whether the result screen should say more when a total is below
  the goal.
- **Phase 5.** It now also applies `20260922230000` and `20260922230100` (both
  come with `--include-all`), and the owner's support grant needs renewing
  every 7 days.
