# Prompt 10 — hosted preparation completion and handoff

P10's work independent of P7–P9 is complete and locally verified. This is
**preparation only**, not hosted operating acceptance or permission to deploy.
The owner was away from devices; no device session was requested or performed.
No later prompt started and all 18 readiness entries remain false.

## Exact source and preservation

| Identity | Commit / location |
| --- | --- |
| Consolidated input | `fd193e71b12dccbbb680eb78682e0a36cd7b1ffd` on `codex/beta-working-baseline` |
| P10 preparation and verification artifacts | `3a6f6633bfb0071a2d07a73d924dd1f17492df09` on `codex/hosted-preparation-p10` |
| Preserved P10 working copy | `/private/tmp/gametime-p10-20260912` |
| Consolidated baseline retained | `/Users/user/firstmate-workspace/projects/gametime-beta`, still `fd193e71b12dccbbb680eb78682e0a36cd7b1ffd` |

This report is the documentation-only handoff commit after the preparation
commit above. The final task response records that exact resulting branch tip.
The P10 branch is retained in the consolidated repository's Git metadata; it has
not been merged into the baseline or pushed. All 76 applied migration files and
539 tracked application/script/config/test files are byte-identical to input.
The original dirty GameTime copy, earlier branches, P7 prepared binary and all
prior databases/device resources were preserved.

The existing **gametime-beta-release-readiness-b7** record remains the owner of
hosting, identity, support, retention and publication decisions. Its current
backlog hold and repository handoff were read; there is no separate task directory
for that decision. No duplicate task or worker was created. Live app task inventory
showed no other active P10 worker; retained prior work was not restarted.

## Delivered preparation

- [Hosted operation plan](../../docs/BETA_HOSTED_PREPARATION.md): current versus
  approved identities; Apple/native versus web sign-in; invitation/AASA and client
  integration; feature flags; RPC roles; scheduler, snapshots, monitoring, pause,
  rollback and recovery. Covers all current P4/P5/P6 behavior and its limits.
- [Unapproved settings worksheet](../../docs/release/beta/hosted-settings.draft.json):
  actual adopted requirements separated from proposed operating defaults; missing
  project, budget, identities, publication values, staff and policies remain null.
  It cannot be loaded as runtime/deployment configuration.
- [Support/retention runbook](../../docs/BETA_SUPPORT_RETENTION_PREPARATION.md):
  P6 challenge moderation versus independent global support/appeals, stable requests,
  scoped grant/revocation procedures, record-class policy decisions and a future
  guarded deletion workflow. No retention duration or legal policy was invented.
- [Read-only access audit](../../docs/release/beta/inspect-access.sql) and
  [executed local evidence](p10-20260912/README.md), including actual HTTP denials.
- Updated existing operating/rollout/handoff/baseline/prompt entry points. Corrected
  stale instructions implying challenge moderators can globally suspend or that
  paused claim workers process new safety leases. No product behavior changed.

## Performed checks

| Check | Actual result |
| --- | --- |
| Fresh local database | 76 migrations successfully applied; seed disabled; Supabase CLI 2.109.1, PostgreSQL 17; no hosted credentials/linkage copied |
| Final catalog audit | Zero violations: 46 public challenge RPCs (29 authenticated, 17 service-only, zero anonymous); 43 private helpers and 36 private relations; effective grants/PUBLIC inheritance, RLS, definer search paths and closed runtime checked |
| Existing focused SQL | Eight files / **203 assertions passed**, zero skips: 493, 497, 498, 502, 504, 506, 507, 508; actual local fixtures cover sessions, operator scopes, recovery/pauses, snapshot privacy and appeals |
| Local HTTP denials | **68/68 passed**: every challenge RPC as anonymous, all 17 service-only RPCs as authenticated, absent-session detail/operator/support reads and private-schema/table access |
| Existing worker transport tests | **2/2 passed**; per-item transport failure does not abandon remaining claims; failed claim does not start completion |
| Source release preflight | Expected exit 1: **17 passed, 3 blockers** for privacy URL, terms URL and monitored support. Not reclassified as release success |
| Preservation | All 76 migration hashes preserved; all 539 inspected product/config/test files unchanged; readiness JSON remains exactly 18 false entries |
| Preparation review | One [focused self-review](p10-20260912/review.md); no unresolved preparation defect identified; not an independent release audit |
| Final cleanup | All fictional SQL transactions rolled back; zero Auth users/profiles/challenge lobbies, runtime flags false. Only owned audit stack stopped; Docker backup and raw outputs retained |

SQL tests ran through direct `psql` after the CLI returned `LegacyDbConnectError`
at the explicit loopback URL. The committed exact-run reproducer validates each
exit status, sequential pgTAP assertion, plan and lack of skips/failures. This does
not claim the CLI runner or advisors succeeded. The initial Docker network-pool
failure and exclusion-name mismatch were resolved using an inspected, nonoverlapping
owned network; an initial catalog query without the local password was retried
successfully. These failures and private raw-log locations are retained in the
evidence README. No original/hosted database was used as a fallback.

The final prepared source was tested. This last commit only records the handoff;
its links, JSON, preserved input bytes and whitespace were checked afterward.
No new migrations or product code required an old-data upgrade, changed-invariant
race, native build, full SQL matrix or long soak. Those earlier acceptance records
remain prior evidence, not fresh P10 results. Actual Apple sign-in, devices,
minimum/current iOS, human accessibility and hosted operation were not tested.

## Dependencies left explicit

1. **P7:** exact device opt-in and physical observations; four accepted source
   policies, correction/completeness rules and measured timed-distance band.
2. **P8/P9:** real minimum-fact/integrity contracts; versioned real admission and
   worker/publication boundary; adapters; approved HTTPS/native Apple/link wiring;
   all 13 actual journeys. Normal signed-in Cobalt still uses the unavailable
   challenge client. No fixture flag can stand in for these requirements.
3. **Existing release-readiness owner decisions:** separate project/region/budget,
   immutable candidate, team/bundle/host, supported data flows, staff and credential
   ownership, monitored support/policy URLs, retention/deidentification/backup
   policy, community target/minimum/capacity/timezone/duration/simulated amount.
4. **Hosted implementation and acceptance:** scheduler/monitor credentials still
   need a reviewed least-privilege boundary; current service role remains broad.
   Durable trigger journal, real runtime controls, dead-letter recovery, sanitized
   monitoring/alert delivery and snapshot capture must be implemented and exercised
   on the separately approved target after source-backed integration.
5. **Deployment hazards:** the applied chain registers four active historical
   cron jobs, including push and retention; review/prevent their execution before
   hosted migration application. Review all historical public RPCs and Edge
   deployments for the separate target. No new hosted schedule or API allowlist
   has been enabled here.
6. **P11–P13:** approved hosted capacity/recovery including its soak, immutable
   source-backed release audit, physical/human acceptance and actual operating
   support. Distribution/recruitment remain separately authorized actions.

These are documented follow-ups, not a request to wait for devices or approval
in this P10 turn. Continue from this committed P10 branch when reviewing its
preparation or after explicitly accepting it into the consolidated baseline;
do not recreate P10, restart completed P4/P5/P6 or the cancelled recovery task.

No push, deployment, provisioning of hosted resources, credential changes,
external messages, user-data deletion, live Health access, payments or readiness
changes occurred. All amounts remain nonredeemable simulation.
