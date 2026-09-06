# Responsible engagement: implementation scope and verification

September 6, 2026 (UTC). Requested by the owner after reviewing the supplied
*Engagement, Compulsion, and Responsible iOS Design in Contract-Trading Apps*
report. This is a local native/presentation and planning change. It does not
establish clinical effects, demand, legal classification or live-money safety.

## Implemented

- Native duel review and agreement history now show an at-a-glance summary:
  event/source, timing and acceptance window, $20 simulated each, $0 fee,
  combined simulated outcome, ties/nonfinishes/uncertain results, exits and
  seven-day review. The exact original detailed rules remain under **Full
  duel rules**; new invitations and invitees keep their existing consent text.
- Native commitment review now shows target/source, dates, $20 simulation,
  $0 fee, miss/other outcomes, unselected recipient, exits and review. The
  complete earlier rule text remains under **Full goal rules**. Historical
  agreement/detail access, original consent and request recovery are preserved.
- Remove native legacy lead-loss/comeback category/action setup and the dormant
  launch-time OS permission request. The coordinator's foreground handler
  returns no presentation options. All environments still disable push; no
  token registration, delivery, preferences or new notification route is enabled.
- Repository working guidance now points engagement-related changes to the
  business requirements for internal review.
- The business model now adopts progress/comprehension/voluntary-return
  objectives with pressure, privacy and exit guardrails. The small pilot no
  longer has a seven-day-return-after-loss target or a weekly activity quota.
  A limit, mute or withdrawal is not a failed growth conversion.
- The current plan honors participant-selected distances and separately
  validated metrics; the mandatory-5K launch recommendation and obsolete
  next-task prompt are removed from current direction. Historical completed
  phase specifications and actual 5K agreements are retained.
- New work has explicit requirements for rest/injury-sensitive progress,
  deliberate social sharing, contextual reminders, limited analytics,
  experiments, service-fee/club incentives, and financial limits before money.
  See [D130](../DECISIONS.md#d130-engagement-rewards-athletic-progress-and-informed-voluntary-participation).

## Preserved boundaries

No migration, evaluator, source policy, consent string, amount, beneficiary,
result, payment mode, existing agreement or remote service changed. The new
summary displays the existing fictional official-5K policy honestly; it does
not offer an unsupported distance selector. Personal, Solo and charity history
retain their rules. Existing uncommitted native commitment/backend work and
unrelated skills/design outputs were present at task start and preserved.

New-money limits, notification preferences/caps, native attempts/milestones/
following and broader metric policies remain planned implementation work in
[the current order](../PLAN.md#current-implementation-order-after-the-engagement-review).
No inert controls imply otherwise. Numerical limits, cap windows/delays, live
pricing, recipient, provider and jurisdiction are not selected by this change.
No hosted changes, recruitment, external messages or live money were enabled.

## Verification

- Initial Debug simulator build passed through XcodeBuildMCP on iPhone 17e,
  iOS 26.5. Log: `build_sim_2026-09-06T04-27-00-199Z_pid29586_a604b9de.log`.
- Final Release simulator build passed with no reported warnings or errors.
  Log: `build_sim_2026-09-06T04-45-11-817Z_pid29586_739200ad.log`.
- Twenty distinct targeted checks have passing evidence: 19 native UI checks
  across DuelUITests and PerformanceCommitmentUITests, plus the existing
  all-environment push-disabled regression. The first run passed 18/20. Its
  two failures were test harness issues: a newly offscreen send button and an
  XCTest identifier query exceeding 128 characters. Tests now scroll to buttons
  before inspecting enabled state and match the long rule by label predicate.
  The four-case rerun (both failures plus duel-summary and goal-recovery checks)
  passed 4/4. Repeated tests are not added to the unique count.
- The first MCP test call exceeded its 300-second response timeout, but the
  underlying suite completed. Its finalized result bundle independently reports
  20 tests, 18 passed and two harness failures. The corrected focused run
  completed normally; no production change was needed to address those failures.
- Local Markdown file links and new section anchors resolve; all prior Text
  strings in both changed rule views are preserved; whitespace checks pass.
- Duel and commitment summary/consent screenshots were exported from test
  attachments and visually inspected. Expansion/collapse and explicit consent
  behavior are covered by the passing UI tests.

Result bundles under
`~/Library/Developer/XcodeBuildMCP/workspaces/GameTime-7b9ccaa5aefb/result-bundles/`:

- Initial: `test_sim_2026-09-06T04-31-21-948Z_pid29586_12be1e35.xcresult`
- Corrected focused run: `test_sim_2026-09-06T04-42-26-302Z_pid29586_8cbbe0e5.xcresult`

Screenshot manifests are local inspection artifacts at
`/tmp/gametime-engagement-screens/manifest.json` and
`/tmp/gametime-engagement-goal-screens/manifest.json`.

The UI matrix includes summary amounts, expanding/collapsing complete rules
without consenting, creator/recipient consent, exact recovery, changed-preview
fresh consent, gate-off decline, rematch/link revocation, provisional/final
result separation, and injury exits at accessibility text sizes. The existing
push-disabled regression covers Debug, Staging and Release configuration.

No backend/portable full suite is required for this native-only change; no
backend source changed. VoiceOver traversal, physical devices, actual push
permission/delivery, real organizer proof, human comprehension and long-term
behavior remain unverified. Proposed policies and passing UI checks are not
proof of safety under real stakes.

## Sources and interpretation

The owner's report supplies the engagement framework. Its specific company
features and regulatory claims were not independently re-audited and are not
imported as GameTime legal requirements. Apple guidance checked September 6:

- [Contextual notification permission](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)
- [Health and fitness data restrictions](https://developer.apple.com/health-fitness/)

The relevant product adaptation is that exercise pressure and rest/injury
choices matter alongside financial autonomy. The plan requires a separately
reviewed real-money policy; current simulated exits do not promise future
unconditional refunds.
