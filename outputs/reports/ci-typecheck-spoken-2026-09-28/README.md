# Home challenge card VoiceOver label: Xcode 26.2 type-check fix (Sep 28, 2026)

## Failure

CI on `main` was red in the "iOS product and conformance (Xcode 26.2)" job,
"Test product app" step. The same error appeared in both runs:

- https://github.com/m1jenkins/GameTime/actions/runs/36506681827
- https://github.com/m1jenkins/GameTime/actions/runs/36507542589

```
LiveChallengeShell.swift:257:13: error: the compiler is unable to type-check this expression in reasonable time
```

That was the only compile error in either log. Edge, DB and Client Core passed.

## Fix

In `heroCard` (`ios/GameTime/GameTime/LiveChallengeShell.swift`), the single
chained `([...] + (pot.map {...} ?? []) + people.map {...} + (sync.map {...} ?? [])).joined(...)`
is now built step by step in a `parts` array and then joined. The words, their
order and the `" "` separator are unchanged, so VoiceOver reads the same thing.
No UI, copy, test or behavior changes.

## Local verification

This Mac has Xcode 27.0 only, so the local build can't reproduce the 26.2 timeout.

- `xcodebuild -scheme GameTime -destination 'generic/platform=iOS Simulator' build`
  with `-Xfrontend -warn-long-expression-type-checking=150`: **BUILD SUCCEEDED**.
  No expression anywhere in the app target took more than 150 ms to type-check.

## CI after the fix

See the CI section below; it is updated when the run finishes.
