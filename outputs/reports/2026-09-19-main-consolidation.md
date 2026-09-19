# September 19 main consolidation

## Published source

[PR 19](https://github.com/m1jenkins/GameTime/pull/19) merged into `main` as
`b687ce74a73c0afca649facf1143d86ffbc927e3`, with source head
`c39b6c87113a6a7f63c835f82e55738aa824d683`. This preserves the commits
from the HTTPS invitation, administrator recovery, suspended-account repair,
review/appeal monitoring, selected community snapshot status, iOS 18
compatibility and fictional Personal lifecycle branches. The prior main
profile-retry and actor-switch fixes remain in the merge ancestry. The
[integration record](2026-09-19-integrated-candidate.md) retains the original
input identities, conflict resolutions and focused test evidence.

## Verification and limit

The portable `scripts/weekly-local-verify.sh` gate passed on the PR source head:
99 pgTAP files with 4,465 assertions, 845 Deno tests, 141 Swift core tests and
the persisted weekly lifecycle smoke. The disposable database project and its
dedicated Docker network were removed after the run. Focused local iOS checks
passed for the Personal detail route and both cancellation flows; the Debug
product build and iPhone product guard also passed. The separate iOS 18.6
report records 159 focused native tests and unsigned Release builds.

At merge, [PR CI run 35456816723](https://github.com/m1jenkins/GameTime/actions/runs/35456816723)
had passed Database, Edge Functions and Client Core. The full iOS product and
conformance job was still running. The owner asked to skip waiting for that
check; this record does not claim it passed. The earlier failing CI runs and
their corrected SQL/UI fixtures remain visible in the PR history.

These are local implementation and CI checks, not P12 release acceptance.
All 18 readiness entries remain false. No source, hosted operation, physical,
human, payment, distribution or release gate was accepted by this merge.

## Branch and worktree disposition

The merged local branch refs for administrator recovery, selected snapshot
status, HTTPS invitations, integration, iOS 18 compatibility, review/appeal
monitoring, suspended-account access and the PR branch were deleted. Their five
linked worktrees were verified clean before removal. Earlier already-main
actor-switch, P7 device-session and profile-retry refs were also retired, as
was the stale remote profile-retry branch. The PR remote branch was deleted on
merge. The checkout now has one branch and one worktree, both on `main`.

The conflicting, unmerged community snapshot freshness experiment was saved as
remote annotated tag `archive/community-snapshot-freshness-20260919`, pointing
to `0442638`, before its clean worktree and local branch were removed. The
September 6 stash containing the older `DeleteAccountState` rename was left
intact under the repository's preservation rule. Neither was folded into the
selected implementation.
