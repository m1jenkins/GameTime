# D9 remediation — round 2

Implementation: `0a2fd0c5a750c8fed784a846537351bc6392c67d`, directly after
`75064ba552ec0e3071c697a1bfbed32e350aa048` on
`fm/gametime-beta-real-validation-c8`. The following documentation commit changes
no tested inputs. This is focused local software validation with fictional data.
Independent re-review and the complete corrected-candidate gate remain pending.

The existing independent review closed D9-1 at 75064ba and left D9-2 open solely
for the residual D9-3 overlap race. D9-3 is the same remaining closure obligation,
not another task. [Phase A](BETA_D9_REMEDIATION.md) remains a historical record.
Its results are not fresh round-2 executions; its SQL correction is unchanged.

## Trigger and correction

Two More requests start from the same live cursor and snapshot. The second
returns own-only challenge C first. The older shared response then arrives within
60 seconds, without any actor or refresh change. Previously its duplicate row
was skipped during append but still reconciled into all cached copies of C,
restoring counterpart identity/activity. Numeric challenge revisions do not order
privacy changes; lower, equal and higher old revisions reproduce the rollback.

The store now records an in-memory restriction epoch for each accepted own-only
challenge. Every initial-page, More and detail request captures the current epoch
before awaiting its response. A response crossing a newer restriction for one of
its challenge IDs is rejected before cache mutation. More additionally checks
that its captured cursor is still current, preventing consumed-cursor rewind.

A stale page is rejected as a whole: existing unrelated rows, cursor and read
times stay intact. New rows in that obsolete page wait for a fresh request; no
mixed page is installed or cursor advanced. Unrelated requests remain usable,
and both detail and page requests started after restriction can accept newly
authorized shared projections. Those later reads do not unblock older requests.

Restriction markers contain only ID, epoch and monotonic receipt time. They
outlive expired content when necessary, and expire after 60 seconds: a request
started before such a marker can no longer pass the existing response-age guard.
Account replacement and hide clear markers with the caches. Existing generation,
refresh, visibility, exact-request and reconciliation lifetime rules remain.
No source policy, agreement, SQL, configuration or product copy changes here.

## Checks actually run

| Check | Observed result |
| --- | --- |
| Final baseline at 75064ba with identical new regression source | 10 methods failed, 0 passed/skipped, 89 assertion failures, 0 unexpected; exit 65; `native-before-final` |
| Corrected focused native group | 37 passed, 0 failed/skipped/expected failures; exit 0; `native-after` |
| New overlap methods within the 37 | 10 passed, including same-cursor lower/equal/higher revisions; page/detail permutations; held refresh page; consumed cursor; future authorized page/detail; unrelated read; original expiry and saved-request bytes |
| Existing methods within the 37 | 9 restriction, 9 section, 5 native request/recovery, 4 policy; all passed |
| Debug Simulator build | Compiled by `native-after`, exit 0; no separate build counted |

Mounted production Home and detail each run lower/equal/higher old revisions on
the same controller through shared → own-only → late shared completion. No
refresh, remount or additional detail read masks the late completion. Native
rendering/OCR and store assertions establish the result. Before and after each
retain 18 overlap PNGs and 18 OCR attachments, with exact paths/hashes in
`mounted-observations.json`. Inspected equal-revision images show counterpart
`Sharedfriend` and fictional `321 steps` return only on the baseline; the corrected
detail retains own `100 steps`. Corrected Home keeps the exit state and unrelated
`507` card. Existing sequential mounted tests also pass.

These are actual production views rendered on 430×3000 test canvases with a
controllable fictional client. They are not physical Health observations, human
comprehension/accessibility acceptance or authenticated HTTP evidence. No SQL,
portable gate, broad native gate or release build matrix was rerun this round.

## Retained attempts and infrastructure limits

All attempts remain distinct; none was overwritten or counted as a later pass.

1. `native-before`: compiled, then runner/IDE connection failed before any method
   ran; exit 65. Xcode reports one synthetic infrastructure failure, not one
   executed regression method.
2. `native-before-retry`: all ten methods ran and failed with the same 89 expected
   assertions. Xcode then hung in Simulator diagnostic collection for over
   40 minutes. A process sample and exact process identities were retained.
   Under Firstmate 025/026, SIGINT then SIGTERM targeted only owned xcodebuild
   71700; child exit was -15 (wrapper shell exit 241). Its proven diagnostic
   child 75792 was subsequently terminated. The incomplete bundle is retained.
3. Final baseline and corrected runs use Xcode's documented
   `-collect-test-diagnostics never`. This disables verbose failure diagnostics,
   not tests, assertions or retained attachments. Both finalized normally.
4. The first after-summary export returned 64 because simultaneous summary and
   attachment reads raced Xcode's SQLite materialization. Attachment export
   succeeded; serialized summary retry succeeded. Subsequent exports were
   serialized. The failed export log remains; it was not a test failure.

## Reproduction, resources and next action

Private round-2 evidence:
`/Users/user/firstmate-workspace/data/gametime-beta-real-validation-c8/remediation-round2-20260909-1300`.
Each command JSON records exact arguments, working directory, start/end and exit.
The separate `remediation-round2-report.md` in the parent directory records the
clean final review commit and final preservation checks. Prior reports, stacks,
volumes, builds, result bundles and previews remain retained.

New native-only root: `/tmp/gametime-d9-round2-20260909-1300`, with separate
`before` / `after` source archives and `before-derived` / `after-derived`.
New Simulator: `GameTimeD9Round2`, iPhone 17 Pro / iOS 26.5,
`AC74B752-7A3D-4C0F-943E-A562461BEE1C`. No database or port was created/reused.
Native executors were serialized. No shared Xcode/CoreSimulator service changed.

Corrected local build:
`/tmp/gametime-d9-round2-20260909-1300/after-derived/Build/Products/Debug-iphonesimulator/GameTime.app`.
The prior interactive preview is unchanged. The new Simulator's last test run
was the baseline; do not mistake its installed test app for this corrected build.
For a future foreground launch, first confirm exclusive ownership, then:

```sh
xcrun simctl install AC74B752-7A3D-4C0F-943E-A562461BEE1C \
  /tmp/gametime-d9-round2-20260909-1300/after-derived/Build/Products/Debug-iphonesimulator/GameTime.app
xcrun simctl launch AC74B752-7A3D-4C0F-943E-A562461BEE1C com.mjenkins.gametime.staging
```

This launches the configured local app, not a newly seeded authenticated preview.
No such launch was performed in this round. Existing fictional preview launch
instructions remain in [the handoff](BETA_REAL_VALIDATION_HANDOFF.md).

**Next:** Firstmate routes the exact clean descendant and this evidence to the
existing D9 reviewer. D9-2 remains awaiting that disposition. Phase B's complete
gate and separate Prompt 0A stay paused; there is no merge or landing approval.
All 18 external readiness gates remain false. Physical opt-in, four source
policies, real ingestion, timed tolerance, human checks and owner acceptance
remain pending under the existing source/release tasks. Beta is not finished.
