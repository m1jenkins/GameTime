# Beta text-size support — September 24, 2026

Local follow-through from clean `main` at `6a6714c`, on
`codex/beta-dynamic-type`. The task addresses the fixed-text implementation gap
recorded by Phase 4 of the [friends TestFlight plan](../../docs/FRIENDS_TESTFLIGHT_PLAN.md).

## Implemented

- A shared SwiftUI scaled-font modifier preserves the approved default point
  sizes and follows the person's text-size setting. Existing scaled metrics and
  creation typography keep their own scaling; decorative icons keep their size.
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

All user-facing wording, historical consent, source rules, financial gates and
backend behavior are preserved. This changes presentation, not activity scoring
or the meaning of missing data.

## Verification scope

The owner's instruction was to avoid unnecessary extensive testing. Validation
is limited to the native build, two focused simulator journeys and inspection of
their captures. The full weekly/database gates and the broader accessibility
audit are not rerun for this presentation-only change.

- Debug app and test targets compiled with Xcode 27, targeting iOS 18 or later.
- On the existing iPhone 13 simulator running iOS 26.5, both focused UI tests
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
- Final AX5 captures of Home, goal details, Challenges and You were visually
  inspected. They sample the initial viewports, not every scroll position or
  every possible title, username or result.

Local run artifacts: `/private/tmp/gametime-dynamic-type-final-20260924.xcresult`,
`/private/tmp/gametime-dynamic-type-final-20260924.log`, and
`/private/tmp/gametime-dynamic-type-captures/`.

## Remaining acceptance

Human VoiceOver, physical accessibility and comprehension remain open. This
receipt does not establish every screen/state at every text size. No physical
installation, hosted mutation, signing, TestFlight upload or push is performed.
Phase 5 hosted settings/provider/deletion work and Phase 6 release inputs remain
separate tasks.
