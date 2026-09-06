# Game Time — weekly challenge concepts

The owner requested 100,000 steps in one week and 400 activity minutes this week as additional design examples. These use the same visual identity, with a weekly total and daily contributions replacing the timed-5K attempt chart.

## Reusable challenge patterns

| Pattern | Example | Main visual | What success means |
| --- | --- | --- | --- |
| Week total | 100,000 steps in a week | Accumulated total, progress track, daily bars | Total reaches the target inside the agreed week |
| Week total | 400 activity minutes this week | Accumulated minutes, progress track, daily bars, counted workouts | Counted time reaches the target inside the agreed week |
| Every day | 10,000 steps each day for seven days | Daily completion marks plus selected-day detail | Each day satisfies its own target |
| Best attempt | Run a 5K under 25:00 | Best comparable attempt and chronological attempt plot | An accepted attempt beats the agreed time |

“Every day” is an additional design pattern, not a newly selected launch requirement. The two requested examples are totals; no daily minimum is implied. Rest days are compatible with reaching a weekly total.

A common creation flow can ask for the metric, target, time window and personal/friend format, then show the actual source and rules before agreement. A friend version needs its own agreed outcome: both reaching a target, first to reach it and highest total are different formats. This exploration does not silently choose one.

## Exact fictional data

Example week: Monday September 21 through Sunday September 27, 2026, America/Chicago. Snapshot follows the end of Thursday. The mockup's “3 days left” is a calendar-day summary. A final agreement needs the exact start/end instants and timezone; “this week” and a rolling seven days remain separate choices.

| Day | Steps | Activity minutes |
| --- | ---: | ---: |
| Mon | 12,300 | 50 |
| Tue | 15,800 | 65 |
| Wed | 14,400 | 45 |
| Thu | 18,200 | 80 |
| Fri–Sun | Upcoming | Upcoming |
| Total | 60,700 | 240 |
| Target | 100,000 | 400 |
| Remaining | 39,300 | 160 |
| Fraction complete | 60.7% | 60% |

Daily bars begin at zero and show each day's contribution, not the running total. Future days are dashes, not recorded zeros. Unknown past data needs a distinct “Waiting for update” state. No daily red/green pass/fail state belongs on the weekly-total view.

## Proposed activity-minute definition

For this concept, one activity minute is one minute of recorded workout time. Pauses are excluded and overlapping time counts once. This is a proposed Game Time rule; the current app does not implement this new ingestion and counting policy. Accepted workout types, source precedence, manual entries, pause availability and late updates need a concrete policy before implementation.

The minute definition belongs visibly near progress and in full before agreement. It must not silently combine providers' differently defined metrics:

- Garmin's intensity-minute total doubles vigorous minutes. See [Garmin's official manual](https://www8.garmin.com/manuals/webhelp/GUID-4205DB9F-0ACD-4AC2-86A8-957F27150AE4/EN-US/GUID-63522E07-AD5E-4D2D-B680-3129A2300238.html).
- Apple Exercise time uses qualifying brisk activity, including activity outside a recorded workout. See [Apple's Exercise-time definition](https://developer.apple.com/documentation/healthkit/hkactivitysummary/appleexercisetime).

If the intended product is specifically “400 Garmin intensity minutes,” use that name and weighting. If it is Apple Exercise minutes, use that source's definition. The 400-minute target is the owner's example, not a health recommendation.

## Visual and interaction direction

Preserve the first pass's warm canvas, tabular hero numbers, orange data, black primary buttons and quiet source status. Weekly progress uses a horizontal completion track and seven day positions. A source-driven goal uses “View daily activity” or “View workouts”; a manual check-in does not add verified steps or counted workout time.

On selecting a day, show the exact total and give one light selection haptic. On a fresh confirmed goal completion, give one success haptic and readable status. No background sync vibration, repeating urgency or celebration of money. These are proposed native behaviors; the PNGs are static.

[Inspected Strava weekly widget on Mobbin](https://mobbin.com/screens/1c996718-ab94-4247-85b3-80885bab44c9) provided a reference for compact day labels and bars; it is an activity-count widget, not proof that Strava uses our proposed minute definition.

## Deliverables

- [Weekly steps mockup](05-weekly-steps.png)
- [Weekly minutes mockup](06-weekly-minutes.png)
- [Exact prompts](weekly-prompts.md)
- [Comparison gallery](index.html#weekly)

Generated with built-in imagegen, one original image per page. PNGs are concept assets. Existing app code, agreements, provider integrations and payments are unchanged. These screenshots contain no amount or payment action, so they omit an ambient money-mode banner; any later stakes screen must retain its actual mode disclosure.

Both generated images were visually inspected: the displayed daily values add to their hero totals, remaining amounts are correct, and future days are explicitly upcoming. Bar heights and completion-track fills are illustrative raster geometry; a native implementation should compute them directly from the values. The screenshots share 853 × 1844 dimensions. Secondary rules links should use a stronger accessible text contrast in implementation.
