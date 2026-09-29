# Home hero contrast fix, September 28

## Failure

CI run [36513016376](https://github.com/m1jenkins/GameTime/actions/runs/36513016376)
(bb1660a, Xcode 26.2, iPhone 17 Pro) failed one test:

```
LiveDesignUITests.swift:766 testFriendsScreensPassTheSystemAccessibilityAuditApartFromTextSize
Home action rows, default text: 1 Contrast failed — 1 min ago at (319.0, 351.0, 51.0, 16.0)
```

This was the first CI run since 9d02a01 that got past the Xcode 26.2 type-check,
so it was the first time this audit saw the Floodlight Home card.

## Root cause

The text is `FloodlightSyncTime` in the Home hero card's footer
(`LiveChallengeShell.swift`, `heroCard`), 12.5 pt medium in `Floodlight.muted`
(#3E6278). The footer sits at the bottom of the frosted hero, where the white
gradient is thinnest (`hero-bottom`, 52 % white over `.ultraThinMaterial` on the
sky), so more sky shows through than anywhere else on the card.

The adopted mocks (round 9.2 onward) set `--muted: var(--gt-hero-muted)` for
everything inside `.sky`, so secondary text on the hero is `hero-muted`
(#365A70 light, #D2DDE2 dark). The native Home card used plain `muted` instead.

Local reproduction did not fail. The unfixed code passed on an iPhone 17 Pro
with iOS 26.5 and again with the iOS 26.2 runtime CI pins, both under Xcode 27.
There the text sat on about #EAF0F4 (about 5.7:1). CI's virtualized GPU renders
the material differently. Estimated worst case with no frost at all, just 52 %
white over the sky: `muted` 5.4:1, `hero-muted` 6.2:1. The audit still flagged
`muted`, so it's judging the rendered small glyphs more strictly than the token
ratio; `hero-muted` adds about 13 % contrast on every background.

## Change

- `FloodlightSyncTime` takes a `color`, defaulting to `Floodlight.muted`, so the
  goal page's plain white numbers card is unchanged.
- The Home hero card uses `Floodlight.heroMuted` for its secondary text: the
  sync time, the dates line, the chevron, the "/ 20 km" goal and "No update
  yet". That matches the mock. No token values changed; `FloodlightThemeTests`
  already checks `heroMuted` on the sky.

No tests were skipped or loosened.

## Verification

- Focused test on iPhone 17 Pro, iOS 26.5, Xcode 27, fixed code: passed (156 s).
  Home default notes record only the 2 unnamed "Potentially inaccessible text"
  reports the test already expects. The sync text renders #365A70.
- `scripts/check-iphone-product.py`: passed.
- Remote CI: see the next commit or the run on the pushed tip.

## Second attempt

`hero-muted` was not enough. CI run
[36518284371](https://github.com/m1jenkins/GameTime/actions/runs/36518284371)
(13caa28) failed the same audit at the same frame, while the fix passed locally
on both iOS 26.5 and 26.2. The dates line at the top of the same card, same size
and weight, passes on CI. So CI's virtualized GPU renders the frost at the
card's bottom edge much darker or greyer than any local simulator does.

- The Home hero's sync time now uses `Floodlight.ink` (about twice the contrast
  of either muted token). The rest of the card keeps `hero-muted`.
- CI gets two failure-only steps, "Collect accessibility audit captures" and
  "Upload accessibility audit captures". They upload the audit screenshots and
  notes (fixture screens only) as the `accessibility-audit-captures` artifact for
  7 days, so the next failure comes with the rendered pixels. The collect script
  was dry-run against a local result bundle: 28 files.
- Focused test on iPhone 17 Pro, iOS 26.2 runtime, Xcode 27: passed (147 s).
