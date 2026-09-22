# First private friends TestFlight

Owner-directed scope, September 22, 2026. [D142](../DECISIONS.md#d142-first-private-testflight-adds-friends-opens-apple-sign-up-and-ships-goals-first)
records the decisions. This document sets the phase order and the verified
starting state, and it lists the items that remain open. It is a plan, not
evidence that anything below exists. It does not authorize hosted mutation,
Apple provider changes, TestFlight submission, recruitment or money.

**Success means** two new people install GameTime, become friends, run a
challenge together, and see saved activity and results, with nobody
operating the system by hand.

## Build 1 scope

| Area | Build 1 | Later |
| --- | --- | --- |
| Testers | Fewer than 10 people the owner knows, invited to TestFlight by email only | Wider cohorts need a new decision |
| Sign-up | Any Apple account on `gametime-p11b`, after the 21+ question during account setup. Email, phone and anonymous sign-in stay off | — |
| Uploads | Account mode for every age-confirmed account. Every request records its verification mode, and the agreement copy says we don't run a device check | Revisit if a score looks fabricated, and before any real money |
| Friends | Requests, accept, silent decline, cancel, remove, block, unblock and report, all through versioned RPCs. Friends live under You, with requests and actions as Home action rows | The D134 shell is unchanged |
| Abuse protection | Request IDs, expected state, suspension checks, one daily request cap and a lookup rate limit. The owner reads the report queue | Decline cooldown, pending cap, friend-list cap |
| Challenges | Four friend goals; Personal Steps and Outdoor runs | Four D141 received-score leaderboards in the next build |
| Closed on the server | Community join, reusable-link issue and redeem, contacts import | Separate decisions |
| Stakes | Simulated and nonredeemable; settlement off | — |

## Verified starting state (September 22)

These facts come from source and receipts, and they shape each phase.

- **Friends block invites.** The challenge `invite` command requires
  `app.is_friend` (`supabase/migrations/20260908050105_challenge_policy_matrix_v1.sql:177`).
  No live screen can create a friendship.
  - Friendship writes are direct PostgREST table writes: the grant is at
    `20260724203000_identity_social_graph.sql:786`, the RLS policies at
    `555–590`, and the dormant client code at `SupabaseClients.swift:733–769`,
    which runs only behind `legacySocialRuntimeEnabled`, off by default.
  - Either party can delete a row, with no check on its current state.
  - Suspension is not checked, and there is no rate limit.
- **Block and report have gaps.** Both require some past shared challenge
  (`20260908050901_challenge_access_links_safety_v1.sql:108`, and block as
  redefined at `20260911143019…:187–206`).
  - No unblock command or iOS path exists.
  - `find_profile_by_handle` hides blocked people in both directions.
  - Blocking a co-participant exits them before finality, which can void a
    two-person challenge.
- **Membership rules**
  - Friendship is checked only at invite time. Unfriending leaves a lobby
    untouched.
  - Link redemption adds entrants with no friendship check (`…access_links_safety_v1.sql:78–86`).
  - Roster freeze runs admission and slot checks for every member
    (`…policy_matrix_v1.sql:194–199`), so one member at a limit fails the
    whole freeze.
  - A friend steps goal and a steps leaderboard collide on the same metric.
- **The trial guard**
  - `app.challenge_private_device_allowed_v1` returns true for everyone when the
    trial is off, and turning the trial off opens every real policy, community
    included.
  - Account mode additionally needs `not require_device_verification` and an
    enrolled row (`20260920164443_private_account_health_v1.sql:9–13`).
  - The only per-policy control is the immutable
    `challenge_real_health_policy_available_v1`
    (`20260920050238_challenge_exercise_credit_v2.sql:23–27`) plus the trial
    pair guard (`20260922150718`).
  - `challenge_real_health_runtime_v1` has only global flags.
- **Client configuration**
  - `privateHealthAccountMode` works only in Staging on the exact p11b host
    (`AppConfiguration.swift:52–55`), and it also drives `personalStepsOnly`
    (`AppShellView.swift:52`).
  - Release targets the historical backend with Stripe sandbox, and inherits
    `CHALLENGE_V1_ENABLED = NO`.
  - TestFlight needs its own configuration.
- **Age confirmation** exists only in the challenge-access sheet
  (`ChallengeV1EntryViews.swift:170–178`). The natural place for it is
  `LiveOnboardingView`.
- **Invite step** is a text field for an exact username
  (`ChallengeCreationInviteView.swift:130–158`). There is no friend picker and
  no contacts. Links show "not available yet".
- **Copy tests.** `GameTimeUITests.swift` still expects the retired `Today`
  tab, and `scripts/beta-native-smoke.py` does not run that suite. Put
  product-scoped copy checks in `ChallengeV1UITests` and `LiveDesignUITests`,
  and decide separately whether to repair or retire the old suite.
- **Hosted `gametime-p11b`**
  - `20260920162025` (the leaderboard migration) is unapplied, while the later
    `20260920164443` and `20260922150718` are applied.
  - Its ingest markers don't overlap with 164443's, so applying it late is
    safe for markers. It does rewrite `challenge_real_health_evaluate_v1`,
    `challenge_evaluate_policy_v1`, `challenge_policy_v1` and
    `challenge_mutate_unmetered_v1`.
  - Pushing it needs `--include-all`.
  - The checkout's CLI link and `supabase/staging-project-ref` point at the
    historical `jrkzdttophnmkxjoyioo`, so always pass the project ref explicitly.
  - Deployed functions: worker, snapshot, monitor, `attest-device` and
    `ingest-challenge-health`.
  - `delete-account` is not deployed. It needs the Apple client ID and a
    pre-generated client secret (`supabase/functions/delete-account/index.ts:28–31`),
    which Apple caps at 6 months.
- **Owner goals.** A September 21 readback found two scheduled
  `personal_steps_goal_v1` records on hosted.
  - The documented one, 4,703 steps over September 22–28: corrections close
    October 1 00:00 PDT, the provisional notice is due October 2, and review
    closes about October 4.
  - A September 22 device screenshot shows a second Steps goal for
    September 24–30. If that is the second record, its corrections close
    October 3, the provisional notice is due October 4, and review closes about
    October 6.

## Responsible-engagement review

Reviewed September 22 against [BUSINESS_MODEL.md](BUSINESS_MODEL.md#responsible-engagement-and-commercial-incentives).

- **What it increases**
  - Friend connections, challenge invitations, and return visits to act on
    Home rows.
  - Amounts stay simulated, so financial exposure does not rise.
  - Social pressure to join or to exercise can rise, so the controls below
    target pressure.
- **Controls adopted for build 1**
  - Every request is deliberate, by exact username. There are no suggestions,
    contact import, automatic sends or "people you may know".
  - Decline is silent: the request disappears with no notice to the sender.
  - Home rows show only actionable items: an incoming request, an accepted
    request, a pending invitation, or a challenge awaiting your agreement with
    its factual deadline. Rows leave once handled.
  - There is no badge count, no push and no friend count shown as status.
  - Friend lists and freeze failures reveal no other person's challenges.
  - Block, unblock, report and remove use neutral wording and are easy to find
    under You.
  - Analytics stay off, and neither health data nor results feed suggestions
    or targeting.
- **Open item for the owner.** The 30-day decline cooldown is deferred, so a
  declined person can be sent the same request again, up to the daily cap.
  BUSINESS_MODEL rules out "repeated prompting after decline". Before Phase 2
  closes, the owner either:
  - accepts block as the remedy for this under-10, invite-only cohort, or
  - adds a minimal re-request rule for a declined pair.

## Phases

### Phase 0 — land and record: complete

Landed the in-flight Personal Outdoor runs work:
- the chips
- the private-trial row-guard migration `20260922150718`, already applied on
  hosted, with its receipt
- the "Challenge locked in." post-save screen

Recorded:
- D142
- this plan
- updates to the planning pointers
- this engagement review
- `docs/COPY.md` glossary rows

The Phase 0 commits are listed in [WORKING_BASELINE.md](WORKING_BASELINE.md).

### Phase 1 — mocks (can run alongside Phase 2)

- **You › Friends:** accepted, incoming and sent lists, with empty, loading and
  offline states.
- **Add a friend:** by exact username, with a plain-text share of your own
  username.
- **Safety:** block, report and unblock.
- **Home action rows:** incoming request, request accepted, pending invitation,
  and awaiting agreement with "Agree before <date>".
- **Invite step:** a picker of accepted friends with inline add-friend,
  replacing the username field.
- **Onboarding:** a 21+ step in `LiveOnboardingView`, plus an early "you need
  an Apple Watch" note.
- **After a friend lobby saves:** replace "Challenge locked in." for open
  lobbies, because nobody has agreed yet. Say that the creator picks the
  roster and everyone agrees before the start.
- **Invite mock:** drop contacts and links, matching the native app.
- **Unchanged:** the locked Goal → Challenge → Friends flow is not reopened.

### Phase 2 — server (local; migrations and pgTAP)

- **RPCs:**
  `friend_{request,accept,decline,cancel,remove,block,unblock,report,list,lookup}_v1`,
  each with:
  - actor-bound request IDs
  - expected-state guards
  - suspension checks
  - one daily request cap
  - a lookup cap that reuses the invite command's 30-per-minute pattern
    (`20260912013929_challenge_private_community_v1.sql:431–433`)
  - a typed `incoming_request_exists` error
- **Write guard:** a project setting plus a row trigger on `friendships` and
  `blocks` that refuses writes unless an RPC set a transaction-local marker
  (the `app.challenge_real_health_command_v1` pattern). Historical tests keep
  their behavior.
- **Block and report:** extend them beyond co-participants, keeping the current
  consequences inside a shared challenge.
- **Per-policy allowlist:** a runtime allowlist with admission and row guards,
  also covering link issue and redeem and community join. It replaces the trial
  pair guard, and a status projection reports the allowed policies and the
  verification mode.
- **Account mode:** a setting independent of enrollment. Every request keeps
  its `verification_mode`.
- **pgTAP coverage:**
  - crossed, stale and retried mutations
  - suspension
  - both caps
  - block with no shared challenge
  - unblock
  - deletion
  - the allowlist, including links and community
  - an upgrade rehearsal that applies `20260920162025` after
    `20260920164443` and `20260922150718`, with an in-flight personal goal
    evaluated across it

### Phase 3 — native (after the mocks are approved)

- **`FriendsStore`,** modeled on `ChallengeV1Store`: actor generation checks, a
  per-account journal, and refresh on show. Idempotent request IDs are enough.
- **New screens:** Friends under You, Home rows, the invite-step picker, and
  the onboarding age step.
- **Server-driven policies:** replace `personalStepsOnly` and
  `privateHealthAccountMode` with the server-reported allowed policies.
- **Hide:** link controls, and legacy history on a failed load as well.
- **TestFlight configuration:** a new build configuration (production bundle,
  p11b, V1 on, account mode on, settlement off), with the host and bundle
  check extended rather than loosened.
- **Candidate check:** rework `scripts/check-beta-candidate.sh`.

### Phase 4 — local verification

- **Friend goals:** all four at 2 and 6 participants, plus the Personal goals,
  with clock control.
- **Membership and limits:**
  - a seventh member rejected
  - a member at a limit fails the freeze, with copy that reveals nothing
  - fresh consent after any change
- **Outcomes:**
  - cancellation when consent is incomplete
  - a void with fewer than two
  - corrections
- **Friends and closed features:** the friendship matrix; links and community
  refused by the server.
- **Accessibility and regressions:** VoiceOver, large text, and Personal
  regressions.
- **Full gate:** `scripts/weekly-local-verify.sh`.

### Phase 5 — hosted (explicit approval; after both owner goals are final)

- Read back both scheduled goals and the migration list.
- Deploy with `--project-ref lyushhqoednheqwzsmxh`: dry run first, then with
  `--include-all`.
- Deploy `delete-account` and record the client secret's renewal date.
- Add the production bundle to the Apple provider, and open Apple-only sign-up.
- Grant global support to the owner by name.
- Close dormant legacy grants.
- Confirm that Steps and outdoor distance still save.
- Settle whether the Free plan has a restorable backup and whether the project
  can pause.

### Phase 6 — TestFlight (explicit approval)

- **App Store Connect:** beta description, feedback email, privacy policy URL
  and terms.
- **Review notes:** the Apple Watch requirement, simulated stakes only, a
  reviewer account already friended with the owner, and a screen recording,
  since a reviewer can't agree without Watch data.
- **Testers:** email-invite fewer than 10.
- **Owner's own install:** the owner switches to the TestFlight build only
  after the Staging goals settle, then deletes Staging. Two builds uploading
  for one account can move a saved score backwards.
- **First cycle:** observe it through to the result. Include at least one
  Activity minutes goal and one timed-run goal.

A friend challenge needs about 8 days from creation to final (2-day lead,
1-day window, +48h corrections, provisional within +72h, +48h review).
Hosted work waits until both owner goals are final, around October 4–6, so the
earliest success is mid-to-late October.

## Open owner inputs

- Legal entity, jurisdiction and a monitored support inbox, for the privacy
  policy, terms and feedback email.
- Who renews the Apple client secret, and when.
- Confirm that the second scheduled goal is the September 24–30 Steps goal,
  which sets whether hosted work can start October 4 or October 6.
- The decline re-request rule (see the engagement review).
- Whether first-tester observation meets the finish line's human comprehension
  check, and whether legacy-shell replacement acceptance applies to this build.
  D142 leaves both unchanged.

## Logged, not in scope

- The fixture branch of `app.challenge_admit_v1` lost its age check when
  `20260920010824` rewrote it (lines 720–727; the earlier check was at
  `20260908050901…:36`). It is harmless while fixtures are off on hosted.
