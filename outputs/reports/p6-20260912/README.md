# P6 verification artifacts

The [completion report](../2026-09-12-p6-completion.md) owns the result and limits.
Implementation: `05f405c24453fe6743ece994d646058958bfdbb2`.
P5 input: `e16cff4b3beaa7bcce95db6b0e82eedaa94865fa`.

- `sql-final-91.log`, `sql/`, `sql-results.json`: clean 91-file, 4,073-assertion
  portable pass. `p6-complete.log` is the final 49-assertion affected-file rerun
  after adding the actor-only appeal filing state (4,074 distinct final assertions).
- `upgrade-complete-*`: final whole-migration P5-data upgrade, 197 assertions.
- `concurrency-*`, `p5-concurrency`, `checks.json`: two 50-check runs and five
  P5 checks. The small `p4-p6-concurrency.py` adapter preserves the original runner
  and changes only the documented P6 contracts, plus a grant-revocation race.
- `load-summary.json`, `load-accepted-source.log`, `load-arrivals.json`: final
  short 250-arrival run from `scripts/beta-p6-community-load.py`.
- `native-final.log`: 21 passing tests; `native-complete.log`: eight affected
  tests after final UI additions. Full xcresults are retained at the owned root.
- `checker-complete.log`, `advisors.log`: direct checker results and blocked CLI.
- Earlier failure logs and result JSONs remain separately labeled. They are not
  substituted for final passes or represented as infrastructure-only failures.
- `migration-hashes.json`, `validation-summary.json`, `SHA256SUMS`: source and
  result inventory. `shutdown-db.log`, `stop.log`, `containers-after.log`: closure.

The scripts here have explicit owned local paths and loopback ports. They are
reproduction notes, not a new allocator/framework. A new run must use its own
project/resources and equivalent ownership checks. Never point them at hosted
state or another checkout's stack. Credential/status/startup output is excluded.
