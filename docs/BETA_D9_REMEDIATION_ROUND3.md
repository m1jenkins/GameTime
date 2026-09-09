# D9 remediation — round 3

Implementation: `d18deb3b85270cc23301a945c95464fa5593e205`, directly after
`f4aeafeea51d338a071ef58513b5e87f3a29c2a1` on
`fm/gametime-beta-real-validation-c8`. The following documentation commit changes
no tested input. This is focused local software evidence with fictional activity;
independent re-review and the complete corrected-candidate gate remain pending.

The independent round-2 reviewer closed D9-1 and the original own-only D9-2/D9-3
schedules. It identified D9-4 as a related preexisting omission for partial
departure redactions, not a regression introduced by round 2. Firstmate 029/030
authorized this bounded correction within the existing task. [Round 2](BETA_D9_REMEDIATION_ROUND2.md)
and [Phase A](BETA_D9_REMEDIATION.md) remain unchanged historical records.

## Contract and correction

In a three-person friend challenge, the remaining two participants can continue
after one leaves. Their projection keeps `socialHidden=false` and preserves
sharing with the continuing counterpart. R5 independently marks the departed
counterpart `exited=true`, blanks their username and removes current target/fact.
Their pseudonymous membership and permitted historical agreement/result remain.
The existing SQL contract and SQL 501 already define this behavior correctly.

Previously, that partial redaction established no native restriction marker. A
held initial Active page, More page or detail response could arrive afterward
and restore the departed person's `exited=false`, identity, goal and activity.
Account, refresh generation and response age could all remain valid.

The existing common fence now recognizes an exited counterpart as a restricted
response, as well as an own-only challenge. It uses the contract's explicit exit
signal, excludes the current actor from the counterpart predicate, and does not
infer privacy from a numeric revision increase. It neither edits member/history
fields nor turns off remaining authorized sharing. The epoch/cursor acceptance,
atomic-page rejection, marker/content expiry, account/refresh checks and exact
request behavior from round 2 remain unchanged.

## Fresh runtime evidence

| Check | Actual outcome |
| --- | --- |
| Baseline f4aeafe with identical new departure tests | 9 failed methods, 0 passed/skipped, 94 assertion failures, 0 unexpected; exit 65; `native-before` |
| Corrected focused native group | 46 passed, 0 failed/skipped/expected failures; 88.935 seconds of method execution; exit 0; `native-after` |
| New departure methods within the 46 | 9 pass: initial Active-page/detail lower/equal/higher old revisions; More/detail, detail/More and detail/detail reversals; cache/marker expiry; unrelated and fresh authorized reads; agreement/final-history preservation; mounted Home/detail |
| Prior focused methods within the 46 | 10 overlap, 9 restriction, 9 section, 5 native request/recovery, 4 policy; all pass |
| Debug Simulator build | Compiled by `native-after`; no separate build counted |
| Result summaries and attachments | Four serialized exports, all exit 0 |

Both tests compiled and finalized normally on their first round-3 attempt, with
unique result bundles and `-collect-test-diagnostics never`. No infrastructure
interruption or fixture repair occurred this round. Earlier failed/interrupted
attempts remain in their original evidence directories, not relabeled here.

Mounted production Home and detail remain on the same controllers through shared
→ partially redacted → late unredacted completion. The held refresh waits on the
initial **Active** page so the three-person active challenge retains its real
section/status shape. A detail response carries the intervening redaction. No
remount, second refresh or extra detail read conceals the late completion.

Each phase retains 18 new departure PNGs and 18 OCR texts, covering both screens,
three old revisions and three checkpoints. In baseline detail, `Departedfriend`,
`2,000 steps` goal and fictional `321 steps` return after the late page. Corrected
detail retains `Former participant` without those fields, while
`Continuingfriend`, their `3,000 steps` goal and `654 steps` remain visible.

Home itself does not display counterpart fields. Its test checks the same cached
projection and uses own fictional activity changing from 100 to 109 to make
rollback visible: baseline returns to 100, corrected stays 109. Both retain the
unrelated 507 card. Store assertions check the redacted member fields and exact
agreement object too; expiry exposes the independent detail-cache fallback.
The separate terminal-history fixture preserves its received final object.
These are native object/rendering checks, not newly executed backend settlement
or historical-database checks.

The screenshots are real production views on 430×3000 test canvases using a
controllable fictional client. They do not prove authenticated HTTP, physical
Health accuracy, human comprehension or accessibility acceptance. No SQL,
portable gate, full native/HTTP/historical UI suite or release matrix ran here.

## Retained resources, build and handoff

Private evidence:
`/Users/user/firstmate-workspace/data/gametime-beta-real-validation-c8/remediation-round3-20260909-1832`.
Command JSON files record exact argv, working directory, start/end and exit;
`mounted-observations.json` maps image/OCR names, paths, hashes and observations.
The separate parent `remediation-round3-report.md` records the final clean review
SHA and preservation inventory. Prior reports and resources remain retained.

New native-only root: `/tmp/gametime-d9-round3-20260909-1832`, with independent
before/after source archives and DerivedData. New Simulator: `GameTimeD9Round3`,
iPhone 17 Pro / iOS 26.5, `84537120-77D4-45E5-88D7-043F37265CFE`.
No database/port was created or reused; executors and result exports were
serialized. No shared Xcode service or retained Simulator was reset or stopped.

Corrected build:
`/tmp/gametime-d9-round3-20260909-1832/after-derived/Build/Products/Debug-iphonesimulator/GameTime.app`.
The new Simulator last ran this corrected test app. That is not a newly seeded
interactive preview. After confirming exclusive native ownership, a foreground
launch can use the verified bundle ID:

```sh
xcrun simctl install 84537120-77D4-45E5-88D7-043F37265CFE \
  /tmp/gametime-d9-round3-20260909-1832/after-derived/Build/Products/Debug-iphonesimulator/GameTime.app
xcrun simctl launch 84537120-77D4-45E5-88D7-043F37265CFE com.mjenkins.gametime.staging
```

Those standalone launch commands were not run in this round. The retained c8
interactive preview and its [launch instructions](BETA_REAL_VALIDATION_HANDOFF.md)
remain unchanged.

**Next:** route the exact clean descendant to the same D9 reviewer for D9-4
disposition. D9-1 and original own-only closure remain credited; no blanket clean
verdict is inferred here. Phase B and separate Prompt 0A remain paused. All 18
external readiness gates stay false; physical opt-in/all four policies, real
ingestion/timed tolerance, human checks and owner acceptance remain pending under
the existing source/release tasks. No landing is authorized. Beta is not finished.
