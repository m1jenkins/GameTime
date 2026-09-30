# Floodlight round 13 implementation

Implemented in `/Users/user/.codex/worktrees/round13/GameTime` on
`feat/round-13-floodlight`, cut from `origin/main` at `f1dd690`. The owner's
September 30 request requires this branch and worktree only; no merge or push.
The dirty main checkout was read only for the supplied copy and captures.

The source references were its `docs/COPY.md` Round 13 table and
`.lavish/floodlight-refinement-2026-09-27/round-13/captures/`, including
`checks.json`. The worktree's [copy contract](../../../docs/COPY.md#round-13)
now records those words and the owner's additional decisions.

## Built

- Challenges: agreement card above the live challenge, one blue Review and
  agree action, gray Decline with its existing confirmation, outlined filters,
  and the exact empty state without filters or an invitation link.
- You: the existing data-derived record above Friends, with the captured
  finished-result cards. Missing final data alone still does not imply a miss.
- Friends: matching gray request actions; an accepted request disappears and
  joins the top of Friends with Added today until local midnight, without a
  toast. Existing request, removal, blocking and reporting operations remain.
- Create: Who, Goal, Challenge, Friends in the captured order, outlined activity
  choices, chosen-row check, date card, amount and pot, existing outcome pictures,
  rules, and selected friends. Terms, draft validation, consent and request
  replay remain. Completed step labels use the existing hero-muted token to pass
  contrast against the native sky.
- Settings: persisted System/Light/Dark with System as the default; Apple Health,
  Privacy Policy, Beta Terms and one Contact support row; quiet Sign out and
  Delete account, with the existing deletion confirmation. No version or Account
  section. Existing Personal history remains reachable when there is history.

Create remains a full-screen cover, Settings a sheet, and the root navigation
uses the native system tab bar. The empty library's Create action preserves the
existing explicit age-confirmation sheet for an unconfirmed account; it enters
Who after confirmation. No new admission terms or confirmation copy were added.

## Screenshots

Twenty original simulator PNGs, 1206 × 2622 (402 × 874 points), from the ordinary
native controls with a fictional, in-memory capture account:

| State | Light | Dark |
| --- | --- | --- |
| Challenges | [PNG](../../design/round-13-2026-09-30/light/challenges.png) | [PNG](../../design/round-13-2026-09-30/dark/challenges.png) |
| Empty Challenges | [PNG](../../design/round-13-2026-09-30/light/challenges-empty.png) | [PNG](../../design/round-13-2026-09-30/dark/challenges-empty.png) |
| You | [PNG](../../design/round-13-2026-09-30/light/you.png) | [PNG](../../design/round-13-2026-09-30/dark/you.png) |
| Friends | [PNG](../../design/round-13-2026-09-30/light/friends.png) | [PNG](../../design/round-13-2026-09-30/dark/friends.png) |
| Friend accepted | [PNG](../../design/round-13-2026-09-30/light/friends-accepted.png) | [PNG](../../design/round-13-2026-09-30/dark/friends-accepted.png) |
| Create: Who | [PNG](../../design/round-13-2026-09-30/light/create-who.png) | [PNG](../../design/round-13-2026-09-30/dark/create-who.png) |
| Create: Goal | [PNG](../../design/round-13-2026-09-30/light/create-goal.png) | [PNG](../../design/round-13-2026-09-30/dark/create-goal.png) |
| Create: Challenge | [PNG](../../design/round-13-2026-09-30/light/create-challenge.png) | [PNG](../../design/round-13-2026-09-30/dark/create-challenge.png) |
| Create: Friends | [PNG](../../design/round-13-2026-09-30/light/create-friends.png) | [PNG](../../design/round-13-2026-09-30/dark/create-friends.png) |
| Settings | [PNG](../../design/round-13-2026-09-30/light/settings.png) | [PNG](../../design/round-13-2026-09-30/dark/settings.png) |

## Validation

Xcode 27.0, GameTime scheme, Debug, iPhone 17 Pro simulator on iOS 27.0:

| Check | Result |
| --- | --- |
| Complete `LiveDesignUITests` | **34 passed, 0 failed, 0 skipped**, including the default/largest-text system accessibility audit |
| Final dark screenshot capture | **1 passed, 0 failed**, with all ten original PNGs exported |
| Age-confirmation and original viewport regression checks | **2 passed, 0 failed** after the fixes |
| Broader app unit execution | **669 passed, 11 harness-dependent skips**; one small-heading OCR failure was repaired and its focused rerun passed |
| iPhone product/input guard | Passed, 242 active source files |
| Diff whitespace check | Passed |
| Read-only implementation/spec review | No remaining actionable findings after the age-route fix |

Result bundles and build logs stay in ignored `tmp/`: the complete UI result is
`round13-live-design-final.xcresult`, and the repaired viewport/age result is
`round13-access-viewport.xcresult`. The final dark capture is
`round13-dark-capture-final.xcresult`. The original broader run and the red runs are
retained there; they are not described as green full-unit runs.

The long complete UI run used `xcodebuild` after the MCP call's five-minute
timeout. Its exact selection was `-only-testing:GameTimeUITests/LiveDesignUITests`,
with `-configuration Debug`, `-parallel-testing-enabled NO` and
`CODE_SIGNING_ALLOWED=NO`. The simulator was
`B3E5DFC7-ED3F-4620-B86A-4F20B2AEAA2A`. The screenshot test attaches ten named
`round13-*` PNGs; `xcresulttool export attachments` supplies the originals.

Added assertions in `LiveDesignUITests` cover the new copy and order, empty-state
restraint, separate agreement consent, accepted-friend behavior, four-step
progress, selected pending seats without an increased pot, settings and stored
appearance, and the retained age-confirmation route. `FriendsStoreTests` checks
local midnight and limits Added today to accepted incoming requests.

The existing render tests now require Review and agree instead of Accept and
measure the Floodlight primary fill instead of the retired Signal fill. Vision
may split GameTime into two words at large text sizes; the exact source and
deadline clauses still have to appear in order. The 1× viewport check re-reads
the small date heading from its actual pixels at 4×, accepts only Your dates,
and retains all original unit, button-edge and fixed-footer geometry checks.

No push, TestFlight operation, Stripe operation, hosted mutation or user-data
deletion was performed. Simulator evidence does not replace physical iPhone
or human VoiceOver acceptance.
