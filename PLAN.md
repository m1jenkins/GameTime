# Implementation plan

Audited 2026-07-25 against `main` (`945be96`), the four open pull requests, and
the nine remote branches.

The README's checklist says what is built. DECISIONS.md says why each choice was
made. Neither says what happens next, which is why the plan had drifted out of
step with the code without anything catching it. This file is the forward plan:
current state, what the audit found, and the decisions that have to be made
*before* a milestone is built rather than discovered halfway through it.

---

## Where the work actually is

| Milestone | Checklist says | Actually |
| --------- | -------------- | -------- |
| M0–M4 | done | done, on `main` |
| M5 | underway; timezone consent remaining | complete, in PR #9, unmerged |
| M6 | not started | substantially built, in the *same* PR #9, unmerged and unchecked |
| M7 | not started | not started, and four of its load-bearing decisions are undeclared |
| M8 | not started | not started, and carries every empirical validation in the project |

The overall verdict: **the engineering is on track and the plan is not.** Five
milestones of evidence machinery are built to a standard the checklist
undersells, while the plan has stopped tracking what is in flight, has no owner
for four decisions M7 cannot start without, and defers every claim that needs a
real iPhone or a real scheduler to the last milestone.

---

## Findings

### 1. M6 is being built inside a pull request titled M5

PR #9 carries two commits. The first, `60538db`, is the last M5 item —
`timezone_change_consent`, D62, 763 lines of migration and 800 of pgTAP. The
second, `537aa47`, is a milestone: `contest_geofences`, `geofence_checkins`,
`geofence_location_observations`, the `ingest-checkin` endpoint, the Swift
check-in queue and its two suites, D63–D66, and 881 lines of pgTAP. That is M6,
both halves of it — the geofence check-ins and the workout-overlap validation.

Its own README diff knows this: it adds "M6 adds exact geofence boundaries…" to
the harness section and lists the `geofence_checkin_failure` and
`workout_overlap_validation` flags. It then leaves the M6 checkbox unticked.

Two consequences worth separating. The bookkeeping one is that the checklist no
longer describes the repository, so nobody can read the plan and know what is in
flight. The reviewable one is that a 27-file, 8,500-line pull request spanning
two milestones cannot get the review that M3's ledger and M5's integrity
sidecar each got on their own — and this is the diff that introduces the first
new ingest endpoint since M3.

**Do:** split PR #9 at the commit boundary. `60538db` closes M5 and can merge on
its own once finding 2 is fixed; `537aa47` becomes the M6 pull request and gets
reviewed as one. Whoever opens it states explicitly whether M6 is complete or
what remains, because the unticked box currently means both.

### 2. PR #9's red pgTAP job is a flaky assertion, not a schema defect

`Database (pgTAP)` fails one assertion out of 558. Deno and Swift are green.

```
140_timezone_change_consent.test.sql
# Failed test 37: "the final approval supplies effective_at from the server clock"
```

The test captures a lower bound and then asserts the applied epoch falls inside
it:

```sql
create temporary table t_approval_window as select clock_timestamp() as lower_bound;
...
select ok((select effective_at >= (select lower_bound from t_approval_window)
                  and effective_at <= clock_timestamp() ...));
```

`review_timezone_change()` stamps `effective_at` as
`date_trunc('milliseconds', clock_timestamp())`, deliberately — the column
comment explains that JavaScript and Swift carry milliseconds where Postgres
carries microseconds, so truncating at the authority keeps all three layers on
one epoch boundary. `date_trunc` truncates rather than rounds, so the stamped
value is always at or *before* the instant it was taken. When the approval lands
in the same millisecond the bound was captured in, the truncated value is
strictly below the untruncated bound and the assertion fails.

So the migration is right and the test is wrong, and it is wrong in a way that
passes most of the time: it is a race between two statements.

The pull request's own history proves it. Run 16 on `60538db` — the timezone
commit alone, carrying this exact test and this exact migration — passed. Run 17
on `537aa47` failed on assertion 37, and the geofence commit between them touches
neither `140_timezone_change_consent.test.sql` nor
`20260725230000_timezone_change_consent.sql`. Same code, both outcomes. Re-running
CI would likely turn it green and would prove nothing.

**Fix:** truncate the bound to the same precision the column uses —
`date_trunc('milliseconds', (select lower_bound from t_approval_window))`. One
line, and it makes the assertion a statement about the clock rather than about
how fast the runner is.

**And note the convention it broke.** The README's harness section states the
rule: "anything that happens on a schedule takes its clock as a parameter…  A
scheduled job that cannot be tested without waiting for wall-clock time is a job
that does not get tested." `app.activate_due_contests(p_now)` follows it.
`review_timezone_change()` does not — it reads `clock_timestamp()` internally
with no injectable clock, which is exactly what forced the test into a timing
race. The column comment says there is "deliberately no effective-time argument
in the authenticated API", which is correct as an API decision and does not
require the *internal* stamp to be untestable. Either give the definer function
an owner-only clock parameter defaulting to `clock_timestamp()`, or accept the
truncation fix above and record that this one path is tested against the wall
clock on purpose.

### 3. Nothing runs on a schedule, so no contest can start in a deployment

`app.activate_due_contests()` is the only thing that moves a contest from
`pending` to `active`. Nothing calls it. There is no `pg_cron` in
`config.toml`, no scheduled Edge Function, and no workflow — the only callers in
the repository are `080_participant_lifecycle.test.sql` and the README.

This is declared rather than forgotten; the migration says "Called by cron,
which M7 sets up alongside settlement; until then it is exercised directly by
the test suite." What is not written down anywhere is the consequence: **through
M6 there is no end-to-end path in a deployed environment at all.** Attested
ingest, integrity assessment, quarantine review, source reputation, timezone
epochs and geofence check-ins are all gated on a contest being `active`, and
every one of them has only ever run against a contest a test forced into that
state with `contests_assert_future_window` disabled.

That is a legitimate way to build a backend, and the suites are strong enough to
carry it. It is not a legitimate thing to leave un-said in the plan, because it
means the first genuine integration is M7's and its blast radius is five
milestones wide.

**Do:** move the scheduler to the front of M7, before settlement. It is small —
enable `pg_cron`, schedule `app.activate_due_contests()` hourly, assert the
schedule in pgTAP — and once it exists, the whole M3–M6 stack can be exercised
against a contest that activated on its own.

### 4. M7 cannot start: four of its decisions are undeclared

Every other milestone in this repository was built on top of decisions written
down first. M7 is not, and the gaps are not peripheral.

**a. How a donation is confirmed.** This is the product. The README's first
paragraph is precise about what the app is — "the stake is a pledge, and the app
tracks whether it was honored" — and D4 fixes the shape of a settlement as
`(winner, loser, amount, charity)`. Nothing anywhere says how the pledge becomes
*honored*. The deferred list mentions "a decayed ratio of confirmed settlements
to total obligations" and never defines `confirmed`. Self-attestation, a receipt
upload, the winner acknowledging, a charity-side integration, and a timeout are
five different products with five different abuse surfaces, and the whole
anti-cheat programme M3–M6 exists to protect a number that this decision
defines. It has to be written before the settlement schema, not after.

**b. The terminal state for a contest that ran but cannot be decided.**
`contest_status` is `pending → active → cancelled | finalized`, and `active →
finalized` is the only forward edge from `active`. D54 says an unresolvable tie
returns `undecided` / `tie_break_inconclusive`, and D51 says a contest with no
qualifiers is void and nobody donates. Neither has a status. As the schema
stands, a contest whose tie-break is inconclusive stays `active` forever and a
void contest is `finalized` and indistinguishable from one that settled. D30's
"voids itself" case is `cancelled` with `insufficient_participants`, which is a
different thing — that contest never ran.

**c. Whether the ingest grace period and quarantine review can both hold
finalization.** D43 sets a six-hour grace window after `ends_at`; D60 says M7
must refuse to finalize while a quarantine review is unresolved. Both are right
on their own. Together they need a stated order of operations, because a
quarantine opened by a snapshot written in the fifth hour of the grace window
extends finalization by however long a reviewer takes.

**d. The standings read surface and who may see it.** D56 deferred this to M7
deliberately and correctly. It is still work M7 owns that has no design: the
scoring engine is a pure TypeScript function with no endpoint, so nothing can
read standings today, and a leaderboard has to render while a contest is live.

### 5. Silence blocks settlement, and nothing exists to break silence

D60 is right to reject timeout-as-approval: "silence becomes consent in the
exact path meant to fail closed." But it pairs that with "M7 must block
finalization on unresolved review," and the third option — what happens when the
opponent simply never votes — is not written down. As designed, one participant
who stops opening the app holds a contest open indefinitely, and the person
waiting has no way to escalate.

The same shape appears in D62: a timezone change needs unanimous approval from
every other accepted participant, and silence leaves it pending. That one fails
closed harmlessly — the relocation just does not happen.

Compounding it: **there is no notification layer, and no milestone owns one.**
The only mention in 1,767 lines of decisions is one deferred bullet observing
that "a notification layer is the natural home" for invitation reminders. Yet
M5's quarantine review, M5's timezone consent, M2's invitations and M7's
settlement confirmation all require a specific human to take a specific action,
and nothing can tell them. An accountability product whose accountability
mechanism is silent-by-construction has a hole in the middle of it.

**Do:** make the review-silence outcome an explicit decision entry in M7 — the
plausible answer is that unresolved review at the grace deadline resolves the
contest to void rather than to either party, since void is already the outcome
when evidence cannot decide. And give notifications a milestone. Push
notification is also the first thing in this project that needs APNs
credentials, an app target, and a device, which makes it another argument for
finding 6.

### 6. Every empirical claim is deferred to M8, including the load-bearing one

The plan puts one client milestone last and calls it "Minimal SwiftUI shell."
Landing on it: Sign in with Apple wired to a real client (D12), HealthKit
authorisation and entitlements, the iOS 18.0 target that was reasoned rather
than measured (D2's owner action, still open), the avatar bucket and its
policies, handle-change throttling, group contest visibility, invitation expiry
— and App Attest against an actual iPhone.

That last one is not a milestone item, it is a risk to everything under it. D46
says it plainly: the Deno suites mint their own P-256 keys and their own
Apple-shaped certificate chain, so "it proves the verifier agrees with the
test's signer, not that either agrees with an iPhone," and it names two Apple
format details that need confirming against a real device.
`APP_ATTEST_ROOT_CA_PEM` is still unset, and the functions refuse to start
without it. Attested ingest is the product's entire credibility claim; M3 and M6
both route through it, and it has never been exercised against the hardware it
is written for.

**Do:** insert a device-conformance spike — call it M6.5 — between M6 and M7. It
does not need the app. It needs a throwaway Xcode target that fetches Apple's
real root, performs one attestation and one signed batch against a staging
project, and reports whether the verifier accepts it. That retires D46 and D2
together, at a point where a format surprise costs a fix rather than a rewrite,
and it is the cheapest de-risking available anywhere in this plan.

### 7. Repository hygiene, and one file that is invisible to search

**Four pull requests are open and only one is live.** #5 (M3) and #6 (M4) have
heads that are ancestors of `main` — their content merged through other pull
requests and they were never closed. #7 duplicates #3 (M2), which merged
instead. Seven of the nine remote branches are dead. Anyone opening the
repository to see what is in flight currently finds four candidates.

**`supabase/functions/_shared/scoring.ts` contained two raw NUL bytes.** They are
intentional in purpose — a field separator in the composite map key `scoreContest`
uses to catch a bucket carrying two local days,
`` `${row.userId}\0${row.metric}\0${row.bucketStart}` `` — but they were written
as literal `0x00` bytes rather than as escapes, which made `file` report the file
as `data` and made `grep` and `ripgrep` skip it as binary by default. The one
file D3 calls the only implementation of who won was the one file you could not
text-search. Fixed here by writing the separator as the escape `\u0000`, which
produces the identical string, plus a comment saying why the separator is a NUL
at all.

---

## Corrected forward plan

M0–M4 unchanged. From here:

### M5 — close it out
Fix the flaky assertion in finding 2, merge `60538db`. M5 is then done: D57–D62,
integrity scoring, quarantine review, source reputation, consented timezone
epochs.

### M6 — geofence check-ins and workout-overlap validation
Re-open `537aa47` as its own pull request and review it as a milestone. State
whether it is complete. Tick the box when it is.

### M6.5 — device conformance spike *(new)*
Apple's real App Attest root, one attestation and one signed batch from a real
iPhone against a staging project. Retires D46 and D2. No product surface, no
schema. This is the highest-value unit of work remaining in the plan and it is
currently in nobody's milestone.

### M7 — settlement, disputes, charity pledge lifecycle, cron finalization
Ordered so the decisions come first:

1. Write the four missing decisions from finding 4 — donation confirmation
   above all, then the terminal states, the grace/review interaction, and the
   standings read surface — plus the review-silence outcome from finding 5.
2. Enable `pg_cron` and schedule `app.activate_due_contests()`. First real
   end-to-end activation; expect it to find things.
3. Settlement schema, the finaliser reading `app.ingest_grace_period()` rather
   than its own copy, the dispute path, the reliability score.
4. Account deletion versus contest history, which the deferred list already
   assigns here and which needs the obligation to exist before it can be
   answered.

### M8 — client
Split it. The shell that proves the loop — sign in, create, invite, accept,
sync, see standings, settle — is one milestone. Handle throttling, avatars,
group feed, invitation expiry and reminders are product surface that follows it.
Notifications need an owner; the loop milestone is the earliest place they fit,
because quarantine review and settlement confirmation both need a human to be
told something.

### Post-M7
Retention on finalized contests, per the deferred list.

---

## Owner actions that block launch

Neither is a code change, both are already tracked, and the first one blocks
every manual end-to-end test anybody tries to run.

- **`charities` is empty in production on purpose** (issue #4, D26). With an
  empty table `create_contest()` fails its `is_active` check, so no contest can
  be created at all. That is the intended failure mode, and it also means the
  first person to try the product end to end against a real project cannot. The
  list needs EINs verified against IRS Tax Exempt Organization Search.
- **`APP_ATTEST_ROOT_CA_PEM` needs Apple's real root** (D46), from
  https://www.apple.com/certificateauthority/. The functions refuse to start
  without it. Pairs with M6.5.

---

## Things no milestone owns

Not a criticism of the milestones — a list of what is missing from the plan as a
whole, so the gaps are chosen rather than discovered.

| Gap | Why it matters here |
| --- | --- |
| Notifications | Four flows need a specific human to act and nothing can tell them (finding 5) |
| Staging environment | No deployed target exists; M6.5 and cron both need one |
| Observability | An ingest path that refuses evidence needs to say how often and why, or a rejection is invisible |
| Rate limiting | The three endpoints verify a caller's JWT but cap nothing; one signed-in client can hammer `attest-device/challenge` freely |
| Abuse reporting | Blocks exist; there is no route for reporting somebody |
| Privacy disclosure | HealthKit data, location check-ins from M6, and App Store review all need it before a build ships |

---

## Next steps, in order

1. Fix the flaky assertion in `140_timezone_change_consent.test.sql` and merge
   the M5 commit.
2. Split the M6 commit into its own pull request.
3. Close #5, #6 and #7; delete the seven dead branches.
4. Write the five missing decisions (finding 4a–d and finding 5) before any M7
   code.
5. Run M6.5 — Apple's real root, a real device, one signed batch.
6. Enable `pg_cron` as the first M7 commit.
