# GameTime project memory

This file records adopted direction and working agreements. For implemented
behavior, performed checks and remaining work, use the latest entries in
[WORKING_BASELINE.md](docs/WORKING_BASELINE.md) and the
[friends TestFlight plan](docs/FRIENDS_TESTFLIGHT_PLAN.md). Dated completion
reports are evidence of their own run, not instructions for the next task.

## Adopted business direction

The owner selected **friend duels and personal performance commitments** on
September 4, 2026 ([D123](DECISIONS.md#d123-friend-duels-and-personal-performance-commitments-are-the-adopted-business-model)).
This supersedes older solo-only future scope, while preserving the rules of
existing Personal and Solo agreements. D143 removed charity.

- Friends agree to an athletic challenge, follow progress, receive a result
  and may deliberately choose a new challenge or rematch.
- Personal commitments pair a measurable athletic goal with a deadline;
  longer goals and selected progress remain within the adopted direction.
- No mandatory fixed 5K: people choose supported distances and targets.
  Historical official-5K fixtures do not define the future product.
- Participant stakes, pooled entries and winner payouts are future design
  scope. Deposits, authorization holds and later failure-contingent charges
  are different funds flows. A saved payment method is not locked money.
- Spectator wagering, a public prediction exchange and tradable contracts are
  outside the initial scope.

Active adults, especially people in their twenties who enjoy competition, are
an audience hypothesis. Interest in Kalshi or Polymarket does not establish
GameTime demand. Rematches and friends following progress are engagement
hypotheses, not proof of retention or permission to send invitations.

## Current delivery target

[D142](DECISIONS.md#d142-first-private-testflight-adds-friends-opens-apple-sign-up-and-ships-goals-first)
and the [friends TestFlight plan](docs/FRIENDS_TESTFLIGHT_PLAN.md) select the
first private build:

- Fewer than ten known testers, invited to TestFlight by email.
- Friend requests under You, with Home action rows; keep
  `Home · Challenges · You`.
- Open Apple sign-up after 21+ confirmation on `gametime-p11b`.
- Disclosed account-mode uploads for age-confirmed accounts, without a
  separate device check; authentication, source rules and consent still apply.
- Four friend goals plus Personal Steps and Outdoor runs.
- Leaderboards deferred to a following build; community and links closed on
  the server. All new amounts remain nonredeemable simulation.

These are the selected build requirements, not a statement that every hosted
setting is enabled. The working baseline and Phase 5 receipts distinguish the
applied migrations from pending settings, provider and deployment work.
D142's narrower first build does not erase D134/D135/D140/D141's later product
rules or the original acceptance requirements it leaves unchanged.

## Product, design and source authority

- [BUSINESS_MODEL.md](docs/BUSINESS_MODEL.md) separates adopted strategy,
  recommended defaults, commercial hypotheses and unresolved decisions.
- [BETA_IMPLEMENTATION_PLAN.md](docs/BETA_IMPLEMENTATION_PLAN.md) and
  [BETA_REMAINING_WORK_CONTRACT.md](docs/BETA_REMAINING_WORK_CONTRACT.md) own
  versioned challenge rules, iPhone-only architecture, community privacy and
  capacity targets. New products get new terms, models and requests.
- The September 22 adoption at the top of
  [SIGNAL_UI_MIGRATION.md](docs/design/SIGNAL_UI_MIGRATION.md) and its linked
  approved mocks control current presentation. Earlier cobalt and Signal
  studies are dated history, not alternative current themes.
- D138 selects source rules and timed-run tolerance; D139 separately versions
  Exercise credit; D141 specifies received-score leaderboard v2. Their
  contracts and reports distinguish decisions, local checks and actual source
  acceptance. Empty or missing data alone never proves a miss.
- [COPY.md](docs/COPY.md) governs app language. Preserve exact historical
  consent and Personal's promise that missing final step data does not count
  against the person.

Keep retained Personal usable until replacement acceptance. Do not delete or
reinterpret historical product records. Dormant social code, generic distance
fields and a provider identifier do not implement a new product or integration.
There is no active GameTime Watch app; iPhone reads eligible Watch-origin Health
data. Hardware is required for launch, not all pre-hardware implementation.

## Responsible engagement and unresolved commercial choices

Follow the [responsible-engagement requirements](docs/BUSINESS_MODEL.md#responsible-engagement-and-commercial-incentives):
optimize understood agreements, athletic progress, fair results and voluntary
return. Preserve consent and easy exits. Do not target people using Health data
or losses, encourage injured exercise, automate rematches or stake increases,
or reward paid-challenge frequency. Proposed prices, caps, reminder schedules
and pilot sizes remain proposals until adopted and validated.

Demand, live pricing, forfeiture recipients, permitted funds flow, provider,
jurisdiction and launch clearance remain separate decisions. New local products
use simulation; existing Personal test-only/sandbox restrictions stay intact.
No plan, cleanup or local test result authorizes live money or external rollout.

## Working agreements

Develop from local `main` in `/Users/user/Documents/GitHub/GameTime`; inspect
status first and preserve unrelated changes. Use short-lived task branches,
avoid new full clones, commit completed authorized work and merge it into local
`main`. Push requires separate authorization.

Planning does not authorize implementation. Hosted mutation, Apple-provider
changes, device actions, distribution and recruitment need their applicable
explicit authorization. Follow current receipts for target identity and gates;
old checkout paths or prompts are not authority to repeat those actions.

Do not replace the owner's active private Staging installation with the Debug
scheme. Follow the current device receipt before authorized physical work.
Keep local verification on its documented disposable stacks and preserve the
normal development database. Historical weekly acceptance is separate from
Beta source and release acceptance.

## Historical records

The completion chronology formerly repeated here is preserved in Git at
`98b511863275a2c478e2f1523569308116c9e0f9:PROJECT_MEMORY.md`. Its dated receipts
remain linked from [WORKING_BASELINE.md](docs/WORKING_BASELINE.md), acceptance
documents and [PLAN.md](PLAN.md). [Archive recovery](docs/archive/README.md)
also locates retired prompt packs and agent runs. Keep implemented behavior,
adopted decisions, proposed defaults and unverified assumptions distinct.
