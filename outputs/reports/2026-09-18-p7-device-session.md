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

Session A has been handed to the owner for phone-only, Watch-only and combined
steps checks. No categorical source findings have been received yet. Sessions
B–D, all four source policies, whole-run distance tolerance, source-backed
integration and human/release gates remain pending. No source is accepted or
enabled by installation or a successful read. An empty read cannot establish a
miss.

The ordinary app icon may launch without the investigation argument after the
current process ends; relaunch with that argument before resuming a private
session. Raw records, source identifiers, exact activity times, screenshots,
logs and accuracy measurements must remain on-device. This report contains none.
