# Native actor-switch isolation audit — September 18, 2026

## Baseline and scope

The initial clean checkout was `codex/profile-creation-retry` at `70584f1`.
Freshly fetched `origin/main` was `4f5b528` and did not yet contain that fix.
Local `main` was fast-forwarded to the existing `70584f1` commit before these
changes. Its profile-retry correction and tests are included. No remote merge
or push was performed. An audit branch was created; the shared checkout was
subsequently switched back to `main` at the same commit outside this task's
commands. The audit edits remain uncommitted in that checkout.

Read the repository instructions, product memory, working baseline, plan and
copy contract. Reviewed AppModel, both shells in AppShellView and their RootView
wiring, pending challenge/invitation persistence, SupabaseMetricUploadClient,
account deletion/session cleanup, and existing account-switch tests. Inspected
the retained `8e2e267d2c853175ec4bf63cd5555419b639c983` accessibility commit with
`git show` as reference, especially its onboarding mutation ownership test.
No archived branch was merged and no archived UI was restored.

## Confirmed defects and corrections

Each of the following was reproduced with a focused failing regression before
its production correction:

| Defect | Correction |
| --- | --- |
| An actor check passed its generation guard, suspended on the current-auth read, then allowed an old profile to attach after account replacement. | AppModel rechecks actor and generation after the final await. |
| An old onboarding submission kept a replacement account busy, then cleared that account's newer busy state when it finished. | Auth transitions release obsolete busy state; onboarding completion clears it only for its own actor generation. |
| Apple's name prefill remained visible when an external auth event selected a different account without a profile. | Prefill is supplied to auth resolution and retained only for the same account, including a same-account launch retry. |
| A deletion cleanup completion could publish the previous account's deletion notice after the authenticated actor changed. | Completion checks current auth and generation before publishing; resolving a new account clears the old notice. |
| Delayed deletion cleanup removed the shared invitation file after a newer invitation was received. | The shared locator is removed synchronously before any owner-scoped cleanup awaits. |
| A fast signed-in A-to-B transition could preserve all three retained navigation stacks because SwiftUI never observed the intermediate launching phase. | RootView resets navigation on actor changes and keys the displayed view tree by actor, discarding old view-local drafts and presentations. Its queued Personal activation reads the current model identity. |

Production changes are limited to `AppModel.swift`, the account-cleanup portion
of `SupabaseClients.swift`, and `RootView` in `GameTimeApp.swift`. AppShellView's
Signal presentation and SupabaseMetricUploadClient's transport implementation
needed no changes. No new user-facing strings or agreement text were added.

## Regression boundaries

Eight new tests cover the six reproduced defects plus account-scoped pending
invitation recovery and late metric refusals. Existing focused tests also cover:

- Delayed signed-out/old-actor auth snapshots cannot replace the new actor.
- A suspended old pending-challenge load cannot attach after switching.
- Sign-out detaches visible protected data while the original account retains
  its exact saved request; the same account can restore it later.
- Two accounts' pending invitation redemptions remain separate. Finishing the
  old request cannot clear the new request, its busy state, or either account's
  durable recovery. Switching and sign-out do not automatically redeem links.
- Issued invitation locators and receipts are isolated by actor and challenge;
  copied cross-account journals fail closed.
- A late metric refusal after sign-out or replacement cannot invalidate either
  account's saved key. Existing assertion/HTTP and key-rotation switch checks
  remain in the focused run.
- Retained Personal refresh/cancellation ownership, account-deletion receipts,
  protected file validation, and the existing profile-retry correction.

The pre-auth invitation locator remains deliberately account-neutral and
requires an explicit redemption action. Account-owned redemption requests,
issued links and private challenge rows are separate. Sign-out preserves the
existing opaque account-deletion receipt recovery flow; account deletion and
ordinary sign-out retain their different data-lifecycle rules.

## Verification

Final main focused run: **113 tests passed, zero failures**, exit 0.
`git diff --check` also passed. The run includes 38 AppModel/routing, eight
account-deletion, 13 invitation-recovery, nine challenge-section, five pending
challenge, three pending metric, 28 metric-client and
nine profile-client tests.

```sh
xcodebuild test -project ios/GameTime/GameTime.xcodeproj -scheme GameTime \
  -destination 'platform=iOS Simulator,id=B3E5DFC7-ED3F-4620-B86A-4F20B2AEAA2A' \
  -only-testing:GameTimeTests/AppModelAndRoutingTests \
  -only-testing:GameTimeTests/AccountDeletionTests \
  -only-testing:GameTimeTests/ChallengeInvitationRecoveryTests \
  -only-testing:GameTimeTests/SupabaseMetricUploadClientTests \
  -only-testing:GameTimeTests/PendingChallengeStoreTests \
  -only-testing:GameTimeTests/PendingMetricUploadStoreTests \
  -only-testing:GameTimeTests/ChallengeSectionTests \
  -only-testing:GameTimeTests/SupabaseProfileClientTests \
  -only-testing:GameTimeTests/PersonalAccountabilityTests/testAccountSwitchDiscardsStaleRefreshResult \
  -only-testing:GameTimeTests/PersonalAccountabilityTests/testPendingCancellationIsIsolatedByOwner \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -resultBundlePath /tmp/gametime-actor-isolation-final.xcresult \
  CODE_SIGNING_ALLOWED=NO
```

Final main log: `/tmp/gametime-actor-isolation-final.log`.
The two `PersonalAccountabilityTests` selectors in that command matched no
XCTest class and were not counted as executed. The actual class is
`PersonalAccountabilityStoreTests`; both checks were dispatched separately:

```sh
xcodebuild test -project ios/GameTime/GameTime.xcodeproj -scheme GameTime \
  -destination 'platform=iOS Simulator,id=B3E5DFC7-ED3F-4620-B86A-4F20B2AEAA2A' \
  -only-testing:GameTimeTests/PersonalAccountabilityStoreTests/testAccountSwitchDiscardsStaleRefreshResult \
  -only-testing:GameTimeTests/PersonalAccountabilityStoreTests/testPendingCancellationIsIsolatedByOwner \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -resultBundlePath /tmp/gametime-actor-personal-final.xcresult \
  CODE_SIGNING_ALLOWED=NO
```

Personal run: **2 tests passed, zero failures**, exit 0. Together the two final
runs executed **115 distinct tests with zero failures** on the final Swift source.
Personal log: `/tmp/gametime-actor-personal-final.log`. Result bundles/logs are
local temporary evidence, not committed binary artifacts.

Earlier runs are retained separately:

- `/tmp/gametime-actor-isolation-before.xcresult`: three new AppModel tests,
  four expected assertion failures before correction.
- `/tmp/gametime-actor-deletion-before.xcresult`: two new deletion tests,
  two expected assertion failures before correction.
- `/tmp/gametime-actor-isolation-focused.xcresult`: 112 tests passed after
  the first five fixes, before adding the mounted shell regression.
- `/tmp/gametime-actor-shell-before.xcresult`: the initial mounted test passed
  with legacy-social fixture work introducing suspension points.
- `/tmp/gametime-actor-shell-immediate-before.xcresult`: the mounted test was
  refined to verify populated navigation before switching and use the ordinary
  dormant-social behavior (`personalFixture`). It reproduced three stale-path
  assertion failures. That refined regression is retained in the final suite.

Simulator/Xcode commands initially needed filesystem/Simulator service access
outside the workspace sandbox; they subsequently ran with approved escalation.
No test failure was treated as a pass.

## Limits

These are local iPhone 17 Pro / iOS 27.0 Simulator tests with Xcode 27.0
(27A5237l), Debug, signing disabled. Suspensions, Auth actors, transport replies
and invitation values are fictional. The mounted RootView check verifies native
lifecycle/navigation wiring; existing invitation tests also mount native views.
This is not physical-device, real Apple sign-in, hosted Auth/RLS, end-to-end
network, human accessibility, full native-suite or release acceptance.

P7 source rules, Health ingestion, hosted configuration, deployments, payments
and release/readiness claims were not changed. No real Health data was read or
uploaded. Existing Signal UI, default-off gates and historical agreements remain.

## Final tested source fingerprints

SHA256 of the changed Swift files after the final passing run:

```text
ccc72a6035db5ea7bae1799fe45aeb3211fb236e087ba741aa75982172acac7e  ios/GameTime/GameTime/AppModel.swift
880c02eef242e3eb8015dd315ecf218f5cd304dd95b0fca83f4259f9e6c29d1a  ios/GameTime/GameTime/GameTimeApp.swift
b7f96cfa95f71b6f4cf38ef7a4d8614b06f1582c78adbd5e982832d7253d41ec  ios/GameTime/GameTime/SupabaseClients.swift
8d9d7412ed377bb604bd54b3c4463d8cfe5b7cdc790f21a97d2c86a4a182e651  ios/GameTime/GameTimeTests/AppModelAndRoutingTests.swift
4a1727da8601d903fba41ada3aaabb67339eff5b54c8467cc1c7be0d8b2fe51c  ios/GameTime/GameTimeTests/AccountDeletionTests.swift
a9b92069a1a4df4710f6c95bab37d29a8c603597262845d234ff55c2a6c4b312  ios/GameTime/GameTimeTests/ChallengeInvitationRecoveryTests.swift
79b2a653aef8a94d2f61c97f7e4119d74f3b692723d5b01f4459d5023bc0efa0  ios/GameTime/GameTimeTests/SupabaseMetricUploadClientTests.swift
```
