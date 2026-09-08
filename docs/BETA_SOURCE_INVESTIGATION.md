# Private source investigation — physical execution pending

Build `GameTime` / Debug from the b7 worktree. In the Xcode Run scheme add
`--health-source-investigation`. This mode returns before constructing product
services and skips auth, upload, product background reads and Watch connectivity.
It is absent from Staging and Release. Nothing is installed on a physical device
by this task without an explicitly opted-in device session.

1. On the opted-in iPhone, launch that scheme. Choose a narrow fixed From/Until
   window, then Begin private session → Connect Apple Health. A permission sheet
   may clear the session when the app becomes inactive; begin again afterward.
2. Tap Read this window. Inspect details only on the device. Do not screenshot,
   screen-record, export, log, upload or paste records, source identifiers or
   activity values. Clear session or leave/lock the app to discard memory.
3. While remaining foreground, repeat the same window after a separate Watch
   sync or Health edit to compare visibility. When permission changes, locking,
   offline or background testing clears the session, compare qualitatively with
   a new opt-in read; absence does not prove deletion or completeness.
4. For each row below record only the performed action, device/OS family,
   qualitative finding, limitation, and pass/fail/unperformed. No raw Health
   values, record IDs, usernames, timestamps, routes or source metadata leave
   the phone. Never call Simulator data a physical observation.

| Case | Required action / question | Actual observation |
| --- | --- | --- |
| Phone steps | Walk with phone, then read | Unperformed |
| Watch steps | Walk with Watch alone, then sync | Unperformed |
| Device overlap | Carry both; inspect overlaps and reconciliation uncertainty | Unperformed |
| Manual/import | Add a manual record; examine whether it can be distinguished from imported/device activity | Unperformed |
| Downward edit/deletion | Edit/delete activity, repeat fixed-window read; distinguish lost visibility from confirmed deletion | Unperformed |
| Late sync | Keep Watch offline then reconnect; compare fixed-window reads | Unperformed |
| Lock/offline | Lock/unlock and airplane mode; new opt-in; assess read availability without completeness claims | Unperformed |
| Permission/source loss | Revoke selected-source permission; investigate empty vs unavailable response | Unperformed |
| Account/session isolation | Clear/start new session; no earlier records may reappear | Simulator store race test passed; physical unperformed |
| Timezone/DST | Change timezone and confirm selected absolute instants; compare boundary-crossing records | Unperformed |
| Exercise lineage | Record Watch exercise; inspect manual/import lineage and overlaps without treating minutes as workout duration | Unperformed |
| Cumulative run | Record whole running workout; inspect distance origin, overlap and edits | Unperformed |
| Timed run | Known distance, pauses, start/end versus reported duration; test whole workouts crossing the window | Unperformed |
| Timed tolerance | Owner chooses distance tolerance from measured whole-workout accuracy | Unapproved; source disabled |
| Trustworthy misses | Can any accepted policy distinguish complete admissible activity from invisible/missing activity? | Unresolved; every real source disabled |

The existing [source matrix](WEEKLY_SOURCE_METRICS_ACCEPTANCE.md) remains useful
history. Its Exercise fixture unit does not change D134's integer-second unit.
This UI intentionally supplies no scoring total, completion assertion, export,
source approval switch or upload. Suggestions and adapters remain dependent work.

## New readiness presentation mapping still needs reconciliation

The governing Beta plan asks to preserve seven visible readiness states. The
retained `PersonalHealthReadiness` implementation in
`ios/GameTime/GameTime/PersonalAccountabilityClient.swift` has five historical
cases and a different authorization contract. It is not widened or reused for
new Beta consent. As the four physical policies are accepted, record the exact
seven-state mapping and copy for the new source adapter, including unsupported,
empty successful reads and interrupted/revoked access. A completed permission
prompt never means Ready. The new local shell currently states that every real
source is unavailable for scoring; fictional readiness is explicitly separate.
No extra physical readiness state is inferred from these Simulator tests.
