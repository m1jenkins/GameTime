# GameTime TestFlight readiness — September 30, 2026

The remaining technical gate is successful Health saving from the owner's
phone. The server recovery fix already exists and is deployed; repeating the
deployment would not resolve the observed client refusals. The physical iPhone
was unavailable, so its installed Staging build could not be verified.

This task reviewed the recent **Identify pre-beta launch tasks** chat and its
release, acceptance and code-audit results, the current repository contracts,
and the September 27–29 reports. Source started at `f1dd690` on local `main`.
The app and Core source match the validated `b16685b` archive; the new native
source edits are confined to test measurement. Unrelated copy/design edits
and untracked owner work were preserved.

## Reconciled status

| Item | Current evidence | Remaining action |
| --- | --- | --- |
| Version and archive | Existing 0.9.0 (2), `b16685b`; development signature, entitlements, privacy reasons and iPhone guard verified locally | Distribution signing/export, then separately approved upload |
| Apple sign-up | Live public Auth settings: Apple enabled, sign-up open, email/phone/anonymous off; September 28 applied receipt records both bundles | Real sign-in and new-account acceptance on the signed candidate |
| Legal and deletion setup | Public privacy/terms HTTP 200, published entity/support address; deletion deployment recorded September 28 | Real deletion with a separate opted-in test identity; inbox receipt/reply and staffing acceptance |
| Health server fix | Active ingest version 9; all 12 deployed files byte-identical to current source | Do not redeploy this completed fix |
| Health client fix | `dff4be9` recovery is in current source and the existing archive | Verify the installed Staging identity; update the same bundle if older, after device approval |
| Real activity saves | Zero saved facts after September 28 22:27:11 UTC; 34 ingest requests through September 30 20:56:13 UTC, all HTTP 422 | Successful private-account Steps and outdoor-distance saves, with no new binding refusals |
| Review contact/access | Owner supplied the phone and exact friend username; private draft uses the reviewer's own Apple sign-in and a friend request | Contact is filled locally; owner availability to accept the request and arrange access needs confirmation before submission |
| Export compliance | Archived plist has no declaration; active source uses Apple networking, hashing/storage and device-check APIs | Owner confirms the proposed OS-only/exempt answer before filing it |
| Apple distribution access | One local development identity, no App Store profile, no cached Xcode Apple account | Owner signs into Xcode/ASC; changes to credentials or agreements need separate approval |
| App Store Connect state | September 29 receipt says no upload or fields entered then; no upload occurred in this task | Current authenticated app record, agreements, fields, build and review state remain unverified |
| Human acceptance | Automated checks and fictional fixtures are separate evidence | Physical accessibility/VoiceOver; comprehension and retained-Personal replacement decisions |
| Operations | Initial support grant, backup dump and secret issuance already recorded | Support renewal by October 4, independent appeals person, backup/pause routine, secret renewal owner by March 13, 2027 |

Detailed performed checks: [release audit](RELEASE_AUDIT.md),
[Health audit](HEALTH_AUDIT.md), [native validation](NATIVE_VALIDATION.md),
[rendered-rank regression repair](RENDERED_RANK_CHECK.md),
[export declaration draft evidence](EXPORT_REVIEW.md).

The active [friends plan](../../../docs/FRIENDS_TESTFLIGHT_PLAN.md) and
[hosted runbook](../../../docs/FRIENDS_PHASE5_HOSTED_RUNBOOK.md) now point at
the completed Apple/provider/legal work and distinguish current checks from
dated failures. Historical reports keep their original outcomes.

## Work performed locally

- Prepared an App Store Connect draft with the supplied review contact.
  Reconciled its own-Apple-ID/friend-request path with the friends plan;
  no pre-friended reviewer account is claimed, and the manual acceptance
  dependency remains an explicit gate before submission.
  Corrected its claim that a person without Watch data can complete a
  challenge: real creation/consent requires matching activity and an
  acknowledged readiness check (`ChallengeCreationViews.swift:32`,
  `ChallengeHealthFlowStore.swift:123–126`). Browsing is available without it.
- Kept the export-compliance answer pending. The source audit also found
  CryptoKit SHA-256, Keychain and the Apple device-check path; the old “only
  HTTPS and Sign in with Apple” statement was incomplete. The OS-only
  exemption is a proposed inference, not a submitted declaration. The
  resolved SDK crypto and archived binary imports were also inspected; see
  [the bounded export review](EXPORT_REVIEW.md). The existing archive and
  plist were not changed.
- Ran native verification and repaired two reproducible test measurement
  errors. The initial run had **673 passed, 2 failed, 11 skipped**; the
  original failed result and isolated unchanged retries are retained.
  Creation's lower-button-edge check compared Display P3 bytes to sRGB
  tokens. It now uses an sRGB buffer and the light-resolved primary-fill
  token, retaining the original tolerance and docking/viewport assertions.
  The rank check now inspects the numeral beside the rendered You label,
  preserving the exact rank transition and late-response checks.
- Prepared a clearly labeled fictional simulator recording from existing
  Debug fixtures. Its chapters show separate examples, rather than evidence
  of one real elapsed challenge. It does not close real Health or physical
  acceptance. Submission still requires owner review and approval.

## Fresh checks and limits

| Check | Result |
| --- | --- |
| Core | 187 Swift Testing tests plus 3 XCTest cases passed |
| Health HTTP/database/handler tests | 77 passed, 0 failed |
| TestFlight source candidate | 23 passed, 0 source blockers |
| Candidate fixture guards | Passed |
| iPhone product guard tests | 15 passed |
| Legal generator | 6 passed; final generated pages match |
| Existing archive signature/profile/product | Passed read-only local checks; development signing |
| Fresh Debug and TestFlight simulator builds | Succeeded; product guard passed |
| Six current shell/creation/friends/Health fixture UI tests | Passed |
| Creation suite after measurement repair | 13 passed |
| Overlapping-response suite after measurement repair | 21 passed, 0 failed, 0 skipped; both strict mounted-rank methods also passed in their targeted run |
| Staging device candidate | Signed 0.9.0 (930.26.1) built; signature and product guard passed; no physical installation |

The September 29 full **706 passed, 0 failed, 68 skipped** product run remains
that run's evidence. This task did not silently replace its skipped gates or
claim a new full physical acceptance. The 38 retired-shell skips remain
owner-approved; the 13 retained Personal-detail tests were already repaired.
Known largest-text onboarding/profile polish remains deferred by the existing
build-1 instructions. D144 payments remain disabled in TestFlight; the completed
local-emulator payment work is not reopened as a first-build gate.

No hosted mutation, deployment, credential change, agreement acceptance,
physical app launch/install, TestFlight upload or tester invitation occurred.
No personal Health totals, request bodies or raw user identifiers were read
for the hosted check; it selected aggregate counts/timestamps only.

## One installation uploading for the owner

The score-backwards warning is verified in source and its existing regression.
Staging and TestFlight share the backend and account, while retaining separate
Health permissions, comparison baselines and durable upload journals. Each
reads its own Health view, obtains the server's current revision and submits a
replacement. Later replacements can legitimately lower a score or mark its
data unresolved. Choosing the maximum would break adopted correction rules.

Keep TestFlight uninstalled for this account while the active Staging goals
continue. When device work is approved, inspect the current bundle/build first.
If it is old, update **`com.mjenkins.gametime.staging` in place**, without
uninstalling, signing out, clearing its journal or switching bundles. Preserve
the existing account and goal; do not recreate either to pass acceptance.
Then confirm successful saves using the runbook's read-only aggregate.

The existing outdoor-distance corrections close **October 3 at 00:00 Central
(05:00 UTC)**. If that window expires, acceptance needs a separately approved
new eligible goal. The eventual TestFlight cutover follows actual final goal
states; **October 9 is an estimate**, not an automatic authorization or proof
of finality.

## Local review material

Ignored files stay on this Mac, outside public Git history:

- `tmp/testflight-readiness-2026-09-30/ASC_BETA_INFO.md` — supplied review
  contact, revised notes and proposed export answer; mode 600.
- `tmp/testflight-readiness-2026-09-30/native/fictional-simulator-challenge-demo.mp4`
  — fictional simulator walkthrough; original recording is retained beside it.
- `tmp/testflight-readiness-2026-09-30/native/` — build/test results, original
  failures, targeted reruns and staged device app.
- `tmp/testflight-readiness-2026-09-30/native/StagingDeviceDerivedData/Build/Products/Staging-iphoneos/GameTime.app`
  — prepared same-bundle Staging 0.9.0 (930.26.1), unchanged native app source
  `f1dd690f4db5125b69407e7d8beaf4925e357c0b`, binary SHA-256
  `cdedeb195a2653dff6edc560ae4a13dd765c8f2de94c01615e082461ca80feb2`.
- `tmp/testflight-readiness-2026-09-30/release-audit/` — local signature,
  archive and public HTTP readbacks.

Next owner action: connect and unlock the iPhone for read-only installed-build
inspection, then approve the prepared same-bundle update if needed. Apple
distribution access, export answer, human/operational acceptance and later
upload/recruitment approval remain separate gates.
