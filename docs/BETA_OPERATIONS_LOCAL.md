# Beta local operations — b7

This runbook targets only project `gametime-finish-b7`, API 58321, DB 58322.
Run commands from the isolated branch worktree. The CLI refuses any other project
or URL. These commands are **not hosted instructions**. All activity is fictional;
no real-source, ingestion, analytics, payment or distribution gate can be enabled.

## Monitoring and recovery

```sh
scripts/beta-operator.py --owned-project gametime-finish-b7 status
scripts/beta-operator.py --owned-project gametime-finish-b7 run-once --run-id "$(uuidgen)" --limit 20
```

The status includes source/processing/admission switches, due count, missing
notice count after the operational +72-hour deadline, overdue reviews and recent
SQLSTATE-only failures. No raw records or request bodies enter these summaries.
A batch examines at most 50 challenges belonging to currently allowlisted
fictional creators. With processing paused, safety checks still run. An outage
never silently shortens the actual notice's 48-hour review window. A changed
allocation produces another notice and full window. Unanswered reviews exclude
the affected result conservatively; insufficient eligible participants void the
challenge and return simulated entries.

Keep the UUID and limit for a run if its response is interrupted. Retry exactly
those arguments to retrieve the saved response. Changing the limit under that UUID
is rejected. The CLI does not loop or create a new request automatically. A failed
item reports SQLSTATE, leaves its transaction changes rolled back, and can be
retried in a later bounded pass after diagnosis. Preserve old run receipts.

## Assigned operators

A service owner grants one capability for one challenge, expiring within seven
days. A participant cannot review/moderate their own challenge. A suspended or
expired operator cannot read cases. Use fictional actor 7 as the independent
operator while the preview controller is active; `--email` instead prompts for a
**local** account password without logging. CLI logout ends only that login's
session, preserving simultaneous participant/native sessions.

```sh
scripts/beta-operator.py --owned-project gametime-finish-b7 grant \
  --actor "$OPERATOR_UUID" --challenge "$CHALLENGE_UUID" \
  --capability review --expires 2026-10-25T12:00:00Z
scripts/beta-operator.py --owned-project gametime-finish-b7 --local-actor 7 \
  cases --challenge "$CHALLENGE_UUID"
scripts/beta-operator.py --owned-project gametime-finish-b7 --local-actor 7 \
  resolve --challenge "$CHALLENGE_UUID" --review "$REVIEW_UUID" \
  --decision upheld --request-id "$REQUEST_UUID"
```

Choose `upheld` only when the normalized result matches the agreed rule. `exclude`
removes the disputed result, returns its simulated entry, and may void a leaderboard
or an undersized group. Do not infer missing physical-source facts. Case context
includes only the filer, their structured reason, agreed policy/window/digest,
optional goal, latest normalized fact and their provisional allocation. It excludes
other participants' histories, raw Health samples, source IDs and routes. Case and
report reads and operator actions are audited. No freeform sensitive review text
is collected. Deadline equality closes resolution; actual time is returned by status.

For safety, grant `moderate` with the same scope/expiry. Commands `reports`,
`remove`, `suspend`, and `close-community` have `--help`. Removal affects the named
challenge; suspension hides shared data and triggers safe settlement of unfinished
participation. Own final history remains available. Blocking and voluntary leaving
remain participant actions. Community closure returns all simulated entries and
preserves the agreement and audit history. These actions do not delete accounts,
Health records, historical agreements or legacy rows.

Publication is available only as `publish-fixture --fictional`, with explicit
config JSON, target, minimum, capacity and request UUID. It stores
`unapproved_fixture_only`. Community settings have not been accepted for a pilot;
real publication and discovery must stay disabled.

## Executed drills and pending acceptance

`scripts/beta-operator-smoke.py` passed 11 authenticated local CLI checks, including
unauthorized rejection, scoped context, exact recovery across separate logins,
worker recovery, session isolation, report/suspension privacy and safe closure.
SQL 497 passed 19 assertions, including processing pause, delayed notice and
unanswered review producing a new full review window. The all-policy native run
also filed reviews and left active challenges with admission/processing paused.
These are fictional local evidence, not physical or hosted acceptance.

Before hosted use: obtain explicit authorization, accepted source policies,
monitored support and named operators; provision new-product hosted client wiring,
least-privilege credentials and an approved scheduler/alert destination; repeat
these drills there. Never run this CLI against another stack or copy local fixture
credentials into a hosted environment. See the finish-line handoff for gates.
