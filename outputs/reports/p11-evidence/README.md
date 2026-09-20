# P11 portable local evidence

These files contain synthetic local aggregate results. The
[completion report](../2026-09-20-p11-local-scheduling.md) identifies exact source,
commands, failures and limits. Private manifests, credentials, staged source,
Docker resources and the temporary runtime image were removed after acceptance.

| Record | Contents |
| --- | --- |
| [SQL and preservation](sql-and-preservation.json) | 325 assertions by suite, final migration and fixture hashes, unchanged populated-run agreement digest. |
| [Actual scheduling](bounded-acceptance.json) | Three Cron HTTP responses, 27 denials, operating/privacy assertions, paused/unavailable checks, restart replay and staged production-source hashes. |
| [Local monitor sink](monitor-local-sink.json) | Two allowlisted read-only operational responses after jobs were disabled. No identifiers, people counts or Health facts. |
| [Concurrent sessions](concurrency.json) | Six locking/replay checks and measured PostgREST lock timeout. |
| [Source checks](source-checks.json) | Exact Deno commands/results, including corrected CLI flag; existing worker-unit and syntax outcomes. |
| [Security advisors](security-advisors.json) | Final owned-loopback security result. |
| [Cleanup](cleanup.json) | Closed settings and zero remaining resources under the task owner label. |

SQL TAP and command diagnostics remain in mode-0700/0600 local temporary receipt
directories, including earlier failed runs. They are not portable evidence and
contain no retained usable credentials after resource removal. These records do
not establish hosted, physical source, human or release acceptance.
