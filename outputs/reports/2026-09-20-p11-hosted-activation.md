# P11 hosted worker and monitor activation receipt

**Succeeded September 20, 2026 UTC. Worker and monitor remain enabled.**
This establishes **scheduled operation on an empty backend**, not full
operational acceptance or a usable beta.

- **Source:** clean `main` at `4c52664a77c030cba32251f30a5037867e100d72`,
  verified descendant of reviewed `8e45132b35956a1ba74d7e059869ae46789d6181`.
  Reused the [P11 local evidence](2026-09-20-p11-local-scheduling.md),
  [P11B installation](2026-09-20-p11b-hosted-installation.md), and
  [scheduling contract](../../docs/BETA_HOSTED_PREPARATION.md#september-20-local-cron-and-edge-continuation).
- **Target:** `gametime-p11b` / `lyushhqoednheqwzsmxh`, Better Bet
  (`nfokjrpuwftlmvfrathp`), `us-west-1`; healthy, Free plan. No purchase or
  upgrade; the owner's $20 ceiling and credential custody are unchanged.
- **Approved changes:** one guarded transaction enabled `worker_enabled` and
  `monitor_enabled` in `app.challenge_schedule_config_v1`, called
  `public.challenge_real_health_runtime_v1(false, false, true)` through the
  existing authorized `postgres` service context, and activated only existing
  jobs `challenge-worker-v1` (6) and `challenge-monitor-v1` (8) using
  [supported `cron.alter_job` controls](https://supabase.com/docs/guides/cron/quickstart#activatedeactivate-a-job).
  Both retain `* * * * *`. All eight job IDs, schedules and command fingerprints
  match preflight. The exact Edge base URL remains
  `https://lyushhqoednheqwzsmxh.supabase.co/functions/v1`; existing distinct Vault
  references and Edge secrets are preserved. No secret value was printed or
  replaced. Batch 20, five completion lanes, timeouts, leases and retries remain
  the installed defaults.

Activation returned at **09:47:50.336570 UTC**. One observation of the natural
09:48 tick established both HTTP outcomes and the durable worker receipt:

| Observation | Result |
| --- | --- |
| Worker Cron run 2 / HTTP request 1 | HTTP **200**, `empty`; zero completed, failed or pending items; no transport error or timeout. |
| Worker invocation `a6d8ed6b-3ae2-42e7-a167-23b1eb15cc31` | Machine state **`finished`** at 09:48:01.286886 UTC; saved result `empty`; journal `dispatched`, one dispatch, zero claims, batch limit 20. |
| Corresponding heartbeat | **`healthy_empty`** at 09:48:01.220040 UTC; claimed/due/retry/dead-letter/failed counts all zero; no error code. |
| Monitor Cron run 1 / HTTP request 2 | HTTP **200**; sanitized `state=empty`, `processing_state=empty`, processing unpaused, admission paused; work/review/appeal counts zero. Snapshot `capture_state=unconfigured`, `snapshot_state=unavailable`. |
| Combined final readback | Auth GET at 09:49:38.482275 UTC and SQL at **09:49:41.169127 UTC** passed: only worker/monitor jobs and configuration enabled; processing on; admission, ingestion and legacy/weekly fixtures closed; Auth signup/providers/manual linking closed; backend empty; no community selected or published; snapshot disabled and never queued. Vault references unchanged. |

Acceptance ended after **110.833 seconds**, within five minutes. No further
hosted checks or acceptance runs followed; no rollback was needed. Prior
processing was false. Existing invocation, heartbeat and Cron receipts remain.

Only this receipt and a working-baseline pointer changed locally. No source,
schema, API, credential, deployment or source-policy change; no seeded actors,
challenges or Health data, local acceptance rerun, broad regression, load/soak/P12,
app connection, upload, community publication, external message, release, branch
switch, merge or push.

App identity/connectivity, external alerts, staffed participant operations,
retention/recovery policy, real challenge processing acceptance and release
qualification remain unresolved. D134–D139, Signal, historical Personal access
and exact recovery remain intact. Missing data cannot establish losses or
complete rankings. Nine available goals and four unavailable leaderboards still
do not satisfy the unchanged four-metric/all-13 release requirement.
