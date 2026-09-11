# Crisp cobalt implementation

Started September 11, 2026 from accepted local main
`a18f00fa19ac95f946c4686ba3b6a068064d797b` in an isolated clone at
`/private/tmp/gametime-crisp-cobalt-20260911`, branch `codex/crisp-cobalt-ui`.
The source repository is `/Users/user/firstmate-workspace/projects/gametime-beta`.
The original dirty GitHub source files and all retained candidates remain untouched.
The only carried files are the approved image, its prompt, and the two cobalt
implementation documents. No unlanded backend experiments were carried.

## Execution order

1. Resolve baseline and routes; capture the existing local screens.
2. Define semantic cobalt colors, scalable typography, content and control components.
3. Integrate Home, friend standings and personal progress using existing projections.
4. Migrate creation, lobby, links, agreements, results, recovery and account screens.
5. Reconcile reachable historical screens through shared components and targeted layout work.
6. Build Debug, Staging and Release, run focused native behavior checks, inspect native
   renders and interactions, and record actual coverage in the screen matrix.

## Owned verification resources

Simulator `GameTimeCobalt-20260911`, iPhone 17 Pro / iOS 26.5,
`ECC9E8B4-65CA-42F7-A6A6-B2F114FAC9AA`.
DerivedData `/private/tmp/gametime-cobalt-derived`.
No retained controller, database, simulator state, or physical device is reused.
The iOS deployment target remains 18. No release gate is opened by this work.

## Implemented behavior

The selected prompt is the crisp cobalt UI implementation prompt, read together
with its screen/state matrix. The user's attached Home image is the visual
reference. The implementation uses a true bundled condensed italic typeface,
white canvas, vivid cobalt feature panel, initials, large metric values with
upright units, inline personal progress and compact upcoming rows. Home's
recovery/action ordering remains server-driven. Its date and greeting use the
current local calendar; no real account name is fabricated to copy “Alex.”

Shared form, account, navigation, notice and historical components use the same
semantic palette. Native glass is limited to supported controls/navigation;
iOS 18 and Reduce Transparency use opaque fallback surfaces. Existing goals,
agreements, outcomes, privacy fences and availability gates remain authoritative.

Review [the design system](DESIGN_SYSTEM.md), [screen ledger](SCREEN_LEDGER.md)
and [verification report](VERIFICATION.md). The primary visual comparison is
[screenshots/native/cobalt-home.png](screenshots/native/cobalt-home.png).

## Verification boundaries

Tests use owned fictional local accounts and a separately copied Supabase
stack (`gametime-cobalt-20260911`, loopback ports 60321/60322, controller 60339).
No database reset or live service mutation was used. The test controller and
credential manifest are ignored local files and are not part of the change.
No other simulator, controller, database or Docker container is modified.

The compact runtime is a separate iPhone 13 mini / iOS 18.6 Simulator,
`B5424EF1-239E-4B59-9A94-7E018C3D86EB`. Native image renders at phone-sized
bounds supplement actual touch tests; long model detail renders are not OS
screenshots. Human VoiceOver and physical Health acceptance are not claimed.

