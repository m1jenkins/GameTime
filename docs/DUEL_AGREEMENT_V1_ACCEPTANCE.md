# Phase 1A — simulated 5K duel agreement backend

September 4, 2026. Implemented and verified on the disposable local Supabase
stack only. [PLAN.md](../PLAN.md#phase-1a--local-simulated-duel-agreement-recommended-first-slice)
and [D123](../DECISIONS.md#d123-friend-duels-and-personal-performance-commitments-are-the-adopted-business-model)
define scope. The existing Personal app, Solo agreements and charity agreements
retain their original meanings. Pre-existing unrelated working-tree changes
were preserved; no historical migration was edited.

## Delivered files and boundaries

- [Forward migration](../supabase/migrations/20260904225326_duel_agreement_v1.sql):
  new policy, event, challenge, participant, private request, enrollment,
  runtime and allowlist records; versioned RPCs and a D81 deletion trigger.
- [Agreement tests](../supabase/tests/460_duel_agreement.test.sql): authenticated
  RLS, immutable consent, exact retries, cutoff boundaries, rollback, deletion,
  privacy, default-off state and safe exits.
- [Concurrency tests](../supabase/tests/461_duel_agreement_concurrency.test.sql):
  two actual worker sessions, observed PostgreSQL lock waits and both relevant
  lifecycle commit orders. Temporary worker helpers disappear on disconnect;
  committed fictional fixtures are removed with the established local-test
  cleanup convention.
- [Runnable example](../scripts/duel-agreement-example.sh) and its
  [SQL](../scripts/examples/duel-agreement.sql): fictional actors and event,
  participant RPCs, exact retry after gate-off, cancellation, then rollback.
- Implemented-state notes in [README](../README.md), [PLAN](../PLAN.md),
  [PROJECT_MEMORY](../PROJECT_MEMORY.md) and [BUSINESS_MODEL](BUSINESS_MODEL.md).

No Edge endpoint, iOS feature, workout ingestion, result/scoring implementation,
provider adapter, scheduler registration, hosted mutation, deployment,
publication or live money is included. Simulation creates no redeemable asset.
The new code does not write `contests`, `personal_challenge_terms`,
`solo_contracts`, legacy request ledgers, results or charity obligations.

## Agreement and request contract

Policy `duel-fixture-5k-v1` fixes source `fixture_official_5k_v1`, one outdoor
5,000 m event/course/wave, one attempt, no handicap, organizer chip timing at
whole-second precision, simulated USD 2,000 cents each and fee zero. Its frozen
specification also names result, review, cancellation, missing-proof, tie,
correction and finality rules. These are agreement facts for later phases,
not implemented scoring or settlement operations.

The event has explicit UTC instants and an IANA display zone. Both event
instants must fit within 30 elapsed days after creation, and the acceptance
cutoff must still be future. The cutoff is the earlier of creation + 72 hours
or start − 1 hour; equality is too late. End + 72 hours and end + 720 hours
are frozen as result and finality deadlines. Dispute and review periods are
168 elapsed hours from their future durable notice/filing events. Session
timezone and DST never reinterpret event instants or rewrite the digest.

`terms` is the canonical JSONB snapshot containing the policy specification,
version, both actors, event, creation instant and deadlines. `terms_digest` is
the lowercase hex SHA-256 of PostgreSQL's JSONB text serialization. Clients
carry the returned digest verbatim; they must not hash a Swift JSON rendering.
Creator consent is explicit `p_consent = true` at creation, with the selected
immutable event and expected policy version. The server records that consent
against the completed snapshot. Invitee consent must name the same policy
version and full snapshot digest. Each consent timestamp/digest is retained.

| Authenticated RPC | Parameters and result |
| --- | --- |
| `create_duel_v1` | `p_request_id uuid`, `p_invitee_id uuid`, `p_event_id uuid`, `p_expected_policy_version text`, `p_consent boolean`; returns agreement UUID |
| `accept_duel_v1` | `p_request_id uuid`, `p_challenge_id uuid`, `p_expected_policy_version text`, `p_expected_terms_digest text`; returns agreement UUID |
| `decline_duel_v1` | `p_request_id uuid`, `p_challenge_id uuid`; returns agreement UUID |
| `cancel_duel_v1` | `p_request_id uuid`, `p_challenge_id uuid`; returns agreement UUID |
| `get_duel_v1` | `p_challenge_id uuid`; returns agreement JSON with identical `terms`, digest, both participant records and `expiry_due` |
| `list_my_duels_v1` | `p_limit integer = 50` (1–100), optional paired `p_before timestamptz` / `p_before_id uuid`; returns detail JSON rows, descending creation instant and UUID |

Create/accept do not accept mode, amount, fee, metric, source, public title or
URL overrides. There is no overload or storage field for payment identifiers,
proof, routes or credentials. Event and policy tables are immutable and
readable by active authenticated actors for review before consent.

The user request key is `(actor_id, request_id)` across all new duel verbs.
The private ledger stores the exact typed JSONB payload and agreement UUID.
Changed payload, policy, event, digest or verb under a key fails with `22023`.
Committed recovery returns the same UUID before current gate, friendship,
deadline, slot or lifecycle checks; the active caller is always rechecked.
Fetch detail after recovery to obtain current state. A new key after acceptance
does not create another consent. Deleted callers cannot recover private access;
their active opponent can still recover their own committed request.

Lifecycle is `invited → scheduled`, or `invited → declined / expired /
cancelled`; `scheduled → cancelled` is allowed before the exact start instant.
The creator can cancel an invitation; either accepted runner can cancel a
scheduled duel. An unaccepted invitee uses decline. Closed rows remain history.

## Locking, admission and privacy

A creator reserves one duel slot; incoming invitations reserve no invitee slot.
Acceptance reserves the second slot. A partial unique enrollment index enforces
one unsettled duel per actor, independently of Personal and Solo. Deferred
aggregate checks enforce exactly two named rows, identical consent bindings,
scheduled state only with both consents, and open slots only for accepted
participants in open agreements. Failure at the final request insert rolls
back consent, state, enrollment and any opportunistic expiry.

Actor mutations lock both durable profiles in UUID order before agreement
rows. They recheck the caller after waiting, and production create/respond
sample wall clock after blocking locks. Expiry needs the creator profile and
agreement lock. The D81 bridge already holds the deleting profile, takes
agreement locks in UUID order and never requests an opponent profile lock.
It cancels pre-start invitations/scheduled agreements, releases both slots,
removes beta admission and preserves tombstoned agreement/consent history.
It leaves post-start agreements for Phase 2 finality rather than inventing
a result in this slice. Existing deletion logic is unchanged.

`app.duel_runtime` resets disabled and `app.duel_beta_allowlist` resets empty.
Both actors must be active, allowlisted, accepted friends and unblocked for a
new create/accept. Runtime row locking serializes admission changes. Gate-off
and allowlist removal preserve authenticated agreement history, exact committed
recovery, decline and safe pre-start cancellation.

The service-only setup boundary is:

- `set_duel_admission_v1(p_enabled boolean, p_actor_ids uuid[])`: atomically
  replaces the allowlist (maximum 100 active actors) and runtime switch.
- `curate_duel_fixture_event_v1(p_event_id uuid, p_starts_at timestamptz,
  p_ends_at timestamptz, p_display_timezone text)`: stores a fixed fictional
  event/course/wave. Reusing an event UUID with different facts is refused.

These RPCs check service authority and have explicit grants. Service callers
cannot directly write the tables, invent policies, impersonate participant
RPCs or execute private clock helpers. A fresh reset contains no dated event;
the example/tests curate it transactionally so fixtures never become stale
production invitations. No admission is enabled outside fictional local tests.

All eight tables have RLS. Only the pair can read an agreement or its consent
rows; requests, enrollment records and admission state are private with no
client table grants/policies. Only minimal agreement history remains readable
across a block or opponent deletion, so a participant can review and safely
cancel. Duels grant no extra profile visibility or social contact. A deleted
actor's unexpired JWT cannot read rows or use RPC recovery. No new data is
exposed to anonymous or unrelated callers.

`app.expire_duel_invitation_at_v1(id, clock)` is a private manual test seam,
not a service/API entry point. Reads report `expiry_due` without mutation.
New creation (and acceptance by a creator of another overdue invitation)
atomically expires the caller's overdue reservation before claiming a slot.
Phase 2 must add any operational expiry worker and independently approved
scheduling; none is registered here.

## Verification record

| Check | Result |
| --- | --- |
| Focused local pgTAP | 176 assertions across both duel suites passed |
| `./scripts/db-test.sh` | Clean local reset; 52 files / 2,086 assertions passed, including existing Personal, Solo, charity and deletion fixtures |
| `supabase db lint --local --schema public,app --level warning` | No schema errors |
| `supabase db advisors --local --type all --level info` | No warnings or errors; informational notices only |
| `bash scripts/duel-agreement-example.sh` | Identical digest, `scheduled`, exact recovery after gate-off, `cancelled`, constraint check and rollback succeeded |
| `git diff --check`, changed local Markdown links, shell syntax | Passed |

The duel advisor notices are intentional no-policy RLS on four private tables
with all direct grants revoked, and unused indexes on small test datasets.
The indexes cover foreign keys and retained actor history; they are retained.
The broader database's informational notices are pre-existing maintenance work.
Supabase CLI 2.109.1, current official RLS/function documentation and the
Supabase changelog were reviewed. No hosted advisor or hosted test was run.

The race matrix observes lock waits for distinct/exact/conflicting creation,
opposing invitations, competing invitee acceptances, acceptance versus cancel,
expiry and deletion, creation versus deletion, decline versus acceptance,
gate-off versus acceptance, and a public acceptance waiting past the cutoff.
Both relevant commit orders assert final state, retained consent and slot
conservation. The deterministic suite separately covers strict cutoff equality,
full-window limits, DST-independent terms, unauthorized actors/services,
blocked pairs, stale JWTs, immutable history, read-only expiry and injected
final-write rollback during both creation and acceptance.

No Xcode/UI, provider, hosted, physical-device or human-race acceptance was run:
none belongs to this backend-only slice. Local database tests do not establish
actual organizer proof, hosted operation or product demand.

## Phase 1B handoff

Implementation follow-up: [native flow and acceptance record](DUEL_NATIVE_V1_ACCEPTANCE.md).
The instructions below remain the Phase 1B contract.

Build the native fixture flow and typed `DuelModels`, `DuelClient`, store and
views against these RPCs. Keep the route unavailable in Release and treat
backend admission rejection as authoritative. Review the immutable event and
policy before creator consent; show the returned complete agreement, exact
cutoff, cancellation/review rules and simulation disclosure to both actors.
Use existing accepted-friend selection; no public discovery or share links yet.

Add a product-specific durable `PendingDuelRequestStore` envelope containing
actor UUID, request UUID, operation and its exact parameters. Never reuse
`PendingPersonalChallengeStore` or legacy contest envelopes. Persist before
sending, replay only that same actor/payload after an ambiguous response, then
fetch current detail. Account switching/deletion must not replay or display
another actor's private data. Retain the digest returned by the server.

SQLSTATEs are structured failures for client mapping: `42501` is access or
admission denial, `22023` invalid terms/request conflict, `23505` occupied duel
slot, and `55000` a closed/expired/already-accepted/started lifecycle boundary.
Do not render raw backend reason codes; follow [COPY.md](COPY.md). Refresh
detail for lifecycle failures and preserve ambiguous requests for exact recovery.
Do not treat a missing/late result as a loss.

Phase 1B verification remains DTO/envelope tests, two-actor fixture/local flows,
offline/ambiguous-response/account-switch recovery, accessibility/Dynamic Type,
and Debug/Staging/Release configuration tests. Preserve scoped Personal copy
assertions and existing navigation/history. Activation, post-start withdrawal,
proof/results/review, actual durable notices, rematch and expiry scheduling
remain Phase 2 work. Neither handoff authorizes a hosted rollout or money.
