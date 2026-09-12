# Prompt 7 — prepared; physical sessions pending

P7 preparation began September 12, 2026 UTC from the clean completed P6
checkout. **No physical session has run and no source is accepted.** This is a
continuation of the existing source-acceptance work, not a replacement task or
authorization to start P8.

| Item | Identity |
| --- | --- |
| P6 base, including its final handoff | `39e5f202ab0eae0ac6c23cb784afd3df28d1ad37` |
| P6 implementation | `05f405c24453fe6743ece994d646058958bfdbb2` |
| P7 checkout | `/private/tmp/gametime-p7-20260912/GameTime` |
| P7 branch | `codex/physical-source-p7` |
| Built source | P6 base above; no executable source changes |

The P6 task was idle and its checkout clean. Original/product/P4/P5/P6 branches,
databases, Simulators and retained artifacts were preserved. Only this new
checkout and its build outputs were created. No migration, source policy,
agreement, consent, app behavior or readiness gate changed.

## Prepared product and performed checks

- XcodeBuildMCP built `GameTime`, Debug, generic iOS device, using the existing
  project signing configuration and `-disableAutomaticPackageResolution`.
  Build succeeded in 36.8 seconds. The existing `WeeklyModels.swift:275`
  trailing-closure warning remains.
- Product: `/private/tmp/gametime-p7-20260912/DerivedData/Build/Products/Debug-iphoneos/GameTime.app`.
  Bundle ID `com.mjenkins.gametime.staging`; environment `debug`; iPhoneOS;
  deployment target 18.0. This is a prepared signed build, not an installation.
- `python3 scripts/check-iphone-product.py --app <product>` passed: 148 active
  source files, iPhone HealthKit linked, no Watch payload/runtime links.
- `codesign --verify --deep --strict <product>` passed with access to the Mac's
  signing services. The earlier sandboxed check failed with
  `CSSMERR_TP_NOT_TRUSTED`; it is retained as a failed attempt, not a pass.
- Read-only source review confirmed the existing Debug launch argument bypasses
  product model/client construction, product service tasks, URL handling and
  legacy Health observer registration. Reads require the person's in-app opt-in.
  Session/window/activity changes clear stored captures, and generation/identity
  checks reject late responses. These are source findings, not observed physical
  lock, permission, lifecycle or reconciliation behavior.
- Investigation, probe, app launch and observer source files are byte-identical
  to the preserved product main `affd367ebe5411969fd5b7abd45629e0746a5a7d`.
  Existing tests were inspected; no new unit/UI/physical test run is claimed.
- All 18 entries in `docs/release/beta/readiness.json` remain false.

SHA-256 of prepared product executables:

```text
GameTime             7d2a9ec6f129788c45e8fe7bc6b3ddc2673e824c2a2ef875913a2131307d65dc
GameTime.debug.dylib  c057485b5e8596997ba806a871aef33969ba80933e2e6ea0d89b46bb5bf0429f
```

Read-only device discovery identifies a physical iPhone 17 / iOS 27 family,
currently unavailable to CoreDevice. No paired Watch was identified or opted in.
Exact device identifiers are not copied into this ledger. XcodeBuildMCP's device
listing also labeled Simulators as physical; direct CoreDevice `Reality` fields
were used to distinguish them. A sandboxed CoreDevice query timed out after
15 seconds; the read-only query with service access succeeded. No install,
launch, debugger attach, console capture, screen capture or Health access ran.

## Resume with the owner

Follow [BETA_PHYSICAL_SESSIONS.md](../../docs/BETA_PHYSICAL_SESSIONS.md), starting
with its explicit opt-in naming the exact iPhone and its paired Apple Watch.
The earlier Cobalt installation permission did not select a Watch or authorize
this Health investigation. The person must connect/unlock the selected iPhone;
retain only device/OS families in the observation ledger.

After opt-in, recheck the source commit, product hashes and selected device.
Install the prepared Debug product over the existing matching bundle without
uninstalling or deleting its container. Launch with
`--health-source-investigation`, without a debugger, console capture or mirroring.
If using Xcode, turn off Debug executable in the Run action and add the argument.
The ordinary icon launch does not establish that the argument is active: the
person must see **Activity investigation** before proceeding. If it was
terminated, relaunch with the same argument before resuming.

Begin with Session A, about ten minutes: narrow window, Begin private session,
Connect Apple Health, Read this window; then phone-only, Watch-only and combined
comfortable walks, and session clearing. The person controls all Health actions.
Use the guide's categorical reply only. Raw records, values, routes, source
identifiers and exact activity times remain on-device; do not request screenshots
or raw exports. The existing running view covers both cumulative and timed-run
investigation, not accepted scoring for either.

| Required result | Current status |
| --- | --- |
| Phone/Watch steps; overlap and reconciliation | Unperformed / unresolved |
| Exercise lineage and eligibility | Unperformed / unresolved |
| Running source, pauses and whole-workout boundaries | Unperformed / unresolved |
| Manual/import exclusion; edits/deletion; late sync | Unperformed / unresolved |
| Permission, offline, lock and session behavior | Physical unperformed |
| Midnight, timezone and DST behavior | Physical unperformed |
| Completeness and trustworthy miss handling, all four sources | Unresolved; empty reads cannot establish denial, readiness, zero or a miss |
| Timed-distance tolerance | Unselected; requires repeated private measurements and policy review |

Sessions B/C/D remain dependent on actual owner activity and conditions. Record
each performed action and categorical result separately from policy acceptance.
Leave every unresolved source disabled. No P8 ingestion, real scoring, hosted
operation, money or distribution is authorized by this preparation.
