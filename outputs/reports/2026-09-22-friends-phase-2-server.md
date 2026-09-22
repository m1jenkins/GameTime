# Friends TestFlight Phase 2: local server

September 22, 2026. This is Phase 2 of the
[friends TestFlight plan](../../docs/FRIENDS_TESTFLIGHT_PLAN.md) under
[D142](../../DECISIONS.md#d142-first-private-testflight-adds-friends-opens-apple-sign-up-and-ships-goals-first):
migrations and pgTAP, local only. Nothing was applied to `gametime-p11b` or any
other hosted project, and nothing was pushed. Every new setting defaults to the
current behavior. The hosted values in this receipt are proposals for Phase 5.

## What changed

| File | Purpose |
| --- | --- |
| `supabase/migrations/20260922210000_friend_commands_v1.sql` | Friend commands, command journal, write guard |
| `supabase/migrations/20260922210100_challenge_policy_allowlist_v1.sql` | Per-policy allowlist, account mode, status projection |
| `supabase/tests/529_friend_commands.test.sql` | 88 assertions |
| `supabase/tests/530_challenge_policy_allowlist.test.sql` | 47 assertions |
| `supabase/tests/531_friend_commands_concurrency.test.sql` | 12 assertions, separate transactions over dblink |
| `supabase/tests/fixtures/friends-upgrade-{before,after}.inc` | Hosted-order upgrade rehearsal (14 assertions) |

## Friend commands

Every mutation takes an actor-bound request ID. An exact retry returns the
saved receipt. The same ID with a different payload gets
`friend_request_conflict`. Each command also expects a pair state and refuses
with `friend_state_changed` (55000) when the pair has moved on. Commands use
the challenge mutation session, so each one is signed in, bound to its
session, and serialized per actor. Pair commands then lock both profiles in
UUID order, which is how crossed requests serialize.

| RPC | Expects | Needs 21+, not suspended | Result |
| --- | --- | --- | --- |
| `friend_lookup_v1(username)` | — | yes | `{found, id, username, display_name, relation}`, with relation `none`, `incoming`, `outgoing`, `friends` or `self` |
| `friend_request_v1(id, subject)` | none | yes | `{"state":"outgoing"}` |
| `friend_accept_v1(id, subject)` | incoming | yes | `{"state":"friends"}` |
| `friend_decline_v1(id, subject)` | incoming | no | row deleted, `{"state":"none"}` |
| `friend_cancel_v1(id, subject)` | outgoing | no | row deleted |
| `friend_remove_v1(id, subject)` | friends | no | row deleted; shared challenges untouched |
| `friend_block_v1(id, subject)` | not already blocked | no | `{"state":"blocked"}` |
| `friend_unblock_v1(id, subject)` | blocked by you | no | `{"state":"none"}`; no friendship restored |
| `friend_report_v1(id, subject, reason)` | — | no | `{"saved":true}` |
| `friend_list_v1()` | — | no | `friends`, `incoming`, `outgoing`, `blocked` |

- **Hidden accounts.** Lookup, request and accept treat these accounts as
  absent:
  - blocked in either direction
  - deleted or inactive
  - suspended
  - never confirmed 21+
  Lookup answers `{"found":false}`, and request and accept refuse with
  `friend_unavailable`. The lists drop them too, except that the blocked list
  keeps everyone you blocked.
- **Lookup budget.** Lookup shares the invite command's `lookup` bucket, 30
  per minute. Over the limit it returns an error body
  (`friend_lookup_rate_limited`, status 429) instead of raising, so the counter
  commits. Only exact usernames match: no prefix search, no listing.
- **Daily request cap.** `friend_runtime_v1.daily_request_limit` defaults to
  **20 a day**, a proposed value. Only requests that are actually created count
  toward it. Over the cap you get `friend_request_limit`.
- **Block.** Block works for any active account. Inside a shared challenge it
  keeps the `challenge_block_v1` consequences. Challenge scopes lock first,
  then profiles, the block severs any friendship or request, and the safe tick
  exits both people from every unfinished shared challenge. A two-person
  challenge then voids or cancels, as it does today. The legacy
  `challenge_block_v1` and `challenge_report_v1` are unchanged.
- **Report.** Report works for any active account. It writes to
  `challenge_reports_v1`, the queue `challenge_support_reports_v1` already
  reads. It takes the same three reasons (`username`, `unwanted_contact`,
  `unsafe_behavior`) and the same 10-per-hour `reports` budget. Over the
  budget it refuses with `friend_rate_limited`. No free text is stored.
- **Write guard.** Setting `friend_runtime_v1.commands_only` refuses every
  write to `public.friendships` and `public.blocks` except three: those from a
  friend command, from the legacy challenge block, or from account deletion.
  Direct PostgREST writes are refused with `friend_command_required`. The
  default is off, so historical tests and fixtures keep working. The
  `friend_commands_v1` journal is always guarded.
- **Deletion.** Account deletion already removed friendships and blocks. A
  trigger on the profile tombstone now also removes the deleted account's own
  command journal.

Other error codes: `friend_age_required`, `friend_account_restricted`,
`friend_request_already_sent`, `friend_already_friends`,
`friend_incoming_request_exists` and `friend_invalid_request`.
`docs/COPY.md` has the sentence for the renamed incoming-request row. Phase 3
maps the rest, per COPY.md.

## Per-policy allowlist and account mode

- `challenge_policy_allowlist_v1` holds (policy, source) pairs. Check
  constraints require a known policy, an available source and a matching
  metric. The table is seeded with the private trial's two pairs, Personal
  Steps and Personal Outdoor runs. The trial's pair guard now reads this list,
  so the enabled trial behaves exactly as before, including its
  `challenge_private_trial_personal_steps_only` error.
- With `challenge_policy_runtime_v1.allowlist_enforced` on, the list applies
  to everyone, with or without the trial:
  - **New rows must name an allowed real pair:** lobbies, agreement consents,
    readiness, readiness requests and admissions. Refusals raise
    `challenge_policy_unavailable`.
  - **The fictional fixture path is closed**, at admission and at the lobby
    row.
  - **Community publication and joining are closed** unless
    `community_steps_goal_v1` is on the list.
  - **Link issue and redemption are refused** with
    `challenge_link_unavailable` unless `links_enabled` is on. Row guards
    also cover privileged writers.
  - **In-flight agreements keep saving.** Activity saved for an agreement
    already made is not checked against the list. A goal whose pair is
    removed keeps saving until it finishes.
- **Account mode.** `account_mode` lets any age-confirmed account that isn't
  suspended save activity without device verification, with or without trial
  enrollment. Every readiness and ingest request still records its
  `verification_mode`.
- **Status projection.** `challenge_availability_v1()` is for signed-in
  clients. It returns:
  - `restricted`
  - `admission`
  - `account_allowed`
  - `verification_mode`: `private_account` or `app_attest`
  - the allowed `policies`
  - `links` and `community`
  Phase 3 replaces the app's `personalStepsOnly` and `privateHealthAccountMode`
  with this.

**Found while testing.** The public friend-create command inserts its lobby
with no source, then sets the source in a follow-up update. Under enforcement,
the lobby guard allows that insert only while the real-health command marker is
on. The update is where the pair is checked. Test 530 creates an allowed friend
goal through the public command, and refuses a leaderboard, to cover this.

### Proposed hosted values for Phase 5 (not applied)

- **Friends:** `friend_runtime_v1.commands_only = true`, with the daily limit
  left at 20.
- **Policy runtime:** `allowlist_enforced = true`, `account_mode = true` and
  `links_enabled = false`.
- **Allowlist:** add the four friend goals: `friend_steps_goal_v1` with
  `apple_watch_steps_v1`, `friend_exercise_goal_v1` with
  `apple_watch_exercise_credit_v2`, `friend_distance_goal_v1` with
  `apple_workout_outdoor_distance_v1`, and `friend_timed_goal_v1` with
  `apple_workout_outdoor_timed_v1`.
- **Private trial:** turn it off only after the settings above are in place,
  so turning it off no longer opens every real policy.

## Checks

All runs used one disposable local stack. It was built from a copy of the
tracked `supabase/` inputs in the session scratch directory, with project ID
`gametime-friends-p2`, ports 57530–57539 and its own Docker network
(`10.231.57.0/24`, created with an explicit subnet because Docker's default
pools were exhausted by older networks, which were left alone). No other
checkout's stack was reset or reused.

- **Baseline** (98 migrations, latest `20260922181912`): 111 files, 5,058
  assertions, all passing.
- **With both migrations, before the new tests:** the same 111 files and
  5,058 assertions passed.
- **Full suite** (100 migrations, latest `20260922210100`): 114 files, 5,205
  assertions, all passing. That is the baseline plus 88 + 47 + 12.
- **Hosted-order rehearsal:**
  1. The stack was rebuilt with 96 migrations, the latest `20260922150718`,
     leaving out `20260920162025`, `20260922181912` and both new migrations.
     That matches `gametime-p11b`.
  2. `friends-upgrade-before.inc` set the private trial up as on hosted and
     committed a Personal Steps goal: 4,703 steps, Sep 24–30, $20 simulated.
     It started the goal and saved one update, all without device proof.
  3. `supabase migration up --include-all` then applied `20260920162025`,
     `20260922181912`, `20260922210000` and `20260922210100` in that order.
  4. `friends-upgrade-after.inc` passed 14 assertions:
     - status, revision, agreement digest, terms, saved facts and evaluation
       are unchanged across the upgrade
     - a later update saved, and both requests record `private_account`
     - after the deadlines the goal reached review, scored as met, with the
       full $20 simulated returned
     - the status projection shows the trial's two pairs
     - the trial still refuses friend challenges
     - the friend commands are callable
  Without `--include-all`, `migration up` applied nothing.
- **Concurrency.** Test 531 commits fictional rows, runs each race in two
  real transactions and deletes the rows afterwards. After the run, a query
  found zero leftover rows. A first attempt failed at setup and committed 12
  fictional users on the disposable stack. They were deleted with the test's
  own cleanup statements before the passing run.

## Open items

- **Decline and re-requesting (owner decision; the plan says it's due before
  Phase 2 closes).** As planned, decline deletes the request, so the sender can
  send it again, up to the daily cap. Deleting also removes it from the
  sender's "Requests you sent" list. Nobody is notified, but a watchful sender
  can infer a decline. The minimal re-request rule would fix both: keep a
  declined request hidden from the recipient while the sender keeps seeing it
  as sent. The other option is to accept block as the remedy for this cohort.
- **Stale block and unblock.** A block of someone you already blocked, or an
  unblock of someone you haven't, is refused as stale rather than treated as
  success. That follows the plan's expected-state rule.
- **Legacy direct grants.** `find_profile_by_handle` and the direct table
  grants are unchanged. `commands_only` covers writes. Closing the dormant
  grants is Phase 5 work.
- **Native work.** No native, Edge function or copy change beyond the one
  COPY.md code rename. Phase 3 maps the new codes.
