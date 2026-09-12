# P5 local evidence

The [completion report](../2026-09-11-p5-completion.md) owns disposition and limits.
Source: `e0a94bd793e4720ae04795760d614b049005618b`; base:
`369e7b90dfeb74314244a923a87864e368348412`. Final migration hashes are included.

- `before-final` / `after-final`: seven query plans per query (first plus six warm
  measurements), summaries. `equivalence.json` binds exact equal work, history
  order and detail results; raw fictional result payloads remain at the task root.
- `deep-final`: exact inner generic keyset plans, live discovery plan, full dense
  pagination result and observed main-fork storage sizes.
- `candidate-no-index` / `candidate-index`: exploratory index comparison, before
  the final session/trigger corrections; not final-source acceptance evidence.
- `write-total-final`: final code, identical rollback-only writes with/without P5
  maintenance, execution plans plus total transaction WAL. No old guard disabled.
- `community-before-fix` / `community-after-fix`: the measured review finding and
  its correction for a 250-person membership exit statement.
- `sql-results.json`, suite log: final fresh 88-file/3,998-assertion pass, zero skips.
- `upgrade-*-final.log`: final forward upgrade, 194 assertions including 188 old
  table digests and a real pre-upgrade cursor. Historical data were not rewritten.
- Final race logs/command receipts, checker/blocked-CLI logs, review and shutdown
  identify actual final checks. Early failed logs are retained as separate attempts.

Scripts here are the small task-specific adapters actually used, with explicit
owned `/private/tmp/gametime-p5-20260911` paths and loopback port 59622. They reuse
P2 fixture construction without relaxing its original fixed-parent guard. Do not
point them at a hosted or existing user-data database. A new reproduction needs
its own project/ports/root and equivalent ownership checks, then migration inputs
at the named commits. No credential/startup logs are published.

Main commands, from the dedicated checkout (loopback credentials are disposable):

```sh
python3 /private/tmp/gametime-p5-20260911/seed.py
python3 /private/tmp/gametime-p5-20260911/measure.py before-final
psql postgresql://postgres:postgres@127.0.0.1:59622/postgres -XqAt -v ON_ERROR_STOP=1 -f /private/tmp/gametime-p5-20260911/upgrade-before.sql
psql postgresql://postgres:postgres@127.0.0.1:59622/postgres -XqAt -v ON_ERROR_STOP=1 -1 -f supabase/migrations/20260911235041_challenge_bounded_queries_v1.sql
psql postgresql://postgres:postgres@127.0.0.1:59622/postgres -XqAt -v ON_ERROR_STOP=1 -f /private/tmp/gametime-p5-20260911/upgrade-after.sql
python3 /private/tmp/gametime-p5-20260911/measure.py after-final
python3 /private/tmp/gametime-p5-20260911/write-total.py write-total-final
python3 /private/tmp/gametime-p5-20260911/compare-results.py
python3 /private/tmp/gametime-p5-20260911/deep-plans.py deep-final
supabase db reset --local --workdir /private/tmp/gametime-p5-20260911/stack --network-id gametime-p5-20260911 --no-seed
python3 /private/tmp/gametime-p5-20260911/run-sql.py
python3 /private/tmp/gametime-p5-20260911/final-runs.py
```

Only the owned disposable stack was reset to separate clean SQL tests from
committed fictional measurement/upgrade fixtures. The first final fresh reset
applied all 75 migrations; the subsequent P4-only reset supplied the old-data
upgrade. Final SQL again used all 75. Scripts/phase logs preserve that order.
