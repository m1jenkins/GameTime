# Challenge creation recovery — September 20, 2026

## Outcome

Mason's iPhone now runs the challenge-enabled signed Staging product
`0.8.1 (926.21.1)`. It was installed over the same
`com.mjenkins.gametime.staging` bundle and launched successfully, preserving the
existing app container and account state.

## Cause

Read-only device metadata showed `GameTime 0.8.1 (1)` installed. That is the
ordinary Debug product. Debug and Staging share the Staging bundle identifier,
so a physical Debug run had replaced the private-trial build. Debug inherits
`GAMETIME_CHALLENGE_V1_ENABLED = NO` from `PublicClient.xcconfig`; Signal therefore
opened the intentional “new challenges aren't open yet” route.

The checked-in Staging configuration was already correct. No challenge policy,
admission rule, agreement, Health rule or user-facing copy changed.

## Performed recovery and evidence

- Verified the preserved artifact at
  `build/signal-native-staging-20260921-926.21.1/GameTime.app` against its existing
  receipt hashes: executable
  `992b06f39ea02c5be47bb9134d7680ebe0de1e91dae0f54c43f316cfaeae29af` and
  Info.plist `033243c7fd9a93f01de1b6ea6848e4936c7633a4657524cf468bf428bb4d45ae`.
- Read back `GAMETIME_ENV = staging`, `GAMETIME_CHALLENGE_V1_ENABLED = YES`,
  `GAMETIME_PRIVATE_HEALTH_ACCOUNT_MODE = YES`, and the selected
  `lyushhqoednheqwzsmxh` HTTPS origin from that product.
- The iPhone-product guard passed: HealthKit is linked and the product contains
  no Watch app, WatchConnectivity payload or Watch runtime link.
- Installed the product in place with the enabled physical-device workflow and
  launched it with no arguments. Read-only device metadata then reported
  `GameTime Staging 0.8.1 (926.21.1)` under the same bundle identifier.
- Current hosted readback found the private trial enabled, device proof disabled
  for the selected account-only trial, exactly one enrolled and source-ready
  account, and real admission, ingestion and processing all enabled. It found
  two scheduled `personal_steps_goal_v1` records. No hosted write was made.
- `ChallengeAppConfigurationTests` passed 8/8 with no failures or skips. Result:
  `~/Library/Developer/XcodeBuildMCP/workspaces/GameTime-7b9ccaa5aefb/result-bundles/test_sim_2026-09-21T05-44-13-747Z_pid21662_d701157a.xcresult`.

No phone screenshot or raw Health data was captured. The installed Info.plist
gate and the native `ChallengeV1Shell` branch establish that **New personal goal**
now opens `ChallengeV1Create` instead of the closed-service sheet. A deliberate
person-entered target and consent are still required before another challenge is
created; this recovery did not manufacture one.

## Recurrence guard

While Debug and Staging retain their adopted shared bundle identity, do not run
the `GameTime` Debug scheme on Mason's iPhone during this private trial. Physical
device builds for this trial must use `GameTime-Staging` / `Staging`. Simulator
Debug work remains separate from the phone.
