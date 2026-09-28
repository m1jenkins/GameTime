# Personal-detail UI tests repaired

Change on `claude/personal-detail-uitest-repair`, from `5561746`, September 28,
2026, fast-forwarded into `main` and pushed. Nothing hosted was touched.

## The decision

Game Time Dev approved this repair on September 28, under Mason's September
27–28 autonomy mandate for the TestFlight beta: repair the 13 Personal-detail
tests that the [skip receipt](2026-09-27-legacy-uitest-skip.md#1-next-the-13-personal-detail-tests)
listed first, unskip only those once they pass, and touch product code only
for missing accessibility identifiers. The other 38 skips are unchanged.

## What was wrong

The 13 tests opened a Personal challenge with `--fixture-open-result-challenge`
or `--fixture-open-active-challenge`, then waited for the old "Your challenge"
navigation bar. `LivePersonalRouteBridge` now opens those routes as the
`LivePersonalDetailView` sheet over the new shell. The sheet hides its
navigation bar and takes its title from the challenge ("September steps"), so
every test failed at that first wait. Past it, most of the page had also
changed; the table below maps each old expectation to the new one.

Working through the sheet turned up one product bug the tests needed fixed.
**The payment card hid its controls' identifiers.** `LivePersonalPaymentCard`
put `.accessibilityIdentifier("personal.payment.status.card")` on a plain
stack. SwiftUI hands a stack's identifier to each child, so the state line,
Request a review, Refresh and Contact Support all reported
`personal.payment.status.card`. Their own identifiers
(`personal.payment.status.state`, `personal.review.request`,
`personal.payment.status.refresh`, `personal.payment.status.support`) never
reached the accessibility tree.

## What changed

**Product**, three accessibility lines in `LivePersonalHistoryView.swift`, with
no change to copy, layout or behavior:

- The payment card is an accessibility container
  (`.accessibilityElement(children: .contain)`), so the card keeps its
  identifier and each control keeps its own. In the accessibility tree the
  card is now one element holding the same controls as before.
- The review reason picker is `personal.review.reason`. It had no identifier.
- The detail page's scroll view is `personal.detail.page`, so tests can wait
  for the sheet and scope Personal checks to it.

**Tests**, `GameTimeUITests.swift` and `RetiredShellSkips.swift`:

- Each test waits for `personal.detail.page` and then Full rules
  (`personal.details`), which only a loaded challenge shows. The first wait is
  30 seconds: on CI the controller-owned suites and `DuelUITests` skip before
  launching, so these are now the first UI tests to launch the app, on a cold
  simulator.
- Personal checks run on the sheet, not the whole app. The new shell stays
  behind the sheet in the accessibility tree, and its friends and invitations
  are allowed; docs/COPY.md says to scope this check to Personal screens
  once new routes exist. `assertNoForbiddenLanguage` and
  `assertNoLegacyPersonalHealthSurfaces` take the page, and their word lists
  are unchanged.
- Contact Support is found by identifier alone, and Full rules as either a
  button or a disclosure triangle. Contact Support is a SwiftUI `Link`: iOS
  26.5 reports it as a button and iOS 27.0 as a link, which failed six of the
  tests there on a first run. For Full rules, iOS 27.0's XCTest warns that
  its modern type is a disclosure triangle, though it still reports a button.
- The 13 entries and the `personalDetail` reason are gone from
  `RetiredShellSkips.swift`; 38 entries remain.
- The tests that are still skipped keep their old helpers
  (`assertEnvironmentDisclosure`, `healthStatus` and the rest), unchanged.
  `assertCumulativeProgress`, which only the repaired review test used, is
  gone.

| The tests expected | The sheet has, and the tests now check |
| --- | --- |
| The "Your challenge" navigation bar | `personal.detail.page`, then Full rules |
| One `personal.environment-disclosure` banner with the mode's line | The line under the step count: "$20.00 test payment", or "$10.00 test commitment · No money will be charged". The banner's exact line is inside Full rules, checked there |
| A `personal.progress` bar, "Week progress" | "56,000 steps this week" and "14,000 to this week’s goal". The bar is hidden from VoiceOver; these lines carry its facts |
| Two reason buttons, "Selected" and "Not selected" | A menu picker. Its menu offers exactly the two fixed reasons, in order, with the current one checked; the test chooses "I disagree with the result" |
| Refresh and Contact Support hidden once a state is final | Both on every state. Each state is checked for exactly those two, plus the review reason and request while a review is open, and never a payment retry |
| Contact Support opens Account & support | A `mailto:` link. Simulators have no Mail app, so the test checks the link's label and reach without tapping it |
| "Your pace" | The goal, today’s steps and what’s left |
| "Challenge details", "Hidden" then "Showing" | Full rules, closed until tapped. The test opens it and checks the terms: goal, how it counts, amount, time zone, start, end, updates through, the missing-data line and the mode's line. Sandbox rules also keep the exact consent sentence |
| "Scheduled" | "Starts soon" |
| "Waiting on steps" | "Checking activity" |
| `personal.health.status` | The same sentence in the Apple Health card, by text |
| After cancelling, the Challenges list, showing Cancelled | The sheet stays open with "Cancellation confirmed.", the Cancelled label and no Cancel button. The sandbox test then opens Earlier challenges (You → Settings) and finds the challenge there, cancelled |

The copy these checks read is the product's existing copy; none was changed.
Payment states, the review deadline rule, the exact consent and the
missing-data promise are checked as before.

## Found, not changed

- **The review reason is clipped at the largest text.** At accessibility
  XXXL the menu picker shows only "wrong or" of "My step data is wrong or
  incomplete": its text is about 300 points tall inside a 77-point button.
  Its accessibility label is complete and the open menu is readable, so the
  test checks reach and choice, and a comment points here. Fixing it means a
  layout change, such as a menu whose label wraps, which this approval
  doesn't cover.
- **The environment banner isn't shown anywhere in the new shell.** docs/COPY.md
  asks for one compact banner above the app root in every test-only and
  Stripe-sandbox configuration. `EnvironmentDisclosureBanner` is only used by
  the retired creation flow. Personal detail names the mode in its own line and
  in Full rules instead. Whether the new shell needs the banner is the owner's
  call.
- **Refresh and Contact Support now stay on final payment states**, where the
  retired card hid them. docs/COPY.md only limits recovery actions to those
  two, so the tests accept it; restoring the old behavior would be a product
  change.
- **The cancellation card has the same identifier bug.**
  `LivePersonalCancellationRecovery`'s `personal.cancellation.pending` hides
  its Try again button's `personal.cancellation.retry`. No repaired test
  reaches that card. Fix it the same way before repairing
  `testPendingCancellationFixturesStayActionableAndRouteToSupport`. The result
  card's `personal.result` spreads to its two lines the same way, which is
  harmless.
- After a sandbox cancellation, the payment card keeps "Test method saved. No
  test charge exists." until Refresh; a fresh launch shows "Challenge closed —
  $0 test charge." Both are true.

## What was run

Xcode 27.0 (27A5237l), on a new iPhone 17 Pro simulator with iOS 26.5, with
its own derived data. The booted `GameTimeLiveDesign-iPhone13` simulator,
which another session was streaming logs from, wasn't used.

| Check | Result |
| --- | --- |
| `bash scripts/tests/check-beta-candidate.test.sh` | Passed |
| `python3 scripts/tests/build-legal-site.test.py` | 6 tests passed |
| `bash scripts/check-beta-candidate.sh --personal-copy-only` | 1 passed, 0 blockers |
| `python3 scripts/check-iphone-product.py` | Passed |
| `GameTime` `build-for-testing`, Debug | Succeeded, with no warnings in the changed files |
| The full `GameTime` scheme `test`, as in CI's "Test product app", on an erased simulator | UI: 86 tests, 29 passed (these 13 and all 16 of `LiveDesignUITests`), 57 skipped, none failed. The skipped tests are exactly the 38 listed and the 19 controller-owned ones. Unit: 648 passed, 11 skipped, none failed. 18 minutes |
| The 13, three times over | 39 of 39 passed, in 17 minutes |
| The 13 on iOS 27.0, a new simulator | After the element-type fix above, 12 passed; a launch hang cut off the 13th (see [Limits](#limits)), which then passed twice on its own |
| Mutation checks, one at a time, on an earlier draft of the tests | Each made the tests fail as it should. Without the card's container: "The authoritative payment state is missing." With "Invite friends" on the page: "Reachable Personal V1 UI contains forbidden copy". With a "Retry payment" button in the card: "The Payment test status card offers other actions." |
| `GameTime-Staging` (Staging), `GameTime` (Release) and `GameTime-TestFlight` (TestFlight), generic iOS Simulator, unsigned | Each build succeeded, with no warnings in the changed file |

A throwaway probe test dumped the sheet's accessibility tree for each fixture
before the rewrite; it was deleted and isn't in the commit.

## Remaining skips

38 tests stay skipped by name in `RetiredShellSkips.swift`, with the reasons
and repair plan from the [skip receipt](2026-09-27-legacy-uitest-skip.md#repair-plan):

| Reason | Tests | Why they stay skipped |
| --- | --- | --- |
| `accountScreens` | 2 in `GameTimeUITests` | Sign-in, onboarding and account deletion moved to new screens with different copy; they need rewriting, partly covered by `LiveDesignUITests` |
| `personalFlow` | 17 in `GameTimeUITests` | They start from the retired Today tab, old creation or the Signal shell. Those steps no longer exist |
| `friendDuels` | 11 in `DuelUITests` | Their entry under the old You screen is gone |
| `runningGoals` | 8 in `PerformanceCommitmentUITests` | The same |

## Limits

- CI uses Xcode 26.2 and iOS 26.2, which aren't installed here. The menu
  picker's accessibility (its label format, and the menu as a collection
  view) was only observed on iOS 26.5 and 27.0. The picker's label is matched
  with "contains", not exactly. Element types can differ between iOS
  versions, as Contact Support's did; the tests find it by identifier alone
  and accept either type for Full rules.
- On iOS 27.0, one app launch hung at XCTest's wait for the app to go idle,
  before any test step, and xcodebuild restarted the runner after three
  minutes. That test then passed twice. No iOS 26.5 run restarted.
- No VoiceOver or device check was made.
- CI's first launch is slow; the 30-second first wait is a guess from the
  LiveDesign receipts' 30–54 second launches, most of which `launch()` itself
  absorbs.
