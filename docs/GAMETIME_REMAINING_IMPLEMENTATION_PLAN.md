# GameTime remaining implementation plan

Reevaluated September 13, 2026 against clean local `main` at `b25834c`.
Use the [working baseline](WORKING_BASELINE.md) for source identity and the
[prompt pack](FIRSTMATE_REMAINING_IMPLEMENTATION_PROMPTS.md) for scoped tasks.
The original reevaluation changed planning. The subsequent P9A native status
below records presentation work; product terms and release gates are unchanged.

September 13 owner clarification: there is no physical Watch yet; current work
is simulator-only, with no owner-operated Watch sessions. Signal native source
is published on `main` at `b351a47`. The combined S2/P8/P11A candidate
landed on local main at
`a3d2c3f9cafb0c97191b90ce9794dfd36474b3aa`, reverified September 14.
The [P11A report](../outputs/reports/2026-09-14-p11a-local-recovery.md) and
[verification follow-up](../outputs/reports/2026-09-14-p11a-community-verification.md)
retain their dated pre-landing statements and original limits. The local operator
interface also landed on local main at
`6fea1c28d98ef0ee86a3f9aec72e47b8088c5ec1`, with owner approval on September 14.
Its [operator report](../outputs/reports/2026-09-14-p11a-operator.md) retains the
actual CLI/Auth HTTP checks and historical pre-landing status. The owner now
requests a fresh review of this plan from the consolidated baseline; phone-only
testing can be planned around the available iPhone 17, with device actions still
separately scoped.
It does not complete real P8/P9 or hosted operation. Defer physical P7, while
preserving its later source/distribution requirements.

The shortest path is to finish real activity → agreed challenge → corrected
result, operate it on one approved backend, and test it with people. Preserve
the chosen native design. Do not restart completed implementation or commission
another design, infrastructure or general audit workstream.

## What is actually left

| Area | Verified status / remaining work |
| --- | --- |
| P0/0A/3, P4–P6 | Local foundation, iPhone-only runtime, closed Health contracts, scoped locks, bounded queries and private community are implemented. Their reports remain evidence; do not repeat these prompts. |
| Signal / P9A | Local native migration implemented on `codex/signal-native-migration` from `b25834c`; ordinary and retained routes use Signal, with cobalt rendering and fonts removed. [Native verification](../outputs/reports/2026-09-13-signal-native-migration.md) records tested source, route coverage and limits. Use this implementation for P9 under the [migration contract](design/SIGNAL_UI_MIGRATION.md). |
| P7 | [Preparation](../outputs/reports/2026-09-12-p7-preparation.md) is complete; physical observations, four source policies and timed-distance tolerance remain unaccepted. |
| P8/P9 | Configured ordinary Signal now shares the app authentication session and existing challenge client; checked-in opt-in remains off. [Bounded P9 connection](../outputs/reports/2026-09-15-p9-authenticated-app.md) records local substitute checks. Real consent/ingestion, accepted adapters, approved HTTPS/Apple identities/links and source-backed journeys remain. |
| P10 | [Device-independent preparation](../outputs/reports/2026-09-12-p10-completion.md) is complete. Approved settings, functioning hosted scheduler/alerts, retention/deletion and operating acceptance are still missing. |
| P11A | Local worker/recovery/snapshot/status code landed at `a3d2c3f`; scoped human operator tooling landed at `6fea1c2`. Administrator grant response reconciliation remains manual. Account deletion and review repairs are landed through `c6f88cd` ([local record](evidence/beta-finish-line-b7/account-deletion-local-20260914.md)). Hosted schedules, credentials, alerts and actual retention/deletion operation remain outstanding. [Recovery report](../outputs/reports/2026-09-14-p11a-local-recovery.md), [operator report](../outputs/reports/2026-09-14-p11a-operator.md) |
| P11–P13 | Operated backend, integrated candidate, physical/human acceptance and authorized distribution remain. Public App Store submission is a later milestone. |

The landed combined candidate contains S2's Signal adaptations of the
older overnight issued-link/redemption/detail fixes and P8's verified Privacy1/S1
corrections. Their original branches and dated reports remain evidence. Do not
reimport the overnight implementation or restart those corrections; use the
verified landed base and distinguish its local checks from source-backed
or external acceptance.

## Product requirements stay intact

- Preserve all 13 policies: eight friend policies for 2–6 people, four personal
  goals and one private community steps goal. All four sources must pass before
  TestFlight under D134/D135. Steps-first implementation is not a steps-only
  release. If a source cannot support its result rules, present a concrete scope
  decision instead of inventing completeness.
- The iPhone reads eligible Watch-origin activity; there is no GameTime Watch
  app. Empty/missing data never proves zero or a missed goal. Keep consent,
  admission limits, correction/review time, exact retries, privacy and safe exits.
- Community exact anonymous counts require five joined, active, nonremoved
  members and a server snapshot at least 15 minutes old. Under five, expose no
  exact or differential counts. Five is not the outcome minimum.
- Amounts remain visibly nonredeemable simulation. Preserve historical Personal,
  Solo and charity agreements. Legacy Personal access remains until replacement
  acceptance; deleting old data is not required to replace navigation.

## Recommended execution order

| Step | Work and completion condition | Dependency |
| --- | --- | --- |
| P9A — adopt Signal natively | Local implementation and verification recorded in the native report; preserve its source and continue with P9 integration. | Independent of P7 and hosting; current stores, closed clients and explicit local fixtures. |
| P7 — settle source rules | Resume [private sessions](BETA_PHYSICAL_SESSIONS.md). Record eligibility, overlap, corrections, late sync, missing-data behavior and whole-run tolerance. Accept each source or state why it remains unavailable. | Exact iPhone/paired Watch opt-in and actual owner participation. |
| P8 → P9 — complete a real journey | Start with accepted steps: versioned minimal ingestion and real admission/worker rules, then existing native screens through progress, correction, review and final result. Apply the proven path to Exercise, cumulative running and timed runs; finish community and all 13 policies. | Each metric's accepted P7 policy. Work may alternate P8/P9 by metric; all four are required for distribution. |
| P10 follow-through → P11 — operate one backend | Use the existing worksheet to select settings. Implement missing scheduler/recovery, scoped operator access, alerts, account deletion and approved retention. Test locally, then deploy/exercise only the authorized target. | Independent local operating code can accompany P7; hosting needs approved settings/actions, and real activity operation needs P8/P9. |
| P12 + P13 — qualify one candidate | Integrate chosen native UI and real Apple sign-in/HTTPS links. Run the release matrix once, plus device/accessibility/comprehension and operating checks. Fix defects and complete gated legacy shell retirement. | Integrated source-backed candidate; authorization for actual hosting and device checks. |
| Private TestFlight, then public launch | After acceptance/authorization, run a small supervised simulated pilot, fix observed problems, then prepare the App Store release. | Actual Beta results, working support and separate submission/release authorization. |

P7 remains the next source-dependent task, deferred while the owner lacks a Watch.
The P11A local recovery and operator CLI slices are both landed; neither resolves P10's hosted
inputs. Next work depends on accepted real-source contracts and an explicitly
authorized hosted target. Do not fabricate source policies to fill time. Each
prompt is separately scoped; this plan does not dispatch later work.

### P8/P9: finish the product connection

Reuse `ChallengeHealth*`, `ChallengeV1Store`, policy evaluators and auth/retry
mechanisms. Add the missing versioned real contracts, minimum-fact integrity
boundary and transport. Preserve fictional contracts; never enable fixture
actors or clocks on hosting to make real operation work.

The journey is Apple sign-in → 21+ confirmation → create/open invitation →
propose/freeze/consent → activity update → correction → review → final simulated
history. Also exercise community join, withdrawal, block/report, account switch,
expired session, relaunch and lost-response recovery. Verify two- and six-person
journeys and all 13 policies using existing coverage.

Use the official Signal UI completed in P9A; native migration is required even if
the earlier reported candidate cannot be located. Match charts to
available authorized data; absent daily values are unknown, not invented points.
Do not upload extra Health history or widen friend visibility to reproduce a
browser chart. Fix broken actions, unreadable terms and misleading states;
defer optional visual flourishes.

### P11: implement operation before load testing

[P10's hosted plan](BETA_HOSTED_PREPARATION.md) and
[support/retention preparation](BETA_SUPPORT_RETENTION_PREPARATION.md) describe
the gaps. Close them with the smallest workable implementation:

- One scheduled claim/complete worker with durable retry identity, bounded
  retries and item-specific dead-letter recovery; one delayed community snapshot
  job. Reuse the existing worker, not a new queue platform.
- Scoped authenticated operator tooling/grants, sanitized failure/backlog alerts,
  staffed support, admission pause and tested recovery/rollback. An audited CLI
  is sufficient; no custom admin dashboard is required.
- In-app account-deletion initiation connected to an approved, idempotent
  new-domain deletion/deidentification workflow, session/Apple-token revocation,
  disclosed holds and verified completion. A support runbook alone is insufficient.
  Keep historical bulk cleanup separate. [Apple deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app/).
- Exact HTTPS/Apple/bundle/link identity, RPC/Edge exposure and credentials.
  Prevent the four active historical cron registrations from executing during
  hosted migration application. Review API grants and RLS separately.
  [Supabase API security](https://supabase.com/docs/guides/api/securing-your-api).

Use the existing Beta workload: 2,000 accounts / 250 DAU / 100 concurrent /
25 requests per second / one 250-person cohort. Preserve proposed acceptance
budgets: unexpected errors <1%; read p95/p99 ≤500/1,500 ms; mutation p95/p99
≤800/2,000 ms; zero deadlocks/unrelated global-lock waits; lock-wait p95 ≤100 ms;
30% connection headroom; worker start within 60 seconds; outage backlog 95%/100%
drained within 5/15 minutes; one two-hour stability run. Correctness/privacy
failures always fail. Approve target and cost before hosted execution.

P2's contention, disconnect and scale failures remain historical failures.
P4/P5/P6 show local improvements, not hosted capacity. Adapt the existing harness
to the authorized environment and real contracts; isolate synthetic load traffic
from participant data.

## Beta and launch finish lines

| Milestone | Evidence needed |
| --- | --- |
| Working local Beta | Identified native candidate; P8/P9 contracts and functioning journeys; focused checks on final code. This does not establish physical, hosted or distribution acceptance. |
| Ready for private TestFlight | Four accepted sources; 13 usable policies; approved community settings; real Apple sign-in/HTTPS links; hosted capacity/recovery; account deletion/support/privacy/terms; physical accessibility and human consent/result/exit comprehension; accepted replacement and actual signed binary; exact distribution/recruitment approval. |
| Public simulated launch — recommendation | Beta demonstrates credible updates/results, usable exits/reviews and manageable support. Fix blockers, select regions and initial enrollment limit, prepare truthful metadata/screenshots/privacy declarations and review access, and obtain App Review plus owner release authorization. |
| Funded launch — separate future work | Provider, funds flow, jurisdiction/platform clearance, source integrity under stakes and payment/reconciliation controls under PLAN.md Phase 6. Beta/design passes do not satisfy these requirements. |

Apple's first external TestFlight build requires review; App Store submission
has its own build/metadata process. Provide review access and a working backend;
explain the Watch requirement, Health use and simulation accurately. These are
submission tasks, not another feature phase.
[TestFlight review](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/),
[App Store submission](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/),
[App Review requirements](https://developer.apple.com/app-store/review/guidelines/).
Official guidance was checked September 13; recheck at actual submission.

The existing 20–30-adult/two-round pilot is a proposal, not a recruited cohort or
a launch gate by headcount. Use D134's 2–6-person rules and all-mode availability,
not the older weekly 2–5 contract. Predeclare the actual cohort and checks.
Observe a full activity/correction/review/result cycle; report missingness,
comprehension, voluntary return, support burden and pressure. Manual feedback is
enough initially; analytics can stay off.

All 18 [readiness entries](release/beta/readiness.json) remain false. They record
different acceptance and permissions, not 18 features to enable. Real money and
optional analytics should remain false for this simulated Beta.

## Proportionate verification and deferred work

Use focused tests and one concise review per change, on final source. SQL needs
an owned disposable DB, affected privacy/retry tests, relevant actual-session
races and an old-data upgrade/historical smoke. Native changes need the affected
build/journey; docs need link/meaning/diff checks.

Reserve the full relevant SQL/native/historical/controller matrix, minimum/current
iOS, supported sanitizers and signed Release packaging for P12; repeat affected
checks after fixes. Minimum target remains iOS 18.0; use the lowest compatible
installed 18.x lane and document any exact-runtime gap. Prior lanes/counts are
historical evidence, not fresh checks.

Keep the existing 90-minute local validation/20-minute command working defaults;
the planned release soak is a milestone exception. After the same environment
obstacle twice, record it once and continue independent work. Required untested
correctness stays open. Do not build another resource allocator, verification
framework or recurring audit process.

Defer 25k/10k-community characterization, four-hour soaks, speculative partitioning,
generic queues, public/user-hosted communities, photos, push, chat, growth analytics,
paywalls and payment adapters. Approved deletion and staffed support are required;
a generalized retention platform and custom operator UI are not.
