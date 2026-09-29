# Round 12 Sign in and Connect Apple Health — receipt

Backlog item (b) from the Floodlight backlog atop
[SIGNAL_UI_MIGRATION.md](../../../docs/design/SIGNAL_UI_MIGRATION.md).
Proposed September 28, built and verified September 29, 2026.

## Commits

| Commit | What |
| --- | --- |
| `28a5048` | Round 12 proposal: mocks, checks and the COPY.md section, before the native build |
| `f6da6cc` | Build round 12 Sign in |
| `ee58d52` | Build round 12 Connect Apple Health |
| `d2c4c4f` | Light and dark screenshots from the UI test run |
| this commit | This receipt |

## What changed

**Sign in** (`LiveAccountEntryViews.swift`, `AppModel.swift`, `AppleSignIn.swift`)

- Follows the phone's appearance; sign in, onboarding and the loading screen
  between them no longer force light mode.
- Wordmark, one line ("Private challenges with friends. Proof from Apple
  Health."), Apple's own `SignInWithAppleButton` at its default height and
  shape (black in light, white in dark), then Privacy Policy and Beta Terms.
- The old "Sign in" heading, intro rows, "Private account" tag and account
  sentence are gone.
- Every failure, including the server's, shows one card: "Couldn't sign in.
  Try again." No GameTime alert. Cancelling Apple's sheet shows nothing.
- While signing in, Apple's button dims and "Signing in…" shows below it.
- A fixture-only launch argument (`--fixture-sign-in-attempt=fail|wait`)
  drives the failure and in-progress states for UI tests.

**Connect Apple Health** (`ConnectAppleHealthView.swift`,
`ChallengeHealthFlowStore.swift`, `ChallengeHealthPermissionService.swift`,
`LiveChallengeShell.swift`, `LiveGoalDetail.swift`)

- Appears once per person, the first time they create a challenge, agree to
  one or join a community challenge. Never during onboarding.
- Lists Steps, Activity minutes and Outdoor runs; Connect makes one HealthKit
  request for all three and marks every source connected.
- "Friends see your progress, not your workouts." (owner, Sep 28) replaces the
  earlier "totals" wording; `docs/COPY.md` updated.
- Not now goes straight on (to "Who's it for?" when creating) with no
  follow-up screen. A challenge's Health card still says Apple Health isn't
  connected.
- If nothing from the last 30 days is readable after Apple's sheet, the
  screen shows "No matching activity yet" with Refresh activity check,
  Manage access in Apple Health and Continue.

Onboarding and Settings are unchanged for build 1. The create flow keeps
"Who's it for?" first after the Health screen.

## Tests

All runs used Xcode 27.0 beta, iPhone 17 Pro simulator on iOS 27.0
(`B3E5DFC7-ED3F-4620-B86A-4F20B2AEAA2A`), Debug, fixture mode, built from
`ee58d52`. No hosted services were touched.

**Round 12 UI tests, light and dark** — 8 tests each, 0 failures in both:

- `testSignInShowsOneSentenceWhenTheServerRefuses`
- `testSignInDimsAppleButtonWhileSigningIn`
- `testConnectAppleHealthComesBeforeTheFirstCreateAndNotNowGoesStraightOn`
- `testConnectAppleHealthWithNothingReadableOffersRefreshAndContinue`
- `testConnectAppleHealthComesBeforeTheFirstAgreement`
- `testOnboardingSavesProfileAndAccountSignOutClearsTheNewShell`
- `testChallengeHealthCardBeforeConnectingShowsNoProgressOrUpdateTime`
- `testLargestTextKeepsOnboardingConsentAndExitReachable`

**Broader pass** (light): all of `GameTimeTests` plus the
`LiveDesignUITests`, `ChallengeV1UITests`, `ChallengeHealthSignalUITests` and
`SignalCreationUITests` classes. Result **Passed**: 723 tests, 693 passed,
0 failed, 30 skipped.

- `LiveDesignUITests`: 24 passed, 0 skipped.
- New unit tests passed: `SignInFailureTests` (3) and the three new
  `ChallengeHealthFlowStoreTests` (screen appears once and Not now is
  remembered; Connect asks for all three types; people already connected
  skip the screen).
- The 30 skips are environment-gated and not Round 12: `ChallengeV1UITests`
  (11), `SignalCreationUITests` (7) and `ChallengeHealthSignalUITests` (1)
  need a local Beta controller, diagnostic mode or owned synthetic
  fixtures; in `GameTimeTests`, 7 native smoke tests need the disposable
  local stack and 4 `ChallengeHealthOrdinaryAppTests` need the synthetic P9
  loopback controller.
- Legacy `GameTimeUITests` (Today shell), `DuelUITests` and
  `PerformanceCommitmentUITests` were not run.

**Other checks**

- `swift test` in `ios/GameTimeCore`: 187 tests in 20 suites passed, plus 3
  XCTest cases.
- `scripts/check-iphone-product.py`: exit 0.
- `scripts/beta-preservation-check.py` refuses to run from the main checkout
  by design; not run.

An earlier attempt (September 29, ~04:49) was interrupted mid-run and left
no result. These runs replace it.

## Screenshots

`outputs/design/round12-signin-health-2026-09-28/light/` and
`outputs/design/round12-signin-health-2026-09-28/dark/`, 9 each:

| File | Screen |
| --- | --- |
| `signin-error.png` | Sign in after a refused attempt |
| `signin-loading.png` | Sign in while signing in |
| `health.png` | Connect Apple Health before the first create |
| `health-denied.png` | Nothing readable after Apple's sheet |
| `floodlight-challenge-health-card.png` | A challenge's Health card before connecting |
| `onboarding-age.png` | Onboarding age step (unchanged) |
| `onboarding-largest-text.png`, `onboarding-age-control-largest-text.png`, `profile-largest-text.png` | Largest text size |

## Not done

- No TestFlight upload, no hosted changes, no phone install.
- The real Apple sign-in sheet and the real HealthKit sheet were not driven;
  the fixture covers the states around them.
