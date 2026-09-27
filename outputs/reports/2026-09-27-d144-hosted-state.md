# D144 commitment state on gametime-p11b

Read September 27, 2026, between 19:36 and 19:41 UTC, from `gametime-p11b`
(`lyushhqoednheqwzsmxh`) only, with the owner's approval for read-only SQL for
this task. Every query ran inside `begin read only; … rollback;` through the
Supabase MCP with the project ref named, and the Edge Functions were listed
through the same MCP. Nothing was written. The checkout's linked project
(`jrkzdttophnmkxjoyioo`) was not used. The switch and eligibility were left as
found. Nothing was pushed.

## What the record said and what hosted shows

D144's Boundaries paragraph says the migration was applied "with the switch
off and no account eligible". That was true when the migration ran: it creates
the switch off and the eligibility table empty. It stopped being true within
the hour. Nothing in the repo recorded the later changes until now.

## Switch and eligibility

| Setting | Value | Last changed (UTC) |
| --- | --- | --- |
| `app.challenge_commitment_runtime_v1.enabled` | **on** | Sep 26 03:27:37 |
| Eligibility rows | 1, **eligible** | Sep 26 03:32:30 |

Hosted still has one account. The single eligibility row belongs to it, so the
owner's account is eligible.

## Stripe sandbox records

- **Card setups:** 1, `consumed`, started Sep 26 03:43:56 for $20. Test mode.
- **Customers:** 1, created Sep 26 03:43:56. Test mode.
- **Webhook receipts:** 2, both `applied`: `setup_intent.created` at 03:43:58
  and `setup_intent.succeeded` at 03:44:28.
- **Charges:** none.

## Commitment agreements

There is one.

| Goal | Window (UTC) | Goal status | Commitment | Charge |
| --- | --- | --- | --- | --- |
| Personal Steps (`apple_watch_steps_v1`) | Sep 27 05:00 – Oct 4 05:00 | active, revision 2 | $20, to GameTime, Stripe sandbox | none |

**The September 27 – October 4 Steps goal carries a commitment.** It is the
goal the [Sept 26 receipt](2026-09-26-friends-build1-settings.md) listed as
scheduled: its agreement digest matches that receipt. The commitment and the
goal were saved together, at 03:44:42 UTC on Sep 26. The
frozen terms name `complete_window_v1` and
`one_charge_after_confirmed_miss_v1`, and the stored terms digest matches one
recomputed from the terms. The goal has no final record yet.

Hosted doesn't record which app build saved the goal. The Sept 26 receipt shows
GameTime Staging 0.8.1 (1) on the phone until 16:33 UTC that day, and no
receipt describes that build.

## Timeline, September 26 (UTC)

| Time | Event |
| --- | --- |
| 02:46:24 | D144 migration recorded as `20260926024624` |
| 02:56:31 | Three commitment functions deployed (version 3) |
| 03:27:37 | Commitment switch turned on |
| 03:32:30 | Owner's account made eligible |
| 03:43 | One September 24 goal left, now void (from the Sept 26 receipt) |
| 03:43:56 | Card setup started, Stripe customer created |
| 03:43:58, 03:44:28 | Setup webhooks applied |
| 03:44:42 | Committed Steps goal saved |
| Sep 27 05:00 | Goal started |

## Migration history

103 entries. `20260926024624_challenge_personal_commitment_v1` is present;
`20260925000000` (the repo's name for the same migration) and
`20260923070000_retire_charity_v1` are absent. This matches Sept 26: the
history still needs repair before the next `db push`.

## Edge Functions

Eight deployed, all active. `delete-account` is not deployed.

| Function | Version | Updated (UTC) |
| --- | --- | --- |
| `challenge-worker` | 5 | Sep 20 09:11 |
| `challenge-snapshot` | 5 | Sep 20 09:11 |
| `challenge-monitor` | 5 | Sep 20 09:11 |
| `attest-device` | 4 | Sep 20 16:06 |
| `ingest-challenge-health` | 7 | Sep 20 17:08 |
| `challenge-commitment-setup` | 3 | Sep 26 02:56 |
| `challenge-commitment-charge` | 3 | Sep 26 02:56 |
| `challenge-commitment-webhook` | 3 | Sep 26 02:56 |

## Scheduled jobs

`challenge-worker-v1` and `challenge-monitor-v1` run every minute. The other
six `pg_cron` jobs are inactive. No job mentions commitments, so nothing calls
`challenge-commitment-charge`. Real activity admission, ingestion and
processing are on.

## What happens when the goal ends

Worked out from the source, not observed:

1. The goal ends Oct 4 05:00 UTC and waits 48 hours for Health data. At about
   Oct 6 05:00 the worker records a result with a 48-hour review window, so the
   goal becomes final at about **Oct 8 05:00 UTC** at the earliest, later if a
   review is still open.
2. Under `complete_window_v1`, a met goal, a Health total that doesn't cover
   the whole week, a total saved after Oct 6 05:00, or leaving the goal before
   it ends never charges.
3. A full-week total saved by Oct 6 05:00 that falls short is a miss. The
   trigger on `challenge_finals_v1` then queues one $20 charge as `pending`.
   The trigger doesn't check the switch.
4. Nothing sends it. The app shows "Processing one $20.00 test charge." for as
   long as it stays pending.
5. A pending charge blocks new commitments for the account
   (`challenge_commitment_limit`). Charge rows can't be deleted. A declined or
   action-needed charge also blocks them (`challenge_commitment_unpaid`). Only
   a succeeded charge clears the block.
6. With the switch off, dispatch returns nothing, but a miss still queues the
   charge. A pending charge has no age limit, so it would go out whenever the
   switch is on and the function is next invoked.
7. Stripe live mode is refused: the customer, card and charge tables reject
   live records, the webhook handler refuses live events, and the charge worker
   refuses production. No real money can move.

## Not in this record

Account, goal, Stripe and event IDs, the goal's target, and Health totals are
left out because the repo is public.
