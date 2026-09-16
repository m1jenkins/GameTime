# Historical branch disposition — September 15, 2026

Firstmate completed the four deletions below at **2026-09-16 04:40:37 UTC**
(September 15 in America/Chicago), after an audit of committed history and
exact-hash preflight checks. Main remained
`1642ba9cf56ae43661db6273665c1c50f6aaf4b8`. The five retained refs were unchanged.
The captain conditionally authorized deletion only when the historical work
was unnecessary; the recovery bundle was not treated as proof of irrelevance.

## Executed deletions

| Scope / full ref | Deleted tip | Why the ref was redundant |
| --- | --- | --- |
| Local `refs/heads/codex/beta1-policy-foundation` | `0f5491009f956c623041863d96dc54ddcaad2477` | Direct parent of retained archive-beta1; all nineteen commits remain reachable there, including useful controller corrections. |
| Local `refs/heads/codex/signal-native-migration` | `823ee0a769da2695c4d24c55584913cdfaf6d0d9` | Native source/tests/configuration match published `b351a4775a938056ca229301caa513c3e1d85022`. Supporting screenshots/manifests/results are on main; remaining document differences are superseded status or preserved report text. |
| Origin `refs/heads/codex/ios-accessibility-audit` | `8e2e267d2c853175ec4bf63cd5555419b639c983` | Exact duplicate of the retained local accessibility tip. |
| Origin `refs/heads/daybreak-ledger-tokens` | `ea16beb67e6a683b2a07a7e8b4db1a782f4c07e9` | Direct parent of retained local Daybreak tip, which also preserves its unpushed follow-up. |

Firstmate verified the live remote pins and that neither remote branch was
held by an open pull request before deletion. Remote-tracking counterparts
were removed too. The Signal source/evidence is incorporated independently;
the other three deletions rely on their retained local carriers below.

## Retained references

These are bounded retention findings, not instructions to merge old branches
or restore superseded interfaces. No new captain decision is needed to keep them.

| Local full ref | Pinned tip | Relevant material / smallest follow-up |
| --- | --- | --- |
| `refs/heads/codex/archive-beta1-20260912` | `8d63f93aec65c6d56eecd022b28fcbd6bbbd6d88` | `af72170815fd5208222d55515aa179e7a97490a1` adds legacy native-controller leases and ownership-checked cleanup absent from main. Preserve its focused tests and unique acceptance records; selectively assess those corrections when changing the retained controller. The competing Beta1 app/schema is superseded. |
| `refs/heads/codex/archive-original-20260912` | `8014c97d1b5e7798c0d1669047efc1bfad01fb12` | Unique September 10 failed-gate and September 12 source-preservation receipts retain possible evidence-ledger value. Resolve that narrow provenance uncertainty before pruning. Its alternative disclosure/consent edits and older design studies are not recommended changes. |
| `refs/heads/codex/ios-accessibility-audit` | `8e2e267d2c853175ec4bf63cd5555419b639c983` | Profile retry recovery and actor-switch/accessibility regression material remain useful. Review the specific current-code finding below before final testing; preserve Signal. |
| `refs/heads/codex/overnight-integration-20260913` | `264bbd00bccc4f924b36c9e2146c7350bdf406d6` | Native fixes are incorporated. Preserve the distinct N1/N2/N3/R1 baseline failure/correction ledger used by S2 until its provenance is consolidated into the current evidence index. Privacy1/S1 are already corrected by P8. |
| `refs/heads/daybreak-ledger-tokens` | `0957d075c7fba85e8f4b07647b2fd0bdec6c672b` | Unique readable-time-zone and large-text test material may apply to retained Personal screens. Assess only that material against Signal; the paper-ledger appearance is obsolete. |

## Static finding before final testing

The accessibility branch recovers an already-created profile when a retry
collides with its primary key after a lost response. Current
[profile creation](../ios/GameTime/GameTime/SupabaseClients.swift) still inserts
without that recovery, while [error mapping](../ios/GameTime/GameTime/DomainModels.swift)
treats generic duplicate-key errors as an unavailable username. This can
mislabel a successful first submission as “That username is taken.” A bounded
review of current profile retry handling and the branch's focused regression
cases is needed before final testing. This is a **static-only finding**, not a
runtime reproduction, accepted fix or reason to merge the old onboarding UI.

## Evidence and unchanged scope

The private audit report, full per-commit/path ledger, exact ref pins and
`executed-pruning.json` are retained under the Firstmate task data directory
`gametime-historical-branch-audit-20260915`. The audit covered all thirty-one
distinct unique commits across seven local and two remote refs. The private
recovery bundle remains precautionary. No build, test, database, device,
hosted-service or product-code change was part of this audit/follow-through.

[Signal migration evidence](../outputs/reports/2026-09-13-signal-native-migration.md)
and its hashed manifests remain unchanged historical records except for a
separate dated publication/pruning note. The [S2 report](../outputs/reports/2026-09-13-signal-simulator-integration.md)
records the landed native recovery adaptations; the
[P8 report](../outputs/reports/2026-09-13-p8-concurrency.md) records Privacy1/S1
corrections. Do not reimplement them from the retained overnight branch.

The [working baseline](WORKING_BASELINE.md) and
[remaining implementation plan](GAMETIME_REMAINING_IMPLEMENTATION_PLAN.md)
still govern P7–P13. All four accepted sources, thirteen policies, real ingestion,
hosted operation and physical/human/release acceptance remain required. All
readiness entries remain false and checked-in challenge transport stays off.
Historical Personal/Solo/charity agreements and access remain intact. Existing
source/release decision tasks remain authoritative; no new hold was created.
