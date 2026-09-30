# TestFlight release audit — September 30, 2026

Read-only release audit at `f1dd690f4db5125b69407e7d8beaf4925e357c0b`,
before the September 30 readiness fixes. Reviewed all three files in
[the September 29 release prep report](../testflight-release-prep-2026-09-29/README.md),
the current friends TestFlight plan, repository context, archived app and
local signing inventory. The current report directory's README records the
team's subsequent changes and checks.

No account or credential changed. No certificate or profile was created.
No export, upload, invitation, hosted write or device action was performed.
The live network checks below were GET requests only.

## Verified locally

The documented archive exists at:

```text
/Users/user/Library/Developer/Xcode/Archives/2026-09-29/GameTime 0.9.0 (2) TestFlight b16685b.xcarchive
```

Its embedded version is **0.9.0 (2)**, bundle
`com.mjenkins.gametime`, team `87Z29RTC26`, arm64, iPhone only, minimum
iOS 18.0. The archive's source identity comes from its September 29 receipt;
the embedded app does not independently prove a Git commit. At the audit
tip, `git diff --name-only b16685b..HEAD -- ios/GameTime ios/GameTimeCore
scripts/check-beta-candidate.sh scripts/check-iphone-product.py` returned
no paths.

| Archived value | Result |
| --- | --- |
| Runtime and backend | `testflight`, `https://lyushhqoednheqwzsmxh.supabase.co` (gametime-p11b) |
| New challenges / account-mode activity | Both `YES` |
| Sandbox commitments / legacy contest mutations | Both `NO` |
| Retained Personal settlement | `test_only` |
| Stripe return URL | Empty |
| Required-reason APIs | UserDefaults `CA92.1`, SystemBootTime `35F9.1` |
| Tracking | `false` |
| dSYM | Present |
| Export declaration | `ITSAppUsesNonExemptEncryption` absent |
| Product guard | HealthKit linked; no Watch payloads or links; exit 0 |

The beta remains simulated money: this audit found no release configuration
change needed to disable payments. The separately completed D144 Stripe
sandbox work does not turn commitments or card setup on in this TestFlight
configuration.

## Signing: development confirmed; distribution still unavailable locally

`codesign --verify --deep --strict` **passed** after a read-only sandbox
escalation. The signed authority is `Apple Development: MASON PHILLIP
JENKINS`, and signed entitlements include Apple sign-in, HealthKit,
background delivery, production App Attest and `get-task-allow = true`.
There is no push entitlement.

The embedded profile's CMS signature also verified using OpenSSL. It is
`iOS Team Provisioning Profile: com.mjenkins.gametime`, a development
profile with two provisioned devices, expiring September 11, 2027.

The current Mac has **one valid signing identity, Apple Development**.
All three decoded local provisioning profiles are development profiles;
none is an App Store profile for the production bundle. Xcode's cached
Apple-account list has zero entries. These checks substantiate the local
distribution-signing gap reported September 29. They do not prove that
nobody exported or uploaded a build elsewhere.

The first default-sandbox attempt returned `CSSMERR_TP_NOT_TRUSTED`, showed
the authority as unavailable and reported zero signing identities. The
read-only escalation successfully validated the same unchanged archive and
found its development identity. **The default-sandbox failure is not an
archive-signature blocker.** Default-sandbox `security cms` decoding also
failed; OpenSSL verification without keychain trust decoded all profiles.

No new distribution export was attempted. The September 29 export failed
for lack of an App Store provisioning profile; that remains historical run
evidence rather than a newly repeated export result.

## Live public checks

Read September 30 with the checked-in TestFlight publishable key, passed
only as an HTTP header and never printed:

`GET https://lyushhqoednheqwzsmxh.supabase.co/auth/v1/settings` → **HTTP 200**.

| Public setting | Value |
| --- | --- |
| Apple provider | `true` |
| Sign-up disabled | `false` — sign-up is open |
| Email provider | `false` |
| Phone provider | `false` |
| Anonymous users | `false` |
| Email autoconfirm | `false` |
| Phone autoconfirm | `false` |

Apple-only sign-up is already configured. The
[September 28 Step 3 applied receipt](../2026-09-28-phase5-steps2-5.md#step-3-applied)
records the production bundle and provider-secret update; public settings
do not expose those fields. This audit did not rerun that change and did
not exercise a real Apple authorization or a new person's sign-up.

[Privacy](https://m1jenkins.github.io/GameTime/privacy.html) and
[Beta Terms](https://m1jenkins.github.io/GameTime/beta-terms.html) both
returned **HTTP 200**. Both name Squirrel Labs, Inc. and
`gametime-support@agentmail.to`; neither has the draft banner. Their archived
URLs and support email match the current configuration. The
[legal-pages runbook](../../../docs/LEGAL_PAGES_PUBLISH_RUNBOOK.md) already
records the entity, jurisdiction, publication and inbox setup as complete.
No test email was sent, so ongoing inbox monitoring was not verified.

Default-sandbox DNS requests failed. The successful HTTP checks used a
read-only network escalation; no authenticated user session or Management
API credential was used.

## Checks run

| Check | Result |
| --- | --- |
| `scripts/check-beta-candidate.sh --testflight` | 23 passed, 0 source blockers |
| `scripts/tests/check-beta-candidate.test.sh` | PASS |
| `python3 scripts/build-legal-site.py --final --check` | Published-source files match |
| `python3 scripts/tests/build-legal-site.test.py` | 6 passed |
| `python3 scripts/check-iphone-product.py --app '<archive app>'` | Exit 0 |
| `codesign --verify --deep --strict '<archive app>'` | Exit 0 with read-only escalation |
| Embedded profile CMS signature | Verified; certificate chain trust omitted for extraction |

These are focused release checks. The September 29 full Xcode and Swift
test counts remain that run's evidence; this audit did not rerun those
suites or claim new physical-device acceptance.

## Reconciled blockers and limits

- **Finished:** version bump, privacy required-reason fix, development
  archive, candidate configuration, release drafts, Apple-only open sign-up,
  legal pages and support-address setup. Repeating these setup tasks is
  unnecessary.
- **Apple access and approval:** distribution signing/export remains
  unavailable on this Mac. Upload and tester invitations require the owner's
  explicit approval. No authenticated App Store Connect connection was
  available to this audit, so app-record existence, filled fields, agreements,
  uploaded builds and review status are **unverified today**. The September 29
  receipt says nothing had been entered or uploaded then.
- **Release materials:** review contact values were supplied during the
  September 30 task and belong only in the ignored local ASC draft. A challenge
  demonstration recording and the owner's export-compliance answer remain
  separate completion items until the task's current README records them.
  The archived plist still has no export-compliance declaration.
- **Physical and human gates:** real Apple sign-in, new sign-up, current
  Health-upload acceptance, VoiceOver, comprehension and a complete friends
  challenge cycle were not run by this release audit. Phone metadata and the
  dual-build score warning are audited by the separate Health/device work.
  No installation was performed here.
- **Deferred polish:** the September 29 tester notes identify the largest-text
  onboarding sentence and profile-keyboard overlap. Earlier owner instructions
  defer those changes for build 1; this audit does not reopen that decision.
  No failing source candidate guard calls for new release tooling. Fresh native
  test findings and their disposition are in the task's current README.

## Local evidence and exact commands

The following logs are ignored local artifacts, copied from the tool outputs
of this audit. They are not committed release evidence. This report preserves
their results and limitations.

| Artifact | Local path |
| --- | --- |
| Candidate and legal checks | `tmp/testflight-readiness-2026-09-30/release-audit/candidate-checks.log` |
| Signature verification and signing inventory | `tmp/testflight-readiness-2026-09-30/release-audit/signing-verification.log` |
| Archive metadata, profile and product guard | `tmp/testflight-readiness-2026-09-30/release-audit/archive-metadata.log` |
| Live HTTP response summaries | `tmp/testflight-readiness-2026-09-30/release-audit/public-http-readback.log` |
| Reusable archive-inspection command body | `tmp/testflight-readiness-2026-09-30/release-audit/archive-inspect.py` |
| Exact successful HTTP command body | `tmp/testflight-readiness-2026-09-30/release-audit/public-readback.py` |

Working directory: `/Users/user/Documents/GitHub/GameTime`.

```sh
scripts/check-beta-candidate.sh --testflight
scripts/tests/check-beta-candidate.test.sh
python3 scripts/build-legal-site.py --final --check
python3 scripts/tests/build-legal-site.test.py
python3 tmp/testflight-readiness-2026-09-30/release-audit/archive-inspect.py
python3 scripts/check-iphone-product.py --app \
  '/Users/user/Library/Developer/Xcode/Archives/2026-09-29/GameTime 0.9.0 (2) TestFlight b16685b.xcarchive/Products/Applications/GameTime.app'
codesign --verify --deep --strict \
  '/Users/user/Library/Developer/Xcode/Archives/2026-09-29/GameTime 0.9.0 (2) TestFlight b16685b.xcarchive/Products/Applications/GameTime.app'
codesign -dvv \
  '/Users/user/Library/Developer/Xcode/Archives/2026-09-29/GameTime 0.9.0 (2) TestFlight b16685b.xcarchive/Products/Applications/GameTime.app'
security find-identity -v -p codesigning
python3 tmp/testflight-readiness-2026-09-30/release-audit/public-readback.py
git diff --name-only b16685b..HEAD -- ios/GameTime ios/GameTimeCore \
  scripts/check-beta-candidate.sh scripts/check-iphone-product.py
```

The signature/identity and HTTP commands needed read-only sandbox
escalation in this session. The inspection script combines the local
metadata extraction and profile queries originally run inline; the HTTP
script preserves the successful request body without a literal key.
