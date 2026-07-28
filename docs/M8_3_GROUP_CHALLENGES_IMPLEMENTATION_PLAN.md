# M8.3 group challenges implementation plan

> Planning baseline: 2026-07-28.
>
> This plan turns the existing one-to-one duel product slice into a two-to-four
> person challenge product without changing the contest, scoring, privacy, or
> pledge rules already fixed in `DECISIONS.md`. It is a forward plan, not a claim
> that group challenges are implemented.

## Outcome

GameTime uses **Challenge** as the user-facing product noun. A challenge has two
to four accepted participants in the first product release. A two-person
challenge may still be presented as a **Duel** and keep the rope visualization;
a challenge with three or four participants uses provisional ranked standings.

The complete slice lets an author:

1. select one to three accepted friends;
2. review the complete immutable roster, participant ceiling, terms, and personal
   pledge exposure;
3. submit one atomic, restart-safe request;
4. see invitation and acceptance progress before the challenge starts;
5. enter a two-person rope or a three-to-four-person provisional leaderboard
   after activation; and
6. see a final ranked result and the resulting per-loser donation obligations
   after finalization.

## Agreed product rules

1. **Challenge is the container.** Use `Challenges`, `New challenge`, `Start a
   challenge`, and `Challenge details` across navigation and general copy.
   `Duel` is an optional two-person format label, not the core object.
2. **The first client cap is four accepted participants.** Creation selects one
   to three invitees and sends `max_participants = invitee_ids.count + 1`.
   The database's existing 20-person ceiling remains unchanged for future
   formats.
3. **This is free-for-all, not teams.** No team assignment, team scoring, or
   shared team charity is added.
4. **Selecting several friends does not create a persistent group.** Existing
   friendships remain the invitation boundary. `group_id` stays independent and
   nil for this flow.
5. **The initial selected roster is the V1 roster ceiling.** M8.3 does not add a
   post-creation “invite more” surface. If at least two people have accepted at
   `starts_at`, the existing activation worker opens the challenge and lapses
   outstanding invitations. Otherwise it cancels with
   `insufficient_participants`.
6. **Exposure is per person, not multiplied for one loser.** In a four-person
   challenge with a $10 stake, each loser owes at most $10 and one winner can
   produce three $10 obligations to the winner's selected charity.
7. **Live order is provisional.** It is a presentation ordering, not a predicted
   winner. Qualification against the target and the declared tie-break decide
   the result.
8. **No live data is invented.** Fixture standings may demonstrate every state,
   but a live build renders an explicit unavailable/syncing state until M7's
   canonical D77 standings response exists.

## Existing foundation to preserve

- `contests.max_participants` already models both duels and group contests.
- `public.create_contest_with_invites_v1(...)` already accepts a bounded UUID
  array, canonicalizes its order, locks the complete actor set, creates every
  invitation atomically, and binds the payload to the caller's request UUID.
- The author is accepted at creation. Invitees individually accept with their
  frozen timezone and charity.
- Activation already requires two accepted participants and lapses outstanding
  invitations.
- D4 keeps every participant's exposure capped at the stake and produces one
  obligation for each loser.
- D51 scores qualification against the challenge terms; highest raw progress
  alone does not win.
- D77 limits live and final standings to accepted participants and requires
  provisional labeling and phase-aware redaction.
- M8.2a saves the exact reviewed request before the first network attempt and
  permits only explicit same-request recovery after an ambiguous result.
- Release contest mutations remain locked until the existing App Attest and
  release gates are closed.

## Non-goals

- persistent social groups or a group feed;
- public challenges, leagues, matchmaking, or invitations outside the accepted
  friendship graph;
- more than four accepted participants in the first client;
- team-vs-team scoring;
- pairwise round-robin pledges;
- post-creation roster expansion or replacement invitations;
- changing the scoring engine, tie-break semantics, activation quorum, or
  settlement exposure;
- fabricating live standings from local HealthKit data;
- unlocking Release mutations, TestFlight, or production deployment.

## Delivery slices

### M8.3a — Challenge terminology, creation, and durable submission

This slice can proceed on the current backend contract.

#### Domain model

- Replace the one-person `DuelDraft.inviteeID` with an ordered, unique
  `ChallengeDraft.inviteeIDs`.
- Introduce `ChallengeTerms` with:
  - the existing request UUID and immutable terms;
  - one to three unique invitee UUIDs;
  - `maxParticipants`, validated as exactly `inviteeIDs.count + 1` for this
    product flow; and
  - canonical millisecond timestamps.
- Canonicalize invitee UUIDs into a stable order before review, persistence, and
  RPC encoding. Reject duplicates, the active actor, missing invitees, and more
  than three invitees.
- Rename client protocols and mutation methods from duel-specific names to
  challenge names while leaving the server's neutral `contest` vocabulary
  intact.
- Extend `ContestCard` to decode `max_participants`. Use that value, not a client
  guess, to choose two-person versus group presentation.
- Keep a computed `isDuel` convenience only where the two-person visual needs it.

#### Restart-safe compatibility

- Replace `PendingDuelSubmission` with `PendingChallengeSubmission`, but preserve
  the current per-actor file location so an app update does not orphan a saved
  request.
- Advance the protected-store envelope from version 1 to version 2.
- Decode version 1 into a two-person `ChallengeTerms` value with the original
  invitee, `maxParticipants = 2`, unchanged request UUID, and unchanged
  timestamps.
- Do not rewrite a version 1 file merely because it was read. The first valid
  monotonic update may atomically replace it with version 2.
- Preserve the existing owner isolation, complete file protection, backup
  exclusion, conflict checks, warned local-only discard, and no-automatic-retry
  behavior.
- Treat any roster, ceiling, or immutable-term change under the same request UUID
  as a conflict. A saved group request must retry with the exact reviewed UUID
  set.

#### Creation UI

- Rename the tab and general surfaces from Duels to Challenges.
- Rename the sheet and navigation title to `New challenge`.
- Change the `Who` card to multi-select accepted friends:
  - one to three selections;
  - visible check state and initials;
  - selected count such as `You + 3 friends`;
  - an accessible maximum-state explanation; and
  - no selection based on color alone.
- Keep `Invite` as navigation to Friends; do not allow direct challenge
  invitations by handle.
- Keep the current metric, cadence, target, duration, stake, charity, and
  tie-break controls.
- Change stake copy to make personal exposure explicit:
  - author editor: `$10 each`;
  - review: `Your maximum: $10`;
  - four-person explanation: `If one person wins, each of the other three
    donates $10 to the winner's charity`.
- Change the tie copy for `both_donate` from `Both pledge` to
  `Everyone donates`.

#### Immutable review

- Replace `Opponent` with `Players`.
- Show the author plus every selected friend, the participant ceiling, and the
  total number of possible loser obligations.
- Change `Neither of you can move the target` to
  `No one can change these terms after you send them`.
- Keep the request UUID visible in the retry review and preserve every existing
  immutable-term row.
- Submit one call to the existing
  `public.create_contest_with_invites_v1(...)` with the complete UUID array and
  exact ceiling.

#### M8.3a completion criteria

- One-, two-, and three-invitee drafts validate and encode deterministically.
- The complete selected roster survives force-quit and explicit retry.
- A version 1 saved duel still retries the identical old server payload.
- Changed roster retry is rejected locally and by the server.
- A three-invitee creation produces exactly one contest, one accepted author,
  three invited participants, and one private request record.
- The two-person creation path remains functional and is presented as a
  challenge with an optional Duel format label.

### M8.3b — Pending roster and invitation experience

This slice adds a privacy-bounded roster summary. It does not expose live
standings.

#### Backend read surface

- Add a versioned, caller-bounded challenge summary RPC rather than broadening
  table access or joining profiles client-side.
- Return only the fields needed by the product:
  - contest ID and `max_participants`;
  - the caller's participant status;
  - accepted, invited, declined, withdrawn, and lapsed counts;
  - the author's minimum profile card;
  - minimum profile cards for accepted participants when the caller is already
    accepted; and
  - no standings, integrity detail, raw evidence, charity choice, timezone, or
    nonparticipant data.
- Before an invitee accepts, disclose the author, terms, maximum participant
  count, and aggregate acceptance count. Do not reveal other pending invitee
  identities.
- After acceptance, disclose the accepted roster's minimum profile cards.
  Pending invitees remain aggregate slots, not named people.
- Preserve access to accepted challenge history after a later block or profile
  pseudonymization as required by D77/D81.
- Implement the RPC with explicit `REVOKE`/`GRANT`, an empty `search_path`,
  active-caller enforcement, stale-JWT denial, and pgTAP coverage. Do not depend
  on automatic Data API exposure defaults.

#### Pending and invitation UI

- Challenge list cards show:
  - `3 of 4 accepted`;
  - avatar stack for accepted participants;
  - anonymous pending slots;
  - start time; and
  - an explicit `Starts with whoever has accepted` explanation.
- Invitation review shows:
  - `Marcus challenged you`;
  - `Up to 4 players`;
  - `2 accepted`;
  - the immutable terms;
  - `Your maximum: $10`; and
  - the caller's charity selection.
- Replace two-person phrases such as `both of you`, `opponent`, and
  `their money` with roster-safe copy.
- Keep decline and accept individually scoped. One invitee's response must not
  optimistically change another invitee.
- Keep Today useful before activation with a compact accepted-count card, not a
  fake rope or leaderboard.

#### M8.3b completion criteria

- Invited, accepted, declined, lapsed, blocked, tombstoned, stale-JWT,
  cross-contest, and outsider access matrices pass in pgTAP.
- An unaccepted invitee cannot enumerate other invitees.
- An accepted participant sees only the accepted minimum roster and aggregate
  pending slots.
- A two-of-four acceptance opens at activation and lapses the other two invites.
- A one-of-four challenge cancels as insufficient and lapses every invite.
- Refresh and force-quit/relaunch reproduce the server roster summary exactly.

### M8.3c — Provisional group standings and final results

This slice is blocked until M7 supplies the canonical D77 standings and result
contracts. Fixture UI can be developed earlier, but live enablement cannot.

#### Client standing model

- Replace `DuelStanding` as the general model with `ChallengeStanding` containing
  a stable array of participant standings:
  - participant minimum profile card;
  - rank;
  - progress total or daily rate as supplied by the server;
  - qualification state;
  - reached-target time when the response phase permits it;
  - caller identity;
  - provisional/final phase and reason; and
  - only the integrity detail D77 permits for that caller and phase.
- Derive `myStanding`, `leader`, `rankText`, `gapToLeader`, and accessible summary
  from the server response.
- Keep a two-person adapter for `DuelRope` so Today, list, detail, and result all
  consume the same canonical participant array.
- Replace `theyPulled` activity with actor-specific events. Do not infer an actor
  when the server does not provide one.

#### Live presentation

- Two accepted participants keep the rope and its exact-value reveal.
- Three or four accepted participants use:
  - a compact ranked summary on Today and the Challenges list;
  - `Provisional standings` shown prominently;
  - `2nd of 4` and a human gap-to-leader line;
  - a full vertical leaderboard on detail;
  - qualification badges distinct from raw rank; and
  - a syncing/unavailable state when the canonical read is absent.
- Do not call the current leader the winner or describe live order as a predicted
  result.
- Keep Talk trash and Share, but generate roster-safe copy. The app still does
  not collect phone numbers or implement group messaging.

#### Final result and settlement UI

- Replace the two-column `VS` result with a final ranked field for group
  challenges.
- Support all explicit M7 outcomes:
  - one winner;
  - everyone-donates tie;
  - void; and
  - inconclusive.
- Show one obligation row per loser without combining them into a misleading
  group total.
- For the caller, state `You owe $10` or `You owe nothing` directly.
- Show the winner's nominated charity only when the final result contract permits
  it.
- Keep the user's W/L record per challenge. A group challenge contributes one
  win or one loss to that user, never one result per opponent.
- `Run it back` preselects the previous accepted roster only if those
  friendships are still eligible; otherwise it returns to an editable draft with
  unavailable people clearly removed.

#### M8.3c completion criteria

- Fixture and live-client shapes are identical.
- Live order is always labeled provisional and exposes no rival-only integrity
  detail.
- Two-person challenges still render the existing rope without a second scoring
  implementation.
- Three- and four-person challenges render correct rank, qualification, and
  accessibility output at supported Dynamic Type sizes.
- Final winner, everyone-donates, void, and inconclusive fixtures each have
  unit and UI coverage.
- Settlement copy matches the append-only M7 obligation rows exactly.

## Test plan

### PostgreSQL and RPC

- create with one, two, and three distinct eligible invitees;
- reject zero, duplicate, self, ineligible, blocked, tombstoned, and oversized
  invitee sets;
- prove one ineligible invitee rolls back the entire contest and request record;
- prove identical retry with the same set in a different array order returns the
  original contest;
- reject same request UUID with one changed invitee or ceiling;
- serialize concurrent copies of the same three-invitee request;
- activate with two, three, and four accepted participants;
- cancel with only the author accepted and lapse every outstanding invitation;
- challenge-summary RPC role, grant, stale-JWT, block, tombstone, outsider, and
  field-redaction matrices;
- preserve D77 standings access and D81 pseudonymized history behavior; and
- run the complete migration, pgTAP, lint, and advisor gates, not only the new
  test file.

### Swift unit tests

- draft selection, deselection, ordering, uniqueness, minimum, and maximum;
- stable RPC encoding and exact request equality;
- version 1 pending-duel decode into a two-person challenge;
- version 2 group round trip, monotonic attempts, corruption, owner mismatch,
  and changed-roster conflict;
- AppModel refresh partitions for pending, invited, active, done, and lapsed
  challenges;
- two-person rope adapter and group rank derivations;
- provisional versus final copy;
- group result and per-caller obligation copy; and
- router reset and account-transition isolation after the terminology rename.

### SwiftUI tests

- select one, two, and three friends and enforce the maximum;
- review all names, participant count, personal maximum, request UUID, and
  everyone-donates tie copy;
- resume a saved four-person request without automatic retry;
- accept and decline from group-safe invitation copy;
- render pending `2 of 4`, active two-person rope, active four-person
  provisional leaderboard, and every final outcome;
- preserve loading, empty, offline, stale, unavailable-standings, and Release
  lock states;
- verify VoiceOver rank summaries, button names, non-color selection state,
  Reduce Motion, and supported Dynamic Type layouts; and
- remove or intentionally alias every legacy `duel.*` accessibility identifier
  so tests do not silently stop exercising the renamed surface.

## Implementation sequence and review boundaries

1. **Decision and contract patch**
   - record Challenge terminology, the four-person client cap, exact initial
     ceiling, and dual visualization rule in `DECISIONS.md`;
   - update the milestone language in `PLAN.md`; and
   - add no functional code.
2. **Domain and persistence patch**
   - add `ChallengeDraft`/`ChallengeTerms`;
   - add version 1-to-2 protected-store compatibility;
   - update protocols, fixtures, and unit tests; and
   - make no visual redesign.
3. **Atomic group-creation patch**
   - send UUID arrays through the existing versioned RPC;
   - add the multi-select editor and immutable review;
   - update general user-facing terminology; and
   - add pgTAP, Swift, and UI coverage for exact group retry.
4. **Roster-summary patch**
   - create the bounded RPC through a new Supabase migration generated with
     `supabase migration new`;
   - add explicit privileges and redaction tests;
   - add pending and invitation roster UI; and
   - verify refresh/relaunch against staging.
5. **Provisional-standings patch**
   - consume M7's canonical D77 API;
   - add the shared participant-array model, duel adapter, and group
     leaderboard;
   - keep live enablement off until the M7 contract and privacy tests pass.
6. **Final-result patch**
   - consume M7 results and obligations;
   - add group result, settlement, receipt, and run-it-back behavior; and
   - cover winner, everyone-donates, void, and inconclusive outcomes.
7. **Staging acceptance and enablement**
   - complete the external proof below;
   - run complete CI and hosted Supabase advisors;
   - preserve Release locking; and
   - update `README.md`, `PLAN.md`, and the dated implementation-status evidence
     only with checks that actually ran.

Do not combine the standings or final-result patches with a provisional client
guess. If M7 is not ready, M8.3a and M8.3b may land independently with explicit
standings-unavailable UI.

## Staging acceptance

Use four controlled, Apple-authenticated staging users A, B, C, and D. Do not
record Apple IDs, tokens, keys, or private profile data.

1. Establish accepted friendships from A to B, C, and D.
2. As A, select B, C, and D and review every immutable term, the four-person
   ceiling, personal maximum, and request UUID.
3. Repeat the existing deliberate lost-response test. Relaunch A, inspect the
   saved four-person request, retry manually, and prove the server contains one
   contest, four participant rows, and one private request record.
4. Relaunch B, C, and D separately. Confirm each sees the same contest terms,
   maximum roster size, and aggregate acceptance count without seeing other
   pending invitee identities.
5. Accept from B, then force-quit and confirm A and B see `2 of 4 accepted`.
   Repeat for C and D until all four are accepted.
6. Force-quit and relaunch every app. Confirm the same contest UUID and accepted
   roster reload for all four users.
7. Observe scheduler activation on a committed row. Confirm the challenge becomes
   active for all four and no invitation remains open.
8. When the M7 standing API is available, confirm all four see the same
   provisional order and only the role/phase detail D77 permits.
9. When finalization is available, confirm all four see the same explicit result
   and each caller sees only their correct obligation.
10. Re-run a two-person challenge to prove the rope and old version 1 pending
    retry compatibility remain intact.

## Rollout and rollback

- Keep `create_contest_with_invites_v1` backward compatible. Do not replace or
  reinterpret an already-committed payload.
- Add new read RPCs under versioned names and explicit grants.
- Land group-safe read rendering before enabling group writes in any distributed
  build. An older client must not misrepresent a group challenge as a duel.
- During internal alpha, require every staging tester to update before group
  creation is enabled.
- Keep Release mutation locked under the existing configuration.
- If a client rollback is needed, disable group creation while preserving
  generic read-only challenge cards for already-created group contests.
- Database rollback must be forward-fix only after a migration is deployed.
  Never delete contest, participant, request, result, or obligation history to
  undo this feature.

## Definition of done

M8.3 is complete only when:

- Challenge terminology is consistent across signed-out, Today, Challenges,
  invitation, review, retry, detail, result, share, accessibility, and test copy;
- two-to-four-person creation is atomic and restart-safe;
- version 1 saved duels remain exactly retryable;
- pending roster disclosure passes its privacy and stale-session matrix;
- live group standings come only from M7's canonical D77 response and are
  prominently provisional;
- two-person challenges retain the rope;
- final group results and per-loser obligations match M7's persisted records;
- unit, UI, complete pgTAP, Deno, GameTimeCore, product, configuration,
  conformance, and CI gates pass;
- the four-user staging run is recorded; and
- no Release, TestFlight, production, App Attest, or settlement completion claim
  exceeds the evidence actually observed.
