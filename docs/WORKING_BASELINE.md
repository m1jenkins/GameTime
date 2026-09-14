# GameTime working baseline

Develop in `/Users/user/Documents/GitHub/GameTime` on `main`.
Read `git status --short --branch` and `git log -1` before starting work.
This is the current local development line; GitHub publication is a separate step.

The history contains Cobalt, completed P4/P5/P6, P7 preparation and P10 through
`01f1dd159839769fe31ce33804e757876eb4b573`, followed by the consolidated preview
launcher, entry documents and September 13 browser design studies at `b25834c`.
Existing commits are preserved without squashing. The
[consolidation map](WORKTREE_CONSOLIDATION_STATUS.md) records the
archive branches, backup and disposition of old checkouts.

September 13: **Signal is the official native UI/UX.** Native source, tests and
configuration are published on GitHub `main` at `b351a4775a938056ca229301caa513c3e1d85022`.
They replace the ordinary shell and shared presentation, preserve retained
Personal access, and remove superseded rendering and fonts. See the
[P9A report](../outputs/reports/2026-09-13-signal-native-migration.md) for source
identity, actual checks and limits, and the [contract](design/SIGNAL_UI_MIGRATION.md)
for continuing design requirements. The complete migration, including its local
documentation and screenshots, is preserved at `823ee0a` on
`codex/signal-native-migration`. Those supporting files remain local working-copy
changes: automatic approval review rejected their inclusion in the public push.
The separately recorded native recovery branch has not been integrated.

## Current work

| Work | Status | Evidence |
| --- | --- | --- |
| Foundation / Prompts 0, 0A, 3 | Implemented locally; iPhone-only runtime and closed Health contracts; historical cobalt presentation superseded by P9A | [Historical UI](design/crisp-cobalt/DEFAULT_UI.md), [Health contracts](BETA_HEALTH_CONTRACTS.md) |
| P9A — Signal | Native source published on `main` at `b351a47`; tested source and acceptance limits recorded separately from real integration/release | [Native report](../outputs/reports/2026-09-13-signal-native-migration.md), [contract](design/SIGNAL_UI_MIGRATION.md) |
| P2 | Historical load baseline preserved, including failures | [Capacity report](load/capacity-report.md) |
| P4 | Scoped locks and durable worker claims completed locally | [P4 report](../outputs/reports/2026-09-11-p4-completion.md) |
| P5 | Bounded history and measured query improvements completed locally | [P5 report](../outputs/reports/2026-09-11-p5-completion.md) |
| P6 | Private 250-member community, moderation and quotas completed locally | [P6 report](../outputs/reports/2026-09-12-p6-completion.md) |
| P7 | Preparation only; physical sessions and four accepted sources pending | [P7 checkpoint](../outputs/reports/2026-09-12-p7-preparation.md) |
| P10 | Device-independent hosted/support/retention preparation included; actual hosting unperformed | [P10 report](../outputs/reports/2026-09-12-p10-completion.md) |
| P11A — local recovery | Bounded local worker/snapshot invocation and recovery code is implemented on the unlanded task branch; hosted schedules, credentials and external alerts remain disabled | [P11A report](../outputs/reports/2026-09-14-p11a-local-recovery.md) |
| Local design preview | Fictional friend/personal journeys with configurable owned resources | [Preview guide](BETA_LOCAL_PREVIEW.md) |
| P8/P9 | Real ingestion, accepted adapters, authenticated transport/links and integrated journeys remain; reuse existing closed contracts and screens | [Remaining prompts](FIRSTMATE_REMAINING_IMPLEMENTATION_PROMPTS.md) |
| P11–13 | Operating code/deletion, hosted capacity/recovery, physical/human/release acceptance, then authorized private Beta remain | [Remaining plan](GAMETIME_REMAINING_IMPLEMENTATION_PLAN.md) |

## Next work

The owner has no Apple Watch yet and explicitly selected simulator-only work.
Do not request physical Watch actions or start P7 device sessions now. The
bounded P11A local recovery slice is implemented on the unlanded task branch;
its report records the combined S2/P8 source, worker/snapshot interfaces and
the local validation limits. P7 source acceptance remains deferred until
hardware is available; simulator success cannot accept a source or select
timed-distance tolerance. All four sources still gate distribution. The next
dependency is approved real-source P8/P9 work and, separately, an authorized
hosted target for operation. Do not recreate P9A/P10/P4/P5/P6 or the cancelled
candidate-gate recovery.

Native fixes exist outside `main` on `codex/overnight-integration-20260913`
(code `a3e7733`, report `264bbd0`). The branch report records issued-link,
redemption and detail-response fixes with 66 focused passes; these were not rerun
by this planning review. Reconcile them in P9. Its Privacy1 read/revocation finding
has source confirmation but no runtime proof/fix; S1 create/suspension remains an
unverified concern. P8 includes scoped verification and any required correction.

Normal signed-in Signal still uses `UnavailableChallengeV1Client`; development
transport remains loopback-only. All 18 readiness entries remain false.
Consolidation does not enable real activity scoring, community publication,
hosting, money or distribution. Preserve existing Personal agreements and access
until replacement acceptance. P9A's native checks are recorded in its report;
they do not validate the earlier unlocated candidate or establish source,
hosted, physical or human acceptance.

## Evidence and archived work

The P4/P5/P6/P7/P10 reports retain their performed checks, failures and original
source identities. Their old paths and next-task instructions are historical.
The cleanup's actual checks are recorded in the consolidation map; they do not
replace physical, hosted or release acceptance.

The old dirty copy, earlier Beta1 code and old branch tips are preserved separately.
Do not apply their whole patches to this source. Use a short-lived branch from
current `main` for future work, and use a worktree only when isolation is needed.
