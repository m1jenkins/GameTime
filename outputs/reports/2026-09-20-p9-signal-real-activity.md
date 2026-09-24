# P9 Signal real activity — local implementation report

Implemented on `codex/p9-signal-real-activity` from clean P8
`8a9d1f007ab235d580d83bae47077a26f13090a7`. Initial application/contract implementation:
`cbfaf255612bf55e87fde7c4262902825f271d6d`. Acceptance follow-ups:
`c19bb28` (actor-scoped synthetic pacing) and
`b336f4c3c1cbc8e09f895018f50fba6cb0bcac21` (ordinary deleted/unresolved replacements).
Final application follow-up `b0ce67e64ae1a47dd222d5e56e8ea0ef4c63dfae` enables unlock/network opportunities before
protected connection state is available, with a native notification regression.
The subsequent report commit changes documentation and review artifacts only.
Main began at `848ef6ee02d95b57bdad4b36d3c7600a4ba3f192`. Final inspection
found it separately fast-forwarded to `cb3a0ec6a758683eb1bc026859833c5b96b4ccf6`
(the P8 merge), containing P8 but not P9. This task did not push, merge or move main.

The [P9 contract](../../docs/P9_SIGNAL_REAL_ACTIVITY.md) records implemented rules;
D139 records the owner’s separate Exercise credit decision. The
[interactive report](../../.lavish/p9-signal-real-activity.html) uses Signal’s own
colors, typography and spacing and includes actual native captures. The
[next-chat prompt](https://github.com/m1jenkins/GameTime/blob/98b511863275a2c478e2f1523569308116c9e0f9/docs/P9_NEXT_PLANNING_PROMPT.md) asks another chat to plan
one next task, answer repository-backed questions and isolate necessary owner decisions.

## What changed

One app-lifetime transport coordinator now orders exact saved requests across
readiness, challenge activity, retained metrics, Personal coverage and diagnostic
writers sharing the App Attest key. All journals reload under the lease; recovery
uses ascending counters per key before new signatures. Malformed/conflicting
counters fail closed. The diagnostic writer gains its missing protected journal;
production uses the bounded decoder from GameTimeCore. Each endpoint keeps its
original wire format, receipt validation and terminal key handling.

AppModel’s separate Health flow connects ordinary Signal creation, readiness,
deliberate consent/community joining, scheduled/active progress, corrections,
review and history. Readers and protected local comparisons are isolated by
actor/session/binding/purpose. New facts require fresh server terms; local drafts
cannot upload activity. Seven readiness states, local suggestions, hourly background
opportunities, observer/foreground/unlock/connectivity recovery and manual Refresh
are wired. Sign-out preserves exact work; accepted deletion clears only the owner’s
new caches, journals and signer state. Suspension/cancellation fence async work.

New agreements use `apple_watch_exercise_credit_v2` for Activity minutes. It
accepts disclosed unknown causal origin, excludes identifiable manual/unsupported
records, reconciles before flooring total minutes × 60 once, and keeps every
other uncertainty unresolved. Strict v1, old agreement digests, consent and pending
bytes remain intact. Exercise native reads now use bounded plus anchored queries,
explicit deletions, active bounds and cancellation. Existing running readers keep
D138 boundaries, Watch reconciliation, inclusive 100–102%, pauses and strict time.

Nine goal policies are integrated; four real leaderboard modes explicitly remain
unavailable without creation, suggestions or invented ranks. Positive observations
can prove success; incomplete history cannot prove a miss. Community keeps server
counts delayed 15 minutes and hidden below five active nonremoved members; the
outcome minimum is separate. Invitations, reconsent, safe exits, restricted
projections and Existing challenges/retained Personal remain usable.

## Performed verification

These are focused local checks, not P12/P13 or release qualification. All Health
input and app signatures in the ordinary-app harness are synthetic; Auth, Edge
handlers, PostgREST, SQL and product composition are real local implementations.
Full consent/correction/review periods were advanced through the source clock.

| Check | Result |
| --- | --- |
| Complete GameTimeCore | 182 tests / 20 suites passed |
| Affected native suites | 246 unique checks ultimately passed across the aggregate run and targeted reruns. Aggregate: 244 passed, one community fixture failure; the final fresh-stack community rerun passed. An additional unlock lifecycle regression passed. Counts are not additive. |
| Ordinary app steps | Matching readiness/consent, 10,001, explicit deletion, unreadable replacement, 9,999 at inclusive end +48h, late actual notice, 48h review / 72h resolution, void and own entry returned. Separate correction 11,000 → 10,001 finishes met. |
| Four-metric native policy matrix | 12 ordinary AppModel journeys passed: each metric through Personal, two-person and six-person friend goals, invitations/own targets/roster/consent. Two with one unresolved void; six with four successes/two unresolved yield four met/two excluded, everyone’s own entry returned. |
| Community ordinary app | Readiness/join/own-only progress/leave passed. Four/five/six-member disclosure and exact 15-minute boundary passed; five remaining with four successes below outcome minimum five void and return entries. |
| Recovery | Shuffled five-writer counters; malformed/conflicting counters; held signing; all endpoint response-loss/relaunch paths; actual diagnostic HTTP replay; actor/session switches/expiry; key rejection; gate-off exact replay; no-active-list recovery passed. |
| Local state / safety | All seven states, simultaneous contexts, readiness versus suggestion/activity, distance invalidation, relaunch comparison continuity, corrupt/unavailable cache, suspension, deletion owner isolation, restricted projections, invitation/reconsent/offline-exit and retained Personal checks passed. |
| Touch-driven UI | 5 tests passed: ordinary Signal steps through returned-entry history, plus retained shell/access, Personal start-now/Sync Now, private historical detail and automatic progress. |
| Large text / appearance | New unavailable creation screens for all four metrics and Exercise disclosure/readiness captured and OCR-checked at Accessibility 3 in light/dark. Representative actual captures visually inspected. |
| Affected Edge endpoints | 96 tests passed: challenge Health, retained metrics, Personal coverage and diagnostic |
| Signed HTTP journeys | Steps 14, Exercise v2 14, distance 14, timed 15 passed; separate steps race seed 9 passed |
| Actual SQL connection races | One same-parent correction commits, one new fact, exact concurrent replay agrees, expiry and revocation after session-row lock waits both rejected |
| SQL | 1,245 assertions / 33 affected challenge suites (490–523, selected existing files) passed. New 523 suite has 93 assertions. |
| Populated/fresh upgrade | Five P8 and two P9 migrations applied in order on an 848ef6e baseline with retained agreement/consent digests unchanged. Final fresh-stack rerun again applied all seven and passed 523’s 93 assertions. |
| Product/static guards | `check-iphone-product.py` passed for source and built app: 187 active sources, no Watch target/payload. Changed Deno files type-check/lint/format; Python compilation and `git diff --check` passed. |
| Preservation | Existing migrations, dated P7/P8 reports, checked-in transport configuration and all 18 false external readiness entries unchanged. P8 ancestry verified. |

The [evidence index](p9-evidence/README.md) contains exact commands, source mapping,
suite selections, credential-free receipts and local xcresult/log locations.

## Failures and their disposition

- Final lifecycle review found that a locked connection cache could suppress
  unlock/network opportunities. Those recovery observers now register for the
  authenticated actor independently of Health sources and stop on sign-out or
  suspension. The affected flow and retained observer suites were rerun.
- Early owned Auth startup lacked the required port/audience/issuer/email settings.
  The P8 local runner now supplies explicit loopback Auth settings. No hosted
  credentials or development project were used.
- Intermediate native fixtures used an invalid short App Attest key; the fixture
  was corrected to a 32-byte key. An earlier community fixture attempted activity
  after a safety exit had already made the result void; the fixture now exercises
  valid active progress and separate suspension tests preserve that behavior.
- UI test initially selected a TextField for a multiline timezone control. The
  unnecessary edit was removed; assertions use the actual frozen configuration.
  A final-return assertion also used wording not present in the app. Actual
  screenshots showed the correct return; the assertion now matches the recorded
  amount. The subsequent five-test UI run passed.
- Two Simulator attempts failed before app/test-runner launch with “Busy / failed
  preflight checks.” Booting the owned Simulator before the next run resolved the
  environment failure; later native/UI runs passed. Failed result bundles remain.
- Aggregate community discovery hit the existing actor-wide quota. The synthetic
  controller had paced by JWT, allowing fresh sign-ins to reset its budget. Pacing
  is now per actor across sessions; server quotas were not weakened. The paced
  12-journey matrix passed in 365 seconds, beyond MCP’s 300-second reply limit;
  the completed xcresult, not that tool timeout, records its result.
- The failed discovery run had left one synthetic community published. A later
  publication correctly failed the one-community guard. After preserving receipts,
  rebuilding only the manifest-owned disposable stack provided a fresh fixture.
  The final extended steps and community tests both passed.
- One Edge command omitted `--config`, causing unresolved import aliases before
  tests ran; the configured 96-test run passed. Python’s default cache location
  was sandbox-blocked; compilation passed with a task-local cache prefix.
- Lavish’s protected artifact URL could not be inspected as a standalone page
  without its load token. The portable local HTML was checked directly instead:
  all images loaded, screenshot controls worked and no horizontal overflow occurred
  at desktop or an exact 390-point mobile viewport, in light/dark appearances.

Intermediate failures came from uncommitted development states or the explicitly
listed committed harness runs; they are not presented as passing acceptance.
No known application failure remains from the performed focused checks.

## Resource cleanup and unperformed work

The controller restored its prior clock, disabled local real admission/ingestion/
processing and revoked its fictional sessions. Owner-label-checked cleanup removed
only this task’s disposable containers/network and private manifests. The owned
Simulator was shut down and removed. Source, native build/xcresult artifacts,
private failure receipts and credential-free report evidence were retained.
The review page is local only; it was not published or shared externally.

Not performed: physical Health reads/uploads or new measured P7 sessions; physical
App Attest/Apple sign-in/OS invitation association; hosted deployment/scheduler/
alert/retention operation; distribution, recruitment or money; full P12/P13 matrix,
long soak, human comprehension or physical accessibility acceptance; replacement
retirement or historical-data cleanup. Simulator locked-state behavior is injected,
not a claim about physical data-protection timing. The conformance device app was
not separately rebuilt; the extracted production decoder is covered in Core and
native builds.

Nine goals plus four unavailable leaderboard states do **not** satisfy the unchanged
four-metric/all-13-policy release requirement. Hosting identities, community launch
settings, operating approval and later acceptance remain separate. Local community
values are fixtures. All external readiness entries and checked-in gates stay closed.
