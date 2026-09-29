# App Store Connect beta information — draft

Drafts for Mason to paste into App Store Connect for GameTime 0.9.0 (2),
bundle `com.mjenkins.gametime`, team `87Z29RTC26`. **Nothing here has been
entered in App Store Connect, and no build has been uploaded.** Scope follows
[D142](../../../DECISIONS.md#d142-first-private-testflight-adds-friends-opens-apple-sign-up-and-ships-goals-first)
and Phase 6 of the [friends TestFlight plan](../../../docs/FRIENDS_TESTFLIGHT_PLAN.md#phase-6--testflight-explicit-approval).

## App record (only if it doesn't exist yet)

| Field | Value |
| --- | --- |
| Platform | iOS |
| Name | GameTime (App Store names are unique; if taken, try "GameTime: Challenges with Friends") |
| Primary language | English (U.S.) |
| Bundle ID | `com.mjenkins.gametime` |
| SKU | `gametime-ios` (any unique string) |
| Primary category | Health & Fitness (matches `LSApplicationCategoryType`) |

## TestFlight → Test Information

| Field | Value |
| --- | --- |
| Beta App Description | See below |
| Feedback Email | gametime-support@agentmail.to |
| Marketing URL | leave empty |
| Privacy Policy URL | https://m1jenkins.github.io/GameTime/privacy.html |
| Licence agreement / terms | Beta terms: https://m1jenkins.github.io/GameTime/beta-terms.html (link it in the description; ASC has no separate beta-terms field) |

**Beta App Description** (under 4,000 characters):

> GameTime runs private fitness challenges with friends. Pick a goal together
> (steps, Activity minutes, an outdoor run distance or a timed run), agree to
> the rules, and GameTime checks everyone's progress from Apple Health.
> Missing or partial activity never counts as a miss.
>
> This beta is for a small group of invited friends. You need an iPhone and an
> Apple Watch, and you must be 21 or older. All stakes are pretend: no real
> money moves and we never ask for a card.
>
> GameTime is run by Squirrel Labs, Inc. (State of Texas, United States).
> Beta terms: https://m1jenkins.github.io/GameTime/beta-terms.html

**What to Test:** paste the block from [WHAT_TO_TEST.md](WHAT_TO_TEST.md).

## Beta App Review information (needed before external testers)

External testers invited by email need Beta App Review for the first build.
Internal testers (App Store Connect users on the team) don't.

| Field | Value |
| --- | --- |
| Contact first/last name | Mason Jenkins |
| Contact email | gametime-support@agentmail.to (or Mason's own address) |
| Contact phone | **Mason to supply** |
| Sign-in required | Yes — Sign in with Apple only. There's no username and password to give. |
| Demo account | Not applicable to Sign in with Apple. See the review notes. |

**Review notes** (draft):

> GameTime signs people in with Sign in with Apple only; email, phone and
> anonymous sign-in are off. Please sign in with your own Apple ID and confirm
> you're 21 or older.
>
> Challenges are between friends. To add a friend, open You → Friends and send
> a request to the exact username **[owner's username — Mason to fill]**. We'll
> accept it so you can create a challenge together.
>
> Progress comes from Apple Health data recorded by an Apple Watch (steps,
> Activity minutes and outdoor runs). GameTime only reads Apple Health and never
> writes to it. Without Watch data a challenge still works, but shows "No update
> yet"; a screen recording of a full challenge is attached **[Mason to attach]**.
>
> All stakes are simulated. No real money moves, no card is collected, and no
> in-app purchase is offered in this build.
>
> Account deletion: You → Settings → Delete account.

## Export compliance

The app uses only Apple's HTTPS networking (URLSession, via the Supabase
client) and Sign in with Apple. It has no custom or proprietary encryption.
The usual answer is "None of the algorithms mentioned above" (exempt), which
App Store Connect asks for on each build because `TestFlightAppInfo.plist` does
not set `ITSAppUsesNonExemptEncryption`. Adding
`ITSAppUsesNonExemptEncryption = NO` to that plist would skip the question on
future builds. That's a legal declaration, so it's left for Mason to confirm.

## App Privacy (needed before App Store, optional for TestFlight)

Matches `PrivacyInfo.xcprivacy`: name, fitness, other user content, user ID and
device ID, all linked to the person, used for app functionality only, no
tracking. No third-party analytics or ads.
