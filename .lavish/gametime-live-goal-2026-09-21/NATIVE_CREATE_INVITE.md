# Native create/invite correction — September 21, 2026

## Why the installed screen differed

The first native integration (`a3d2ae9`, installed as Staging 0.8.1
(926.21.2)) reused the old creation sheet, oversized number field, suggestion
capsule and date summary. It applied the palette and SF Symbols without
reproducing the approved page layout. The earlier report overstated visual
completion. Its passing behavior tests did not establish fidelity to the mock.

A separate, deliberate product restriction also applies on the physical phone:
the enrolled private trial accepts Personal Apple Watch steps only. It hides
activity and friend choices. The server independently rejects other real sources
and policies; removing the client flag alone would expose failing actions and
change the owner's account-only verification preference.

## Corrected native presentation

- Creation uses a full-screen presentation, scoped quiet header and numbered
  progress, 30-point base headings, and a fixed bottom action.
- Editable goals use compact labels, athletic numbers with inline metric units,
  a period/source footer and the existing exact input parsing.
- The date editor opens from an inclusive start/end calendar card with the real
  selected dates, year and time zone. Longer windows never display a fictitious
  seven-day selection.
- Agreement rows are compact and use Apple Watch, shield and currency symbols.
  Full versioned rules, precise date boundaries, readiness, explicit consent,
  $20 simulated default and $1–$500 amount range remain enforced.
- Invitations use actual accepted-friend usernames and saved member initials.
  The existing link issuer is available in a quiet expandable row. All receipt,
  retry, account and stale-read protections remain owned by the existing store.
- Confirmation uses a single metric hero, inclusive dates with years, real saved
  amounts and docked actions. It describes a saved lobby without claiming that
  invitations were delivered or that everyone agreed.
- Dynamic Type, dark appearance, keyboard scrolling and 44-point touch targets
  remain supported. No hosted state, private admission or agreement rules changed.

## Differences that remain deliberate

The HTML's arbitrary challenge names, address-book discovery, portrait contacts,
optional zero stake and alternative personal-only friend consequences are proposals,
not implemented native contracts. Each friend still chooses their own goal in the
saved lobby. The phone remains Personal steps only until the broader private trial
is separately enabled. HTTPS invitation sharing remains unavailable when no
invitation origin is configured. These limits are not visual-fidelity evidence.

## Verification and device update

The final creation/layout rerun passed all **22 tests**, with no failures or skips.
The Health, invitation-recovery and theme suites passed another **35 tests** on the
same final production source. Those 35 passes are retained from the earlier full
run; its creation-test harness failures were resolved in the 22-test rerun. See the
[verification record](captures/native-create-invite-checks.json) for both bundles.
The iPhone product guard passed for 201 active sources; diff whitespace checks passed.

**Staging 0.8.1 (926.21.3)** was signature-verified, installed in place on Mason’s
iPhone, launched normally (PID 25190), and its installed version was read back.
It replaces 926.21.2. Only CFBundleVersion changed in Info.plist; backend, private
trial and invitation settings match. The app was not uninstalled and no account
or server settings were changed. Physical screen appearance and human VoiceOver
remain to be checked on the phone; the captures below are simulator fixtures.
Native captures use fictional accounts and in-memory transports through production
SwiftUI views. The private 800-step capture includes the actual Health suggestion
view while asserting zero Health reads, permission requests or saved mutations.
No real invitation, new goal, consent, Health upload or payment was submitted.

The final visual tests use child-controller containment with asserted phone bounds
and safe areas. Earlier fixed-frame screenshot mounts cropped the docked footer;
those captures were not accepted as proof. Exact consent is checked in one complete
viewport rather than concatenated overlapping OCR fragments.

## Corrected native captures

- [Private Personal 800-step screen](captures/native-private-personal-steps-visible.png)
- [Goal entry](captures/native-create-goal-page-0.png)
- [Challenge review](captures/native-create-challenge-page-0.png)
- [Invite friends](captures/native-invite-friends-page-0.png)
- [Confirmation](captures/native-create-confirm-page-0.png)
- [Dark accessibility confirmation](captures/native-create-confirm-dark-accessibility-page-0.png)

The original HTML mock captures remain unchanged. Native captures replace the
superseded partial-integration captures and include scrolling/recovery continuations.
