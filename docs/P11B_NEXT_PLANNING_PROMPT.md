# Planning prompt after bounded P11B installation

Copy this into a new chat. It plans one next slice and collects owner answers;
it does not dispatch implementation. Completed authorized changes must be
committed and merged into `main`, as the owner directed after installation.

```text
Plan ONE bounded next GameTime implementation slice. This chat is for planning
and answering owner questions, not execution. Recommend the next slice, help me
resolve its necessary decisions, then produce a copy-ready implementation prompt.

Work in /Users/user/Documents/GitHub/GameTime from local main. Check status and
ancestry first: main must contain reviewed source
8e45132b35956a1ba74d7e059869ae46789d6181, the installation receipt committed at
4c8183b, and merge 9652bc9 or verified descendants. Preserve unrelated changes.
Commit completed authorized work and merge it into main; do not push without
separate authorization. Planning does not authorize implementation or hosting.

Read AGENTS.md and its current authorities, especially:
- outputs/reports/2026-09-20-p11b-hosted-installation.md
- outputs/reports/2026-09-20-p11-local-scheduling.md
- docs/WORKING_BASELINE.md
- docs/GAMETIME_REMAINING_IMPLEMENTATION_PLAN.md
- docs/BETA_HOSTED_PREPARATION.md
- docs/P9_SIGNAL_REAL_ACTIVITY.md
Consult existing support/retention, operations, invitation and release worksheets
only as needed. Older statements that no hosted project exists are superseded by
the installation receipt. Unfilled draft worksheets do not erase adopted choices.

Established state:
- Bounded P11B installation completed in gametime-p11b,
  project lyushhqoednheqwzsmxh, Better Bet organization nfokjrpuwftlmvfrathp,
  us-west-1, Free plan. Supabase quoted $0/month. Owner spending ceiling is $20;
  that ceiling is not permission to upgrade or purchase services.
- The owner is commissioning owner and credential custodian. Reuse existing
  secure custody, Supabase Vault and Edge secrets. Do not request secrets in
  chat or create duplicate credentials without a concrete need.
- All 93 reviewed migrations were applied. Only four temporary migration-copy
  additions deactivated historical Cron jobs before their outer COMMIT.
  Canonical migrations remain unchanged.
- Only challenge-worker, challenge-snapshot and challenge-monitor are deployed.
  Dedicated worker and monitor secrets are distinct. All eight GameTime jobs,
  product gates and fixtures are off. Auth is closed; only public is exposed
  through the Data API; no community is selected or user data imported.
- The single installation readback passed. One authenticated monitor request
  returned sanitized disabled status, HTTP 200. One unauthenticated request to
  each endpoint returned 401.
- Completed P11 local verification and installation checks are established
  evidence. Do not repeat them or reinstall merely to regain context. Active
  scheduling, app connectivity and broader operating acceptance remain separate.

Preserve D134-D140, Signal, historical Personal access, exact recovery, source
policies, Exercise credit v2 and inclusive 100-102% whole-run distance. Do not
restart P7. Missing data cannot establish a loss or complete ranking. Nine
available goals form the working Beta scope; the four friend leaderboards are
deferred under D140. Four goal-metric source acceptance and the other release
gates remain open. Keep those dependencies visible without automatically
expanding this next task into solving them.

First identify the smallest useful remaining slice in the existing dependency
order. Distinguish missing implementation from configuration, owner decisions
and unperformed acceptance. Explain the concrete capability it would deliver
and why it comes next. Reuse existing components and preparation; do not create
another installer, harness, framework or broad preparation pass.

Ask only owner decisions necessary for that slice, in batches of at most three
questions, with a recommendation and concise alternatives. Resolve factual
questions from the repository first. Do not reopen the selected project, region,
custody or budget. Defer Apple/domain identities, community settings, operators,
alerts and retention questions unless this slice depends on them. Wait for
necessary answers before finalizing scope.

After resolving those questions, provide one implementation prompt with exact
starting source/target, objective, included actions, reused components, selected
settings, minimal acceptance checks, exclusions, required action approval and
a clear stopping point. Require completed authorized changes to be committed
and merged into main. Mark unresolved dependencies explicitly rather than
inventing answers or calling a conditional prompt executable.

This planning chat authorizes no hosted mutations, schedule activation, gate
changes, deployments, physical Health uploads, publication, release or external
messages. No local acceptance reruns, broad regression suites, load tests, soaks
or P12 matrix without separate approval. The historical full P11B prompt does
not authorize its remaining work. No push is authorized.
```
