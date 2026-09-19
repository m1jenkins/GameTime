# Integrated candidate: iOS 18.6 and unsigned Release native slice — September 19, 2026

Review branch: `codex/ios18-release-native-20260919`, isolated worktree
`/Users/user/.codex/worktrees/ios18-native-compatibility/GameTime`. The verified
input was `codex/integrated-candidate-20260919` at
`7a6c319fbe2c5065b8b585fd93bf2b9efbaa1cbf`; main was not used as the
integration source or changed. The native/guard correction is
`687a479778101bc720a031b20dd1738eb3e5744f`. The builds and final test
used those corrected source bytes. No product scope, dependencies, hosted state,
P7 rules, readiness entries or historical agreements changed.

## Environment and exact run

- Xcode 27.0 (`27A5237l`), Apple Swift 6.4 (`swiftlang-6.4.0.30.4`), iOS 27.0
  SDK; pinned `Package.resolved` SHA-256
  `452c14b9d0588669721098a59f6c579f2998fb3f6097810e1f906d56141eaac0`.
  Package versions were not changed; resolution used
  `-disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile`.
- Fresh task-owned iPhone 16 Pro Simulator `A81C63B7-F647-4429-86FD-5D0010347FD3`,
  iOS **18.6** (`22G86`). Debug `GameTime` build-for-testing and
  `test-without-building` used `CODE_SIGNING_ALLOWED=NO`, nonparallel tests,
  and an `.xctestrun` manifest beside the products with test-host arguments
  `--fixture-mode --fixture-product-shell`. These launch the fictional services;
  the focused suite did not read Health or contact hosted services. Profile
  response-loss and network errors were simulated in its client tests.
- The exact previously recorded 14-suite selection ran on the final source:
  **159 passed, 0 failed, 0 skipped**. The two selected
  `PersonalAccountabilityStoreTests` methods were
  `testAccountSwitchDiscardsStaleRefreshResult` and
  `testPendingCancellationIsIsolatedByOwner`; all other suite counts match
  [the integration manifest](integrated-candidate-20260919/native-verification.json).
  This covers strict HTTPS invitation parsing and routing, durable/retry
  recovery, profile insertion/read retry, actor switching, deletion cleanup,
  and retained Personal isolation. The final
  [local result bundle](/private/tmp/gametime-native18-release-20260919.uv9gm5/native18-final.xcresult)
  records device, runtime, tests and outcome.
- An earlier broader run selected all 32 Personal store tests instead of two:
  **189 passed, 0 failed**, on the same iOS 18.6 device before the source fix.
  The initial sandboxed build could not fetch pinned packages (DNS blocked);
  an outside-sandbox retry built successfully. The first test invocation
  misplaced the `.xctestrun` manifest, so Xcode found no test product and
  executed no tests; putting it beside `Build/Products` resolved that setup
  error. No failed product assertion is counted as a pass.

## Release products and packaging

Both `GameTime` Release builds passed with `CODE_SIGNING_ALLOWED=NO`:
`generic/platform=iOS Simulator` (arm64 and x86_64) and
`generic/platform=iOS` (arm64). The actual product paths are under
`/private/tmp/gametime-native18-release-20260919.uv9gm5/DerivedData/Build/Products/`
as `Release-iphonesimulator/GameTime.app` and
`Release-iphoneos/GameTime.app`. `scripts/check-iphone-product.py --app` passed
for **each**: 156 active source files, three iPhone targets, HealthKit linked,
and no Watch payload, linkage or runtime symbols. Both `Info.plist` files have
`MinimumOSVersion = 18.0`, `GAMETIME_CHALLENGE_V1_ENABLED = NO`, and
`GAMETIME_INVITATION_HTTPS_ORIGIN = UNCONFIGURED`; both Mach-O load commands
also say minimum iOS 18.0. Release retains the existing `gametime-beta` URL
scheme. The active entitlement input has no associated-domains key, and the
invitation xcconfig, entitlement and AASA templates are not referenced by the
Xcode project or active configuration. Unsigned builds cannot verify a signed
device entitlement or OS association.

Initial inspection of **both** Release executables found
`--demo-interactive` and `--fixture-demo-interactive` literals: the two launch
argument reads sat outside the `#if DEBUG || STAGING` boundary, even though the
Release fixture service branch was already off. The fix puts fixture argument
parsing and `isFixtureTestLaunch` assignment inside that boundary and assigns
`false` in Release. It changes no Debug/Staging behavior or person-facing copy.
The product guard now rejects fixture launch markers in a Release executable;
its **15 mutation/unit tests pass**. After rebuilding, the guard passed on
both actual products and neither executable contains `--fixture-`,
`--demo-interactive`, `FixtureServicesFactory`, `ChallengeLocalLaunch`, or
`SourceInvestigationLaunch` strings. `git diff --check` passed.

The existing `WeeklyModels.swift:275` trailing-closure warning and Xcode
AppIntents metadata-skip warning remain. The Simulator Release link also emits
three nonfatal ambiguous-target-atom warnings on this toolchain (present before
the correction); they did not prevent a product or affect this focused test
result. No dependency or deployment-target change was made to silence them.

## Boundaries and resource disposition

The task-owned simulator was shut down and deleted after the final result bundle
was saved; its disposable device state is not recoverable. Build logs, prepared
products, and xcresults remain in the task-owned `/private/tmp` directory above.
No other simulator or service stack was changed. This iOS **18.6** Simulator
run does **not** establish exact iOS **18.0** runtime compatibility, signed
physical-device acceptance, actual universal-link association/taps, Apple
sign-in or Health source behavior, hosted admission/recovery, accessibility or
human acceptance. The full P12 release/qualification matrix remains open.
