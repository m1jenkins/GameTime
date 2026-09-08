# GameTime UI direction — September 7, 2026

Recommendation: **Athletic Clubhouse**. Bright adaptive surfaces, bold performance numbers, compact friend rows, and GameTime’s existing orange give friend challenges and personal goals a coherent home. A more forceful dark Scoreboard is included as an alternative.

This is a design exploration, not implementation or an adopted product decision. No app code, historical agreement, hosted state, payment behavior, or rollout gate changed.

## Deliverables

- [Home](01-clubhouse-home.png)
- [Friend leaderboard detail](02-clubhouse-friends.png)
- [Personal goal detail](03-clubhouse-goal.png)
- [Scoreboard alternative](04-scoreboard-home.png)
- [Exact generation prompts](prompts.md)
- [Targeted revision prompts](revision-prompts.md)
- Review page: `.lavish/gametime-ui-direction.html` at the repository root.

All four images are 853 × 1844 raster concepts, generated with the built-in imagegen tool. They have been visually inspected. Home copy was revised to count people including the current user. Scoreboard chart dates and the Challenges icon were corrected. Original tool outputs remain in the Codex generated-images directory; final deliverables are saved here and copied beside the review page.

## Product basis

The September 6 audited Beta plan controls this proposal: Home · Challenges · You; friend goals and target-free leaderboards for 2–6 people; personal goals; four Apple Health metrics; one community steps goal; no profile photos. Windows are 1–30 scheduled full local days. The pictured four-person steps leaderboard and personal mile goal are fictional examples.

The mockups cover Home and two active detail screens. They do not depict the complete creation, consent, review, community, or result flows. Source readiness and physical acceptance remain unresolved; a drawn Apple Health status is not evidence of a working connection.

## Inspiration inspected on Mobbin

- [Strava leaderboard](https://mobbin.com/screens/0208fae7-8d33-4d85-8270-f8d371facc83): aligned rank/name/distance columns. Transfer its readable hierarchy into a private friend roster, not its public activity conditions.
- [Runna Today](https://mobbin.com/screens/be9b0bcc-6c28-4abf-bde0-6b046df1207d): clear activity names, supporting totals, and a prominent action. Transfer the hierarchy, without inventing a GameTime training plan or workout recorder.
- [Gentler Streak Activities](https://mobbin.com/screens/81ddb60b-a773-448c-b64a-92cef5221268): progress chart above labeled summary values. Transfer a focused progress story; do not infer training readiness.
- Twelve screenshots across seven apps were examined. The three above are the selected references. Source metadata is preserved in `mobbin-sources.json`.

These are design interpretations of observed static screens, not usability-study results or inspected competitor interaction recordings.

## Visual system proposal

Use the existing CompetitiveTrustTheme as the design source: orange #FC5200, light canvas #F2F2F7, white surfaces, black/graphite dark appearance, thin adaptive dividers, system typography, tabular numerals, and initials. This is project design source 2 in the Lavish workflow, not a new imported design system.

- Main performance: 48–64 point starting size, scaling with Dynamic Type.
- Titles: system bold; normal body copy and names: system regular/semibold.
- Layout: 20 point base gutters, 8 point spacing rhythm, adaptive row height, 8–12 point corners.
- Orange: current person, selected progress and primary action. Darker orange for small text on light backgrounds; black labels on orange fills. Confirm all actual contrast pairs in implementation.
- Friend leaderboard: comparable totals and explicit ranks, no target or percent-complete framing. A tie must retain co-winners when final.
- Friend goal: each person’s progress toward their own agreed target; do not invent a single shared threshold.
- Personal goal: best eligible result, strict target, comparable attempts, dates and counting rule.
- Community: the current person’s progress and anonymous aggregate counts only; no stranger ranking or usernames. Numeric community settings remain undecided.
- Home: actionable reviews first, then pending consent/start, active end time, upcoming start and recent history. The concept’s invitation precedes active progress because no review is depicted.
- Navigation, sheets, selection controls and confirmation remain native. Brand character lives in the content.

## Refinements before native implementation

The generated charts are illustrative, not exact plotted data. Use real values and dates for point positions, bar lengths and thresholds. A 6:14 mile does not meet an under-6:00 goal; equality also does not qualify. The final goal chart should explicitly label the boundary as 6:00 and explain the strict-under rule.

Standardize system numeral shapes, left-aligned detail headers, banner density and small-label contrast across screens. The friend concept emphasizes all bars in orange; reserve the strongest emphasis for the current person in the final component. Keep other participants’ own update statuses available. Home’s leading-pair preview should keep the current person visible even when outside the top two.

Restore precise end times/timezones in details and complete agreements. Summarize people, metric, dates, relevant targets, simulated amounts, fees, outcomes, review and exits before explicit consent. A link opens a request; it never supplies consent. The active detail images do not replace that agreement.

Add empty, loading, offline, stale, review, tie and unavailable-result variants. Retain last known values if refresh fails. Missing data is not a confirmed miss. Separate athletic results from simulated return status. Success treatment acknowledges performance; rematches remain a fresh choice.

Next step: prototype Home → friend detail → activity in native components and test comprehension, compact devices, large Dynamic Type, VoiceOver, light/dark appearance, contrast and reduced motion. Static mockups do not validate those behaviors.

## Source files

- `PROJECT_MEMORY.md`
- `docs/BETA_IMPLEMENTATION_PLAN.md`, especially the product matrix and native shell
- `docs/COPY.md`
- `ios/GameTime/GameTime/CompetitiveTrustTheme.swift`
- Prior September 6 concepts were inspected as historical design references, not current product authority.


## Review-page verification

The local HTML was inspected in Chrome at 1440px desktop and 390px phone viewports, and in light/dark appearance. All four local mockups and three remote reference previews loaded. Page width matched viewport width. The full-size image dialog opened and closed correctly. Feedback selection is local until explicitly queued; no feedback was submitted by the agent. The small comparison illustration is an overview and is best read on desktop. Native app behavior and accessibility remain untested by this design task.
