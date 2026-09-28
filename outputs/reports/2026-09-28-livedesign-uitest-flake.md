# LiveDesignUITests flakes after the legacy skip

Change on `claude/livedesign-uitest-flake`, from `b89aa82`, September 28, 2026,
fast-forwarded into `main` and pushed. Nothing hosted was touched.

## The decision

Game Time Dev approved this fix on September 28, under Mason's September 27–28
autonomy mandate for the TestFlight beta, so `main` can stay green. It covers
`LiveDesignUITests` and a minimal `FriendUsernameField` fix. No test is
skipped, and the 51 legacy skips are unchanged.

## Before

After the first green run, two docs-only commits turned CI red:

| Run | Commit | Result |
| --- | --- | --- |
| [36380467263](https://github.com/m1jenkins/GameTime/actions/runs/36380467263) | `6653b41` | Green. `LiveDesignUITests` 16 of 16 |
| [36384721914](https://github.com/m1jenkins/GameTime/actions/runs/36384721914), attempt 1 | `6c3cde9` | `testAddAFriendUsesAnExactUsernameAndPlainShareText`, line 406: no "couldn’t find" message after `typeText("nobody_here\n")` |
| The same, attempt 2 | `6c3cde9` | The same line |
| The same, attempt 3 | `6c3cde9` | The friends audit, line 600: "Friends, largest text: 1 Contrast failed — Friends" |
| [36395988173](https://github.com/m1jenkins/GameTime/actions/runs/36395988173) | `b89aa82` | The add-friend test at line 400: the Add a friend sheet never opened. `testTextGrowsAndFriendActionsRemainReachableAtLargestSize` at line 487: no Send request button after `typeText("drew_p\n")` |

## Why the add-friend steps failed

CI keeps no result bundle, so both causes are read from its step log. Neither
reproduced here, where the app launches in about 3 seconds; CI's first
launches took 30 to 54.

**Return raced the redraw.** `FriendUsernameField` ran
`.onSubmit { if enabled { submit() } }`, and `enabled` is the value from the
last time SwiftUI drew the field. The tests typed each name and its return in
one burst: 0.4 seconds for `nobody_here` on CI, 0.34 for `drew_p`. If the app
took the return before it redrew with the name, `enabled` was still false and
return did nothing. That fits lines 406 and 487: the typing succeeded, then
nothing happened for 5 seconds. A throwaway probe submitted 16 names that way
here, and none was dropped.

**Add a friend was tapped before it worked.** `friends.add` stays disabled
until the friends list loads (`FriendsStore.canAct` needs `fresh`), and the
shell's scene-phase handler clears `fresh` whenever the app stops being active,
until the next refresh. The test tapped it as soon as it existed. At line 400,
XCUITest's wait for the app to go idle after the tap took 0.01 seconds, where a
tap that opens the sheet waits about half a second for its animation (0.52 and
0.51 in the `6c3cde9` attempts). So the tap opened nothing. The app had taken
30 seconds to show its tabs. Here the button was enabled when first found in 3
of 3 cold launches.

## What changed

`LiveDesignUITests.swift`:

- `submitUsername` types a name, waits up to 10 seconds for Find
  (`friends.username.submit`) to be enabled, then presses return, so return
  still exercises the field's submit path. It enters all three names in the
  add-friend test and `drew_p` in the largest-text test.
- The add-friend test and the friends audit wait for `friends.add` to be
  enabled before tapping it. The add-friend test allows 10 seconds, not 5, for
  the field.
- The audit's failure message adds the failing element's frame. Its rules,
  exclusions and known reports are unchanged.

`FriendsViews.swift`: return in `FriendUsernameField` always calls `submit`,
and each `submit` checks the current name and state itself.
`AddFriendView.find()` already did, through `canSearch`.
`InviteAddFriendRow.send` now checks `canSend`, the condition that already
enabled its Send request button. The buttons and copy are unchanged, and a
name that isn't complete still does nothing on return.

## The friends audit report, not fixed

Attempt 3's "Friends, largest text: 1 Contrast failed — Friends" has no clear
cause, so the audit's rules stay as they are. What's known:

- The page is stable. On an iPhone 17 Pro simulator with iOS 26.5 at the
  largest text size, the title "Friends" spans y 128–189. The section header
  "Friends" spans y 745–800, past the list's bottom edge at 757 and the Home
  tab's top at 760. Those frames matched in 7 launches, and before and after 4
  full audits, so the audit doesn't scroll.
- On this screen the audit normally reports only the three tab labels'
  fixed-size text. That's all it reported in CI's 4 other runs whose logs show
  it, and in every audit here.
- The failing report wasn't the section header that the tab bar cuts off: the
  audit's cut-off rule didn't excuse it, so its frame ended above the Home tab.
  That leaves the title, bold near-black text on the page background, which
  shouldn't fail contrast unless something covered it or changed as the audit
  read it. CI didn't keep the screenshot.
- It happened in 1 of 6 CI runs of the test since `036d1bc` fixed the audit.

That's the residual risk: about 1 run in 6 could fail on this report alone,
and a rerun of the job is the remedy for now. The next failure's message will
include the frame, which tells the title from the header. Keeping the result
bundle as a CI artifact when tests fail would keep the screenshot too; that
changes the workflow, so it isn't done here. Re-running the audit and failing
only on repeated reports, or excusing "Friends", would relax the audit, and
neither was approved.

## What was run

Xcode 27.0 (27A5237l) on a new iPhone 17 Pro simulator with iOS 26.5, erased
before the first run, using CI's commands with a local destination and
derived-data path:

| Check | Result |
| --- | --- |
| `test -only-testing:GameTimeUITests/LiveDesignUITests`, add-friend first after the erase | 16 of 16 passed in 419 seconds |
| The add-friend and largest-text tests, `-test-iterations 5` | 10 of 10 passed, some while builds ran. In one, the app took 31 seconds to show its tabs |
| The friends audit, `-test-iterations 2` | 2 of 2 passed. On Friends at the largest size, each recorded only the three tab labels’ fixed-size text |
| Throwaway probes at `b89aa82` | 16 of 16 fast name-and-return submissions worked. `friends.add` was enabled when first found, 3 of 3. The frames above |
| Throwaway probes with this change | `ab` then return does nothing on Add a friend or the invite step. A name typed with its return in one burst finds @nobody_here on both, and sends Drew’s request from the invite step |
| `GameTime-Staging` (Staging), `GameTime` (Release) and `GameTime-TestFlight` (TestFlight), generic iOS Simulator, unsigned | All three succeeded, with no warnings in the changed files |
| `check-beta-candidate.test.sh`, `build-legal-site.test.py`, `check-beta-candidate.sh --personal-copy-only`, `check-iphone-product.py` | Passed |

The full scheme `test` wasn't run here; CI runs it.

## CI after the push

Recorded after the run.

## Limits

- CI uses Xcode 26.2 and iOS 26.2, which aren't installed here.
- Both add-friend causes are inferred from CI's logs; neither reproduced.
- No device or VoiceOver check was made.
