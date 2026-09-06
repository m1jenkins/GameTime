# Phase 3(d): selected progress and friend following

Implemented locally September 5, 2026, after the
[Phase 3(d) checkpoint](PHASE_3D_CHECKPOINT.md). This is a separate default-off
backend for explicit friend following, structured encouragement, personal
in-app reminders, private reports and narrowly assigned support access.
Native commitment screens remain separate work. Result/review persistence was
subsequently implemented in [Phase 3(e)](PERFORMANCE_LIFECYCLE_V1_ACCEPTANCE.md);
the Phase 3(d) verification below remains its original local evidence. All amounts remain nonredeemable simulation.

## Sharing contract and reversible defaults

An owner invites one accepted friend to `goal_and_selected_progress_v1` with
explicit consent. The named friend separately accepts or declines. Opening or
listing an invitation never accepts it. Pending invitations expose only their
locator, owner identity, scope and expiry; goal/progress access requires acceptance.
Invitations expire at the earlier of seven days or the commitment deadline.
There can be 32 open and 128 total invitations per commitment. These limits,
the sharing scope and reminder/interaction choices are local defaults in D127.

Accepted followers receive only these deliberately selected facts:

| Data | Shared representation |
| --- | --- |
| Goal | 5,000 metres, strict target in seconds, start, deadline and display timezone |
| Published milestone creation/status entry | The selected entry's name, due instant and reported status, with report/receipt times |
| Published check-in | Occurrence and receipt times, with its check-in kind; **no note text or linked milestone identity/name** |
| Provenance | Every card is `owner_reported` and `counts_as_proof: false` |
| Reaction | The follower's own structured reaction; owners see aggregate counts by code |

The owner publishes each existing progress entry explicitly. Selecting one
entry does not select its subsequent updates, linked notes or other milestones.
All currently accepted followers receive the same selected publication set,
including earlier still-published cards. The scope does not support different
card selections per friend. Owners can inspect the publication set separately.
Private notes, proof documents, event/bib mappings, attempt receipts, agreement
JSON, exact requests, financial amounts and recipients are never serialized
into follower cards. No result is inferred from a goal deadline or a reaction.

Publications are immutable snapshots with a separately recorded retraction.
They are bounded at 512 per agreement, including retracted publications. A
retired/reopened milestone requires explicitly publishing its new status entry;
an earlier shared status remains an explicitly dated report. Retraction removes
a card from future reads and prevents new reactions. A later explicit publication
can share that entry again with a new publication ID.

Reads return at most 50 cards, with `content_revision` and `next_after_sequence`.
Pass the revision with every continuation. Any publication/retraction change
invalidates the old revision and requires a fresh first page. This preserves a
stable selected set without allowing old pagination to recover retracted content.

## Consent, revocation and exact requests

Owners revoke; followers decline or unfollow. Blocking, unfriending, deletion
of either person and safe commitment closure also permanently end existing
grants. Unblock, re-friending and old exact acceptance retries never reactivate
them. Fresh following requires a new invitation and fresh acceptance. Ended
consents cannot be reopened even through an otherwise authorized table update.

An unavailable grant returns `access_allowed: false`, an empty card list and no
goal; unrelated callers receive an authorization error. Actor/session checks
still apply to unavailable reads, own receipts and exact recovery. The generic
unavailable state does not reveal who blocked whom. Locator lists contain no
goal, card, profile text or reminder payload. Every detail read reauthorizes.

All person-initiated writes use one private `(actor_id, request_id)` namespace
for this product slice. The identity binds the operation and every typed input.
Changed payloads fail. Committed owner/follower retries return only the original
action receipt after gate shutdown, revocation, retraction or closure; they
never return previously shared content or restore access. Deleted actors and
revoked/expired sessions lose recovery. Support resolution recovery additionally
requires current independent case authorization and an enabled gate.

New invitations, acceptance, publications, positive reactions and reminder
scheduling require the gate and an open commitment before its deadline.
Existing consented reads remain available after gate shutdown or the deadline
while the commitment is open. Shutdown does not prevent revocation, unfollowing,
declining, blocking, retraction, removing one's existing reaction, cancelling
one's reminder, reporting or reading one's own report history.

## Reactions, reminders and support

Reactions are `cheer`, `well_done` or `keep_going`, with one current value per
follower/publication. A null value removes that person's existing reaction.
There are no free-form social comments, public feeds or follower identities
shared with other followers. Ended follows no longer contribute to the owner's
current reaction counts. These actions never modify progress or proof.

A follower can schedule one personal reminder on an active follow, strictly
after now, within 30 days and before the goal deadline. Null cancels it. A
current authorized detail read reports whether that reminder is due; this is
durable **pull-based in-app state**, with no scheduler, push/email dispatch,
external delivery or notification permission implied. It remains due until
cancelled or rescheduled. Revocation/closure clears it; gate shutdown and the
deadline suppress due reminders. Owners cannot schedule reminders for friends.

Either named person can file a private `pressure`, `harassment`, `privacy` or
`support` report about the follow, including after revocation, blocking, closure
or the peer's deletion. A report contains 1–500 characters of bounded plain
text, with at most 16 reports per reporter/follow. Reporting does not itself
block or send a message. The separate block RPC applies the existing social
block under the new session/exact-request boundary. Reporters can rediscover
their case locators and read only their own submissions and resolutions.

A service-only setter assigns an independent active operator to one case for
at most seven days, or revokes that assignment. Neither named person can act
as its operator. The operator needs their own matching active session, a current
grant and the following gate. Reads are audited and contain only the submitted
report and resolution, without the underlying private progress or proof. One
immutable resolution records `guidance_recorded`, `action_recorded` or
`no_action`; it is an operator classification, not an automatic moderation or
message-delivery claim. This is a local support boundary, not a staffed service
or an approved real-user support policy. Post-final result corrections remain
Phase 3(e) work.

## Storage, locking and retention

The [forward migration](../supabase/migrations/20260905230148_performance_following_v1.sql)
adds ten private `app.performance_following_*` tables: runtime, grants,
publications, content revision, reactions, cases, support grants, exact requests,
retention and audit. All have RLS and revoked client/service table grants;
function grants are explicit. No earlier migration or existing consent changed.

Sharing operations lock pair profiles in UUID order, then the caller's matching
Auth session, runtime, agreement and applicable grant. Active sessions are
checked again after blocking locks. Existing friendship/block writes and
deletion serialize through their profile locks; their new revoke triggers never
acquire an additional peer profile. This keeps old deletion ordering intact.
Support operations use sorted pair/operator profiles, caller session where
applicable, runtime, agreement, case and case grant, then recheck expiry.

The new `performance_following_v1` hold retains selected snapshots, grants,
requests and cases through closure/deletion against the existing tombstones.
Legacy raw-evidence purge has no authority over these tables. This is a local
fictional hold, not an approved duration for real social/report data. There is
no release/purge procedure or post-deletion account-recovery capability. Only
the remaining active reporter or a currently assigned independent support
operator can read the respective retained report.

## APIs and reproduction

| RPC group | Purpose |
| --- | --- |
| `set_commitment_following_enabled_v1` | Service-only default-off gate, audited |
| `invite_commitment_follower_v1`, `respond_commitment_follow_v1`, `end_commitment_follow_v1` | Owner scope consent, friend consent and independent safe exits |
| `publish_commitment_progress_v1`, `retract_commitment_progress_v1`, `get_commitment_publications_v1` | Owner selection and bounded publication inspection |
| `list_commitment_follows_v1`, `get_commitment_follow_v1` | Locator discovery and current authorized projection |
| `react_commitment_progress_v1`, `set_commitment_follow_reminder_v1` | Structured encouragement and personal in-app reminder |
| `block_commitment_follow_v1`, `report_commitment_follow_v1` | Explicit social block and separate private report |
| `list_commitment_follow_reports_v1`, `get_commitment_follow_report_v1` | Reporter-only case discovery and history |
| `set_commitment_follow_support_v1`, `read_commitment_follow_support_v1`, `resolve_commitment_follow_support_v1` | Service assignment, audited independent read and immutable resolution |

With a local stack containing the migration:

```sh
supabase test db --local supabase/tests/475_performance_following.test.sql supabase/tests/476_performance_following_concurrency.test.sql
bash scripts/performance-following-example.sh 55322
```

The [two-account example](../scripts/examples/performance-following.sql) uses
public product RPCs after seeding fictional Auth/profile/session rows. It creates
a 60-day agreement, explicitly publishes selected progress, consents twice,
asserts note redaction, records encouragement, revokes with the gate off, verifies
that exact recovery cannot restore sharing, and files a private report. All
fixtures and gate changes roll back. The runner accepts only a validated
loopback database port; its default is 54322. This task used 55322 exclusively.

## Verification

All verification used `/tmp/gametime-phase3d-following`; the normal development
database was preserved. The snapshot has a separate project identity and ports
(`5532x`), disables the unused Apple provider and includes the native JSON DTO
fixtures imported by Deno. All 278 source inputs under the tested migrations,
tests, functions, scripts, portable Swift core and imported native fixtures were
hash-compared with the working repository with no mismatches.

| Check | Fresh result |
| --- | --- |
| Following SQL boundary suite | PASS: 180 assertions, including role/RLS, consent, exact recovery, note/proof redaction, pagination, expiry/capacity, report privacy and retention |
| Following transaction races | PASS: 36 assertions across 16 observed waits, including both read/revoke orders, block/unfriend/deletion, retraction, gate shutdown, session revocation/natural expiry and support expiry/revocation |
| Full database rebuild and pgTAP suite | PASS: 67 files / 3,221 assertions |
| Deno install, format, lint, type checking and tests | PASS: 613 tests |
| Portable Swift build and tests | PASS: 103 tests |
| Schema lint and warning/error security/performance advisors | PASS: no issues |
| Rollback-only public-RPC example and shell syntax | PASS |
| Scorer isolation | PASS: the complete persisted attempt snapshot is unchanged by all social/support actions; no slot is released |

The first full portable invocation passed SQL and Swift but failed Deno because
the disposable snapshot omitted its imported native fixture JSON. Those files
were copied and the complete Deno stage passed on rerun. After adding private
report-locator recovery, the final full SQL rebuild/suite and advisors were
rerun; Deno/Swift inputs remained identical. The initial focused SQL run also
found a shared-trigger record-field error, which was fixed, and an assertion
expecting a custom truncation guard before PostgreSQL's foreign-key rejection,
which was corrected. Failed runs are not counted as passing evidence.

Logs: `/tmp/gametime-following-{portable,database-final,deno,focused,races,lint,advisors,example}.log`.
The final migration was recorded as `20260905230148` on the disposable stack.
Its seven new-product gates finished off, with zero sessions, open duel or
commitment slots, follows, publications, cases or progress entries. The normal
database did not receive this migration. Only the disposable stack was stopped,
with its local database backup retained. Unrelated skills, their lockfile and
generated trash were preserved. No native source changed; no fresh native HTTP,
simulator, VoiceOver, physical-device or hosted acceptance is claimed. Earlier
native evidence and its limitations remain in the checkpoint record.

The [Supabase changelog](https://supabase.com/changelog.md), official
[function permissions](https://supabase.com/docs/guides/database/functions) and
[RLS documentation](https://supabase.com/docs/guides/database/postgres/row-level-security)
were checked with CLI 2.109.1. No dependency or platform upgrade was needed.

## Native and Phase 3(e) handoff

No native commitment client, cache or screen was added. The later native slice
must persist complete requests before sending; distinguish an action receipt
from current authorization; and clear shared goal/cards, reactions and reminders
on account changes, revocation/block/deletion, any failed authorization/read,
or `access_allowed: false`. Reject responses from a previous actor/generation.
Do not retain shared content through relaunch or display cached content while
current access is unknown. Restart pagination on a changed content revision.
Server revocation cannot erase content a person has already seen or copied.
Render selected names and private support notes as untrusted plain text.

The following handoff is now implemented in [Phase 3(e)](PERFORMANCE_LIFECYCLE_V1_ACCEPTANCE.md).
Phase 3(e) owns durable commitment result notices, review/withdrawal history,
complete-proof-snapshot commits, a clock-injected lifecycle, immutable final
results, post-final support and separate simulated consequences. It must not
turn follower reactions, progress reports or support classifications into
proof, completeness, consent changes or settlement. Any future result-sharing
scope needs explicit selection and its own reviewed projection. Real organizers,
retention/support operations, native/device acceptance, hosted rollout,
external delivery, true-mile policies and live money remain separate gates.
