# Beta text-size support — September 24, 2026

Local follow-through for the large-text gap recorded by Phase 4 of the
[friends TestFlight plan](../../docs/FRIENDS_TESTFLIGHT_PLAN.md). Work began on
clean local `main` at `6a6714c` and was first saved as `f95d0f2`. Before handoff,
the remote tracking branch was found to contain seven newer commits, through
`c3b45f3`, including PRs #24/#25's shared styling and font scaling. Those commits
are integrated locally, preserving their adopted presentation and other work.
The resulting change adds the missing accessibility layout behavior on top of
that newer implementation; it does not replace it with a second typography system.

## Implemented

- Retained the remote `liveFont(_:weight:)` modifier and its semantic scaling,
  shared components, 20pt margins, button hierarchy and shell refactor. Its
  optional italic treatment lets record numbers follow the same setting.
  Existing scaled metrics/creation typography and decorative icon sizes remain.
- Home, Challenges, You, Friends, goal details/rules, onboarding, Settings and
  retained Personal presentation use scalable text. Crowded summaries, grids,
  action rows and controls reflow vertically at accessibility sizes.
- Friend safety/report sheets scroll; their accessibility presentation uses the
  large sheet. Buttons expand around their labels. Long usernames, captions and
  deadlines can wrap. Startup errors remain reachable in a scroll view.
- Two focused regressions check actual text growth, friend request actions,
  and the age confirmation/exit at the largest accessibility size. The broader
  historical audit retains its existing exclusions and is not claimed as new
  evidence for this change.

The added accessibility changes preserve user-facing wording, historical consent,
source rules, financial gates and backend behavior. The merge also preserves the
remote branch's previously approved charity retirement; no migration is applied
as part of this task. Presentation work does not change activity scoring or the
meaning of missing data.

## Verification scope

The owner's instruction was to avoid unnecessary extensive testing. Validation
is limited to the native build, two focused simulator journeys and inspection of
their captures. The full weekly/database gates and the broader accessibility
audit are not rerun for this presentation-only change.

- The initial Debug app and test targets compiled with Xcode 27, targeting iOS
  18 or later. On the existing iPhone 13 simulator running iOS 26.5, both focused UI tests
  passed: **2 tests, 0 failures, 42.985 seconds**. The font-growth baseline
  explicitly selects the default Large category, then compares with AX5.
  Accepting a request and finding/sending another request passed at AX5;
  onboarding kept Continue disabled until the age toggle, kept the under-21
  exit reachable, and advanced to the profile form after confirmation.
- The screenshots show the unchanged default Friends composition and enlarged,
  wrapping Friends/onboarding/profile content. The Add a friend capture also
  contains the simulator keyboard's first-use tutorial; the subsequent search
  and send assertions passed.
- An early build started before parallel edits finished and reported the new
  `FriendsActionGroup` as missing. The complete-source build passed. Capture
  review then identified a mid-word wrap in the Challenges tab at AX5; the tab
  now scales down only as needed to keep its short navigation label on one line.
  Goal headings also move below the Back button to use the full width at AX5.
  These final layout-only refinements are built and inspected without repeating
  the two journeys.
- Initial AX5 captures of Home, goal details, Challenges and You were visually
  inspected. They sample the initial viewports, not every scroll position or
  every possible title, username or result.

Local run artifacts: `/private/tmp/gametime-dynamic-type-final-20260924.xcresult`,
`/private/tmp/gametime-dynamic-type-final-20260924.log`, and
`/private/tmp/gametime-dynamic-type-captures/`.

After integration with `c3b45f3`, the same two focused journeys were repeated.
The app compiled and Friends passed in 29.470 seconds. Onboarding's first run
failed because its coordinate tap did not switch the partly visible age row.
The test now scrolls until the entire row is above the pinned footer, asserts
that geometry, and taps the accessible switch. The isolated rerun passed in
13.710 seconds; no app behavior was changed to make the assertion pass.
Both focused journeys therefore pass on the integrated app, with the failed
attempt retained. Integrated Friends/Add a friend captures were also inspected.

Integration artifacts: `/private/tmp/gametime-dynamic-type-integrated-20260924.xcresult`,
`/private/tmp/gametime-dynamic-type-integrated-20260924.log`, and
`/private/tmp/gametime-dynamic-type-integrated-captures/`.
Onboarding rerun: `/private/tmp/gametime-dynamic-type-onboarding-20260924.xcresult`,
`/private/tmp/gametime-dynamic-type-onboarding-20260924.log`, and
`/private/tmp/gametime-dynamic-type-onboarding-captures/`.

## Remaining acceptance

Human VoiceOver, physical accessibility and comprehension remain open. This
receipt does not establish every screen/state at every text size. No physical
installation, hosted mutation, signing, TestFlight upload or push is performed.
Phase 5 hosted settings/provider/deletion work and Phase 6 release inputs remain
separate tasks.
