# CI contrast: measure Home's sync time, run CI on Xcode 27 (Sep 28–29, 2026)

Approved by Game Time Dev (beta-driver) under Mason's September 27–28
autonomy mandate for the TestFlight beta. This continues
[the Home hero contrast receipt](../livedesign-home-contrast-2026-09-28/README.md).

## Failure

CI run [36520964738](https://github.com/m1jenkins/GameTime/actions/runs/36520964738)
at `7e93b6f`, job "iOS product and conformance (Xcode 26.2)". The other three
jobs passed.

```
LiveDesignUITests.swift:766 testFriendsScreensPassTheSystemAccessibilityAuditApartFromTextSize
Home action rows, default text: 1 Contrast failed — 1 min ago at (319.0, 351.0, 51.0, 16.0)
```

It was the third run to fail at exactly this frame, each with a different
text color: muted (`bb1660a`), hero-muted (`13caa28`) and ink (`7e93b6f`).

## What the pixels say

`7e93b6f` added a failure-only upload of the audit captures, so this run kept
the screen the audit ran on (`audit Home action rows, default text`,
1206×2622 px). In the flagged frame (153×48 px at 3×):

- The text is #0A2D44, ink, in 840 of 7,344 pixels (11 %).
- The background is #EAF0F4 (the median pixel), light frost.
- Contrast: **12.4:1**.

On this Mac (Xcode 27, iPhone 17 Pro, iOS 27.0), the same frame with
hero-muted measures #365A70 on #EAF0F4, 6.4:1. The frost is the same color
on both, so CI renders the card like the Mac. What differs is the audit's
verdict on that one text: CI's Xcode 26.2 audit flagged it in all three
colors, while this Mac's audit passes muted and hero-muted and flags faint
(3.9:1) as "Contrast nearly passed". The earlier receipt's theory that CI's
GPU drew the frost darker was wrong.

## Changes

1. **Product.** The Home hero's sync time is `Floodlight.heroMuted` again,
   as in `13caa28`, the adopted mock and the rest of the card's secondary
   text. The comment claiming CI's renderer failed both muted colors now
   says what CI's screenshot showed. `FloodlightSyncTime`'s doc comment names
   `heroMuted` again. Nothing else on screen changed, so there are no new
   design screenshots.
2. **Test, Home sync time only.** In `LiveDesignUITests.audit`, a contrast
   report on a "Home action rows" screen whose element reads "Just now",
   "N min ago" or "N h ago" is measured. The test screenshots that element
   (`XCUIElement.screenshot()`), attaches it as "audit measured …", and
   computes WCAG contrast from its pixels. The median pixel is the
   background; the pixel 3 % in from the far end of the luminance range is
   the text, so thin or faded glyphs measure lower, never higher. A ratio of
   4.5:1 or more goes into the audit notes with the ratio. Anything less, or
   an element that can't be measured, still fails, with the ratio in the
   message. No other report, screen or label is affected.
   `testMeasuredTextContrastRejectsLowContrastText` draws both texts at the
   sync time's size and pins the boundary without launching the app.
3. **CI toolchain.** The iOS job runs on GitHub's `xcode-27` image, selects
   `/Applications/Xcode_27.0.app`, creates an iPhone 17 Pro on iOS 27.0 when
   the image has none, and runs the product and conformance tests on
   `platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0`. The job is now named
   "iOS product and conformance (Xcode 27.0)"; no branch protection or
   ruleset requires the old name. The audit-captures comment no longer says
   CI's pixels differ.

## Why Xcode 27.0 and iOS 27.0

| | Xcode | Host macOS | iPhone 17 Pro simulators |
| --- | --- | --- | --- |
| This Mac | 27.0 (27A5237l) | 27.0 (26A428) | iOS 26.2, 26.5, 27.0 |
| `macos-26` image 20260907.0351 (old CI) | 26.0.1 to 26.6 | 26.6.2 | iOS 26.2, 26.4, 26.5 |
| `xcode-27` image 20260921.0210.1 (new CI) | 27.0 (27A266a), 27.1, 27.2 beta | 27.0 (26A428) | none; the job creates one on iOS 27.0 |

- The Mac develops with Xcode 27: it compiles the Staging, Release and
  TestFlight configurations and installs Staging on the owner's phone. On
  CI, Xcode 26.2 needed two type-check fixes this week (`7724a32`,
  `bb1660a`) and failed this audit; the Mac's Xcode 27 passed all three.
- Only `xcode-27` has Xcode 27, and its only iOS runtime is 27.0. So the
  match is Xcode 27.0 and an iPhone 17 Pro on iOS 27.0, a pairing this Mac
  also has. No runner offers Xcode 27 with iOS 26.5, the runtime most local
  acceptance runs used.

What this gives up, and the risks:

- CI no longer compiles with Xcode 26.2, so it won't catch type-check
  timeouts that only 26.2 hits. Those matter only for a build made with
  Xcode 26.x.
- `xcode-27` is a GitHub preview: its announcement warns of possible
  instability and queueing.
- The runner has the Xcode 27.0 release (27A266a), and this Mac has an
  earlier build (27A5237l).

## Local verification

This Mac: Xcode 27.0 (27A5237l) and an iPhone 17 Pro on iOS 27.0
(24A5408d), with the three committed changes.

- **CI's `Test product app` command** on
  `platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0`: TEST SUCCEEDED in 30
  minutes, with 695 of 763 tests passed, 68 skipped and 0 failed. UI tests:
  32 passed (the previous 31 plus the new measurement test) and 57 skipped by
  the existing lists. Unit tests: 663 passed and 11 skipped, as in the
  September 28 baseline. The friends audit passed on every screen. This
  Mac's audit didn't flag the hero-muted sync time, so the measured check
  didn't run there.
- **Conformance harness**, same destination: 10 of 10 passed.
- **Builds:** CI's Staging and Release commands, plus `GameTime-TestFlight`
  in the TestFlight configuration (which CI doesn't build), all for the
  simulator without signing: BUILD SUCCEEDED.
- `scripts/check-iphone-product.py`: passed.
- **The measurement against known colors.**
  `testMeasuredTextContrastRejectsLowContrastText` draws "1 min ago" and
  "Just now" at 12.5 pt medium, 3×. Both texts measured each pair's exact
  WCAG ratio:

  | Text on background | Measured |
  | --- | --- |
  | ink #0A2D44 on light frost #EAF0F4 | 12.41 |
  | hero-muted #365A70 on #EAF0F4 | 6.40 |
  | faint #5A7B8F on #EAF0F4 | 3.92, fails |
  | dark hero-muted #D2DDE2 on dark hero-bottom #18252B | 11.34 |
  | faint #5A7B8F on #18252B | 3.49, fails |

- **On the real app:** a temporary test (not committed) found Home's "1 min
  ago" at (319.3, 351.4, 50.7, 15.3), CI's frame. Its element screenshot
  measured 6.40:1, #365A70 text on #EAF0F4.
- **A real failure still fails:** for one run (not committed), the sync time
  was made `faint`. The audit flagged it, the test screenshotted the audit's
  own element, and it failed:

  ```
  Home action rows, default text: 1 Contrast nearly passed — 1 min ago at (319.0, 351.0, 51.0, 16.0), measured 3.9:1 on screen
  ```

## CI after the change

Run [36528661491](https://github.com/m1jenkins/GameTime/actions/runs/36528661491)
at `b93c729`: **green**, all four jobs.

- Edge Functions, Client Core and Database passed.
- "iOS product and conformance (Xcode 27.0)" passed in 70.5 minutes on
  `xcode-27-arm64` 20260921.0210.1 with Xcode 27.0 (27A266a). A runner took
  the job within a minute, and the job created the iPhone 17 Pro on iOS
  27.0. "Test product app" took 54 minutes (about 30 on the old image), with
  no failures. UI tests: 32 passed, 57 skipped. Unit tests: 663 passed (the
  parallel output cuts one of their log lines short) and 11 skipped. The
  Staging and Release builds took 12 minutes, and the conformance harness
  passed 10 of 10.
- **The measured check fired on CI.** Xcode 27.0's audit on the runner still
  flagged the hero-muted "1 min ago" on "Home action rows, default text".
  The log shows `Added attachment named 'audit measured Home action rows,
  default text, 1 min ago'`, and the test passed, so the element's own
  pixels measured at least 4.5:1. Moving to Xcode 27 didn't change the
  audit's verdict on the runner; the measurement is what cleared it. CI
  uploads the audit notes only on failure, so this run's exact ratio wasn't
  kept.

## Follow-up: the ratio in CI's log (`f26d62b`)

The measured capture's name now ends with the ratio, for example "6.4 to 1"
(artifact file names can't contain colons). The log prints every
attachment's name, so each CI run now shows the measurement, pass or fail.

- Locally (iPhone 17 Pro, iOS 27.0): `LiveDesignUITests` passed 19 of 19.
  With the sync time made faint for one run (not committed), the log showed
  `Added attachment named 'audit measured Home action rows, default text,
  1 min ago, 3.9 to 1'`, and the test failed at "measured 3.9:1 on screen".
- The workflow's toolchain comment no longer says Xcode 26.2 failed "an
  audit" the Mac passed, because CI's Xcode 27.0 audit flags the same text.
- CI: run [36536557436](https://github.com/m1jenkins/GameTime/actions/runs/36536557436)
  at `43cc9b1` was **green**, all four jobs; the iOS job took 75.7 minutes
  ("Test product app" 60). The audit flagged the sync time again, and the
  log shows the measurement:

  ```
  Added attachment named 'audit measured Home action rows, default text, 1 min ago, 6.4 to 1'
  ```

  That's the value this Mac measures, so CI draws the hero-muted text
  exactly as the Mac does and only the audit's verdict differs. UI tests: 32
  passed and 57 skipped. Unit tests: 663 passed and 11 skipped. Conformance:
  10 of 10.
