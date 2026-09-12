# Private community — local P6 contract

P6 extends the existing fictional operator-published steps cohort. It does not
approve publication settings, real activity, money, hosted operation or rollout.
The exact source, checks and limitations are in the
[P6 completion report](../outputs/reports/2026-09-12-p6-completion.md).

## Participation and disclosure

Publication keeps the existing parameterized target, minimum, capacity, amount,
timezone and full-day window. Capacity supports 250 current members. Publisher
identity/type is private metadata; the only permitted type is `operator`, and
publication still requires the service role and the explicit fixture gate.
There is no participant-hosting or feed API. Old agreements remain byte-identical.

Joins require an active session/account, age confirmation, Beta eligibility,
discovery authorization, admission and source-readiness gates, exact terms and
explicit consent. Existing shared overlap/three-unsettled limits remain in force.
The capacity counter is locked only for its cohort; the join locks its caller's
profile, not the entire roster. Membership and reservation changes are atomic.
Exit/removal frees participation capacity. Its unsettled slot/return remains
until finality; a replacement must not discard the former member's agreement.
The evaluator therefore permits retained excluded history beyond 250 while
rejecting more than 250 nonexcluded community participants.

Own activity is current and private. Other members' identities, standings and
activity times never appear in ordinary community projections. The publisher ID
is also hidden. Detail, Home sections, legacy list and catalog use one disclosure
helper:

- Fewer than five selected, active, nonremoved, nonexited people: `joined: null`,
  `state: threshold`, `as_of: null`.
- At least five but no sufficiently old qualifying snapshot: the same null fields
  with `state: pending`.
- Otherwise: the exact count from the latest snapshot **at least 900 seconds old**,
  `state: available`, and its original `as_of` time. A snapshot captured below
  five never contains an exact count and cannot become disclosable later.

The five-person threshold is independent of the agreed outcome minimum.
Disclosed exact counts are never computed afresh for a client response. Capture is a separate
service operation, `challenge_capture_community_snapshot_v1(p_id)`, allowed only
with fixture/discovery authorization and no more than once per 15 minutes.
The caller cannot supply its clock, count or timestamp. Reads cannot capture.
An authorized local operator/worker must call capture; delayed or absent capture
keeps totals pending/older. Hosted scheduling belongs to P10 and is not enabled.

The former shared lobby revision also revealed joins/exits. Community projections
now use private member revisions: own member/fact/review changes and public
lifecycle status transitions. Other members' joins/exits/facts cannot advance
that revision. Original request rows remain immutable; recovery masks old shared
revision metadata, while new receipts retain their exact member revision.
Closed/capacity-rejected joins use the same `challenge_join_closed` client error,
without an exact count or a capacity-specific reason. Admission success/failure
and the agreed lifecycle remain observable; no system can retract a count that
was legitimately disclosed earlier.

## Reports and support

`challenge_report_scoped_v1(request, challenge, subject, reason)` records the
challenge scope explicitly. Members may pass a null subject to report the
community itself. The native detail screen makes that scope clear. A community
report about a named account requires a known friend, preventing stranger-ID
membership probing. Legacy `challenge_report_v1` reports are account/global
reports; no scope is inferred retroactively from overlapping memberships.

A challenge moderator sees only reports filed for the assigned challenge and
can remove a member there. Review authority remains a separate capability.
Moderators cannot globally suspend accounts. Existing report rows, reviews,
agreements, notices and finals are not rewritten.

Service administrators grant/revoke challenge authority through
`challenge_grant_operator_v1` / `challenge_revoke_operator_v1`. Independent global
support instead requires `challenge_grant_support_v1`, expires within seven days,
and is revoked by `challenge_revoke_support_v1`. Grant reads synchronize with
revocation; expiry equality denies access. All grants, revocations, report reads,
suspensions and appeal decisions enter the existing immutable operator audit.

Global support uses `challenge_support_reports_v1` (100-row timestamp/ID keyset),
`challenge_support_suspend_v1`, `challenge_support_appeals_v1`, and
`challenge_resolve_appeal_v1`. Suspension coordinates with admissions and performs
safe exits synchronously. A new admission discovered after lock acquisition
requires a retry rather than escaping the safety operation.

A suspended person retains own reads, reports, exits and review rights. They can
file `challenge_appeal_v1` once per suspension and recover it exactly; their account
screen shows the server-saved filing. `challenge_own_appeals_v1` exposes only their
own decisions. A separately authorized support person, other than the original
suspender or the appellant, may uphold or reinstate. Reinstatement permits future
admission and never revives ended membership, consent, slots or results.
Challenge moderation queues are bounded to 100 rows; older reports remain
accessible to separately authorized global support via keyset pages.

## Local quota defaults

These are implementation defaults for local Beta verification, not approved
hosted traffic/retention policy. Each actor has one bounded counter per category;
windows start with that actor's first call and use the real server clock.

| Category | Limit |
| --- | --- |
| Discovery | 30 calls/minute |
| Exact username lookup during invitation | 30 attempts/minute |
| Link redemption | 20 attempts/hour |
| Community joins | 6 successful new joins/hour |
| Reports, across scopes/endpoints | 10 new reports/hour |
| Other journaled mutations | 120/minute |

Failed valid-form username/token guesses consume their attempt counter. They
return structured HTTP errors without rolling back the counter; the native
client also detects those error bodies in injected/direct transports. Accepted
writes consume their quotas in the same transaction as the effect, and a quota
rejection rolls back membership, consent, slots and capacity together. Exact
saved retries do not consume another quota. Safe leave/cancel/review/block/link
revocation/appeal/stop actions remain exempt so a busy account can still exit.
Malformed envelope rejection is bounded validation, not a counted token lookup.
These per-account controls do not replace hosted gateway/IP or Auth controls.
