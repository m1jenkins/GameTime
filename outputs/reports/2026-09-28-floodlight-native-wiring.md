# Floodlight native wiring, first slice

Commits `fa680fc` (tokens and Barlow) and `9d02a01` (the screens), then this
receipt, on `floodlight-native-slice-1` from `817afad`, September 28, 2026,
fast-forwarded into `main` and pushed. Nothing hosted was touched, nothing was
uploaded to TestFlight and no Stripe mode changed.

## The decision

Game Time Dev approved native Floodlight wiring and fast-forward pushes to
`main` on September 28, under Mason's September 27–28 autonomy mandate. The
scope was a first reviewable slice: the adopted 9.3 tokens in light and dark,
Barlow under the OFL, and the friend Challenge, Home card and Invitation
toward 9.3's look and round 11.1's approved decisions, where the app already
supports the state. Out of scope and not touched: Phase 5 and anything hosted,
Stripe live mode, TestFlight uploads, the Personal-detail UI tests and the
legacy skip list.

## What changed

**Tokens and type (commit 1).** `FloodlightTheme.swift` has 9.3's 63 color and
4 number tokens with light and dark values, plus 9.4's `unconfirmed`,
`unconfirmed-ink` and `unconfirmed-wash` and round 10's `link`, each named
after the CSS token. The hero and quiet card surfaces, the sky and beams,
and the shadows follow the page's Toned material. `FloodlightFonts.swift`
registers Barlow (400–700) and Barlow Condensed (500–800), extracted unchanged
from the 9.3 page, with both OFL files in `ios/GameTime/GameTime/Fonts/`.
`floodlightFont` scales like `liveFont`. `SignalTheme` keeps every light value
and gains dark values from the Floodlight dark tokens. Its blue is split into
`accent` (text and icons) and `accentFill` (behind white labels), because no
single dark blue is readable both ways.

**Screens and appearance (commit 2).** The signed-in shell follows the phone's
appearance. The root no longer forces light; sign-in, onboarding, launch,
configuration failure, creation, Settings (which holds Personal history), the
invitation-link sheet and the Personal detail sheet still ask for light.

| Screen | When the app shows it | What it is now |
| --- | --- | --- |
| Challenge | A friend goal that's active or waiting for final updates, except timed runs | Sky, back button, title, dates and day pips; the 270° dial with one recessed lane per person and the pot in the middle (tap for the pot sheet); the people row; the selected person's numbers (you first); your stake card; an Apple Health card only when Health needs attention; What counts; Full rules; Refresh activity and Leave challenge in neutral gray |
| Pot sheet | From the dial's pot, the stake card or the invitation's pot | Who put in what and the pot bar once everyone has agreed, the four outcomes in two-person or group wording with their pictures, the simulated-stakes line, Full rules |
| Invitation | An invitation you still need to agree to | Not started, "[username] invited you", title; a lit header with the lobby pot (people who agreed filled, the rest dashed), "20 km each", dates and time zone, "$20 in the pot" and the seat line; Stake "$20 each" and Fee "$0"; the agreement heading and outcome cards for two people or a group; four facts; Full rules; Review and agree; Decline, which asks first |
| Home | When you have a current challenge | The GameTime mark and date on the sky; a lit card with the title, dates and end day, your number over your goal, the compact dial with the pot, the people and the update time; the goals-met line; then the existing action rows |
| Tab bar | Everywhere in the shell | Floodlight bar, edge, accent icon and Faint labels in Barlow |

Every other challenge state and sheet keeps its current layout, in Floodlight
colors when dark. Requests, agreements, rules text, stakes, consent, decline
and leave behave as before; Decline sends the same `leave` request the
Challenges list sends.

**Copy.** COPY.md's Floodlight section now says which rows are in the app and
records the variants the native screens need: "2 h ago", an earlier date when
late, per-activity facts, "your goal" when goals differ, the seat line for no
one and for several people, the stake and progress VoiceOver lines, and the
decline confirmation reused from the Challenges list.

## Screens, mockups and screenshots

Screenshots are simulator captures (iPhone 13 size, iOS 26.5) of the design
fixtures (`--fixture-live-design`), taken by `LiveDesignUITests` with the
simulator set to light and then dark. They're untracked, in the main
checkout's `outputs/design/floodlight-native-2026-09-28/`: `light/` and
`dark/` hold each capture as `<name>-light.png` and `<name>-dark.png`, and
three contact sheets set light beside dark: `contact-challenge.png`,
`contact-invitation.png` and `contact-home-and-shell.png`. Mockup paths are in
`.lavish/floodlight-refinement-2026-09-27/`.

| Surface | Capture name | Compare with |
| --- | --- | --- |
| Challenge, top | `floodlight-challenge` (also `live-goal`) | `round-9-3/captures/light.png` and `dark.png`, first phone |
| Challenge, panel | `floodlight-challenge-panel` | the same, lower half; `round-11-1/captures/someone-leaves.png` for the gray Leave button |
| Challenge, Apple Health card | `floodlight-challenge-health-card` (with `--fixture-health-not-saved`) | `round-11-1/captures/detail-and-health.png` and `health-and-sync.png`, "No activity found" |
| Pot sheet, four people | `floodlight-pot-sheet`, `floodlight-pot-sheet-end` | `round-9-3/captures/pot-sheet-light.png` and `pot-sheet-dark.png`; wording and cards from `round-11-1/captures/outcomes-two-and-group.png` |
| Full rules | `floodlight-full-rules`, `live-full-rules-dates` | unchanged layout, now dark-aware |
| Invitation, two people | `floodlight-invitation`, `floodlight-invitation-rules`, `floodlight-invitation-end` | `round-11-1/captures/invitation-and-lobby.png`, "Invitation · two people" |
| Decline confirmation | `floodlight-invitation-decline` | the app's Challenges list decline, reused |
| Pot sheet, two people | `floodlight-invitation-pot-sheet` | `round-11-1/captures/outcomes-two-and-group.png`, "The pot · two people" |
| Review and agree | `floodlight-invitation-agree-sheet` | unchanged layout, now dark-aware; `round-11-1/captures/health-and-sync.png`, "Agree · missing activity" |
| Home | `floodlight-home`, `live-home`, `home-action-rows` | `round-9-3/captures/light.png` and `dark.png`, middle phone; `round-11-1/captures/health-and-sync.png`, "Home · stale" |
| Challenges, You and Friends | `live-challenges`, `live-you`, `friends-list`, `friends-sheet` | no Floodlight design yet: old layouts in the new tab bar and dark colors |
| Creation | `create-type`, `create-goal`, `create-challenge`, `create-friends` | stays light in both captures, by design |

## For Game Time Design

Design QA (agent `53200e28-df81-4925-87eb-cb47dea58c8d`): compare each
screenshot pair with the mockup in the table. The fixture data matches the
mocks' September runs (Tuesday, four people, Priya done) and October runs
invitation from Jordan. Things to judge rather than diff:

- **Colors follow roster slots.** You are always slot 0 (orange); friends
  take the next slots in the saved roster, so colors never shift when someone
  leaves. The mocks key colors to fixed people, so Jordan is green in
  September runs but blue in October runs, where he's second on the roster.
- **Initials come from usernames** ("Sam" gives SA), not full names (the mock's
  SR), because the challenge roster carries only usernames.
- **The people row shows "No update" only,** as 9.3 does, not 11.1's
  per-person numbers; tap a person for their numbers.
- **The Challenge page keeps a "What counts" row** (it opens the activity and
  Apple Health sheet, which has Connect Apple Health) and neutral gray Refresh
  activity and Leave challenge buttons. The mocks show neither on the live
  page; 11.1 shows Leave and Refresh as gray pills on its edge-state phones.
- **The pot sheet uses 11.1's layout:** one card per outcome with the 9.4
  wording from COPY.md, not 9.3's divided list with its older titles.
- **Home keeps the existing action rows** (Needs you) under the card, with
  their blue Review and Accept pills. 11.1's Next up rows aren't built.
- **Sizes follow 9.3** where 11.1 differs: 44pt titles and a 38pt pot hub for
  four people. The back button is 11.1's card button, not 9.3's glass one.
- **Dates use the system formatter** ("Sep 21 – 27", with spaces).
- **The active tab keeps its filled icon** (house.fill); the mocks use outlines.
- **Dark Challenges, You and Friends** are the old layouts painted with the
  Floodlight dark tokens, not a Floodlight design.

## Checks

Local, with Xcode 27 (27A5237l) and the iOS 26.5 simulator runtime, in a
worktree of this branch. CI (Xcode 26.2) runs after the push.

- **Tokens and contrast** (`FloodlightThemeTests`): all 63 colors and 4
  numbers match the 9.3 CSS, and 11.1 hasn't moved any of them; the 4 later
  colors match 11.1. Re-measured natively, the lowest light text pairs are
  `faint` on the tab bar at 4.50 and the pot amount on the pot bar top at 4.52;
  in dark, the POT caption at 4.95. Arc heads on their tracks are 4.44–4.98 in
  light and 6.91–11.21 in dark. Initials on the six member colors measure 4.74
  or more in light (the page's 64% mix gave Priya 4.18, so native uses 78%).
- **Fonts:** the eight faces register from the bundle, both OFL files ship, and
  the only `.ttf` files in the app are these eight.
- **Unit tests, iPhone 13:** the full `GameTimeTests` run found four failures.
  A second theme contrast test still checked white on the text blue; it now
  checks the fill blue, like the first. Vision read my new "$0 in the pot"
  requirement in the invitation render test as "$o"; it now asks for "in the
  pot". A real bug: at the largest text size the Home wordmark cut off
  ("GAMETI…"); the date now moves under it. The fourth,
  `ChallengeCreationFlowTests.testGoalUnitsStayBesideTheirValues…`, fails the
  same way at the untouched base `7ff24d7` on an iPhone 13 simulator (Vision
  reads "20 km" as "20k"); creation isn't touched here. A rerun of the affected
  classes passed 26 of 27, all but that creation test.
- **UI tests, iPhone 13:** `LiveDesignUITests` in light, 15 of 17 on the
  first run. Fixed: the new copy test dismissed iOS 26's decline dialog with a
  cancel button that iOS 26 doesn't show, and the audit flagged the Home
  card's small initials. One test was lost to a runner interruption when a
  second simulator started; it passed alone. The audit still reports
  "Text clipped — Taylor Kim" on Friends, whose layout this slice doesn't
  change. The screenshot runs passed 8 of 8 in light and 8 of 8 in dark.
- **iPhone 17 Pro, CI's destination:** every test in the `GameTime` scheme, as
  CI runs them but on iOS 26.5 rather than 26.2, on a fresh iPhone 17 Pro
  simulator at the rebased branch: **passed**. Unit
  tests 660 passed and 11 skipped. UI tests 87 run, 30 passed (all 17
  `LiveDesignUITests`, including the new copy test and the friends audit, and
  the 13 Personal-detail tests) and 57 skipped by the existing lists. No
  failures, so the creation OCR test and the "Taylor Kim" clip are specific to
  the narrower iPhone 13.
- **Exploratory audit** of the new Challenge, pot sheet and invitation pages,
  at default and largest text (a throwaway test, not committed). Fixed from
  it: the day pips were a tiny accessibility element, an empty placeholder
  under each person was exposed, and capitals were spoken in capitals. The
  remaining flags were misreadings, checked against the screenshots: text
  measured with its button's whole frame (a colored circle beside the name) or
  under the scrolled status bar. No new audit test is committed.
- **Builds:** `GameTime-Staging` (Staging), `GameTime` (Release) and
  `GameTime-TestFlight` (TestFlight) built at the final tree for the
  simulator, without signing, like CI.

## Not built yet

- Results, reviews ("Result updated", "Result stands"), void, cancelled and
  member-exit states; the lobby; waiting for the group after you agree; timed
  runs; leaderboards; personal Rules and Put money on it. They keep their
  current pages.
- Home's Next up rows and the empty-state dial; the Floodlight look for
  Challenges, You, Friends, creation and Settings.
- VoiceOver walk-through, a phone display check and the owner's review.

## Responsible engagement

Nothing new pushes use or stakes. The invitation's pot counts only people who
agreed, so it can't make the stakes look bigger than they are. "Couldn't
confirm" is drawn in blue with a "?" and never as a miss. There are no
rankings, countdowns, money celebrations, notifications or analytics, and no
payment behavior changed. Each Floodlight screen has at most one blue action;
Apple Health, Refresh activity and Leave challenge are neutral gray.
