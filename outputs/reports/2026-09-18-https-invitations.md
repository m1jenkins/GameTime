# Local HTTPS invitation slice — September 18, 2026

## Review source

Branch: `codex/https-invitations`, in
`/Users/user/.codex/worktrees/https-invitations/GameTime`.
Started from committed local `main` at `70584f1`. Tested invitation source is
`71fc742ca96fc7406558d2dfe3b122b8308e1045`; the subsequent report commit changes
documentation only. Main and the concurrent actor-switch edits were not changed.
No merge or push was performed.

## Implemented behavior

- One `ChallengeInvitation` parser/formatter uses an explicitly configured
  `GAMETIME_INVITATION_HTTPS_ORIGIN` and `/challenge-invite/<64 lowercase hex>`.
  Parsing rejects lookalike/unconfigured hosts, credentials, ports, malformed
  tokens, percent encoding, unexpected paths, query parameters and fragments,
  including empty delimiters. The issued-link journal uses the same token
  validator without constructing an artificial custom-scheme URL.
- `AppConfiguration` passes that configuration to the durable invitation intent.
  The entry panel and issued-link display consume that same value. All three
  build Info plists expose the setting; checked-in value is `UNCONFIGURED`.
  Missing configuration closes HTTPS intake/generation without blocking launch
  or revocation of previously issued locators.
- Root `onOpenURL` delivery saves only the opaque intent, before or after sign-in.
  The existing account-neutral intent survives interrupted sign-in and relaunch.
  Redemption remains deliberate after sign-in and age confirmation, now checked
  in the action as well as the button. Existing actor-scoped exact-request retry,
  late-response isolation and conditional clearing of an unchanged link remain.
- Historical fixture-link intake and unrelated duel/Stripe routes are retained.
  Only explicit local fixtures generate custom-scheme invitation links. The
  configured issuer displays HTTPS links; unavailable configuration explains
  that links are unavailable while keeping saved-link revocation accessible.
- Inactive associated-domain/configuration and AASA templates match the path.
  No real host, Apple identifier or backend was selected. No active entitlement
  was added. See the [local contract and remaining acceptance](../../docs/BETA_INVITATION_LINKS_LOCAL.md).

Receiving a link does not send a message, admit someone, freeze a roster,
consent to rules, increase an amount or move money. Existing voluntary agreement,
safe exits and simulation remain unchanged.

## Actual checks

Xcode 27.0 (`27A5237l`), iPhone 17 Pro / iOS 27.0 Simulator
`B3E5DFC7-ED3F-4620-B86A-4F20B2AEAA2A`, Debug, signing disabled.

| Run | Result |
| --- | --- |
| Invitation branch build-for-testing | Passed; one pre-existing trailing-closure warning in `WeeklyModels.swift:275` |
| Invitation branch focused tests | **90 passed, 0 failed, 0 skipped** |
| Invitation + exact actor-switch overlay build-for-testing | Passed |
| Combined focused tests | **104 passed, 0 failed, 0 skipped** |
| Configuration/AASA/plist consistency checks | Passed for all three Info plists, inactive templates and unchanged active entitlements |
| `python3 scripts/check-iphone-product.py` | Passed; three iPhone targets and 156 source files |
| `git diff --check` | Passed |

The 90 tests comprise `ChallengeInvitationTests` (6),
`ChallengeInvitationRoutingTests` (5), `ChallengeInvitationRecoveryTests` (14),
`ChallengePolicyTests` (4), `ChallengeAppConfigurationTests` (7),
`AppModelAndRoutingTests` (34) and `DomainAndConfigurationTests` (20).
Sixteen tests are new in this slice. Routing checks inject cold/warm deliveries
through the same root handler used by SwiftUI, then exercise the real AppModel,
entry action and disk journals with fictional Auth/client replies. They cover
cancelled/failed sign-in, required age confirmation, deliberate redemption,
lost committed responses, exact retry after relaunch, account changes and late
responses. Issuer tests mount/render native views, including recovered HTTPS
links and revocation with missing configuration.

Builds used XcodeBuildMCP `build_sim(buildForTesting: true)` with
`CODE_SIGNING_ALLOWED=NO`. Prepared manifests retained only the focused unit
target and used fixture host arguments: `--fixture-mode --fixture-loading` for
the branch run; `--fixture-mode --fixture-product-shell` for the combined run,
so the actor-switch mounted-root test could exercise its normal launch task.
No Health reader or hosted client was used for invitation verification.

The actual prepared runs can be replayed while their local products remain:

```sh
xcodebuild test-without-building \
  -xctestrun /private/tmp/gametime-https-invitations-fixture.xctestrun \
  -destination 'platform=iOS Simulator,id=B3E5DFC7-ED3F-4620-B86A-4F20B2AEAA2A' \
  -parallel-testing-enabled NO -collect-test-diagnostics never

xcodebuild test-without-building \
  -xctestrun /private/tmp/gametime-https-invitations-combined.xctestrun \
  -destination 'platform=iOS Simulator,id=B3E5DFC7-ED3F-4620-B86A-4F20B2AEAA2A' \
  -parallel-testing-enabled NO -collect-test-diagnostics never
```

Result bundles (local temporary evidence, not committed binaries):

- `/Users/user/Library/Developer/XcodeBuildMCP/workspaces/GameTime-7b9ccaa5aefb/result-bundles/test_sim_2026-09-19T02-44-16-068Z_pid50010_83b71d7c.xcresult`
- `/Users/user/Library/Developer/XcodeBuildMCP/workspaces/GameTime-7b9ccaa5aefb/result-bundles/test_sim_2026-09-19T02-48-55-032Z_pid50010_bff84d2b.xcresult`

## Concurrent actor-switch integration

The completed **Harden actor-switch isolation** task left seven Swift files
uncommitted in main. Their bytes matched all seven fingerprints in its report.
The exact diff was saved to `/private/tmp/gametime-https-actor-switch.patch`:

```text
SHA256 152c5d6719814dda38173e70fe35a8dba0d59b51a50376cfb50a34f48fad6d15
```

`git apply --check` and temporary application to `71fc742` succeeded without
conflicts. The combined 104 tests add its four AppModel regressions, one
invitation regression, all eight account-deletion tests and the late metric
refusal regression. This verifies its actor-keyed view identity, router reset,
post-await identity checks, onboarding ownership, deletion cleanup and both
accounts' request isolation alongside HTTPS delivery.

The exact overlay was reversed after verification, returning this worktree to
clean `71fc742`. The source patch in main was checked byte-for-byte unchanged.
This branch contains the invitation slice; the actor task's fixes remain in
their original checkout for separate review/integration. Future integration
must retain both sets of changes. No archived branch was imported.

## Unperformed acceptance and preserved gates

No physical URL tap, installed/uninstalled web fallback, real Apple sign-in,
approved domain/AASA publication, Apple association/CDN/provisioning, signed
device entitlement, hosted recipient/expiry/revocation journey, minimum-iOS
lane or full release matrix was performed. Local injected delivery does not
establish those results. The [remaining acceptance checklist](../../docs/BETA_INVITATION_LINKS_LOCAL.md#remaining-acceptance)
keeps them explicit.

Readiness JSON and active entitlements are byte-identical to `70584f1`.
`GAMETIME_CHALLENGE_V1_ENABLED` remains `NO`. No Health access, transport
activation, deployment, payment, automatic merge or readiness change occurred.
