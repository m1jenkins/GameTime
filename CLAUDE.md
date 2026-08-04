# Working in this repository

## Read these first

- [README.md](README.md) — what works today, how to run it, how the evidence
  ledger works.
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
- Fail-closed scoring protects the person. Say so plainly: if their data goes
  missing, the week doesn't count, and it never counts against them.

If a new concept genuinely has no plain-English name, add a row to the
glossary in `docs/COPY.md` rather than inventing a second name for it
somewhere else.

`GameTimeUITests` asserts on visible copy and fails on the competitive-social
vocabulary Personal V1 dropped. Update the assertions in the same commit as
the copy.
