# TestFlight release prep, GameTime 0.9.0 (2) — receipt

September 29, 2026. This is the next backlog item after Round 12. It prepares
the first friends TestFlight build locally
([D142](../../../DECISIONS.md#d142-first-private-testflight-adds-friends-opens-apple-sign-up-and-ships-goals-first),
Phase 6 of the [friends TestFlight plan](../../../docs/FRIENDS_TESTFLIGHT_PLAN.md)).
**Nothing was uploaded to TestFlight or App Store Connect.** Nothing was
installed on a device, and nothing hosted changed.

## Commits

| Commit | What |
| --- | --- |
| `29294a6` | Declare the boot-time API (`systemUptime`, reason `35F9.1`) in `PrivacyInfo.xcprivacy`; `check-beta-candidate.sh` now blocks when it's missing, and the fixture test covers both cases |
| `b16685b` | Version bump to 0.9.0 (2). **The archive was built from this commit.** |
| `f677e0b` | What to Test and App Store Connect drafts |
| this commit | This receipt. The tip SHA is in `git log -1`; commits after `b16685b` change only reports |

## Version and build

`MARKETING_VERSION` 0.8.1 → **0.9.0** and `CURRENT_PROJECT_VERSION` 1 → **2**
on all four app-target configurations (Debug, Staging, Release, TestFlight),
so they stay in step. 0.9.0 marks the first external build of the friends
product. Build 2 moves past the `0.8.1 (1)` that every earlier local product
carried, so build numbers only ever go up. Staging device builds still pass
their own date-style build numbers on the command line (for example 926.26.1).
Nothing hard-codes the old version.

## Archive

- **Path:** `~/Library/Developer/Xcode/Archives/2026-09-29/GameTime 0.9.0 (2) TestFlight b16685b.xcarchive`
  (102 MB). It sits in Xcode's usual archives folder, so it shows in
  Window → Organizer.
- **Command:** `xcodebuild archive -project ios/GameTime/GameTime.xcodeproj -scheme GameTime-TestFlight -configuration TestFlight -destination 'generic/platform=iOS'`
  → `ARCHIVE SUCCEEDED` in 1 min 44 s (Xcode 27.0).
- **Signing: succeeded.** `codesign --verify --deep --strict` passes.
  Authority "Apple Development: MASON PHILLIP JENKINS", team `87Z29RTC26`,
  identifier `com.mjenkins.gametime`, arm64. An archive is always signed with
  the development identity; distribution signing happens when it's
  distributed.
- **Distribution signing wasn't possible here.** A local export
  (`-exportArchive`, method `app-store-connect`, destination `export`, not
  upload) failed: "No profiles for 'com.mjenkins.gametime' were found". This
  Mac has only an Apple Development certificate, and no Apple account is
  signed in to Xcode, so Xcode can't create the App Store profile or the
  Distribution certificate. Mason's upload step does both (see follow-ups).
- **Signed entitlements:** `com.apple.developer.applesignin` [Default],
  `healthkit` true, `healthkit.background-delivery` true,
  `devicecheck.appattest-environment` production, and `get-task-allow` true
  (development signing; distribution removes it). No `aps-environment` (push
  is Staging only).
- **Embedded Info.plist:** `0.9.0` (`2`), `GAMETIME_ENV` testflight,
  `SUPABASE_URL` `https://lyushhqoednheqwzsmxh.supabase.co` (gametime-p11b),
  challenges on, account mode on, contest mutations off, commitments off,
  settlement `test_only`, empty Stripe return URL, legal links and support
  email as below.
- The archive holds `PrivacyInfo.xcprivacy` with UserDefaults `CA92.1` and
  SystemBootTime `35F9.1`, plus the dSYM.
- `scripts/check-iphone-product.py --app <archive app>`: exit 0. HealthKit is
  linked, and there's no Watch payload or link.

## Config checklist

The shipping product is the **TestFlight** configuration and the
`GameTime-TestFlight` scheme, as D142 set out. `Release` is the historical
contract. It still targets the historical backend with Stripe sandbox, and it
isn't the build that goes to friends. `scripts/check-beta-candidate.sh
--testflight` → **23 passed, 0 blockers**. The Release run passes 21 with
0 blockers.

| Check | Result |
| --- | --- |
| Bundle ID `com.mjenkins.gametime` | Pass (TestFlight and Release). Tests use `.tests` and `.uitests` |
| Backend gametime-p11b, no leftovers | Pass. TestFlight.xcconfig sets the p11b URL and its public `sb_publishable_` key; `AppConfiguration.accountModeBackend` matches. No loopback, Staging or Debug values. `Staging.xcconfig` and `LocalOverrides.xcconfig` aren't included |
| Debug flags | Pass. The TestFlight config sets no `DEBUG` or `STAGING` compilation condition: `ENABLE_NS_ASSERTIONS` NO, whole-module, `VALIDATE_PRODUCT` YES, dSYM |
| Sign in with Apple | Pass. Entitlement present and signed. Hosted p11b public auth settings (read today with the publishable key): Apple on, sign-up open, email, phone and anonymous off. The production bundle was added to the provider on Sep 28 ([receipt](../2026-09-28-phase5-steps2-5.md#step-3-applied)) |
| HealthKit | Pass. `healthkit` and `background-delivery` entitlements. Read-only (`toShare: []`), so only `NSHealthShareUsageDescription` is needed and present: "GameTime reads the steps, Activity minutes and outdoor runs your Apple Watch records to Apple Health, for the goals and challenges you join." |
| Privacy manifest | **Fixed** (`29294a6`). `ProcessInfo.systemUptime` in `ChallengeV1Store` and `WeeklyStore` is a required-reason API that wasn't declared, which App Store Connect rejects on upload. Tracking is off; the collected types are name, fitness, other user content, user ID and device ID |
| App icon | Pass. A single 1024 px universal icon with no alpha. The deployment target is iOS 18.0, so Xcode generates every size |
| iPhone only, no Watch | Pass (`TARGETED_DEVICE_FAMILY` 1, `check-iphone-product.py`) |
| Secrets | Pass. No secret-shaped literal in public inputs. No secret was printed in this session |
| Export compliance | Not set in the plist; see [ASC_BETA_INFO.md](ASC_BETA_INFO.md#export-compliance) |

## Legal links and support

| Item | In the app | Published page |
| --- | --- | --- |
| Privacy | `GAMETIME_PRIVACY_POLICY_URL` = https://m1jenkins.github.io/GameTime/privacy.html. Sign in and You → Help & documents → **Privacy Policy** | HTTP 200 today |
| Beta terms | `GAMETIME_BETA_TERMS_URL` = https://m1jenkins.github.io/GameTime/beta-terms.html. Sign in and **Beta Terms** | HTTP 200 today |
| Support | `GAMETIME_SUPPORT_EMAIL` = gametime-support@agentmail.to. **Contact beta support** (mailto) | Named on both pages |
| Legal entity | Not shown in the app screens | Both pages name Squirrel Labs, Inc., State of Texas, United States; the terms' governing-law section names Texas |

All three values reach the archived Info.plist (above). No UI changed, so there
are no new screenshots, and `outputs/design/testflight-release-prep-2026-09-29/`
wasn't created. Onboarding and Settings stay plain for build 1, so no version
row was added.

## What to Test and App Store Connect drafts

- [WHAT_TO_TEST.md](WHAT_TO_TEST.md): the tester notes, about 1,600
  characters, including the known polish deferrals. At the largest text size,
  the Apple Watch sentence on "Before you start" sits behind Continue, and the
  keyboard covers the username field during profile setup. Links and
  community challenges aren't available yet.
- [ASC_BETA_INFO.md](ASC_BETA_INFO.md): the beta description, feedback email,
  privacy URL, Beta App Review contact and notes, export compliance and app
  privacy. Items marked **Mason to …** need him.

## Tests

Xcode 27.0, iPhone 17 Pro simulator on iOS 27.0
(`B3E5DFC7-ED3F-4620-B86A-4F20B2AEAA2A`), built at `b16685b`. The command is
CI's full product test (`-scheme GameTime -configuration Debug
CODE_SIGNING_ALLOWED=NO test`).

- **GameTime scheme: TEST SUCCEEDED.** 774 tests: 706 passed, **0 failed**, 68
  skipped.
  - `GameTimeTests`: 669 passed and 11 skipped (environment-gated native smoke
    and loopback tests).
  - `GameTimeUITests` target: 37 passed and 57 skipped. The skips are the
    existing by-name lists (the 38 legacy-shell skips in
    `RetiredShellSkips.swift` plus environment-gated `ChallengeV1UITests`,
    `SignalCreationUITests` and `ChallengeHealthSignalUITests`).
- `swift test` in `ios/GameTimeCore`: 187 tests in 20 suites passed, plus the
  XCTest cases.
- Simulator builds: **Staging** and **Release** `BUILD SUCCEEDED`. The
  **TestFlight** device archive succeeded (above).
- `scripts/tests/check-beta-candidate.test.sh`: PASS, including the new
  undeclared and declared `systemUptime` fixtures.

No test fixes were needed.

## Not done

- **No upload** to TestFlight or App Store Connect, and no App Store Connect
  fields entered.
- No distribution-signed export (it needs an Apple account in Xcode; see
  above).
- No device install. The real Sign in with Apple and HealthKit sheets weren't
  driven. Round 12's fixtures cover the states around them.
- The largest-text polish notes weren't fixed; they're deferred by
  instruction.

## Follow-ups for Mason

1. **Approve and do the upload.** Sign in to Xcode (Settings → Accounts) with
   the team `87Z29RTC26` Apple ID. Open Organizer, select the archive above,
   then Distribute App → TestFlight & App Store (or TestFlight Internal Only)
   → Upload. Xcode creates the Distribution certificate and App Store profile
   with cloud signing.
2. Create the App Store Connect app record for `com.mjenkins.gametime` if it
   doesn't exist, and paste the drafts.
3. Answer export compliance, or approve adding
   `ITSAppUsesNonExemptEncryption = NO` to `TestFlightAppInfo.plist`.
4. For external testers: supply the Beta App Review phone number, the owner's
   username for the reviewer's friend request, and a screen recording of a
   challenge. Internal testers can start without Beta App Review.
5. The plan's Phase 6 timing still applies. The owner moves off Staging only
   after the Staging goals settle (around October 9). Two builds uploading for
   one account can move a saved score backwards.
