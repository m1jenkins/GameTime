# D9 remediation — Phase A

Implementation commit: `d8f49c3e7e9b2cf01528d700672ec1232b8ec311`, a descendant
of frozen candidate `9ce9ea6cd6527fd5a4bec09e640f8777f1df42b8` on
`fm/gametime-beta-real-validation-c8`. The following documentation commit changes
no product or test inputs. This is focused local software evidence, not independent
review, canonical acceptance, a complete corrected-candidate gate or beta completion.

The owner authorized only D9-1/D9-2 remediation and its validation. Firstmate must
return the existing independent review before the fresh complete gate starts.
Prompt 0A belongs to its separate task after those dependencies pass; this task
does not implement it. Acceptance and landing still require owner review.

## Corrections and fresh evidence

- **D9-1:** the new `20260909123228_challenge_session_lock_expiry_v1.sql`
  rechecks the locked session's expiry against the wall clock after `FOR SHARE`
  returns, and checks the active actor again. The shared lock, runtime mutex,
  invoker mode, empty search path and existing restricted grants remain.
  No applied migration or historical agreement changed.
- **D9-2:** accepted page, later-page and detail projections reconcile every
  cached copy of the same challenge, including equal-revision restrictions.
  Section and existing detail timestamps retain their original lifetimes.
  Account/refresh fencing and request storage remain unchanged.

| Fresh check | Before correction | After correction |
| --- | --- | --- |
| Actual concurrent SQL session/RPC checks | 10 controls pass; detail and exact committed recovery incorrectly succeed after unchanged-row expiry; command exits 1 | All 12 cases pass, exit 0: finite live, already expired, unchanged-row expiry during wait, valid wait, deletion wins and missing session, each for detail and exact recovery |
| New native restriction suite | 2 controls pass, 7 tests fail, 0 skips; command exits 65 | All 9 pass, including four mounted Home/detail tests at equal/higher revision |
| Focused native suite with existing policy/cache/recovery checks | Not rerun as a baseline group | 27 pass, 0 failures, 0 skips; exit 0 |
| Challenge SQL 490–502 | Historical results remain historical | 319 assertions / 13 files pass; exit 0 |
| New SQL 502 alone | Initial fixture setup failure retained | 13 assertions pass; exit 0; included in 319 above |
| Local security advisor | Unperformed before this migration | No issues; exit 0 |

The mounted tests use production `ChallengeV1Shell` and `ChallengeV1Detail`, a
fictional controllable client and the real observable store. Native rendering
and OCR establish the visible before/after state on the same mounted controllers.
Home performs zero detail fetches; detail performs only its initial fetch. At
the restriction refresh, Active fails, History returns own-only data and access
status returns nonsuspended. Counterpart identity/activity disappears from the
open detail; both same-ID Home cards show the exit. The unrelated card remains.
These are 430×3000 rendered test canvases, not human navigation or accessibility
acceptance and not authenticated HTTP evidence.

`ChallengeRestrictionTests` also covers all four section caches, detail-cache
fallback, duplicate later-page IDs, original expiry times, account replacement,
exact pending-file bytes through reconciliation and canonical request bytes on
an interrupted retry. Storage JSON key order after an explicit retry is not a
protocol guarantee; no request-store behavior was changed.

## Reproduction and retained artifacts

The complete private command/exit ledger, initial fixture/build failures, before
and after result bundles, OCR text and fictional screenshots are retained in:

`/Users/user/firstmate-workspace/data/gametime-beta-real-validation-c8/remediation-20260909-1235`

The phase report at the same task's `remediation-report.md` records the exact
clean review commit and final preservation checks. Previous `gate-20260909`
evidence and its candidate report are unchanged, not relabeled as this run.

Focused runtime session runner (substitute only a newly owned disposable lab):

```sh
python3 scripts/beta-session-expiry.py \
  --owned-project gametime-d9-<unique-run> --stack <new-stack-directory> \
  --port <checked-free-new-db-port> --report <new-private-report-path>
```

The runner checks project/port ownership, refuses the known retained database
ports and refuses to overwrite results. It uses fictional SQL-role actors and
actual concurrent PostgreSQL transactions. It revokes only its freshly minted
sessions and leaves fictional history and volumes intact. No real Health input
or HTTP credential is required. SQL 502 supplies the accompanying privilege,
expiry-boundary, actor-binding and unbounded-session controls.

Native command: `xcodebuild test`, scheme `GameTimeBetaLocal`, Debug, explicit new
Simulator, unique DerivedData/result path, `CODE_SIGNING_ALLOWED=NO`, parallel
testing disabled, selecting `ChallengeRestrictionTests`, `ChallengeSectionTests`,
`ChallengeV1NativeTests` and `ChallengePolicyTests`. Exact executed arguments are
in `native-after.command.json`.

New resources: project `gametime-d9-remediation-20260909-1235`, API 63321 / DB
63322; Simulator `GameTimeD9Remediation1235`,
`2F5DE602-52A6-4985-818B-96505A9FF128`; source/build root
`/tmp/gametime-d9-remediation-20260909-1235`. These resources remain retained.
The corrected Debug app is
`after-derived/Build/Products/Debug-iphonesimulator/GameTime.app` under that root.
The prior c8 preview, its controller and its installed build remain untouched;
they do not silently become this corrected build.

## Remaining gates

Next: Firstmate routes the exact clean descendant to the existing independent
d9 reviewer. After its disposition, run the already authorized fresh complete
gate on that exact corrected commit with another set of unique resources.
Capture standalone concurrency's own exit; do not reuse historical passes.

All 18 external readiness gates remain false. Physical device opt-in, all four
source policies, real ingestion, timed-distance tolerance, human checks and
release decisions remain unperformed/unaccepted. Existing source/release tasks
remain authoritative. No merge, push, deployment, distribution, external contact,
retained-data cleanup or downstream implementation was performed.
