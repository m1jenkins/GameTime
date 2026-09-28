# One refused Health upload no longer stops Health saving

Change on `claude/health-refused-upload`, from `3d868c7`, September 27, 2026,
merged into `main` as `dff4be9`. Nothing was pushed. The Edge Function change is
live on `gametime-p11b`; see [Hosted state](#hosted-state-september-27).
No other hosted setting changed.

## Reproduced before any change

Three tests failed against the unchanged code. Their stubbed transport throws
`.refused`, which is what the client produced for every HTTP 422:

| Test | Failure on `3d868c7` |
| --- | --- |
| `ChallengeHealthUploadClientTests/refusedAccountUploadDoesNotBlockAnotherChallenge()` | A second challenge's upload failed with the first one's `.refused` |
| `ChallengeHealthTransportCoordinatorTests/oneFailedAccountOnlyRecordDoesNotStopTheOthers()` | Recovery threw `.refused` at the first account-mode record and delivered nothing after it |
| `ChallengeHealthFlowStoreTests.testRefusedAccountUploadDoesNotBlockOtherChallengesOrReadiness()` | The other challenge saved nothing and showed "We couldn’t send your saved activity. Try Refresh when you’re connected."; a new goal's activity check ended `temporarilyUnavailable`, so consent stayed blocked |

The server half of the chain is in source and pinned by pgTAP that passed in CI
on `b86a006`. No migration or SQL test has changed since. The ingest RPC returns
a saved request's response before any rule. It raises
`challenge_real_health_binding_invalid` for status, membership or frozen-term
mismatches, and `challenge_invalid_real_health_revision` for an out-of-order
revision or one past the end +24h/+48h cutoffs (518, 520, and 527 received
leaderboard). The Edge Function maps both to 422. Only account-deletion cleanup
clears the saved journal.

## How the client tells permanent from temporary

The Edge Function adds `reason` to a 422 only for refusals raised after the
replay found nothing. None of them can reverse for an update the app builds,
because the app sends one only while its challenge is scheduled, active or
syncing:

| RPC refusal (22023) | `reason` | Why it can't reverse |
| --- | --- | --- |
| `challenge_real_health_binding_invalid` | `challenge_closed` | Status only moves forward past `syncing`. Exits, agreement versions, digests and frozen windows don't revert. Only a community lobby still `published_open` after its start could begin taking updates later, and the app never builds an update for one |
| `challenge_invalid_real_health_revision` | `revision_not_accepted` | The latest revision and observation only grow, and the cutoff only passes. "Too early" can't occur for a request that passed the earlier timestamp checks |
| `challenge_request_conflict` | `request_conflict` | The request ID already holds other bytes |

Everything else carries no reason and stays saved for an exact retry. That
includes an early device clock (`challenge_invalid_real_health_request`),
serialization failures (40001), other 23xxx codes, 401, 403 and 5xx, and a 422
from the Edge Function deployed today.

## What changed

- **Independence.** Account-mode records carry no device counter, so the
  coordinator delivers each one on its own. A sign-in change, cancellation or
  lost connection (`URLError`) ends the pass, so a dead network doesn't hold the
  lease through one timeout after another. Signed (App Attest) records keep
  counter order and first-failure blocking.
- **Activity checks stay bounded.** A waiting activity check still goes before a
  new one, as before, so refused checks can't pile up. An upload never holds one
  back. Both journals' `enqueue` now refuse what their restore would reject: a
  17th activity check, or a retired upload's request ID.
- **Retirement.** An account-mode request refused with a reason moves from
  `pending` to a bounded `retired` list (32 records) in the same protected
  journal. It keeps its exact bytes, reason and time. The session and epoch are
  checked first, as for an acknowledgement. The head is unchanged. Older
  journals restore without the key.
- **Revision conflict.** Saved bytes are never changed or signed again.
  `refreshOne` reads the server's latest revision and builds a fresh update
  through the existing `confirmedServerRevision` reconcile. A new update
  refused by a race gets one more bounded pass.
- **Per challenge.** A challenge whose own update is still waiting shows the
  existing "We haven’t confirmed this update…" copy. Every other challenge and
  activity check proceeds. A saved update the challenge can no longer take shows
  **Last update not saved** and the new COPY.md sentence, with no Refresh or
  connection advice. Both states record the challenge's frozen binding, so they
  show on the first refresh after relaunch.
- A resubmitted saved request reports its own recovery result in both clients,
  because recovery no longer throws for another record's failure.

## Independent review

A review agent read the diff and the composed SQL. It confirmed that all three
mapped names are raised only after the replay lookup, and that nothing the RPC
calls earlier raises them. It also confirmed that retirement is fenced like
acknowledgement, and that signed recovery and the Personal writers are
unchanged. It found one regression, which is now fixed and tested: unbounded
activity checks could overflow the readiness journal and lock every writer out.
It also found three smaller points, all addressed:

- timeouts added up while the lease was held;
- the "never reverses" wording was too broad;
- the waiting state was invisible after a relaunch.

## Checks performed

| Check | Result |
| --- | --- |
| Four Health suites (upload, readiness, coordinator, flow) | 51/51 passed, including the three reproductions and the unchanged signed-request rules. The upload, readiness and coordinator suites and the four new flow tests (34 tests) passed 5 of 5 repeated runs |
| `LiveDesignUITests`, new copy check plus the Settings/Health test | 2/2 passed. The screenshot shows the new card and no Refresh advice |
| Full `GameTimeTests` | 645 passed, 0 failed, 11 skipped (each skip needs a local stack or smoke controller) |
| `swift test --package-path ios/GameTimeCore` | 187 Swift Testing tests in 20 suites and 3 XCTest, all passed |
| `deno test --allow-env` in `supabase/functions` | 950 passed. `fmt`, `lint` and `check` are clean on changed files |
| `GameTime-Staging` and `GameTime-TestFlight` simulator builds | Both succeeded on the final code. `scripts/check-iphone-product.py` passed on both apps |
| pgTAP 518/520 | Not run, because no SQL changed. CI pgTAP passed on `b86a006` with identical SQL |

## Hosted state, September 27

- **Version 8 of `ingest-challenge-health`** went live on `gametime-p11b`
  (`lyushhqoednheqwzsmxh`) at 22:23:14 UTC. It was deployed outside the session
  that wrote this change, nine minutes after `c687dde`, and was already live
  when the owner's deploy request was checked.
- **Same code as `main`:** all 12 deployed files are byte-identical to
  `c687dde` and to `main` at `dff4be9`. `verify_jwt` stays off, as in
  `config.toml`.
- **Boots cleanly:** the function logs show an unauthenticated POST refused
  with 401 six seconds after the deploy.
- **Already needed:** since 16:35:14 UTC on September 26, every upload from the
  one enrolled account's phone has been refused as
  `challenge_real_health_binding_invalid`. That is more than 90 attempts,
  including seven after the deploy. The last accepted upload was three seconds
  earlier. Version 8 answers these with `challenge_closed`.
- **Not fixed on the phone yet:** the installed build ignores `reason`, so the
  phone stays blocked until it runs a build with this change.
- The other seven functions are at the versions the
  [D144 receipt](2026-09-27-d144-hosted-state.md) recorded earlier that day.
  Migrations and settings weren't rechecked.

## Not done

- Installing a build with this change on the owner's phone is a separate
  device action.
- Signed App Attest records still block on a permanent refusal, as adopted. No
  current build uses that path for challenge Health. Extending retirement to
  them is an owner decision.
