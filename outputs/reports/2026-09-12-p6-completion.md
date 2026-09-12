# Prompt 6 — private community local completion

P6 is implemented and locally verified on `codex/private-community-p6` in
`/private/tmp/gametime-p6-20260912/GameTime`. This is a local result, not a merge
into product main or a release decision. P7 was not started.

| Identity | Exact commit |
| --- | --- |
| Accepted P5 input | `e16cff4b3beaa7bcce95db6b0e82eedaa94865fa` |
| P6 implementation and tests | `05f405c24453fe6743ece994d646058958bfdbb2` |
| Preserved product main | `affd367ebe5411969fd5b7abd45629e0746a5a7d` |
| Preserved original dirty checkout | `577bc321e72750976e2e8027680387707070b0e3` |

P5 was idle and its handoff/clean source matched before the dedicated clone was
created. The completed P4/P5 checkouts, product main, original dirty checkout,
other containers and retained resources were preserved. All **75 earlier
migration files are byte-identical**. There is one new forward migration,
`20260912013929_challenge_private_community_v1.sql`.

## Resulting behavior

The [local contract and operator interface](../../docs/PRIVATE_COMMUNITY_V1.md)
describes the APIs and defaults in detail. P6 adds:

- Atomic capacity reservations for 250 current community members and separate
  private member revisions. Retained exited members still receive their original
  simulated return at finality, including when a replacement joins.
- One fixed server snapshot per 15 minutes at most, released only when at least
  900 seconds old and at least five selected, active, nonremoved members remain.
  Below five, counts and snapshot metadata are null. Catalog/detail/Home/list and
  old retry receipts no longer expose live counts or shared membership revisions.
- Account/age/Beta/discovery admission checks, current own progress, and continued
  safe reads/reviews/exits during admission pause. Publication parameters and a
  private operator publisher identity/type are retained; publication remains off.
- Explicit challenge report scope. Challenge moderators cannot see unrelated or
  unscoped reports and cannot globally suspend. Separately granted, expiring,
  revocable and audited global support owns suspension and independent appeals.
  Reinstatement never recreates ended membership or consent.
- Per-account discovery/lookup/redemption/join/report/mutation quotas. Failed
  valid-form token/username guesses count; exact saved retries and safe exits
  remain usable. Invalid envelope parsing remains a bounded rejection.
- Native null/delayed-count decoding and display, a community-scoped report
  action, and an account appeal action with server-saved filing status.

No earlier agreement, source policy, target, consent, review window or recorded
result was rewritten. Amounts remain nonredeemable simulation. No external
messages, hosted mutations, deployment, push, real Health access, live money,
user-data deletion or distribution occurred.

## Performed verification

Owned PostgreSQL 17.6 / Supabase CLI 2.109.1 project `gametime-p6-20260912`,
ports 5972x, network `10.253.216.0/24`. Native tests used a new owned iPhone 17
Simulator on iOS 26.5. Raw local work and xcresults remain at
`/private/tmp/gametime-p6-20260912`; selected evidence is [committed here](p6-20260912/README.md).

| Check | Actual result |
| --- | --- |
| Fresh migration application | 76 migrations applied successfully. The complete final migration was also applied transactionally to a fresh P5 database with historical fixture rows. |
| Portable SQL | **91 files / 4,073 assertions**, zero failures/skips in the clean full pass. The last actor-only appeal-status addition then passed its complete affected file, **49 assertions**, bringing the final distinct assertion inventory to **4,074**. This is not represented as a single 4,074-assertion full-suite invocation. |
| New P6 tests | **76 assertions** across disclosure, 899/900/901 seconds, alternate endpoints, private revisions, own corrections, exits/removal/suspension, discovery eligibility, scoped reports, grant expiry/revocation, appeal/reinstatement, quotas and historical replacement settlement. |
| Actual SQL session races | **50 checks twice**, adapting P4 only for P6's changed error/suspension/discovery contracts and adding a waiting report read versus grant revocation. **Five unchanged P5 pagination races** also passed. |
| P5-data upgrade | **197 assertions passed on the complete final migration**: all 190 old app/public table digests preserved, historical weekly/Beta records, capacity/member-state backfill, old report privacy, masked old receipt metadata and a real P5 history cursor. |
| HTTP arrivals | **250/250 succeeded**, 25 concurrent clients; 251st entry rejected; ten same-request retries preserved the exact receipt; one freed place admitted exactly one of two competing arrivals; failed token guesses persisted their quota through HTTP. |
| Native | **21 distinct tests passed**, including native models/client/session recovery, policy/section tests and rendered community join/detail screens. The final report/appeal UI changes then passed the **eight affected tests** with a fresh successful build. Renders checked delayed/hidden counts, report scope and absence of stranger names. |
| Direct database checker | **Zero errors, 25 warnings, zero checker failures**. Warnings include existing and new implicit JSON/count type conversions. |
| Static/source | Python parse, final diff whitespace, preserved old migration hashes and exact final migration input recorded. |

The final short HTTP arrival sample completed in **0.515 seconds**: observed
485.3 requests/second, median 41.95 ms, p95 111.94 ms, p99 144.47 ms, zero
unexpected errors. This is one local burst with synthetic signed tokens bound
to actual fictional account/session rows. It is not a sustained-throughput,
provider-sign-in, hosted SLO or connection-headroom claim. Its final capacity/HTTP
logic was unchanged by the later actor-only appeal-status projection.

## Review, failures and limitations

One [focused self-review](p6-20260912/review.md) checked privacy, permissions,
lock order, retries and lifecycle preservation. The actual 250-arrival test
exposed a real defect: replacing an exited member made total historical records
exceed the evaluator's old 250-row limit. The correction preserves all former
members' returns while bounding current participation; SQL and HTTP regression
checks now cover it.

Earlier failed attempts remain visible:

- The first full suite found expected old live-count/global-moderator assertions
  and an ambiguous report-subject variable. The variable was fixed, affected
  expectations were changed explicitly, and the clean full pass followed.
- A legacy Personal fixture's two separate clock reads differed by one microsecond
  in the wrong direction and failed its timestamp constraint once. Its unchanged
  test passed in the final full suite; no Personal product code was changed.
- Early P6 guard fixtures reused an existing quota row, inherited an open discovery
  gate, omitted the legacy claim-sub field, or incorrectly expected an exited
  member's unsettled slot to disappear. Corrected fixtures passed and preserve
  the actual historical-slot contract.
- The first capacity run exposed the evaluator defect above and a cleanup failure;
  the fictional cohort was safely closed after the product fix. The harness now
  closes gates in a `finally` block even if fictional cohort closure fails.
- A later HTTP check found that SQLSTATE 55000 mapped a closed join to HTTP 500.
  The generic closed-join response now uses HTTP 400; final burst checks passed.
- CLI advisors still fail with `LegacyDbConnectError` at the explicit loopback
  URL. Two bounded attempts are retained; the direct checker passed, but this
  does not claim CLI advisors ran successfully. No hosted advisor call occurred.

Snapshot capture is a callable local service operation, never a client-read side
effect. An authorized operator/worker must call it; no hosted periodic scheduler
was configured. Hosted gateway/IP limits, staffed support, retention policy,
physical sources, minimum-runtime/human accessibility, full release matrix and
long soak remain separate gates. Per-account safe escape actions deliberately
remain exempt from mutation quotas. No historical P2 failure or P4/P5 limitation
was reclassified, and no cancelled candidate-gate recovery was restarted.

All challenge gates and the historical weekly fixture gate were disabled before
stopping **only the P6 database**, with its backup retained. The owned Simulator
was shut down. The next work remains separately requested P7 with explicit device
opt-in, or other work authorized under the current remaining plan.
