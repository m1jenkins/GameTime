# Native Signal profile data

Implemented September 21, 2026. This describes the profile's read model, not
acceptance of a source, a device build, or release readiness. The dated native
completion report owns rendering and test results.

The ordinary `SignalProductShell` supplies its `ChallengeV1Store` to
`AppAccountNavigationView`. `ChallengeProfileView` uses that store and the
current `AppModel` actor. The retained `AppShellView` still uses `YouView` and
`PersonalAccountabilityStore`; its agreements and Health controls are unchanged.
Account configuration, privacy and support remain reachable through Settings
from the ordinary profile.

## Source and calculation

| Display | Owner and calculation | Range and limits |
| --- | --- | --- |
| Name, initials, username | `AppModel.profile`, only when its ID matches the current account | Current profile. No invented join date. |
| Upcoming | Unique loaded challenges with `scheduled` status and no own exit | The agreed dates of loaded records. Unconfirmed lobbies are still listed but are not scheduled goals. |
| Active | Unique loaded challenges with `active`, `syncing` or `review` status and no own exit | Includes waiting for activity and reviewing a result. |
| Finished | Unique loaded challenges with `final`, `void` or `cancelled` status, or an own exit | A finished count does not mean a successful goal or competitive loss. |
| Featured goal | Active record first; otherwise earliest scheduled goal; otherwise unfinished setup | Uses the existing challenge detail route and stored terms. Goal scores stay with their challenge. |
| Wins and losses | Final friend leaderboard allocations with `scored` outcome, own selected/consented/nonexited membership, and own `winner` or `placed` status | Only loaded applicable results. The displayed date span covers their final-result recording dates in the viewer's time zone. Shared wins count as wins. No ratio or win rate is inferred. |
| Personal activity totals and streaks | No complete personal activity provider exists for this profile | Shown as unavailable. No additional Health permission or read; no sum of overlapping challenge scores. |

Final competitive allocations retain their policy version. Personal goals,
friend goals, community challenges, pending reviews, unranked/excluded scores,
voids and exits cannot add a competitive loss. A privacy-restricted result may
use its server-provided own allocation; it does not reconstruct other members.

## Completeness, freshness and identity

`ChallengeProfileSnapshot` reads the four bounded section pages, not an
unbounded lifetime query. It deduplicates by challenge ID and keeps the newest
revision. Store reconciliation already applies current safety restrictions to
every cached copy. Counts never include detail-only records, which cannot
establish page completeness.

- **Complete:** the store and all four sections are fresh, the sections are
  unexpired and have no next cursor.
  Exact counts, including zero, are allowed. The screen says all saved
  challenges are loaded; it does not claim lifetime activity totals.
- **Partial:** a section has not loaded or a next cursor remains. Positive
  counts have a plus; zero becomes a dash. Load more reads one page per section
  with remaining records. Refresh returns to the current first pages.
- **Stale:** a read failed, a section expired while others remain, or the store
  invalidated the loaded aggregate after an uncertain action or account restriction. Counts
  become dashes. Unexpired rows can remain visible with a refresh explanation.
- **Unavailable:** no section remains readable, or the actor is absent or
  differs from `AppModel`. No rows or numeric counts are shown.

The checked time is the oldest server time among readable section pages. It is
a page check time, not the last successful Health upload. Rows expire after the
store's existing 60-second monotonic visibility limit; pagination does not
extend earlier rows' lifetime. The profile uses the store's injected clock.

The profile owns no persisted cache. Account changes reset selection and the
pagination task token. Each page request checks the captured actor and token;
the store also fences responses by actor, session, generation and page cursor.
`setActor` and `hide` clear the underlying records. Retained Personal records
never enter this snapshot.

`ChallengeProfileTests` covers an upcoming personal goal, active/review/finished
and exited rows, complete empty and unavailable reads, partial pages, expiry,
duplicate revisions, finalized competitive inclusion/exclusion, private own
results, pagination and account clearing. Simulator and human accessibility
checks must be recorded separately from these calculation tests.
