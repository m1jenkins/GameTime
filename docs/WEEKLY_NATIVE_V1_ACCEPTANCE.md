# Weekly native local implementation evidence

Date: 2026-09-06. Scope: W1C/W2B and the separately named W4 local
prototype entry. This is fictional local implementation, not a launched
challenge or accepted health source. Full native stage acceptance remains
open until the checks below and required human accessibility work are done.

## Implemented contract

- Weekly steps use their own versioned terms, typed RPC projections and actor-bound
  exact request envelope. Existing Personal, Solo, charity and fictional 5K
  clients and agreements retain their own contracts.
- The default-off `--weekly` entry exists only in Debug/Staging against an explicit
  HTTP loopback URL with a port. Release has no weekly route or enabled client.
  No weekly Health permission, notification, payment or external support send exists.
- Creator preview and invitee consent show the frozen roster and every target.
  Friend capacity is the documented working assumption of 2–5 total including
  the creator. Community can be joined without friends and displays one common
  configurable fixture target, currently 12,000 in the local smoke.
- Rules disclose the calendar, fictional source, simulated entry/fee, upload and
  correction cutoffs, full 48-hour filing window and 72-hour resolution window
  after that filing window. Missing/incomplete updates do not imply failure;
  provisional notices use different language from durable final receipts.
- Durable request storage preserves the exact original bytes and request ID.
  Recovery is explicit. The atomic server reconciliation operation either recovers
  a committed receipt or retires a never-committed key before local removal.
  Gate closure and entry pause preserve recovery, review, support and safe exits.
- Actor and session changes reject late responses. Background/account changes and
  failed reads clear private content. Action freshness uses monotonic uptime;
  displayed selected sharing expires after at most 60 seconds without a fresh
  read. The task only clears local display; it sends no notification.
- Selected friend progress requires an owner offer and a separate recipient
  accept/decline. Unfollow and owner revocation remain deliberate safety actions.
  Displayed progress cannot become qualifying proof, a result or financial data.
  Missing progress remains distinct from an explicit zero.
- Optional local study consent begins off and is separate from challenge consent.
  Coarse allowlisted action records contain no step totals, names, amounts or free
  text. Recording errors do not occupy the safety-request queue.
- The separate distance notebook entry shares the opt-in local build gate. It
  records private fictional cumulative/timed-distance agreements and observations;
  it does not connect a health source, evaluate a result or activate money.
  Account changes clear it and account deletion fences/clears its actor storage.

## Executed evidence and pending checks

| Check | Evidence/status |
| --- | --- |
| Native build configurations | Debug compiled during final full unit run; Staging and Release builds passed in `/tmp/gametime-weekly-final-staging-build.log` and `/tmp/gametime-weekly-final-release-build.log` (before the timer-test seam; production sleep unchanged) |
| Full native unit gate | 367 tests enumerated, 3 controller-dependent tests skipped, zero failures; `/tmp/gametime-weekly-final-all-native-units.log`. Skipped controller tests are not counted as executed HTTP evidence |
| Weekly native unit suite | The recorded full gate passed 18: exact envelopes, account/session isolation, retirement, absent completeness, pause/safety, nonblocking optional study delivery, delayed draft previews and scheduled/late-read social-cache expiry. The suite now contains three additional optional-social refresh regressions covering a four-request concurrency bound, late failure without loss of validated own content, and stale account/superseded responses; they are not part of the recorded full-gate count |
| Rendered SwiftUI fixtures | 4 passed within the full gate with foreground-scene hosting, nonblank pixels and overlapping native-size Vision OCR. Actual PNGs independently inspected: five named targets before consent, normal/accessibility3 layout, community solo rules, provisional/final/refund/recovery and closed unaccepted invitation with support. Earlier blank/OCR failures were corrected and excluded from acceptance |
| Real local Auth/native HTTP integration | Passed after the final preview guard in `tmp/weekly-native-c8d692d1.log`; root controller `/tmp/gametime-weekly-native-http-final.log` exited 0 after cleanup. One test, 3.35 seconds, with real Auth, 2/5 consent, phased review/finality, exact recovery, following and safe-exit assertions |
| Python controller | AST syntax passed; real controller execution and cleanup passed |
| Human VoiceOver, accessibility, comprehension and voluntary-exit checks | Not performed; required external/human gate |

The reconciled `6963cad` CI run separately passed 369 native tests plus three
controller-gated skips, 50 legacy UI tests, 10 conformance tests and Staging/
Release builds. The subsequent held-final-authentication regression reproduced
revoked social data returning after a same-account refresh superseded an older
one. Its post-await cancellation/token fence passed red/green and all 24
focused store/lifecycle tests on a disposable copy. See the
[final publication finding](WEEKLY_INDEPENDENT_REVIEW.md#final-publication-fence-follow-up)
and [delivery evidence](WEEKLY_LOCAL_ACCEPTANCE.md#reconciled-delivery-and-final-privacy-correction)
for exact source states and remaining committed-head checks.

The unit JSON `GameTimeTests/Fixtures/weekly-native-v1.json` is explicitly authored
fixture data. It is not a captured database response. The HTTP controller separately
creates three historical agreements through the actual policy/lifecycle worker,
then reads durable notices, review and final/refund records through the production
native transport. Its future-week sequence exercises two- and five-person consent
with a worker tick before the last acceptance, solo community join, real account
switches, committed response loss, uncommitted transport loss and atomic retirement,
two-sided following, gate-off unfollow, support and injury exit. These assertions
passed in the real HTTP run above. The historical review was
read as `review` with no result/allocation before a separate actual-worker call
advanced through the full stored window and the native client reread final/refund.

## Reproduction

Use an isolated local Supabase stack at API `56321`, database `56322`, with the
current migrations. Weekly gates and actor allowlist must start empty/off. Keep
`supabase status -o json` output private; it includes local credentials.

```sh
xcodebuild -project ios/GameTime/GameTime.xcodeproj -scheme GameTime \
  -configuration Debug -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath /tmp/gametime-weekly-native-xcode -parallel-testing-enabled NO \
  -only-testing:GameTimeTests/WeeklyNativeTests \
  -only-testing:GameTimeTests/WeeklyRenderedTests CODE_SIGNING_ALLOWED=NO test

python3 scripts/weekly-native-smoke.py --status-file /private/path/local-status.json \
  --simulator SIMULATOR_UUID --derived-data /tmp/gametime-weekly-native-xcode
```

The controller binds loopback `56329`, creates six disposable fictional accounts,
uses local admin token generation without sending an email, writes a private
short-lived manifest, and records only request IDs/hashes and nonsensitive counts.
The final run retained five owned fictional agreements and 24 request receipts.
Cleanup reported admission off, an empty allowlist and no held response.
Cleanup closes weekly gates, clears the allowlist, revokes scoped sessions and
bans those fictional identities. It retains fictional history for inspection and
removes the credential-bearing manifest. Logs/results remain under ignored `tmp/`.
Rendered PNGs, when run, are under `tmp/weekly-rendered/` and XCTest attachments.
No hosted project, existing development `54322` database or real participant is used.
