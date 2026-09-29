# Stripe end-to-end commitment test, local run

September 29, 2026. This runs the plan in section 8 of the
[payment rules memo](../payment-rules-memo-2026-09-29/README.md) for D144
personal commitments.

**Result:** all 48 checks passed on a disposable local Supabase stack. Stripe
was a local emulator, not Stripe test mode, because this session had no
`sk_test_` key (see [What still needs Mason](#what-still-needs-mason)). No
hosted state was written, and nothing reached Stripe.

## How it was isolated

- **Disposable local stack:**
  [`scripts/commitment-e2e-local-verify.sh`](../../../scripts/commitment-e2e-local-verify.sh)
  follows the `weekly-local-verify.sh` / `friends-local-verify.sh` pattern. It
  copies the committed `supabase/` and `scripts/` into a fresh temp directory,
  pins a unique project ID, ports and Docker network, and runs
  `supabase start`. When the run ends it stops the stack and removes the
  network. It never reads the checkout's `.env`, linked project or database.
- **What ran:** [`scripts/commitment-e2e-local-http.ts`](../../../scripts/commitment-e2e-local-http.ts)
  calls the real `challenge-commitment-setup`, `challenge-commitment-charge`,
  `challenge-commitment-webhook` and `ingest-challenge-health` handlers, with
  their PostgREST database adapters, the Stripe gateways used in production,
  and the D144 migration's SQL. Six fictional local Auth accounts each commit
  **$1** to a one-day Personal Steps goal.
- **Stripe:** a local emulator of the endpoints these handlers call:
  customers, SetupIntents, off-session PaymentIntents and idempotent replay.
  It follows Stripe's test payment methods: `pm_card_visa` (the 4242 card)
  saves and charges, and `pm_card_chargeCustomerFail` (the 0341 card) saves
  but is declined off-session. Every object it returns is `livemode=false`. The
  real Stripe SDK talks to it over loopback. Webhook events are signed with a
  secret generated for this run, and the handler then re-reads each object
  from "Stripe", as it does in production.
- **Clock:** `app.challenge_real_health_now_v1()` is replaced only in the
  disposable database, which lets the run step through the window, the 48-hour
  data cutoff, the review window and finality in minutes. It is restored when
  the run ends. Setup expiry, charge leases and tokens keep wall time.
- **Dispatch secret and signing secret:** random for each run. They are never
  printed.

## Outcomes

| Path | Result | What the run showed |
| --- | --- | --- |
| Save a $1 card | **Pass** | One setup per account is `succeeded` at $1 in test mode, with one test customer recorded. No Stripe payment and no charge row after saving. The same is true after committing. |
| Frozen terms | **Pass** | $1 USD, recipient `gametime` / `gametime_recipient_v1`, `one_charge_after_confirmed_miss_v1`, `complete_window_v1`, `stripe_sandbox`. The stored digest equals the digest recomputed from the terms, the consent digest and the preview digest. The card is `consumed`. A second commitment is blocked with `challenge_commitment_limit`. |
| Met | **Pass** | Final, scored, `met`. No charge. The owner reads "not charged". |
| No data | **Pass** | Void. No charge. The owner reads "not charged". |
| Partial window | **Pass** | Only a total queried through midday was saved. Void, no charge. |
| Full-window shortfall | **Pass** | A complete-day total below the goal, saved before the cutoff, becomes final as `missed` and queues one `pending` $1 charge with the fixed key. Nothing is queued before finality, and reprocessing queues nothing more. |
| Send the charge | **Pass** | A manual dispatch POST with the dispatch secret gives `succeeded`, `livemode=false`, $1. A second and third dispatch claim nothing. Re-sending the same idempotency key returns the same payment, and Stripe holds only one. |
| Lost reply (transport ambiguity) | **Pass** | Stripe was reached but the reply was dropped, so the charge stays `processing`. The next dispatch retries with the same key and gets the same payment back (2 attempts, 1 Stripe payment). |
| Decline (0341 card) | **Pass** | `failed` / `card_declined` after one attempt, with no retry on later dispatches. New commitments and new cards are blocked with `challenge_commitment_unpaid`. The owner reads the failed charge. |
| Webhooks | **Pass** | A signed `setup_intent.succeeded` applies once. A signed `payment_intent.payment_failed` applies once and the charge stays failed. `payment_intent.succeeded` leaves a succeeded charge alone. Each duplicate returns `duplicate` and adds no row. A bad signature returns 401, and a live-mode event returns 403. |
| Kill switch | **Pass** | With the switch off, dispatch claims nothing, the charge stays `pending`, the owner can still read "charge processing", and availability reports `challenge_commitment_unavailable`. After the run the switch was back to its starting state (off). |
| Gates | **Pass** | Dispatch without the secret returns 401. The charge worker refuses to start with `production`. With the switch off no card can be saved, and an account that isn't eligible can't save one either. |

Totals: 3 confirmed misses produced 3 test payments (2 succeeded, 1 declined).
Met and void goals produced none. Every charge row has `livemode=false`.

**Not covered:** a full-window total saved after the 48-hour cutoff (the memo
lists it as void), and a `requires_action` (3-D Secure) charge.

## Mason's real $20 goal

**Untouched.** This session made no hosted writes, no function calls and no
Stripe calls. Before the receipt, a read-only check on `gametime-p11b`
(`begin read only; … rollback;` through the Supabase MCP) matched memo
section 6: switch on, 1 eligible account, 1 setup (`consumed`), 1 customer,
1 agreement (goal active, $20), **0 charges**, 2 webhook receipts, and no
final record for the goal. The shared p11b switch was not changed.

## What still needs Mason

1. **A run against real Stripe test mode.** Run the same test against real
   Stripe test mode:
   `STRIPE_SECRET_KEY=sk_test_… STRIPE_PUBLISHABLE_KEY=pk_test_… scripts/commitment-e2e-local-verify.sh --stripe-test`.
   The wrapper refuses keys that aren't `sk_test_`/`pk_test_`, and nothing
   prints them. This mode confirms cards server-side with `pm_card_visa` and
   `pm_card_chargeCustomerFail`, and counts payments through Stripe's own
   list. It has only been type-checked, not run. The local stack is still
   disposable, and the fictional customers and test payments land in the
   GameTime Stripe sandbox.
2. **The same gap as the memo.** A `failed` charge blocks commitments until a
   webhook reports success. D144 still has no recovery or waiver path.

## Receipt

- **Harness commits:** `35232d4` (harness) and `ad07a44` (format). The final
  clean run used `ad07a44`, according to the disposable stack's input manifest.
  This receipt is the next commit, and the pushed tip is in the session
  summary.
- **Command:** `scripts/commitment-e2e-local-verify.sh` (emulator mode).
  Result: exit 0, 48 checks passed, and the stack and network removed
  (0 containers, 0 networks left).
- **No app code or UI changed,** so no unit or UI tests were run and there are
  no screenshots. The driver passes `deno check`, `deno fmt` and `deno lint`
  with the functions config.
- **Not done:** no TestFlight or App Store Connect upload, no live-mode object
  or charge, no Stripe MCP use, no hosted switch, eligibility, function or
  migration change, no `challenge-commitment-charge` call on p11b, no
  user-data deletion, and no force-push.
- IDs, keys, secrets, card numbers and Health totals are left out because the
  repo is public. The run log itself holds only labels, states and counts.
