# Lobby pot drawing: Xcode 26.2 type-check fix (Sep 28, 2026)

## Failure

`7724a32` split the Home challenge card's VoiceOver label
([receipt](../ci-typecheck-spoken-2026-09-28/README.md)). Its CI run,
[36508999960](https://github.com/m1jenkins/GameTime/actions/runs/36508999960),
no longer stopped at `LiveChallengeShell.swift:257`, but the "iOS product and
conformance (Xcode 26.2)" job failed in "Test product app" on a new expression:

```
FloodlightDial.swift:416:25: error: the compiler is unable to type-check this expression in reasonable time
```

That's `FloodlightLobbyPot.body`, a `Canvas` whose closure drew the orbit, the
pot and every seat. It was the only compile error in the log, and all 138 app
files were compiled. In the run before it,
[36507542589](https://github.com/m1jenkins/GameTime/actions/runs/36507542589),
the module step stopped at the `spoken` error before this file's batch was
compiled, so the error only showed up after that fix. Edge, DB and Client Core
passed.

## Fix

`FloodlightLobbyPot.body` is now `Canvas { context, size in paint(&context, size: size) }`
with the same `.aspectRatio(200 / 192, contentMode: .fit)` and
`.accessibilityHidden(true)`. The drawing moved into three private methods,
`paint`, `paintSeat` and `paintInitials`, written as short statements with
explicit types. `FloodlightComponents.swift` already draws a Canvas this way,
and Xcode 26.2 compiled that one in the same run.

Numbers, colors, fonts and drawing order are unchanged. The seat angle is
computed in the same order, so the floating-point result is identical. The view
is still hidden from VoiceOver. No copy, test or behavior changes.

## Local verification

This Mac has Xcode 27.0 (Swift 6.4) only, and it compiles both versions, even
with its newer solver optimizations turned off. So the 26.2 failure can't be
reproduced here.

- `xcodebuild -scheme GameTime -configuration Debug -destination 'generic/platform=iOS Simulator' build`:
  **BUILD SUCCEEDED**, with no warnings in `FloodlightDial.swift`.
- Type-checking the file with `-debug-time-function-bodies`: the lobby pot's
  `body` went from 4.8 ms to 0.45 ms. The new methods take 2.5, 0.5 and 0.4 ms.
- Same pixels: a temporary unit test (not committed) rendered the old and new
  view with `ImageRenderer` at 3× and compared raw RGBA bytes in 380 cases.
  The cases covered light and dark, 0–6 seats (all agreed, all deciding,
  mixed), five pot amounts on both sides of $100, and 200 and 311 pt widths.
  All 380 matched and none were blank. As a control, changing one dash length
  in the old copy made exactly the 220 cases with a deciding seat fail.

## CI after the fix

Pending. This section is updated when the run for this commit finishes.
