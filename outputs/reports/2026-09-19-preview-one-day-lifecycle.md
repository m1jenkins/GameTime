# One-day local preview lifecycle — September 19, 2026

## Scope

This is a testing aid for an already consented `personal_steps_goal_v1` challenge.
It does not change the challenge contract, real-source admission, payment, hosted
operation, or historical Personal data. The [shortest UI walkthrough](../../docs/BETA_LOCAL_PREVIEW.md#fast-one-day-lifecycle-walkthrough)
starts with explicit agreement consent in the preview app, then uses one CLI
command to advance fictional time and check the saved result.

## Actually run

- `python3 scripts/tests/beta-preview-config.test.py -v`: **5 passed**, including
  full local-day validation across a 25-hour fall DST day, rejection of a
  one-hour window, 1- and 31-day leads, and missing consent.
- `python3 -m py_compile scripts/beta-preview.py scripts/beta-native-smoke.py`
  and `git diff --check`: **passed**.
- Started a new isolated local Supabase project on loopback ports 59421/59422
  and the foreground preview with `serve --no-open`. Docker's default address
  pools were exhausted, so this disposable project used its own temporary
  `10.254.250.0/24` Docker network.
- Through the local authenticated API, fictional account 1 confirmed age,
  requested the personal steps agreement preview, and explicitly consented to
  its digest. The saved challenge was **scheduled** for October 3, 2026,
  `00:00Z` to October 4, `00:00Z`, one full UTC calendar day and two calendar
  days after the preview's October 1 creation date. This API setup was for
  verification; a person using the documented walkthrough consents in the app.
- `latest --actor 1` returned the scheduled challenge ID. The final-source
  `lifecycle --challenge <id> --actor 1` run passed with this saved timeline:

| Saved event | Fictional UTC time | Checked result |
| --- | --- | --- |
| Active progress | Oct 3, 12:00 | 10,001 steps, fact revision 1 |
| Downward correction | Oct 5, 12:00 | 9,999 steps, fact revision 2, end +36 hours |
| Provisional notice | Oct 7, 08:00 | Goal missed; deliberately 8 hours after operational notice due |
| Review filed by account 1 | Oct 9, 07:00 | 47 hours after actual notice; resolution due Oct 12, 07:00 |
| Processing at notice review deadline | Oct 9, 08:00 | Stayed in review with no final record |
| Independent fictional operator upheld review; processed | Oct 9, 08:00 | Final corrected miss; $0 nonredeemable simulated return |

The command checked the persisted timestamps and result after each step.
Foreground preview cleanup reported `gates_off: true`, `actors_revoked: 7`,
`cleanup_failures: []`, and removal of the private credential manifest. The
disposable stack and its dedicated network were then stopped and removed.

This run did not exercise the Simulator UI, physical activity sources, human
review, hosted scheduling, or real money. It did not reset or mutate an
existing GameTime stack; all challenge records in this run belonged to the
new disposable project.
