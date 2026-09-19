# P7 physical source session — started September 18, 2026

This continues the prepared [P7 checkpoint](2026-09-12-p7-preparation.md) and
the [private session guide](../../docs/BETA_PHYSICAL_SESSIONS.md). The owner
opted in to a private investigation on an iPhone 17 paired with their Apple
Watch. The owner controls the phone, Watch and Apple Health actions. Only device
and OS families and categorical conclusions belong in this record.

## Build and installation

| Item | Performed result |
| --- | --- |
| Source | Clean published `main` at `00bccfac36140a846623c5c50f4ee8495e9925ae`; session branch `codex/p7-device-session-20260918` adds this record and the working-baseline pointer. |
| Toolchain and device | Xcode 27.0; connected physical iPhone 17 on iOS 27.0. Paired Watch model and OS not yet recorded. |
| Build | `GameTime` scheme, Debug, generic iOS device, existing project signing settings, package resolution disabled; succeeded. Existing `WeeklyModels.swift:275` trailing-closure warning. |
| Product | `com.mjenkins.gametime.staging`, `debug`; iPhone app executable SHA-256 `00254cfe5819c84fb24abd250ee47ed2f133d969fe2e2762ee3f672b8402df6d`. |
| Package and signature | `scripts/check-iphone-product.py --app` passed: HealthKit linked, no Watch payload or runtime links. `codesign --verify --deep --strict` passed. |
| Device action | Installed over the matching bundle without uninstall or container deletion. Launched with `--health-source-investigation`, without debugger, console bridge, screen capture or mirroring. The owner confirmed the **Activity investigation** screen is visible. |

The app has no active GameTime Watch target. The Watch records to Apple Health;
the iPhone investigation reads eligible records only after the owner begins a
private session and chooses to connect/read. Source review confirms the launch
argument avoids ordinary product model/service construction and the legacy
Health observer. This is a code finding, separate from physical source behavior.

## Physical observations and acceptance

Session A's categorical observations are recorded:

| Check | Owner observation |
| --- | --- |
| Phone-only walk | Steps visible, with clear iPhone origin. |
| Watch-only walk | Steps visible in the iPhone investigation, with clear Watch origin. |
| Carrying both | Both origins visible; the app flagged overlapping records. Which records represent the same activity remains unresolved. |
| Source distinction | Clear for the displayed records. Some records lacked a hand-entry marker. |
| Clear session | Passed: earlier displayed records disappeared. This is not a Health deletion. |

The app also warned that read access and complete activity history cannot be
confirmed. The reads establish visibility for these checks, not complete
history, accepted reconciliation or a trustworthy miss. The iPhone app was
relaunched with the investigation argument for the phone-only read; no console,
debugger or screen capture was used.

Session B has begun. The owner selected Apple Exercise Time and reported visible
records with clear Watch origin in the on-device source/device details. This is
an origin observation only. The inspected records showed **Not supplied** for
the hand-entry field, so that field does not exclude manual entry.
Manual/import eligibility, overlap, conversion to the agreed integer-second
unit, corrections and complete-history behavior remain unsettled.

On September 19, the installed Debug investigation was reopened with its
isolated launch argument on the same connected iPhone, without debugger,
console bridge or screen capture by the investigator. The owner then reported
two comfortable running workouts from the paired Watch; the second included
ordinary pauses. The displayed running-workout records identified the device
as Watch, but their hand-entry fields were **Not supplied**, and no imported
comparison was performed. The unpaused workout's reported duration was close
to its start-to-finish elapsed time. For the paused workout, the reported
duration was shorter than the start-to-finish elapsed time, consistent with
pauses remaining in the elapsed interval. The owner initially said both
distances seemed accurate, then clarified that a run was checked against a
privately measured route and was accurate. This is a qualitative measured-route
observation; no quantitative error series or sufficient repetitions support a
distance tolerance yet. In response to the containing/boundary-cutting window
check, the owner reported that the whole workout record remained inspectable.
The owner later reported not seeing a boundary warning. Whether the selected
window actually cut across the record and the read-status section was inspected
remains unverified; the warning is not counted as a pass or a failure. No
values, exact activity times, route, source identifier or image are retained
in this report.

The owner also added a manual step test entry in Apple Health and reported that
it was not visible in the activity investigation. The UI's default **Until**
is fixed when the investigation opens, so a later entry can fall outside it.
After that limitation was explained, the owner adjusted the selected time and
still did not see the entry. Changing the picker clears the private session;
a completed fresh read with other device-origin steps visible in the same
window has not yet been confirmed. The investigation does not intentionally
filter manual step records. This remains an inconclusive visibility observation,
not evidence that manual steps are reliably excluded or that Health history is
complete.

The owner reports that Watch-only running workouts later sync to the iPhone
and become visible in the investigation, describing this as a successful
late-arrival check. A pre-sync read while the Watch could not sync and a
reread of the same absolute window after reconnection were not specified.
Record later visibility for running workouts, not complete Session C late-sync
acceptance or proof that an initially empty read establishes a missed goal.

Session B still needs Exercise manual/import lineage, a confirmed
boundary-crossing status check, and repeated independently measured whole runs.
Session C's manual-step distinction remains open after the initial invisible
entry.
Running-source eligibility, correction and completeness are unresolved for
both cumulative and timed policies; no whole-run distance band is selected.

The rest of Sessions B–D, all four source policies, whole-run distance tolerance,
source-backed integration and human/release gates remain pending. No source is
accepted or enabled by installation or a successful read. An empty read cannot
establish a miss.

The ordinary app icon may launch without the investigation argument after the
current process ends; relaunch with that argument before resuming a private
session. Raw records, source identifiers, exact activity times, screenshots,
logs and accuracy measurements must remain on-device. This report contains none.

## Owner disposition — September 19

The owner considers all P7 tests a pass, says the app works as intended, and
directs preparation for P8. This is the owner's sign-off on the test effort,
not a retroactive observation of every row above. In particular, the exact
manual/import eligibility, overlapping-source reconciliation, edit/deletion,
permission/offline/time-boundary and trustworthy-miss cases are not established
by the recorded observations; the whole-run distance tolerance is unselected.
Keep these distinctions in the P8 handoff. No real-source adapter, ingestion,
scoring gate, hosted operation or distribution was enabled by this sign-off.
