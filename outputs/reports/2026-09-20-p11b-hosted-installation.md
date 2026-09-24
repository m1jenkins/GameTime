# P11B bounded hosted installation receipt

Completed September 20, 2026 UTC after the owner's single exact-action approval.

- **Source:** `8e45132b35956a1ba74d7e059869ae46789d6181`.
- **Project:** `gametime-p11b`, reference `lyushhqoednheqwzsmxh`, Better Bet
  (`nfokjrpuwftlmvfrathp`), `us-west-1`. Free plan; Supabase quoted $0/month;
  owner ceiling $20. No paid upgrade. Owner remains commissioning owner and
  credential custodian.
- **Installed:** all 93 reviewed migrations and only `challenge-worker`,
  `challenge-snapshot`, and `challenge-monitor`, each deployed version 1.
  The temporary copy adds only the four named historical Cron deactivations
  immediately before their existing outer commits. Canonical migrations and
  function source are unchanged; no fixture or user-data import occurred.
- **Configuration:** distinct worker/monitor secrets in Edge secret storage and
  Vault; existing handler authentication with gateway `verify_jwt=false`.
  Private schemas remain unexposed; Data API exposes only `public`; Auth is closed.
- **Observed:** one combined readback passed exact migration-version identity,
  three active deployments, distinct secret configuration, all eight jobs
  inactive, all product/fixture gates closed, empty user/challenge state, and no
  selected community. One authenticated monitor request returned HTTP 200,
  sanitized `disabled` status, and an unconfigured snapshot. One unauthenticated
  request per endpoint returned HTTP 401 `unauthorized` (3/3).
- **Deployment correction:** the first worker bundle failed to discover the
  shared dependency map. Passing the unchanged reviewed `deno.json` explicitly
  resolved it; only that failed deployment was retried. No acceptance check
  required repetition.
- **Remaining blockers:** none for this bounded installation. Scheduled
  operation, broader hosted acceptance and release remain separately gated.

Temporary commands, migration manifest/diff, readback SQL and sanitized HTTP
results remain in `/private/tmp/gametime-p11b-ij8b5m3i`. No permanent installer,
new harness, local acceptance, regression/load/soak/P12 run, schedule activation,
app release, community publication, external message, merge or push occurred.

After installation, the owner separately directed completed work to be committed
and merged into `main`. Receipt commit `4c8183b` and the reviewed P11 branch were
merged locally as `9652bc9`; its tree exactly matched the completed branch. No
installation check was repeated and no hosted state changed. This merge was not
pushed. The [updated planning prompt](https://github.com/m1jenkins/GameTime/blob/98b511863275a2c478e2f1523569308116c9e0f9/docs/P11B_NEXT_PLANNING_PROMPT.md)
starts from `main` and preserves the owner's commit-and-merge workflow.
