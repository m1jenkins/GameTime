# GameTime working baseline

Consolidated September 12, 2026 UTC at the owner's request.

## Use this checkout

- Durable checkout: `/Users/user/firstmate-workspace/projects/gametime-beta`
- Active working branch: `codex/beta-working-baseline`
- Imported P7 checkpoint: `1b8fe6a3f7299ca851edf1a4255551425590e150`
- Latest implemented product code: P6 `05f405c24453fe6743ece994d646058958bfdbb2`
- Earlier Cobalt main: `affd367ebe5411969fd5b7abd45629e0746a5a7d`, preserved on
  `main` and `codex/crisp-cobalt-ui` as historical baselines.

The active branch preserves the entire Cobalt → P4 → P5 → P6 → P7 commit chain.
Its consolidation commit changes documentation only. Read `git status --short
--branch` and `git log -1` in this checkout before continuing; newer accepted
descendants supersede the dated checkpoint above. Begin later work from this
branch or its accepted successor, not the preserved `main` or a temporary clone.

The original `/Users/user/Documents/GitHub/GameTime` remains the preserved dirty
checkout. Its entry documents point here; its application changes and deleted
assets were not imported. P4/P5/P6/P7 temporary checkouts and other worktrees remain
preserved. No merge, reset, history rewrite, push, database application or device
installation is part of this consolidation.

## Current status and evidence

| Work | State | Evidence |
| --- | --- | --- |
| c8/Cobalt, Prompts 0/0A/3 | Existing local foundation, default Cobalt UI, retired Watch runtime, closed Health contracts | [Cobalt](design/crisp-cobalt/DEFAULT_UI.md), [Health contracts](BETA_HEALTH_CONTRACTS.md) |
| P2 | Historical load baseline retained, including failures | [Capacity report](load/capacity-report.md) |
| P4 | Completed and locally verified; durable worker claims and scoped locking | [Completion](../outputs/reports/2026-09-11-p4-completion.md), handoff `369e7b90dfeb74314244a923a87864e368348412` |
| P5 | Completed and locally verified; bounded history and measured query improvements | [Completion](../outputs/reports/2026-09-11-p5-completion.md), handoff `e16cff4b3beaa7bcce95db6b0e82eedaa94865fa` |
| P6 | Completed and locally verified; private 250-member community, moderation, quotas and native controls | [Completion](../outputs/reports/2026-09-12-p6-completion.md), handoff `39e5f202ab0eae0ac6c23cb784afd3df28d1ad37` |
| P7 | Preparation only; signed Debug build checked, no physical sessions or accepted sources | [Checkpoint](../outputs/reports/2026-09-12-p7-preparation.md) |
| P8/P9 | Real ingestion and four adapters/integrated journeys remain | [Remaining prompts](FIRSTMATE_REMAINING_IMPLEMENTATION_PROMPTS.md) |
| P10–13 | Hosted operation, capacity/recovery and integrated physical/human/release acceptance remain | [Remaining plan](GAMETIME_REMAINING_IMPLEMENTATION_PLAN.md) |

Do not restart P4/P5/P6 or the cancelled candidate-gate recovery. Historical
reports retain their exact input/output identities, failures and resource paths;
their old next-task instructions do not select today's baseline.

## Next work

Resume P7's [physical sessions](BETA_PHYSICAL_SESSIONS.md) after explicit opt-in
naming the iPhone and paired Watch. The prepared binary and raw build outputs
remain at the temporary paths recorded in the checkpoint; if absent, rebuild
from the durable source and recheck it. No Health data or device container is
copied by this consolidation. No physical source is accepted.

P8 uses accepted source policies; P9 connects their adapters and actual journeys.
Use the simplified focused-check policy in the remaining plan. Reserve the full
release matrix and long soak for integration/release. P10 preparation can advance
where separately requested work has no unresolved dependency.

Normal signed-in Cobalt still uses the unavailable challenge client; development
transport remains loopback-only. All 18 readiness entries remain false. This
working baseline does not enable real activity scoring, community publication,
hosted operation, money or distribution. Preserve legacy Personal agreements
and access until replacement acceptance.

## Consolidation verification

The source chain and committed P4/P5/P6 evidence are preserved without squashing.
Verify the documentation commit against P7: only the named Markdown entry/status
documents may differ. Application code, applied migration files, configuration,
tests and readiness settings remain byte-identical to P7. Existing test reports
are prior execution evidence; this documentation consolidation does not claim a
new SQL, native, physical or release test run.
