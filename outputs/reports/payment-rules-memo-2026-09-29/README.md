# Payment rules memo: what GameTime charges, when, and what's still off

September 29, 2026. Read this before the Stripe test-mode end-to-end commitment
test. It covers the D144 personal commitment path on `gametime-p11b`: what the
rules are, what hosted shows today, and what needs Mason.

Sources: [DECISIONS.md](../../../DECISIONS.md) D113–D115 and D144, the
migration
[`20260925000000_challenge_personal_commitment_v1.sql`](../../../supabase/migrations/20260925000000_challenge_personal_commitment_v1.sql),
the [`challenge-commitment-charge`](../../../supabase/functions/challenge-commitment-charge/handler.ts)
worker, [`AppConfiguration.swift`](../../../ios/GameTime/GameTime/AppConfiguration.swift),
the [Sep 27 hosted receipt](../2026-09-27-d144-hosted-state.md) and the
read-only hosted checks listed [below](#receipt). Where the source and a
decision disagree, this memo follows the source and says so.

## The short version

- **Every payment is test money.** The database, the webhook and the charge
  worker all refuse live Stripe objects. The worker also refuses to start in
  production. No real money can move today.
- **Saving a card charges nothing.** Money can move only after a goal is final
  and counted as a miss, and only when someone sends the queued charge.
- **Missing data never counts as a miss.** A committed goal is a miss only when
  Health totals for the whole goal period arrived in time and fall short.
  Anything else is void, and void never charges.
- **One charge per miss, at most.** It uses a fixed idempotency key and is
  never retried after a decline.
- **Mason's $20 Steps goal (Sep 27 – Oct 4) has no Health data yet.** Hosted
  has had no Health upload from any account since Sep 26 16:35 UTC. If none
  arrives by Oct 6 05:00 UTC, the goal voids and nothing is charged.

## 1. Card saved vs. money moving

| Step | What happens | Money moves? |
| --- | --- | --- |
| Save a card | `challenge-commitment-setup` creates a Stripe SetupIntent (`usage=off_session`) for a fixed amount. The setup expires after 24 hours if it isn't used. | No |
| Commit | The goal's agreement freezes the amount, the recipient and the rules, and uses up the saved card. Stripe gets no call. | No |
| Goal runs | Health totals upload. No hold, no authorization, no PaymentIntent. | No |
| Goal final as a miss | A trigger on `challenge_finals_v1` queues **one** `pending` charge row. | Not yet |
| Charge sent | `challenge-commitment-charge` makes one off-session PaymentIntent in **Stripe test mode**. | Test money only |

D113 rejected authorization holds and charging at creation. D144 keeps both of
those out.

## 2. What counts as a confirmed miss (`complete_window_v1`)

Committed goals use their own proof rule. Goals without a commitment keep the
old evaluator unchanged.

**Met.** A saved Health total that reaches the target. It counts even partway
through the week.

**Miss.** All of these must be true:

1. The latest saved Health total was queried through the goal's end.
2. It was recorded no later than **48 hours after the goal ends**.
3. It falls short of the target.
4. The goal becomes `final` with outcome `scored` and the person's status is
   `missed`. The result is published at the end plus 48 hours, then a review
   window runs, so finality comes about 4 days after the end at the earliest
   (Sep 27 receipt, worked out from source).

**Void, no charge.** Any of these:

- no Health total at all;
- a total that doesn't cover the whole goal period;
- a total saved after the 48-hour cutoff;
- a deleted or unresolved total;
- leaving the goal before it ends;
- the goal being cancelled or voided;
- an open review past its deadline, or a review that excludes the person.

That is the promise in D144: *"No data or partial data means no charge."*

**Differences from D113, the legacy Personal sandbox.** D113 used a 24-hour
final sync period and a 7-day review deadline. D144 uses a 48-hour data cutoff
and the `challenge_*_v1` review window. D113 still governs the legacy Personal
path only.

## 3. One charge, idempotency, declines, blocks

- **One row per goal.** The charge table is unique per goal. The trigger inserts
  with `on conflict do nothing`. Charge rows can't be deleted, and their amount
  and key can't be changed.
- **Fixed idempotency key.** The key is built from the goal and the person, and
  every provider attempt uses it.
- **Declines are final.** A card error records `failed` or `requires_action`.
  Nothing retries it automatically, and there's no debt collection.
- **Only a network failure retries.** If we can't tell whether Stripe received
  the request, the same key is reused. That happens at most 3 attempts within
  23 hours, then the row becomes `failed` / `provider_unreachable`.
- **The webhook** checks Stripe's signature and re-reads the object. It never
  changes a `succeeded` charge, it can move a failed charge to `succeeded`, and
  it ignores duplicate events.
- **What blocks a new commitment:**

  | Reason code | When |
  | --- | --- |
  | `challenge_commitment_unavailable` | The switch is off or the account isn't eligible |
  | `challenge_commitment_limit` | Another committed goal is still open, or its charge is `pending`/`processing` |
  | `challenge_commitment_unpaid` | A charge is `requires_action` or `failed` |
  | `challenge_commitment_card_required` | No unexpired saved card for this amount |

- **Gap to know about:** D113 promised an explicit way to fix a failed payment,
  or a policy waiver. **D144 has neither.** A `failed` or `requires_action`
  charge blocks new commitments until a Stripe webhook reports the same
  PaymentIntent `succeeded`. That's acceptable in test mode. Before any real
  money, a recovery path and a waiver path need a decision.

## 4. Recipient, amount, terms

- **Recipient:** GameTime itself (`recipient: gametime`,
  `gametime_recipient_v1`). No charity: D143 removed it everywhere.
- **Amount:** $1 to $50, whole dollars, USD only. The database enforces this
  (`amount_cents between 100 and 5000`, multiple of 100).
- **Frozen terms:** the agreement stores the amount, recipient,
  `one_charge_after_confirmed_miss_v1` and `complete_window_v1`, plus a digest.
  The Sep 27 read showed the stored digest matched one recomputed from the
  terms.
- **What the person sees before committing:** a test payment method ("Add test
  payment method", "Test method saved — no real money moves."). The status
  reads "Processing one $20.00 test charge." while a charge waits. D113
  requires test screens to say plainly that no real money moves. Any future
  live version needs the recipient and the one-charge rule stated before
  consent, reviewed against [docs/COPY.md](../../../docs/COPY.md) and the
  release conditions in [docs/BUSINESS_MODEL.md](../../../docs/BUSINESS_MODEL.md).

## 5. Switch, eligibility, and which build can commit

**Server gates (D115 pattern).** A single runtime switch plus per-account
eligibility. Both start off, and only the service role can change them.
Admission is checked in the database, not the app. It covers new setups, new
commitments and dispatch.

Two details from the source:

- **The finality trigger doesn't check the switch.** A miss queues a charge even
  with the switch off. The charge then waits, with no age limit.
- **Dispatch checks only the switch, not eligibility.** Turning the switch off
  stops every charge from being sent.

**Which app can commit.** Staging and TestFlight share the p11b backend, so the
server can't tell them apart. The build decides.

| Build | Commitments | Settlement |
| --- | --- | --- |
| Friends TestFlight 0.9.0 (2), D142 | **Off**: `challengeCommitmentsEnabled` is false for TestFlight and Release no matter what the plist says | `test_only` |
| Debug / Staging with `GAMETIME_CHALLENGE_COMMITMENTS_ENABLED` | Can offer "Put money on it" when p11b's switch and eligibility allow it | Stripe sandbox |

So TestFlight friends can't create a commitment, even with the hosted switch on.

## 6. Mason's $20 commitment today

Read-only on Sep 29 at 12:39 UTC. It matches the Sep 27 receipt, except for the
Health data finding below.

| Item | State |
| --- | --- |
| Runtime switch | **On** (since Sep 26 03:27 UTC) |
| Eligibility | 1 account, **eligible** (since Sep 26 03:32 UTC) |
| Saved card | 1 setup, `consumed`, $20, test mode |
| Stripe customers | 1 (test mode) |
| Webhook receipts | 2, both `applied` (setup created and succeeded) |
| Committed goal | Personal Steps, Sep 27 05:00 – Oct 4 05:00 UTC, **active**, $20, recipient GameTime |
| Charges | **0** |
| Final record for the goal | none yet |
| Reviews on the goal | 0 |
| **Health totals saved for the goal** | **0**: no admission and no totals |
| Latest Health total from any account | **Sep 26 16:35 UTC** |
| Commitment functions | setup, charge and webhook all active, **version 4** (Sep 26 02:56 UTC). The Sep 27 receipt listed version 3. |
| Cron | `challenge-worker-v1` and `challenge-monitor-v1` active every minute. **No job calls `challenge-commitment-charge`.** |

**Why no Health data?** This matches the open refused-upload issue (see the
[Sep 27 receipt](../2026-09-27-health-refused-upload.md)). The fix is live on
the server (ingest is now at version 9), but the phone needs a newer app build
before it stops refusing. Until the phone uploads, the goal has nothing to
score.

### What happens around Oct 4 – Oct 8

| When (UTC) | What |
| --- | --- |
| Oct 4 05:00 | Goal ends. Uploads are still accepted. |
| **Oct 6 05:00** | **Health data cutoff.** A total must be queried through Oct 4 05:00 and saved by now, or the goal can't be a miss. |
| ~Oct 6 05:00 | The worker publishes the result, and the review window opens. |
| **~Oct 8 05:00** | **Earliest finality**, later if a review is open. |

- **No upload by Oct 6 05:00:** the goal voids, and there's no charge and
  nothing to send. This is the most likely outcome right now.
- **Target met:** no charge.
- **A full-week total that falls short:** at finality one **$20 test** charge
  is queued as `pending`. **Nothing sends it.** `challenge-commitment-charge`
  runs only when someone POSTs to it with the payment dispatch secret (header
  `x-gametime-payment-dispatch-secret`). Until then the app shows "Processing
  one $20.00 test charge." and new commitments are blocked
  (`challenge_commitment_limit`).
- **If a charge is queued,** Mason decides whether to send it. Sending it is
  one manual invocation of the charge function in test mode. It's a hosted
  action, and it's the natural first real step of the e2e test below. The other
  option is to leave it pending, but it stays sendable indefinitely while the
  switch is on.

## 7. Still forbidden without Mason's explicit OK

- Any **live-mode** Stripe object or charge, or turning on live Stripe.
- **Uploading to TestFlight or App Store Connect**, including the local 0.9.0 (2)
  archive.
- **Force-pushing** any branch.
- **Deleting user data**: accounts, goals, Health totals, charges, webhook
  receipts or eligibility rows. D115 records a negative state instead of
  deleting.
- Hosted changes: flipping the switch or eligibility, deploying functions,
  migrations or `db push` (migration history still needs repair), scheduling a
  cron job for the charge worker, or **invoking `challenge-commitment-charge`**.
- Offering commitments in the TestFlight or Release build.
- Any real-money rollout. That needs everything in D113's remaining gate:
  written Stripe approval, US legal review, App Store and HealthKit clearance,
  age and jurisdiction controls, and a separately approved production rollout.

## 8. Recommended next step: Stripe test-mode end-to-end commitment test

High-level only. Nothing here was run in this session.

1. **Isolate.** Use a disposable local Supabase stack
   (`scripts/weekly-local-verify.sh` pattern) with the Stripe **test** secret
   (`sk_test_…`), or a separate fictional test account on p11b with Mason's OK.
   Don't touch Mason's real $20 goal.
2. **Save a card** with a Stripe test card (4242…) at a small amount such as $1.
   Confirm the setup, customer and webhook rows, and that Stripe shows no charge.
3. **Commit** a short goal. Confirm the frozen terms show the amount, GameTime
   as recipient, `complete_window_v1` and the one-charge rule, and a matching
   digest.
4. **Run the four outcomes:** met (no charge), no data (void, no charge),
   partial window (void, no charge), full-window shortfall (one `pending`
   charge at finality).
5. **Send the charge** with a manual dispatch invocation. Expect `succeeded`
   with `livemode=false`. Invoke it again and confirm nothing is charged twice
   (same idempotency key, no new PaymentIntent).
6. **Decline path.** Use a declining test card (4000 0000 0000 0341, which
   attaches but fails off-session). Expect `failed`, no retry, and new
   commitments blocked with `challenge_commitment_unpaid`.
7. **Webhook path.** Confirm signed events apply once and duplicates are
   ignored.
8. **Kill switch.** Switch off: dispatch claims nothing, and owner status still
   reads.
9. **Receipt** with no IDs, secrets or Health totals (the repo is public).

<a id="receipt"></a>
## Receipt

- **Tip commit:** see `git log -1` on `main`. This memo is the only change, and
  the pushed SHA is listed in the session summary.
- **Files written:** `outputs/reports/payment-rules-memo-2026-09-29/README.md`
  only. No code, UI, migration or function changed. No tests were run, since
  this is a docs-only change. No screenshots, since there was no UI change.
- **Hosted reads performed** (`gametime-p11b`, `lyushhqoednheqwzsmxh`, Supabase
  MCP, Sep 29 about 12:39 UTC). Each query ran inside `begin read only; … rollback;`:
  1. The switch, eligibility, setups, customer count, agreements joined to goal
     status and window, charge count, webhook receipts, finals for committed
     goals, and cron jobs.
  2. Health totals, admissions and reviews for the committed goal (counts and
     timestamps only).
  3. Total Health totals, the latest timestamp, and a finals count across the
     project.
  4. The Edge Function list.
- **Nothing was written** to Supabase or Stripe.
- **Stripe:** the Stripe MCP connector here exposes only an unrelated
  **live-mode** account, not GameTime's sandbox. It was listed and **not used**.
  Stripe-side state in this memo comes from p11b's own records.
- **Not done:** no TestFlight or App Store Connect upload, no live charge, no
  test charge, no charge-function call, no switch or eligibility change, no
  force-push, and no user-data deletion.
- IDs, the goal's target and Health totals are left out because the repo is
  public.
