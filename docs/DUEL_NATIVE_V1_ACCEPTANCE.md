# Phase 1B — native simulated duel flow

September 4, 2026 (local date). Implements the native slice from the
[Phase 1A handoff](DUEL_AGREEMENT_V1_ACCEPTANCE.md#phase-1b-handoff).
This is a local experiment. Release access, hosted admission, deployments and
live money remain disabled. Personal, Solo and charity agreements retain their
existing meanings and request formats.

## Implementation

- `DuelModels.swift` decodes the complete v1 policy, event, agreement and both
  consent rows. Unsupported specifications fail closed. The server's digest is
  retained verbatim; the original PostgreSQL creation timestamp is retained for
  exact pagination, and dates display in the event's IANA zone.
- `SupabaseDuelClient.swift` uses the six participant RPCs and the two readable
  immutable catalog tables. Both sides of an asynchronous transport check the
  account. SQLSTATEs map to plain English; backend admission stays authoritative.
- `PendingDuelRequestStore.swift` has its own versioned, actor-bound envelope,
  request UUID, operation and exact parameters. Files are atomic, protected and
  excluded from backup. Corrupt, conflicting and foreign records fail closed.
  An uncertainty marker is persisted before transport. Refresh never resends a
  mutation; only **Retry saved request** does. A successful response is followed
  by current detail before the envelope is removed. Any ambiguous outcome keeps
  the same request. A first definite rejection can clear the failed request.
- `DuelStore.swift` clears private state synchronously at account changes,
  rejects stale completions, retains history when admission is disabled, and
  refreshes detail at lifecycle failures. Deletion clears the store before
  local cleanup and fences queued file writes in that store instance.
- `DuelViews.swift` adds opt-in **You → Friend duels**, accepted-friend and
  curated-event selection, creator review/consent/receipt, invitation details,
  explicit acceptance, decline, pre-start cancellation, history and recovery.
  The rules describe simulated amounts, timing/source, course/wave, deadlines,
  nonfinishes/ties, cancellation, missing results, review and finality. The UI
  explicitly identifies result and review actions as unavailable in this phase.
- Fixtures cover both actors, lost responses, offline behavior and gate-off.
  The existing Personal vocabulary assertions remain scoped to ordinary
  Personal launches; `DuelUITests` adds duel-specific copy and consent checks.

## Run locally

Use Debug or Staging with these launch arguments:

- `--fixture-mode --duels`: creator journey with accepted fixture friends.
- Add `--fixture-duel-incoming`: review an incoming invitation.
- Add `--fixture-duel-lost-response`: commit the next mutation, then lose its
  response so **Retry saved request** must recover it.
- Add `--fixture-duel-gate-off` or `--fixture-duel-offline` for those scenarios.

Ordinary launches do not expose duels. For actual local RPC clients use
`--duels` without `--fixture-mode`, and point Debug's permitted local client
configuration at the disposable loopback stack. Both actors must already be
active, accepted friends and admitted by the Phase 1A service-only setup; a
curated event must still fit the window. The app never grants that admission.
The switch refuses hosted URLs and Release, even when explicitly requested.
Staging's checked-in hosted configuration remains unchanged; Staging can use
the isolated native fixture flow.

## Verification

| Check | Result |
| --- | --- |
| Full `GameTimeTests` on iPhone 17e / iOS 26.5 | 272 passed, 0 failed, including 16 new duel tests |
| New duel UI journeys (focused runs) | All four passed: creator consent/lost-response/receipt; invitee acceptance/cancellation/history; gate-off decline at Accessibility XXXL with Reduce Motion; ordinary Personal launch without duel access |
| Debug, Staging and Release simulator builds | All passed, no compiler warnings or errors reported |
| Compiled route boundary | Staging contains duel view/fixture symbols; Release contains none |
| Local rollback-only two-actor example | Same terms, acceptance, exact recovery after gate-off and cancellation succeeded |
| Actual PostgreSQL DTO | Decodes for both actors, validates consent digests and preserves the original subsecond pagination cursor |
| `check-beta-candidate.sh --personal-copy-only` | Passed; existing Personal copy protections retained |
| `git diff --check` and changed Markdown links | Passed |
| Screenshot inspection | Creator receipt and Accessibility XXXL captured from passing UI tests; text wraps, and the long rule form remains scrollable to its actions |

The UI tests initially exposed unreliable switch targeting and duplicate
accessibility controls across covered sheets. Tests now target the switch and
assert consent before sending; covered sheets suppress their recovery controls,
and an ambiguous creation shows a compact recovery panel. The final focused
runs passed after these fixes. No failed checks were counted as acceptance.

Reproducible checks use the `GameTime` scheme, Debug, iPhone 17e on iOS 26.5,
`CODE_SIGNING_ALLOWED=NO`, and `-only-testing:GameTimeTests` or
`-only-testing:GameTimeUITests/DuelUITests`. Build Staging with
`GameTime-Staging`, and Release with `GameTime -configuration Release`.
The full native result bundle is
`test_sim_2026-09-05T01-33-12-030Z_pid31445_955487ff.xcresult`; the final
creator/recovery and Accessibility XXXL UI bundle is
`test_sim_2026-09-05T01-28-26-966Z_pid31445_2c032fbf.xcresult`, with retained
screenshots. Invitee acceptance/cancellation passed in
`test_sim_2026-09-05T01-24-23-334Z_pid31445_2458c3c2.xcresult`.

The current Supabase changelog, the installed Swift SDK’s RPC interface and
Apple task-cancellation guidance were checked; package versions were not changed. No database schema
was changed, so the full Phase 1A database suite/advisors were not rerun.
The captured `GameTimeTests/Fixtures/duel-agreement-v1.json` is the actual
scheduled response from a new rollback-only run of the Phase 1A local example,
using fictional actors. No fixture actors, event or admission change were
committed by that run. This fixture is DTO evidence, not a future dated race
catalog entry.

## Authenticated native-to-local-HTTP acceptance — September 4, 2026

**Phase 1B is accepted locally.** The remaining HTTP smoke passed on iPhone 17e
/ iOS 26.5, Debug, without `--fixture-mode`. The test uses the production
`SupabaseDuelClient(client:enabled:)`, `SupabaseAuthClient`,
`SupabaseFriendshipsClient`, `AppModel` auth observation, `DuelStore`, and
`FilePendingDuelRequestStore`. No RPC closure or fixture backend substitutes
for the native network path.

The local controller creates two random fictional `example.invalid` Auth
accounts, admits only those actors, and curates a fictional 5K seven days ahead
in `America/Chicago`. The native friendship client requests and explicitly
accepts their friendship. This repository disables password/email login, so
the initial password attempt failed before any duel mutation. The corrected
controller generates one-use local Auth links; the Swift SDK verifies them
and obtains real actor sessions. No email is sent and the checked-in Auth
configuration stays unchanged. The service key stays in the host controller;
the native client receives only the local publishable key and actor session.

Consent actions are driven by native XCTest through the same store methods
used by the UI, with explicit creator consent and invitee policy/digest
acceptance. The creator's confirmed receipt ID is asserted. Five screenshots
render the actual `DuelDetailView` with HTTP data: creator invitation, invitee
before acceptance, both scheduled perspectives, and cancelled history. Earlier
fixture UI journeys separately cover receipt navigation, consent controls,
scrolling and accessibility sizing.

| Authenticated check | Observed result |
| --- | --- |
| A creates and receives confirmation | One invitation; creator consent saved; `lastConfirmedID` names the returned agreement; pending file cleared |
| B reviews and explicitly accepts | Full typed terms, digest and participant rows match A; reads leave B unconsented; explicit accept schedules the duel |
| Both see scheduled agreement | Identical terms and both consent timestamps, policy versions and digests |
| Account switching | Real sign-out/sign-in events clear agreements, friends, catalog, pending request, freshness, receipt ID and errors; B cannot recover A's file |
| Delayed HTTP responses | Responses held after PostgreSQL reads are rejected by the production adapter and discarded by the native store after account changes |
| Lost creation response | PostgreSQL commits; controller replaces its successful response with HTTP 504; reconstructed file-backed store recovers the exact request after switching accounts and closing admission |
| Lost acceptance response | B's explicit acceptance commits, its response is lost, refresh does not resend it, and exact recovery works after gate-off |
| No duplicate mutation | Lost create and accept are each sent three times with the same key and payload; only one request record per mutation is committed |
| Changed payload under an existing key | HTTP 400 / native `invalidTerms`; original agreement and consents retained |
| Gate-off | New create and accept return HTTP 403 / native `accessDenied`; history and committed retries still return HTTP 200 |
| Safe cancellation | Creator and accepted invitee each cancel before start with admission off; both histories retain the agreed terms and consents |
| Final database state | Two cancelled agreements, four consent rows, six committed requests, zero open slots, admission off, empty allowlist |
| Cleanup | Fictional accounts banned, passwords rotated, sessions/refresh tokens revoked, temporary manifest removed; immutable agreement history retained |

The passing native smoke result is
`test_sim_2026-09-05T02-31-21-879Z_pid48500_2287b561.xcresult`, under
`~/Library/Developer/XcodeBuildMCP/workspaces/GameTime-7b9ccaa5aefb/result-bundles/`.
The full native unit regression run then passed **272 tests, 0 failed, 1
skipped** in `test_sim_2026-09-05T02-33-01-107Z_pid48500_0a618504.xcresult`.
That skip is this opt-in smoke after its controller and credentials were
cleaned up; the dedicated authenticated run passed with no skips. No production
client or database defect was exposed. Only the local acceptance harness needed
the Auth setup correction; no schema migration or shipping sign-in change was
needed. Prior Debug/Staging/Release and fixture UI evidence above remains dated
as originally recorded.

The final single-command runner also passed **1 test, 0 failures**, with
automatic cleanup, in `tmp/duel-native-e280ec6c.xcresult` (September 4,
21:37 CDT). Its report records event `be389474-c5f2-4abf-86ec-20363e06935e`,
starting September 12 at `02:36:32.024230Z` and ending at
`04:36:32.024232Z` (September 11 in Chicago). Post-cleanup session and refresh
token counts are both zero. Runner verification corrected Xcode's
case-sensitive simulator UUID handling before this final passing run. The
earlier failed runner attempt and password-login attempt are not counted as
passing acceptance.

### Reproduce the authenticated smoke

Start the disposable local stack with the Phase 1A migration applied. Its duel
admission must already be off with an empty allowlist; the runner refuses to
replace another experiment's active admission. Use an available iOS simulator
UUID (this run used `58877227-2C84-45DF-BD1D-4E01C26A00A8`). From the repository:

```sh
umask 077
supabase status -o json > /tmp/gametime-duel-local-status.json
python3 scripts/duel-native-local-smoke.py \
  --status-file /tmp/gametime-duel-local-status.json \
  --simulator 58877227-2C84-45DF-BD1D-4E01C26A00A8
```

The runner uses the exact loopback database/API addresses, binds its HTTP
controller only to `127.0.0.1:54329`, and builds Debug with that loopback URL
and the local publishable key. It never edits `LocalOverrides.xcconfig`, Staging,
Release or hosted settings. Output is under the gitignored `tmp/` directory:
`duel-native-<run>.xcresult`, its build log, and `duel-native-smoke-report.json`
with request IDs/hashes, upstream statuses, counts and cleanup state. Auth
tokens, service keys and response bodies are not included in the report.

For XcodeBuildMCP, omit `--simulator` to keep the controller running, then run
`GameTimeTests/DuelNativeLocalSmokeTests` in Debug with parallel testing off,
`CODE_SIGNING_ALLOWED=NO`, `SUPABASE_URL=http://127.0.0.1:54329`, and the local
`SUPABASE_PUBLISHABLE_KEY` from the status file. Stop the controller with Ctrl-C
afterward. The single-command mode cleans up automatically, including after a
test failure. A forced process kill cannot execute cleanup; do not use it as
the normal shutdown procedure. Do not commit the status file or manifest.

VoiceOver traversal, physical-device acceptance, Apple sign-in and hosted
operation remain unverified by this local smoke.

## Phase 2 boundary

No activation, result scoring, proof upload/provider, result notice delivery,
review filing, post-start withdrawal action, rematch, expiry worker, payment
setup or payout is implemented. Reading an expired invitation reports its
state; the client never invents a result or treats missing proof as a loss.
The local Phase 1B dependency is now satisfied. At this acceptance, Phase 2 had
not started. Follow-up: [Phase 2(a)'s pure evaluator](DUEL_SCORING_V1_ACCEPTANCE.md)
is now implemented; operational result processing remains open. Phase 2's
scope remains in [PLAN.md](../PLAN.md), preserving these immutable consents and
separate request envelopes. Local acceptance does not open hosted or live-money
admission.
