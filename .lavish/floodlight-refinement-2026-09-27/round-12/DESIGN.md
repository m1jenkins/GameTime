# Floodlight round 12: Sign in and Apple Health

Proposed on September 28, 2026, at owner Mason's request. Open
[index.html](index.html). This round covers two screens for the first TestFlight build,
in light (Aero Toned) and dark (Floodlit slate), at iPhone 17 size (402 × 874
points). It uses only the adopted round 9.3 `--gt-*` tokens and the Barlow and
Barlow Condensed fonts (under the OFL, in `assets/`). Components and restraint
rules match rounds 10.1 and 11.1. Nothing native changed, and no earlier round
changed. All content is fictional.

The page shows each state as a light and dark pair with a note, under the same
Appearance control (Light | Dark | Side by side). `index.html#solo/<state>/<light|dark>`
shows one phone alone at 402 × 874, which the phone-size checks and captures
use.

## Native sources read first

- `LiveAccountEntryViews.swift`: `LiveSignInView` (heading "Sign in", the
  line "Your challenges and your record, in one place.", three intro rows, the
  "Private account" tag, "Signing in…", a sentence about names, and policy
  links). `RootView` in `GameTimeApp.swift` locks sign-in to light mode and
  shows `model.presentedError` in an alert titled "GameTime" with OK.
- `AppleSignIn.swift`: `NativeAppleSignInButton` is Apple's
  `SignInWithAppleButton(.signIn)`, `.black` in light and `.white` in dark,
  52 points tall, with a 14-point continuous corner. Cancelling is silent.
- `YouView.swift`: `PublicSupportLinksView` labels the links **Privacy Policy**
  and **Beta Terms**.
- `ChallengeHealthViews.swift`: `ChallengeHealthCopy` ("Connect Apple Health",
  "No matching activity yet", the readiness wording, "You can keep browsing
  without…").
- `LiveGoalFloodlight.swift`: `FloodlightHealthCard` (a gray Apple Health
  button, "Manage access in Apple Health").
- `ChallengeHealthPermissionService.swift`: `requestAuthorization(toShare: [],
  read: [one type])`. The type is steps, Exercise time or workouts, depending
  on the goal. The app never asks to write.
- `TestFlightAppInfo.plist`: the Health purpose string is "GameTime reads the
  steps, Activity minutes and outdoor runs your Apple Watch records to Apple
  Health, for the goals and challenges you join."
- `docs/COPY.md`: the glossary, the Floodlight rows and the round 11.1 Health
  card rows.

## 1. Sign in

### Sign in (`signin-light.png`, `signin-dark.png`)

- **Source:** `LiveSignInView`, `NativeAppleSignInButton`,
  `PublicSupportLinksView`.
- **Decisions:** the wordmark (the `i-brand` mark in `--gt-brand` over
  "GameTime" in Barlow Condensed Bold) and one line sit on the sky (light) or
  the beams (dark), and only there. The hero content sits low in the sky,
  where the light sky is paler, so the orange mark reaches 3.44:1. Apple's
  button and the two links sit on the plain ground at the bottom. There's no lit
  surface and no blue button. The screen has 17 words.
- **The Apple button, per Apple's Human Interface Guidelines:** the title reads
  "Sign in with Apple", with the Apple logo to its left at title height. The
  button is black in light mode and white in dark, with Apple's system font.
  It's 366 × 52 points, above Apple's 140 × 30 minimum and the 44-point touch
  target, and its 14-point corner matches the app. These are Apple's colors,
  not tokens, and this is the only non-Barlow text besides the status bar. The
  mock's logo is a vector stand-in. Native keeps `SignInWithAppleButton`,
  which draws the real logo and localizes the title.
- **Departures:** the value line is new. The "Sign in" heading, "Your
  challenges and your record, in one place.", the three intro rows, the
  "Private account" tag and the sentence "Signing in creates your private
  account. Apple only shares your name the first time…" are gone. The brief
  said "Terms and Privacy". The mock keeps the app's own labels, **Privacy
  Policy** and **Beta Terms**, in the app's order. Native sign-in is locked to
  light, so the dark screen needs `.preferredColorScheme(.light)` removed.
  "Try demo mode" (shown only when demo mode is available) and the
  account-deletion notice aren't drawn.

### Signing in (`signin-loading-light.png`, `signin-loading-dark.png`)

- **Source:** `model.isMutating` in `LiveSignInView`.
- **Decisions:** the app already has this state. The Apple button is disabled
  and dims to 60%, and a spinner with "Signing in…" sits under it. VoiceOver
  hears "Signing in…" through the existing announcement. At 60%, the title
  still measures 5.89:1 in light and 7.76:1 in dark on real pixels.
- **Judgment call:** the spinner stays outside Apple's button. The HIG doesn't
  allow changing the button's content.

### Couldn't sign in (`signin-error-light.png`, `signin-error-dark.png`)

- **New:** "Couldn't sign in. Try again." in a quiet card (the
  `exclamationmark.circle` icon) above the Apple button. It uses `role="alert"`,
  so VoiceOver reads it. There's no second button, because tapping Apple's
  button is how you try again.
- **Departure:** today's app shows sign-in errors in an alert titled
  "GameTime", with Apple's or our own error text and OK. Examples are "We
  couldn't start Sign in with Apple. Try again." and "Apple did not return a
  usable identity token." The mock replaces them with one plain sentence.
  Cancelling Apple's sheet stays silent.

## 2. Apple Health permission

### Connect Apple Health (`health-light.png`, `health-dark.png`)

- **Source:** `ChallengeHealthCopy`, `ChallengeHealthPermissionService.swift`,
  the TestFlight purpose string.
- **Decisions:** a filled heart (an SF Symbol `heart.fill` stand-in in
  `--gt-brand`) sits on the screen's one lit surface, a small glass tile on
  the sky or beams. The heading is **Connect Apple Health**. The body is one
  line on the hero, then two quiet cards. **What we read** lists Steps,
  Activity minutes and Outdoor runs, each with an icon. The second card says
  "We never write to Apple Health." and "Friends see your totals, not your
  workouts." The footer reads "You can keep browsing without it.", then the one
  blue button, **Connect**, then **Not now** as quiet text. There are 44 words.
- **Departures:**
  1. The brief listed "workouts, distance, steps and active energy". The app
     asks Apple Health for steps, Exercise time (shown as Activity minutes)
     and workouts. It never asks for active energy, and running distance and
     time come from the workout itself. The iOS sheet would show the app's
     list, so this screen follows it.
  2. The brief said GameTime "never writes or shares them". The mock doesn't
     say "never shares", because friends in a challenge see your saved total.
     It says "Friends see your totals, not your workouts." instead.
  3. The app has no screen like this. Today it asks from a challenge's Health
     card, one type at a time. A single screen asking for all three types
     needs a native change to `connect(_:)`.
- **Heart color:** Apple Health's pink isn't a token. `--gt-brand` is the
  closest adopted red. It measures 3.71:1 in light and 4.69:1 in dark against
  the tile.

### After the Apple Health sheet (`health-denied-light.png`, `health-denied-dark.png`)

- **Source:** `ChallengeHealthCopy.title(.noEligibleDataYet)` and
  `explanation(.noEligibleDataYet)` (the readiness wording). "Manage access
  in Apple Health" and the gray button come from `FloodlightHealthCard` and
  round 11.1.
- **Decisions:** Apple Health doesn't tell apps about a denied read, so a denial
  and an empty history both land here, in round 11's words: **No matching
  activity yet** and "We couldn't find matching activity in the last 30 days.
  Check your Apple Health settings and refresh after your Watch has synced."
  A quiet card adds "Missing activity doesn't count against you.", a gray
  **Refresh activity check** and the **Manage access in Apple Health** link.
  **Continue** is the one blue button. The glass tile holds
  `heart.text.clipboard`, the Health card's icon, not a crossed-out heart,
  because the app can't know access was denied.
- **Judgment call on Not now:** it goes straight into the app, with no
  follow-up screen. The app knows Health isn't connected in that case, and a
  challenge's Health card already says **Apple Health isn't connected** with
  its own **Connect** (COPY.md, Floodlight QA row). The round 11 wording, which
  covers the case where the app can't tell, belongs to this screen.
- **New:** **Continue**. The brief asked for copy saying you can keep
  browsing. The mock reuses the Health card's "You can keep browsing without
  it." on both Health screens.

## Responsible engagement

These screens add no notifications, streaks, money, rankings or analytics.
Apple Health stays optional: **Not now** and **Continue** are one tap each,
and the screen says you can keep browsing. The screen names what we read, says
we never write, and doesn't use health data for anything beyond challenge
progress. Nothing implies a missing permission is a miss.

## Open questions for the owner

1. **Active energy and distance.** Should the list follow the app (steps,
   Activity minutes, outdoor runs), or should the app start asking for more?
   Round 12 follows the app.
2. **Where the Health screen appears.** After the profile step in
   onboarding, or at your first goal? Either needs native work: asking for all
   three types at once, or only the one the goal uses.
3. **The friends line.** Is "Friends see your totals, not your workouts."
   accurate for every challenge format, including timed runs? That format
   shows your best run time.
4. **Sign-in in dark mode.** Can native drop the forced light mode on
   sign-in and onboarding together?
5. **Error text.** Should "Couldn't sign in. Try again." replace every
   sign-in error, including the server's, or only Apple's?

## Checks

Chromium 153 through Playwright 1.63, from the global npx cache only. The
full record is in [captures/checks.json](captures/checks.json), and the
scripts are in the git-ignored `tmp/r12/`.

- **Phone size:** each of the 10 phones alone in a 402 × 874 viewport measures
  402 × 874, has page scroll width 402, fits without scrolling (content height
  874 of 874 at most), and has no element outside the phone.
- **Review page:** at 1440 (side by side with light and dark system settings,
  `#light`, `#dark`) and 390 (light and dark system settings, `#dark`), the
  scroll width equals the viewport and no phone element overflows. The
  Appearance control shows 5, 5 and 10 phones. There are no console errors or
  warnings.
- **Restraint:** on all 10 phones, the sky or beams are the first block and
  stay behind the hero. There's at most one lit surface (none on sign-in), no
  blur outside the hero, no gradient buttons or cards, no images, no emoji and
  no text fields. There's at most one blue action: none on sign-in,
  **Connect**, and **Continue**.
- **Tokens and type:** every color, background and border on every phone
  element is a `--gt-*` token value, except Apple's black and white button.
  All text is Barlow or Barlow Condensed, except the Apple button and the
  iOS status bar, which use the system font. Both Barlow families loaded.
- **Copy:** every string listed in COPY.md's new section is on its phone. The
  AGENTS.md banned words and "email" or "password" appear nowhere.
- **Contrast:** 80 text runs and 22 graphics were measured against the pixels
  behind each glyph, with zero misses. The disabled Apple button's text was
  measured too, not skipped. The lowest text is the white **Connect** and
  **Continue** in dark mode at 5.33:1. The links measure 5.67:1 (Privacy
  Policy and Beta Terms, light), 14.41:1 (dark) and 6.03:1 or better (Manage
  access). The Apple button title measures 21:1, or 5.89:1 in light and 7.76:1
  in dark while signing in. The lowest graphic is the GameTime mark on the
  light sky at 3.44:1.
- **Unslop:** the phrase scanner found nothing in this record, the README
  entry, the phone text or the review notes. The structure scanner passed this
  record and the README entry. It raised one soft flag each on the phone text
  and the review notes, for uniform sentence length (0.479 and 0.425). Both
  are short separate lines, not running prose, so they stand as written.
- **Not checked:** native rendering, VoiceOver, Dynamic Type or AX sizes, a
  real device, and Apple's actual button artwork.

## Captures

All captures are in `captures/`. Each phone is 402 × 874 at 3× (1206 × 2622):
`signin-light.png`, `signin-dark.png`, `signin-loading-light.png`,
`signin-loading-dark.png`, `signin-error-light.png`, `signin-error-dark.png`,
`health-light.png`, `health-dark.png`, `health-denied-light.png` and
`health-denied-dark.png`. `overview.png` shows all ten in a grid.
`review-1440.png` and `review-390-dark.png` show the review page.
