# Floodlight QA fixes

Commit `47cb770` (app code, tests and COPY.md), then this receipt with
the design history and working-baseline entries and the screenshots, on
`main` from `410c9aa`, September 28, 2026, pushed fast-forward. Nothing hosted
was touched: no Supabase, Stripe, TestFlight or App Store Connect, and no user
data.

A Floodlight QA task asked for these fixes on September 28, after a design QA
pass over the [first slice's](2026-09-28-floodlight-native-wiring.md)
screenshots. A first session built them and left them uncommitted, with three
UI tests failing and the unit run cut short. A second session fixed those
failures, ran the checks below, took the screenshots and committed.

## What changed

| # | Fix | Where |
| --- | --- | --- |
| 1 | Home action rows: the agree row's **Review** is the only blue pill. **Accept** and **Decline** are gray pills in the old Decline's style, with `--gt-ink` labels; an invitation row's gray **Review** now uses the same ink. Titles are Barlow SemiBold 17 and details Barlow Regular 15 in `--gt-muted`, as in 9.3's Next up rows. | `HomeActionRows.swift`, `LivePillButtonStyle` (`ink`) |
| 2 | The agree row says "Agree by Sun, Sep 27", the day before a midnight start in the challenge's time zone. It adds the time only when it matters: "Agree by Sun, Sep 27, 11:59 PM Central Time" when your own day would end after the deadline, or "Agree by Mon, Sep 28, 8:59 AM" when the start isn't at midnight. VoiceOver spells out the day and month. | `HomeActionRows.deadline`, COPY.md |
| 3 | Challenge page: no Refresh activity pill. The update time on the person card ("1 min ago") is the refresh control, with a spinner in its icon's place while it syncs (VoiceOver: "Refresh activity", value "Updated from Apple Health 1 min ago"). **Leave challenge** is plain `--gt-muted` text across the bottom of the list, not red and not a pill. | `LiveGoalFloodlight.swift`, `FloodlightSyncTime` |
| 4 | Apple Health card before you connect: **Apple Health isn't connected** · "Connect to check your runs. You can keep browsing without it." · **Connect** (VoiceOver "Connect Apple Health") · "Manage access in Apple Health". Steps and activity-minutes goals say "your steps" and "your activity minutes". | `ChallengeHealthCopy`, `FloodlightHealthCard`, COPY.md |
| 5 | The not-connected Health card no longer sits beside "6.4 / 20 km · 1 min ago". A fixture caused it (below); the new `--fixture-health-not-connected` state shows **No update yet** with no update time. | `LiveDesignFixtures.swift`, tests |
| 6 | Tab bar: the system `TabView` with the same labels and icons. On iOS 26 it's Liquid Glass floating over the content, which scrolls underneath. The opaque custom bar and its divider are gone. On iOS 18 the system bar is the solid one `SignalAppearance` already sets up. | `LiveChallengeShell.swift` |
| 7 | Invitation, two people: "Stakes back · Challenge won't count" has a no-break space in "won't count". | `FloodlightChallengeFacts.outcomes` |

Found while testing fix 6 and fixed in the app: the system `TabView` keeps
other tabs' pages alive, and Home carries its own copy of the friends
confirmation. Each copy clears the shared notice after a 2.6-second wait,
and a cancelled wait (`try? await Task.sleep`) clears it at once. In the
failing test's screen recording, "You and Taylor are now friends." showed
for one frame, about half a second, on the Friends page. The confirmation
now shows only on a page that's on screen (`FriendsNoticeToast`). That left
one place with no toast on screen: creation's invite step, which confirms a
friend request in its own line under the field. Its notice then waited and
showed again on Home when creation closed, so the invite step now clears it
(`InviteAddFriendRow`). A throwaway test checked both: the confirmation
repeated on Home before that change and doesn't after.

## The Health card contradiction came from a fixture

The first slice's `floodlight-challenge-health-card` screenshot came from a
throwaway test that opened September runs with `--fixture-health-not-saved`.
That fixture exists for Settings' "Last update not saved" state: its stub
connects only the Steps source. September runs needs the outdoor-runs source,
so its Health card said "not connected", while the same fixture gave you a
saved run from a minute earlier ("6.4 / 20 km · 1 min ago").

The app can't produce that pair on one phone. Before you connect, a refresh
returns "not connected" before it reads Apple Health or sends anything
(`ChallengeHealthFlowStore.refreshOne`). The new unit test
`ChallengeHealthFlowStoreTests.testBeforeConnectingARefreshReadsAndSendsNothing`
checks that nothing is read, sent or saved until you connect, and that the
same refresh sends your update once you do.

So the fix is in the fixture: `--fixture-health-not-connected` connects
nothing and gives you no saved update in September runs. The new UI test
`LiveDesignUITests.testChallengeHealthCardBeforeConnectingShowsNoProgressOrUpdateTime`
checks the card's words, **No update yet**, and that no progress, update time
or refresh control appears. `--fixture-health-not-saved` is unchanged.

One real case remains, on purpose: an update saved from another phone, or
before a reinstall, still shows with its time while this phone isn't
connected. That's a saved score that counts, and "No update yet" would be
false there.

## Create flow: "Who's it for?" is on main, and it stays

The four-step flow in the first slice's `create-type-light.png` isn't a
fixture or base artifact. It's app behavior on `main`:

- `1e991db` (September 26) made `ChallengeCreationDraft` start on the "Who's
  it for?" step whenever the server allows more than one kind of challenge
  (`directEntry = !allowsTypeChange`). `ChallengeCreationViews.swift` draws it
  and adds "Who" before Goal, Challenge, Friends in the progress row. With one
  kind allowed, creation opens on the goal step as before.
- The owner asked for it. `docs/design/SIGNAL_UI_MIGRATION.md`, "Creation asks
  who it's for — September 26, 2026": "This reopens the locked Goal →
  Challenge → Friends flow at the owner's request." Staging 0.8.1 (926.26.1)
  on the owner's iPhone opened on it that day, offering Personal goal and
  Goals with friends, and no leaderboard
  (`outputs/reports/2026-09-26-friends-build1-settings.md`).
  `LiveDesignUITests.testChallengeCreationEntryKeepsTheApprovedNativeFlow`
  asserts it: "Mason, September 26: creation asks who it's for before
  anything else."
- Only the third choice came from the fixture. The design fixture reports no
  allowed challenge kinds, so creation offers all three, including **Friend
  leaderboard**. A signed-in account gets the server's list
  (`AppShellView.allowedPolicies`): hosted build 1 allows the four friend
  goals and personal Steps and Outdoor runs (D142), without leaderboards, so
  the owner's phone shows two choices.
- After **Goals with friends**, the friend flow is still Goal, then
  Challenge, then Friends. "Who's it for?" is the fork in front of it.

**Not removed.** Removing it would undo the owner's September 26 request.
It would also leave no way to start a personal goal while friend goals are
offered, which is the hosted setup. So the step is still on `main`, and the
task's "make sure that extra step is not on main" isn't done. If Mason wants
the three-step flow as the only path, he needs to say where Personal goal
starts instead. The change would then be `ChallengeCreationDraft`'s
`directEntry` and `firstStep`, and the UI tests that expect the step.

## Screens, mockups and screenshots

Screenshots are simulator captures of the design fixtures
(`--fixture-live-design`) on an iPhone 17 Pro with iOS 26.5, taken by
`LiveDesignUITests`: light from the full run below, dark from its three
screenshot tests run again with the simulator set to dark. They're committed
under `outputs/design/floodlight-qa-fixes-2026-09-28/`, as
`light/<capture>-light.png` and `dark/<capture>-dark.png`. The iPhone 17 Pro
is 402 points wide, a little wider than the mocks' 390. Mockups are in
`.lavish/floodlight-refinement-2026-09-27/`.

| Screen | What to look at | Capture | Compare with |
| --- | --- | --- | --- |
| Home with action rows | Next up type; gray **Accept** and **Decline** beside the blue **Review**; "Agree by Sun, Sep 27"; the Liquid Glass tab bar | `home-action-rows` | `round-9-3/captures/light.png` and `dark.png`, middle phone (Next up); `round-11-1/captures/health-and-sync.png`, "Home · stale" |
| Challenge, top | The page under the floating tab bar. On this phone your card's last line ("13.6 km to go", "1 min ago") sits under the glass until you scroll (the old bar hid it the same way); the panel capture shows it | `floodlight-challenge` | `round-9-3/captures/light.png` and `dark.png`, first phone |
| Challenge panel | "⟳ 1 min ago" on your card, now the refresh control; no Refresh activity pill; **Leave challenge** as muted text ending the list | `floodlight-challenge-panel` | the same phones' lower half; `round-11-1/captures/someone-leaves.png`, which drew Leave as a calm gray button before this QA |
| Challenge Health card, not connected | The new heading, body and **Connect**, with the Manage access link; **No update yet** and no update time on your card | `floodlight-challenge-health-card` (`--fixture-health-not-connected`) | `round-11-1/captures/detail-and-health.png` and `health-and-sync.png`, "No activity found" |
| Invitation, two people | "Stakes back · Challenge won't count" with "won't count" on one line | `floodlight-invitation-rules` | `round-11-1/captures/invitation-and-lobby.png`, "Invitation · two people"; `round-11-1/captures/outcomes-two-and-group.png` |
| Home on iOS 18.6 | The fallback: the solid system tab bar with its divider, labels and icons as before | `home-action-rows-ios18` (light only, iPhone 16 simulator) | — |

## Checks

Local, with Xcode 27.0 (27A5237l) and the iOS 26.5 simulator runtime, on an
iPhone 17 Pro simulator, CI's destination. CI (Xcode 26.2, iOS 26.2) runs
after the push. Every check below ran on the committed tree unless it says
otherwise.

- **Every test in the `GameTime` scheme, as CI runs it** (`xcodebuild -project
  ios/GameTime/GameTime.xcodeproj -scheme GameTime -configuration Debug
  -destination 'platform=iOS Simulator,id=<iPhone 17 Pro>'
  CODE_SIGNING_ALLOWED=NO test`), on an erased simulator in light:
  **passed** (`** TEST SUCCEEDED **`). UI tests: 88 run, 31 passed, 57
  skipped, 0 failed. All 18 `LiveDesignUITests` passed, including the new
  Health card test and the friends audit, and so did the 13 Personal-detail
  tests. The skips are exactly the 38 in `RetiredShellSkips.swift`
  (`GameTimeUITests` 19, `DuelUITests` 11, `PerformanceCommitmentUITests` 8)
  and the 19 controller-owned tests (`ChallengeV1UITests` 11,
  `SignalCreationUITests` 7, `ChallengeHealthSignalUITests` 1). Unit tests:
  663 passed, 11 skipped, 0 failed, including the three new ones. An earlier
  full run, before the invite step's change and the tightened audit helper,
  passed with the same counts.
- **The three failures, reproduced first.**
  `testFriendsListAnswersRequestsAndStatesEverySafetyConsequence` failed alone
  at the same line: Accept worked, but "You and Taylor are now friends."
  never registered. With the toast fix, it and
  `testTextGrowsAndFriendActionsRemainReachableAtLargestSize` passed.
  `testFriendsScreensPassTheSystemAccessibilityAuditApartFromTextSize`
  failed alone on Home at the largest text ("Contrast failed" twice, with no
  element). A throwaway diagnostic test, not committed, recorded the issues,
  frames and screenshots behind the caveat below. With the audit change the
  test passed; one run named the two reports "6.4" and "/ 20 km".
- **Dark:** the three tests that take the screenshots
  (`testHomeActionRowsAreOrderedAndLeaveOnceHandled`,
  `testFloodlightChallengePotInvitationAndHomeShowTheAdoptedCopy` and
  `testChallengeHealthCardBeforeConnectingShowsNoProgressOrUpdateTime`)
  passed with the simulator set to dark.
- **iOS 18.6** (iPhone 16 simulator; the app's minimum is iOS 18.0):
  `testFourLockedScreensUseTheNewNativeShell`,
  `testHomeActionRowsAreOrderedAndLeaveOnceHandled` and
  `testFriendsListAnswersRequestsAndStatesEverySafetyConsequence` passed on
  the fallback tab bar.
- **Builds:** `GameTime-Staging` (Staging), `GameTime` (Release) and
  `GameTime-TestFlight` (TestFlight) built for the simulator without signing,
  as CI builds the first two. CI never builds the TestFlight configuration.

## Caveats and follow-ups

- **The friends audit changed, in the test only.** With the floating bar the
  page runs under the glass, and iOS 26 fades it in a band above the bar
  (65 points here; the edge-effect views start at y 726 for a bar at 791).
  The audit already recorded contrast reports for text running into the old
  bar. It now also counts text in a 72-point band above the bar as covered,
  and the audit sometimes can't name that text ("Contrast failed for
  SwiftUI.AccessibilityNode" with no element). An unnamed contrast report is
  recorded, not failed, only while a covered text is left to account for it:
  each covered text excuses one report at most. On Home at the largest text
  the two unnamed reports matched "6.4" (y 672–781, its ink lightening from
  y 742) and "/ 20 km" (y 785–838, under the glass). Once the page was
  scrolled away they went, and only text at the bar was reported. The title
  flake noted on September 28 (the Friends title at y 128–189) is outside
  the band and would still fail. The band was measured on iOS 26.5; CI runs
  iOS 26.2 and hasn't been checked against it.
- **Leave challenge and the invitation's Decline look the same when
  disabled.** Both use the quiet text style, which has no disabled look. The
  gray pill Leave had before showed muted text when disabled. Not changed
  here.
- **A saved score from another phone still shows** beside "Apple Health isn't
  connected", with its update time. It counts, so "No update yet" would be
  false. Only this phone's own activity waits for Connect.
- **"Who's it for?" stays on main,** against the task's wording, for the
  reasons above. Mason's call.
- **Left alone:** while this ran, another session added an uncommitted
  Floodlight round 12 proposal to the checkout (a "Sign in and Health
  permission" section in COPY.md, `.lavish/floodlight-refinement-2026-09-27/round-12/`
  and its README entry). None of it is in these commits, and it's still in
  the working tree.
- **Not done:** a VoiceOver walk-through, a check on a phone and the owner's
  review. Screenshots come from simulator fixtures.
