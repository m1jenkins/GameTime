# Private physical sessions — Session A in progress

[D135](BETA_REMAINING_WORK_CONTRACT.md) requires a paired physical Apple Watch
for launch, not for pre-hardware implementation. Beta has no GameTime Watch app
and no WatchConnectivity dependency: the Watch records into Apple Health and
the iPhone investigates eligible Watch-origin data. Do not build, install or
launch a GameTime watchOS app for these sessions.

Continuation from D134 and [source investigation](BETA_SOURCE_INVESTIGATION.md).
Owner task: **gametime-beta-source-acceptance-b7**; decision key
**physical-source-actions**. Do not create another source-acceptance task.
The owner opted in on September 18 and the Debug investigation is running on
the selected iPhone with a paired Watch. See the [current P7 session record](../outputs/reports/2026-09-18-p7-device-session.md)
for performed Session A observations and remaining checks. This guide retains
the full session procedure. All four real sources and real ingestion remain
disabled; timed-distance tolerance is unselected.

## First action, before installation

Firstmate collects: **“I opt in to a private on-device investigation on [exact
selected iPhone], paired with [selected Watch].”** This authorizes only the
investigation session, not uploading records, scoring, publishing or distribution.
Identify the exact device privately; retain only device/OS families in the ledger.
Use the owner's existing signing identity, or leave signing unresolved. Never
choose an identity or enable capabilities on their behalf by guesswork.

Build the continuation's `GameTime` scheme in **Debug**, add the Run argument
`--health-source-investigation`, and select only the opted-in physical iPhone in
Xcode. Do not use the fictional challenge preview or a Release/Staging build.
Run/install only after the explicit opt-in reaches the worker. The isolated
launch excludes product services, authentication, uploads and background observers.

The person controls every Health/Watch action. There is no physical UI automation,
screenshot, screen recording, remote mirroring, debugger/console capture, telemetry,
export or copy/paste of activity. Raw records, exact activity times, identifiers,
source/device metadata, routes and measured values stay on the device. Keep any
accuracy worksheet volatile or in strictly non-syncing on-device storage; never use
cloud-synced Notes/Files, a backup/export or copy it off-device. Send only the
categorical conclusions below.

## Session A — access and first steps, about 10 minutes

1. Open the investigation. Choose a narrow From/Until window. Begin private
   session → Connect Apple Health → Read this window. The permission sheet may
   clear the session; begin again afterward. A completed prompt or empty read
   proves neither access nor complete history.
2. Take a short comfortable walk carrying only the phone, then inspect a window
   covering it. Repeat with the paired Watch while the phone is set aside, then
   allow normal sync. Inspect on-device whether each source is distinguishable.
3. Walk carrying both, then inspect overlaps. Do not sum overlapping raw samples
   or label any aggregate authoritative. Record whether reconciliation remains
   unresolved.
4. Clear the session and begin another. Prior records must disappear; do not
   count the disappearance as a Health deletion.

Categorical reply to Firstmate (no values):

`A: phone=[visible/empty/unavailable/unperformed]; Watch=[visible/empty/unavailable/unperformed]; overlap=[observed/not observed/unclear/unperformed]; source distinction=[clear/unclear/unperformed]; session clear=[passed/failed/unperformed]. Device/OS families: [...]. Limitation: [no raw data].`

## Session B — early Exercise and running feasibility, about 15 minutes

Use only ordinary comfortable activity; no maximal effort is needed to assess
software behavior. In the investigation, **Apple Exercise Time** inspects Exercise
records; **Running distance and time** inspects whole running workouts and their
reported versus start-to-finish durations. These are different source concepts.

1. Record an ordinary Watch activity. Inspect Apple Exercise Time and its lineage.
   Do not equate Exercise Time with workout duration or the older fixture's unit;
   the future Beta canonical unit is integer seconds.
2. Record a whole running workout on a known, suitable distance. Inspect the
   distance origin and whether it is distinguishable from an import. Include a
   deliberate ordinary pause/resume. Compare reported duration with complete
   start-to-finish time, including the pause, privately on-device.
3. Inspect the same workout using a window containing it and then a window
   cutting across one boundary. Changing the window clears the private session;
   explicitly begin again. No partial-workout scoring policy is adopted here.
4. Repeat distance measurements as practical in a later session. Keep the
   comparison values and error measurements private on-device. One run is not a
   tolerance decision. Firstmate requests **timed-distance-tolerance** only after
   enough measurements support a policy-level conclusion; do not preselect a value.

Categorical reply:

`B: Exercise lineage=[distinguishable/unclear/unavailable/unperformed]; running origin=[distinguishable/unclear/unavailable/unperformed]; pauses=[included in start-to-finish/unclear/unperformed]; whole-workout boundary=[inspectable/unclear/unperformed]; distance accuracy evidence=[insufficient/policy review ready/unperformed]. Limitation: [...].`

## Session C — edits, imports, sync and access loss, about 15 minutes

Use only a disposable test entry or workout the person explicitly chooses for
editing/deletion. Never modify an existing valued record to satisfy this plan.

1. Inspect a manual entry and, if available, an unsupported imported entry.
   Determine on-device whether both can be excluded reliably. An absent manual
   marker is not proof of device origin. If no import is available, say unperformed.
2. Inspect one fixed window, edit/delete the chosen test record in Health, then
   inspect again after returning to the investigation and beginning a new session.
   Backgrounding clears the prior capture. Keep comparisons qualitative; lost
   visibility alone does not establish deletion or complete replacement.
3. Record ordinary Watch activity while it cannot sync, inspect the phone, then
   reconnect/sync and repeat the same absolute window. Record a late arrival only
   if actually observed; an initial empty read never establishes a missed goal.
4. Lock/unlock, try an offline read, then revoke a selected permission and return.
   Begin again as needed. Compare empty, failed and unavailable behavior without
   claiming the app can distinguish denial from absent data.

Categorical reply:

`C: manual=[distinguishable/unclear/unperformed]; import=[distinguishable/unclear/unperformed]; edit/delete=[change observed/visibility uncertain/no change observed/unperformed]; late sync=[arrival observed/unclear/unperformed]; offline=[read available/empty/unavailable/unperformed]; lock clearing=[passed/failed/unperformed]; permission loss=[empty/unavailable/indistinguishable/unperformed]. Source tested: [...].`

## Session D — boundaries and confirmation, scheduled around real conditions

Repeat relevant cases for steps, Exercise Time, cumulative running and timed
running. Reuse private observations only when they actually concern the same
source policy. Cross a local midnight when practical. Inspect a fixed absolute
window before and after a timezone change, then restore the person's timezone.
Travel must not move the selected instants. An actual DST observation requires
that boundary; synthetic Simulator/date arithmetic is software evidence only.

Categorical reply:

`D: source=[steps/Exercise/running distance/timed running]; absolute window=[stable/changed/unclear/unperformed]; midnight=[observed/unclear/unperformed]; DST=[observed/unperformed]; trustworthy miss handling=[supported with stated limitations/unresolved]. Limitation: [...].`

## Acceptance and next implementation

Firstmate records performed actions, categorical findings, limitations and
pass/fail/unperformed for each source. Separate a successful read from policy
acceptance and from owner approval. Empty or invisible history never proves a miss.
A failed or unresolved source remains disabled and blocks all-mode distribution.

For each accepted source, the next implementation slice is its **new versioned
real-source terms**, adapter and exact seven-state readiness mapping, applicable
on-device goal suggestions, and minimum-data attested ingestion with source
binding, replay protection, downward corrections and recovery. Historical
fictional agreements continue to use fictional sources. Prove a real-source
progress/correction/review/final simulated journey before marking that slice done.
No adapter semantics or tolerance are invented from these unperformed sessions.

Human comprehension and physical assistive-control checks are separately listed
in [rollout preparation](BETA_ROLLOUT_PREPARATION.md). Existing support/legal,
retention/deletion, host and community decisions remain under
**gametime-beta-release-readiness-b7**; no messages or installations are implied.
