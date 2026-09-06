# Working in this repository

## Read these first

- [PROJECT_MEMORY.md](PROJECT_MEMORY.md) — the owner's adopted business
  direction: friend duels and personal performance commitments. This controls
  future product planning where older solo-only scope conflicts with it.
- [README.md](README.md) — what works today, how to run it, how the evidence
  ledger works.
- [docs/BUSINESS_MODEL.md](docs/BUSINESS_MODEL.md) and [PLAN.md](PLAN.md) —
  adopted products, recommended defaults, implementation order, and open gates.
- [DECISIONS.md](DECISIONS.md) — why the product is shaped the way it is.
- [docs/COPY.md](docs/COPY.md) — **required before writing or changing any
  user-facing string.**

## User-facing language

The domain vocabulary is precise and it stays precise in code, schema, and
docs. It does not go on screen. Anything a person reads in the app — labels,
buttons, empty states, alerts, every `errorDescription` — is written the way
you would say it out loud to the person using it.

Before adding a string to a view or a `LocalizedError`, check it against
[docs/COPY.md](docs/COPY.md). The short version:

- Say what happened and what to do next. Errors without a next step are bugs.
- "We" for GameTime, "you" for the person. Avoid passive voice.
- No *trusted*, *evidence*, *coverage*, *frozen terms*, *cadence*,
  *diagnostic*, *attestation*, *eligibility hold*, *inconclusive*, *waived*,
  *surface*, *retry record*, *protected storage*, or *handle* on screen —
  `docs/COPY.md` has the replacement for each.
- No build, infrastructure, or Apple-framework names on a shipping screen —
  no *Staging*, *Debug*, *HealthKit*, *App Attest*, *Supabase*, *Edge
  Function*.
- Never render a raw identifier as prose. Map reason codes to sentences
  (`PersonalReasonText`); show unknown ones as `Reference: <code>`.
- Preserve the current Personal promise: missing final step data does not count
  against the person. New duels and performance commitments use their own
  versioned proof/review rules; missing data alone must not imply a loss.

If a new concept genuinely has no plain-English name, add a row to the
glossary in `docs/COPY.md` rather than inventing a second name for it
somewhere else.

`GameTimeUITests` currently rejects competitive-social vocabulary on reachable
Personal screens. That is a Personal regression rule, not a global ban on
friend, invitation, winner or rematch in new duel screens. When implementing
new routes, scope those assertions by product and add new-product checks in
the same commit as the copy. Do not change historical consent strings.

## Product boundaries

Future product authority is PROJECT_MEMORY.md, docs/BUSINESS_MODEL.md, PLAN.md
and D123. Beta and design documents describing solo-only behavior govern the
existing Personal implementation or their dated exploration, not future scope.
Preserve Personal, Solo and legacy charity agreements and their test-only or
sandbox restrictions. New products receive new terms, models and request
formats; generic distance fields and dormant social code do not implement them.
The pivot authorizes planning, not payments, hosted mutations or deployments.

## Engagement changes

For notifications, badges, streaks, celebrations, social invitations, incentives,
paywalls, analytics/experiments and financial admission, apply
[the responsible-engagement requirements](docs/BUSINESS_MODEL.md#responsible-engagement-and-commercial-incentives).
Review what behavior the feature increases and whether greater use could raise
financial exposure or exercise pressure. Preserve explicit consent and easy
exits; never use health data or losses for revenue targeting. Keep implemented
controls distinct from proposed defaults. Use the current order in PLAN.md,
not the completed fixed-5K implementation prompt, to select new work.


## Reproducing weekly local acceptance

Use `scripts/weekly-local-verify.sh` from a committed checkout for the full
portable weekly gate. It creates and tears down a unique disposable local
Supabase project; it does not reuse the original development stack. Do not run
`db reset` or the reset-owning `scripts/db-test.sh` against another checkout's
running project. Native HTTP smoke uses its own documented 5632x disposable
stack, fictional Auth actors and cleanup; it never targets hosted credentials.
See [WEEKLY_LOCAL_ACCEPTANCE.md](docs/WEEKLY_LOCAL_ACCEPTANCE.md) for exact commands,
run evidence and unperformed physical/human/pilot gates.
