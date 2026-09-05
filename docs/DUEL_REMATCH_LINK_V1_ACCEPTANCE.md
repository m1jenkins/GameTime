# Phase 2(e) — simulated rematches and private invitation links

**Accepted locally, September 5, 2026.** Implements the [Phase 2(d) handoff](DUEL_NATIVE_LIFECYCLE_V1_ACCEPTANCE.md#phase-2e-handoff).
This remains an opt-in local simulation. Hosted operation, universal-link domain
hosting, external delivery, organizer permissions, schedules and live money stay
outside this slice. The normal app remains Personal.

## Agreement and link boundary

The forward migration `20260905150210_duel_rematch_links_v1.sql` adds:

- `rematch_duel_v1`: either original participant can invite the same friend after
  a persisted final result. It requires a different event starting after the old
  event ends, within the existing future-event limit, fresh creator consent,
  current friendship, both active actors and admission. The recipient explicitly
  accepts the new digest through the unchanged acceptance RPC. The original
  result, terms, consents, requests and simulated return are untouched.
- Private `app.duel_rematches` links the new aggregate to its predecessor without
  changing the historical agreement format. The original per-person enrollment
  constraint and sorted pair locks prevent duplicate creator reservations.
  A simulated return is never used as a spendable balance.
- `issue_duel_link_v1` and `revoke_duel_link_v1` share the existing exact actor/key
  request namespace. An issuer can have one unrevoked token for an invitation;
  issuing a replacement revokes the previous token atomically. A committed retry
  returns its original receipt and cannot create or reactivate a token.
- `get_my_duel_link_v1` returns the creator's currently available link;
  `resolve_duel_link_v1` returns **only a challenge UUID**, only to the named
  invitee. Opening never accepts. No anonymous preview, raw proof, result,
  participant names, credentials or payment fields are present in the URL.

The local default expiry is the earlier of **24 hours from issue** and the
agreement's acceptance cutoff. Equality is too late. Revocation, acceptance,
closure, expiry, a block, removed friendship or deleted participant prevents
resolution. Revoking a link does not cancel the invitation already available
in the recipient's authenticated history; the UI says so and retains cancel.

All new entry points check a real active participant session after acquiring
pair locks, including exact recovery. This uses Phase 2(b)'s session helper;
Phase 1's active-profile check by itself does not prove the session remains
valid. No user metadata controls authorization. Private tables have RLS, no
client grants and guarded immutable history. Clock seams are private, function
search paths are empty and only the five intended public RPCs grant execution
to authenticated clients. Admission defaults off. Gate-off retains committed
recovery, safe revocation and existing authenticated invitation reads.

## Native behavior

**Challenge again** opens the existing full rule review for the same friend
and a fresh available race. Consent starts unchecked, and the receipt confirms
a new invitation. Each runner must agree again. All three new mutation types
use the existing actor-bound durable request envelope; refresh does not replay
writes and **Retry saved request** sends the exact original parameters.

A creator can create, share and turn off a link from their invitation. The
system share sheet is invoked only by a person's tap. This implementation uses
`gametime-duel://invitation/<opaque UUID>` in Debug/Staging. It has no public
landing page or associated-domain entitlement, and works with the opt-in app
installed. Release retains its original URL registrations and cannot route to
the duel UI; production duel clients remain restricted to selected loopback
endpoints. A hosted universal-link offering is separate work.

Only the untrusted locator persists across login/relaunch. No resolved agreement
or actor is persisted with it. The server decides who may resolve it. A wrong
account receives a generic explanation and can sign in as the intended friend.
In-flight reads are bound to the current account and destination. Account
changes synchronously clear resolved destinations and link/result content;
late replies cannot navigate another account. Opening another URL clears the
previous resolved destination. A successful open consumes the saved locator,
loads the authorized rules and leaves consent unchecked. Failed reads clear
cached links. All copy follows [COPY.md](COPY.md).

## Verification

| Check | Result |
| --- | --- |
| Rollback-only SQL boundary suite | 36 assertions passed: fresh consents, exact payloads, target-only resolution, expiry equality, block, cancellation, deleted recipient, session revocation, gate-off, private grants and no implicit acceptance |
| Real PostgreSQL transaction races | 8 assertions passed: one creator slot, same-request link issue, revoke versus resolve, accept versus resolve; every waiting session observed via `pg_blocking_pids` |
| Focused native unit suite | 34 passed, including 7 new rematch/link tests and all 27 retained agreement/lifecycle tests |
| Full portable regression | Passed: 59 database files / 2,650 assertions; 568 Deno tests; 103 portable Swift tests |
| Local lint and advisors | No schema errors or warning/error issues |
| Personal copy audit | Passed |
| Native UI | New rematch/link and URL-handler journeys passed; URL journey also passed at Accessibility XXXL / Reduce Motion; retained creation/recovery and normal Personal launch passed |
| Full native unit suite | 290 passed, 0 failed, 1 skipped (the opt-in HTTP test, separately passed) |
| Authenticated native HTTP | Passed with two real local Auth sessions and production adapter/store; details below |
| Debug / Staging / Release simulator builds | Passed without compiler warnings; built Debug/Staging contain the duel scheme and view, built Release contains neither |

The integration portable run preceded three additional rollback-only cancellation/deletion assertions; the final focused SQL run passed all 36.

The full database gate resets only the disposable local stack. Concurrency tests
commit only their fictional namespace and clean it up; all duel gates finish
off and the admission allowlist is empty. No hosted operation was performed.

The first SQL run exposed a trigger field lookup on the provenance table; the
shared guard now compares JSON fields safely. A revoked-session test then
exposed the difference between active-profile and active-session checks, and
the new boundary was tightened before acceptance. Those failed runs are not
passing evidence. Simulator runner launch attempts also intermittently failed
with a system “Busy / Application failed preflight checks” error before any
test ran. The initial rematch UI assertion needed an extra scroll because the
new explanation made the send button fall outside the visible form.

Reproduce the database/native checks with `./scripts/test-all.sh`, the
`DuelRematchLinkTests`, `DuelTests`, `DuelLifecycleTests`, and the rematch/link
journeys in `DuelUITests`. Fixture entry remains **You → Friend duels** with
`--fixture-mode --duels`; `--fixture-duel-final` supplies a completed predecessor,
and `--fixture-duel-link` supplies a named incoming invitation for the URL-handler
test. Fixtures are separate from authenticated transport and scoring evidence.

The Supabase changelog and official [database function permissions](https://supabase.com/docs/guides/database/functions)
and [RLS guidance](https://supabase.com/docs/guides/database/postgres/row-level-security)
were checked, along with Apple's [URL launch testing API](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/open(_:)).
No dependency upgrade was required.

## Authenticated local HTTP exercise and artifacts

The [existing loopback runner](../scripts/duel-native-local-smoke.py) now also
exercises rematch creation, link issue/read/resolve/revoke and the new recipient
consent using production Swift clients, durable files and real local Auth
sessions. Its controlled setup restores only its own fictional blocked
friendship; the app never automatically unblocks a real contact.

- A finalized historical fictional duel led to a different future event.
  The rematch response was deliberately lost, and the unchanged saved request
  recovered with admission off. Three successful HTTP sends under the same
  key produced one new aggregate with one fresh creator consent.
- Link issue also lost its response. Recovery returned the available link;
  opening it after signing out and switching to the named account loaded the
  new rules with consent still absent. Gate-off did not block this existing
  authenticated invitation read.
- The creator revoked the link with admission off. Replaying its old issue
  request did not revive the token. The recipient's later resolution returned
  HTTP 403. They subsequently consented through the explicit acceptance RPC;
  both new digests matched, and safe cancellation released both slots.
- Cleanup retained four fictional agreements, thirteen agreement requests and
  eight consents. Open slots, admission allowlist, sessions and refresh tokens
  were all zero. Admission, proof and lifecycle gates finished off. No email,
  external message, hosted mutation or money operation occurred.

Reproduce with the runner command in
[Phase 1B's authenticated smoke instructions](DUEL_NATIVE_V1_ACCEPTANCE.md#reproduce-the-authenticated-smoke).
The runner still refuses non-loopback endpoints and an already-open admission
gate. Its host-only service credential never enters the native app or report.

Evidence on iPhone 17e / iOS 26.5:

- Focused native: `test_sim_2026-09-05T15-15-45-797Z_pid37062_1ddc318e.xcresult`.
- New standard-size UI journeys: `test_sim_2026-09-05T15-27-52-112Z_pid37062_4b172551.xcresult`.
- Retained creation and Personal tests passed in
  `test_sim_2026-09-05T15-22-38-223Z_pid37062_027da392.xcresult`; its first rematch assertion failed, so the overall run was not accepted.
- Full native unit suite: `test_sim_2026-09-05T15-37-17-063Z_pid37062_e43fe83e.xcresult`.
  Its separate Accessibility XXXL UI test initially failed an offscreen-action
  assertion after successfully traversing the rules and reaching unchecked
  consent. The overall combined run failed. A second large-text attempt also needed an explicit scroll to the accept button. The final isolated run passed after each control was scrolled into view.
- Final Accessibility XXXL / Reduce Motion UI: `test_sim_2026-09-05T15-44-17-433Z_pid37062_83dcc88e.xcresult`.
- Authenticated HTTP: `tmp/duel-native-47d7ee7e.xcresult` and
  `tmp/duel-native-smoke-report.json`.

The `test_sim_*` bundles live under
`~/Library/Developer/XcodeBuildMCP/workspaces/GameTime-7b9ccaa5aefb/result-bundles/`.
Passing standard-size screenshots were inspected: the link's restriction,
expiry, revoke action and cancellation distinction wrap and remain readable;
URL-opened consent is unchecked and the accept button disabled.

## Checkpoint follow-up — September 5, 2026

The forward checkpoint migration now locks the caller’s matching Auth session
after pair locks and rechecks natural expiry after admission/agreement waits.
This closes the rematch/link wait race while preserving exact request identity,
consent and revocation semantics. The [checkpoint review](PHASE_3D_CHECKPOINT.md)
records fresh checks separately from the original acceptance above.

## Next work

Phase 3(a) is the next product slice: separate longer personal performance
commitment agreements, initially the proposed official 5K target. Independent
operator tooling, actual organizer sources, human reviewer operations,
retention decisions, VoiceOver traversal, physical devices, hosted pilot
rollout, external delivery and live payments remain separate gates. Nothing
here establishes demand or real-world proof accuracy.
