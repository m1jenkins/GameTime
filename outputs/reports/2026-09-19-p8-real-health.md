# P8 real Health local software record

Local work began from `848ef6ee02d95b57bdad4b36d3c7600a4ba3f192` on
`codex/p8-real-sources`. The owner authorized code and synthetic local
verification, in order: steps, Exercise Time, cumulative running, timed running.
Terra sub-agents implemented and reviewed bounded native, SQL and verification
work alongside the parent. Nothing here is a physical accuracy measurement.

[D138](../../DECISIONS.md#d138-owner-selects-p8-source-rules-and-whole-run-distance-tolerance)
records the owner decisions and measured-test sign-off. The
[real Health contract](../../docs/P8_REAL_HEALTH_CONTRACT.md) owns the exact
implemented rules, API interpretation and P9 integration limits.

## Implemented behavior

- Separately versioned Watch steps and Apple Workout outdoor distance/timed
  readers and adapters. Bounded reads retain the full frozen request; ongoing
  queries stop at their observation time. Anchored deletion UUIDs remain
  distinct from disappearance. Source exclusions, duplicate identity conflicts,
  sync revisions, Watch changes and incomplete reads fail conservatively.
- Whole in-window workouts only. Distance uses the unrounded recorded value
  for inclusive 100–102% matching, then whole elapsed time including pauses is
  rounded up. Steps and cumulative distance round down. History and suggestions
  remain on-device; timed readiness is bound to a selected comparable distance.
- A separate default-off Edge endpoint verifies JWT/session identity and exact
  App Attest body bytes. Private SQL facts bind actor, terms, policy, metric,
  frozen instants, selected timed distance, revision and freshness. Replacement
  values can decrease; deleted/unresolved states are never zero. Durable iPhone
  journals retain exact bodies and signatures across relaunch and response loss.
  A required shared coordinator prevents readiness and activity from signing
  past each other's pending work and holds a lease across suspended operations.
- New real agreements and consent for friend, Personal and community entry,
  separate from historical/fictional agreements. Real source processing reuses
  the existing thirteen allocation policies, notices, reviews and final history.
  Worker claims and community snapshots select their source's gate and clock.
- Account-deletion cleanup removes readiness/replay state with identity cleanup,
  and normalized facts plus their value-bearing request copies at the existing
  30-day detailed-data stage. Agreement-bound admissions follow the existing
  180-day consent cleanup. Existing case holds and restore replay remain in force.

## Concrete limits

Exercise remains **unavailable**. Public Exercise quantity APIs identify the
writer and device but do not identify the activity that caused the credit.
Consequently the adopted exclusion of manual/imported/third-party-derived
Exercise cannot be enforced. Its reader/normalization checks exist; positive
ingestion and real admission are rejected. The three Exercise policy cases in
the matrix use explicitly seeded defensive contracts and verify refusal/void;
they do not establish reachable real Exercise admission.

A successful Health query and App Attest do not establish complete history.
Positive quantity lower bounds or timed upper bounds can prove met goals.
Below-target quantities, absent/unreadable data and all real leaderboards stay
unresolved/void. The complete-input allocation oracle retains strict comparisons
and normalized ties, but these readers do not claim its completeness premise.

The Apple Health system bundle namespace plus the `WatchN,N` product grammar is
a versioned engineering interpretation of OS-owned source metadata, not an
Apple-published exhaustive device list. Names/manufacturer strings and a missing
manual marker cannot admit a record alone. Unknown origin remains unresolved.

P9 ordinary-app wiring is separate. It must extend the shared P8 coordinator's
signing-through-commit/recovery ordering to retained Personal writers sharing
the same App Attest key. The two P8 clients are default-off and currently
uninstantiated by ordinary app flows. An unresolved
refresh must explicitly replace an older positive fact rather than leave it
visible indefinitely.

## Performed checks

The initial steps path was proved before extending the metric policy. Final
focused Swift/native/Edge checks use the complete local source. Database checks
use owned Docker resources with numeric loopback ports, synthetic actors and
test keys. No physical Health records or hosted credentials were used.

| Check | Result |
| --- | --- |
| Complete `GameTimeCore` suite | 178 tests in 19 suites passed |
| Native steps ledger, workout reader, readiness and upload clients | 21 tests in four suites passed on the owned iOS 18.6 simulator |
| Shared ingestion/attestation, retained check-in/metrics and new real Edge endpoint | 820 tests passed |
| Signed steps HTTP → actual handler/PostgREST/RPC → correction/review/history | 14 checks passed |
| Signed cumulative distance equivalent | 14 checks passed |
| Signed timed equivalent, including frozen-distance rejection | 15 checks passed |
| Separate active signed steps concurrency seed | 9 checks passed |
| Concurrent database connections | One same-parent correction commits; concurrent exact retries recover one receipt; token expiry and session revocation after lock waits are rejected |
| iPhone product guard | Passed; active input has 172 source files and no Watch app target |
| Five forward migrations on fresh and populated baselines | Applied successfully; retained historical agreement/consent digests unchanged |
| Historical challenge SQL, suites 490–518 | 889 assertions in 27 suites passed after the final migration hashes; the new 518 suite is counted separately below |
| Focused real SQL, suites 518–522 | 263 assertions passed: 36 ingestion, 20 admission/modes, 143 policy matrix, 20 privacy, 44 worker/snapshot |

The HTTP checks include ordinary participant progress, lower correction,
cross-actor denial, expired JWT and revoked session, wrong terms, gate-off exact
response recovery, actual notice-relative 48-hour review and filing-relative
72-hour resolution. SQL additionally covers exact inclusive 24/48-hour ingress
deadlines and just-late refusals, frozen window/policy/distance, null-parent CAS,
private grants/RLS, Personal preview/consent, community join, and all thirteen
server-derived policy outcomes. The worker cases also prove that real processing
cannot lease a paused legacy row, and that real community captures retain the
five-person threshold and 15-minute source-clock delay.

The native/core cases include raw query truncation before filtering, active
windows, true deletion versus visibility loss, source exclusions and Watch
switching, overlapping and conflicting identities, confirmed sync replacement,
empty/partial/history-limited data, exact distance edges and just-outside values,
pauses, fractional elapsed seconds, strict timed comparisons, normalized ties,
cancelled reads, account changes and journal relaunch. Final native recovery
tests cover exact pending-request draining, failed retries blocking new signing,
cross-client pending recovery after relaunch, and a lease held across suspended
signing. Both clients derive their stores from the required shared coordinator.

## Reproduction and evidence

Run from this branch with cached local Docker dependencies. The verifier checks
ownership labels and loopback bindings and refuses a changed applied migration
set. Its private manifest contains fictional credentials and is not a report.
Start with a new manifest path. To replace this task's existing stack, use
`rebuild` in place of `prepare`, then run `apply-forward` separately; `rebuild`
alone only reconstructs the baseline.

```sh
python3 scripts/p8-real-health-verify.py prepare \
  --manifest /private/tmp/gametime-p8-real-health-verify/manifest.json

python3 scripts/p8-real-health-verify.py apply-forward \
  --manifest /private/tmp/gametime-p8-real-health-verify/manifest.json \
  --tap 518_challenge_real_health_ingest \
  --tap 519_challenge_real_health_metrics \
  --tap 520_challenge_real_health_policy_matrix \
  --tap 521_challenge_real_health_privacy \
  --tap 522_challenge_real_health_worker

deno run --config supabase/functions/deno.json \
  --allow-read=/private/tmp/gametime-p8-real-health-verify/manifest.json \
  --allow-run=docker --allow-net=127.0.0.1 --allow-env \
  scripts/p8-real-health-http.ts \
  /private/tmp/gametime-p8-real-health-verify/manifest.json steps
```

Repeat the HTTP command with `distance` and `timed`. For the concurrency driver,
create its own new `steps --retain-active` HTTP seed; do not reopen an already
final agreement or edit its frozen window. The driver requires its owned
manifest and leaves runtime gates off.

```sh
python3 scripts/p8-real-health-concurrency.py \
  --manifest /private/tmp/gametime-p8-real-health-verify/manifest.json

swift test --package-path ios/GameTimeCore

deno test --config supabase/functions/deno.json --allow-env \
  supabase/functions/_shared supabase/functions/attest-device \
  supabase/functions/ingest-checkin supabase/functions/ingest-metrics \
  supabase/functions/ingest-challenge-health

python3 scripts/check-iphone-product.py
```

The final database and HTTP checks used these exact forward files:

| Migration | SHA-256 |
| --- | --- |
| `20260920010824_challenge_real_health_ingest_v1.sql` | `054ecf8ffbeae36df92d1d631c7a14ff3e8eb52c116b6d07033dc2b17b95032f` |
| `20260920015606_challenge_real_health_metrics_v1.sql` | `3816db03757426223ffd8f55719d0f05aa9219ac1a54505686bdccb279ea4596` |
| `20260920020431_challenge_real_health_metric_contracts_v1.sql` | `48c7310f5765a9597798e0130660b5a131d2765064b3bf17db20e2672ecbf833` |
| `20260920022108_challenge_real_health_privacy_v1.sql` | `fbfad85e6c4fa48d54bfc58c1809007e297c8c7485e941c01a2e13c7711a0f81` |
| `20260920023500_challenge_real_health_worker_v1.sql` | `9402d92d3f89b20e56d4492ce9995d9bf92929d6fa52dd5c8ebda9e0df2f01db` |

Local logs are `/private/tmp/gametime-p8-core-final.log`,
`gametime-p8-native-final.log`, `gametime-p8-edge-final.log`,
`gametime-p8-http-steps-final.log`, `gametime-p8-http-distance.log` and
`gametime-p8-http-timed.log` in the same directory. Private migration, pgTAP and
concurrency receipts are retained separately under the verifier's receipt
directory. They contain only synthetic test data but are not published.

The final concurrency run restored its source clock, session state and all
three real runtime flags. Historical digests, migration hashes and absence of
an ingress overlay were checked once more. The ownership-checked cleanup then
removed this task's DB, Auth, REST and fresh-test containers and network; the
private receipts remain at
`/private/tmp/gametime-p8-real-health-verify/manifest-receipts`.
The task-created `GameTimeP8Local` simulator was removed after its successful
final run. The native log records the exact `GameTimeBetaLocal` test command;
its result bundle remains at
`/private/tmp/gametime-p8-derived/Logs/Test/Test-GameTimeBetaLocal-2026.09.19_20-01-25--0700.xcresult`.

The checked-in clients remain default off, the Edge environment switch is
unset by default, the real database runtime starts with three false flags, and
all 18 external readiness entries remain false. No deployment, distribution,
recruitment, money or physical-data upload occurred. The owner sign-off does
not alter historical observations or satisfy P12/P13 release acceptance.
