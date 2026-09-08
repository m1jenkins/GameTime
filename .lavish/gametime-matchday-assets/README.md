# GameTime — Matchday refinement

September 7, 2026. Design exploration only.

## Recommendation

Continue with **Matchday**: a distinctive event card, paired participant results, comparative progress, and a compact summary of the agreed terms. Preserve clean system numerals and GameTime orange. Use one strong ink panel within an adaptive light shell to create visual hierarchy.

The prior Clubhouse concept emphasized a large isolated step total. This iteration gives the challenge, participants, and goal more identity. This recommendation is a design judgment, not a validated user preference or new adopted business decision.

An optional clarification asked what felt off. No answer had arrived before generation; the working assumption was that the previous composition needed more character and competition emphasis. The palette is retained so the composition can be judged independently.

## Saved mockups

- [Home](01-matchday-home.png)
- [Friend leaderboard](02-matchday-challenge.png)
- [Personal goal](03-matchday-goal.png)
- [Generation prompts](prompts.md)
- [Typography revision prompts](revision-prompts.md)
- [All Mobbin screen metadata](mobbin-sources.json)
- [Portable review](review.html)

Built-in imagegen was used. Final images were copied from the Codex generated-images directory without deleting originals. The final Home and goal images incorporate targeted typography revisions. All images are 853 × 1844 raster concepts.

The live review source is `.lavish/gametime-matchday-refinement.html`; assets are copied beside it. Previous concepts remain intact.

## Selected references and recognition

### Ladder

[Mobbin workout screen](https://mobbin.com/screens/6d965138-0e56-46b6-9e0d-254622b27d67).
Inspected the emphatic workout title, dark content treatment, prominent featured activity, and team context.

Transfer: an authored visual hierarchy and strong primary content object. Keep GameTime’s colors and component identity original.

Recognition: [Apple’s 2025 iPhone App of the Year finalist](https://www.apple.com/newsroom/2025/11/apple-announces-finalists-for-the-2025-app-store-awards/), not the winner.

### Gentler Streak

[Mobbin status screen](https://mobbin.com/screens/597f67c9-a016-40a8-b3fd-2e0c6cd70bf9).
Inspected the contextual illustration, plain-language state heading, and supporting status graphic.

Transfer: make the situation understandable before showing detailed data. Do not transfer health or recovery prescriptions into GameTime scoring.

Recognition: [2024 Apple Design Award winner for Social Impact](https://developer.apple.com/news/?id=3m0ht22s); Apple also identifies its 2022 Apple Watch App of the Year win.

### Phantom prediction markets

[Mobbin sports event](https://mobbin.com/screens/0d42cfe6-357c-407b-95b8-eca5e0c2b77f).
Inspected the event title, colored comparison chart, named outcomes, and aligned value controls.
[Rules and timeline](https://mobbin.com/screens/c14b7161-2ef2-4644-ad38-63a1a3b1923d) separately show expandable event conditions.

Transfer: keep event identity, comparison, and people together. In GameTime the series represents measured athletic performance, not probability; the rows open participant/activity detail, not positions.

No award claim was verified or made for this reference.

### Oddible / Flatstudio

[Published designer case study](https://www.flatstudio.co/work/oddible-ios).
Visually inspected the overview of the iOS design and the My Bets screen’s open-entry composition in Chrome. The card groups a sporting event, a selection, current progress, and discussion beneath the owner context.

Transfer: make a challenge card self-contained with context and status. The betting product’s promotions, forecasts, arbitrage, payouts, badges for betting, and social-copy mechanics do not become GameTime features.

This is designer-published work, not a Mobbin screen or verified award winner. Case-study performance claims were not independently validated and are not used as evidence for the recommendation.

## Research scope

26 returned screen records, 24 unique Mobbin screens, were examined in this round. Named searches for FanDuel, DraftKings, Kalshi, Robinhood, and Sleeper produced other apps; these were never attributed to the named products. A general web betting query also returned unrelated products. The useful prediction-market reference was Phantom. Oddible supplied a supplementary primary-source betting design reference.

Award verification also confirmed AllTrails as Apple’s 2023 iPhone App of the Year, but its visual design did not drive the final mockups. Awards are attributed to the exact app, platform/category, and year; a finalist is not called a winner.

## Five design changes

1. Event identity replaces the isolated giant total as the primary Home object.
2. Your performance appears beside a friend’s, with the total roster clearly stated.
3. Dark challenge panels and light supporting content establish intentional contrast.
4. Comparison charts tell the contest’s progress, with exact standings beneath.
5. Dates, participants, and the simulated amount belong in a quiet agreement summary.

Keep Home · Challenges · You. Actionable reviews and pending consent must precede active progress in the real Home projection. The sample shows one invitation plus two active challenges. Four people in the featured leaderboard includes the current user.

## Exact illustrative data

Friend cumulative steps; daily values are observations, not qualifying targets:

| Person | Mon | Tue | Wed | Thu |
| --- | ---: | ---: | ---: | ---: |
| Alex | 8,000 | 17,000 | 25,000 | 34,120 |
| You | 8,500 | 16,400 | 24,400 | 32,480 |
| Sam | 7,200 | 15,200 | 22,400 | 29,860 |
| Jordan | 6,800 | 14,000 | 20,100 | 27,410 |

Alex’s current lead over You is 1,640 steps. The leaderboard has no target or percent-complete rule.

Personal goal: run 1 mile strictly under 6:00 during September 7–30, 2026. Attempts: September 7 at 6:42, September 8 at 6:28, September 10 at 6:14. The current best has not met the goal. Equal 14-second improvements should have equal vertical distances; September 8 belongs one third of the horizontal date interval.

## Remaining visual limitations

The generated friend chart does not precisely match all daily values or crossings, including the first day when You should be above Alex. The personal chart still has approximate date spacing and point placement after the attempted correction. These are composition studies, not exact charts; implement the series above deterministically.

The friend detail retains a trophy tab icon and differs in selected tab/title typography from the final Home and goal. Normalize to the flag icon and the actual parent navigation when implementing. Avoid interpreting the image model’s residual typography differences as three separate systems.

Check small-label contrast, especially the simulation disclosure. Native layouts need Dynamic Type, VoiceOver, light/dark, reduced-motion, and compact-device verification. Preserve per-person source freshness; a global update row is not enough to imply every participant is current. Use exact end instants and full rule review before consent.

The comparison chart is a proposed user-facing presentation, not evidence that the approved privacy contract currently exposes historical series for every friend. Confirm the minimum necessary history and permission model in native design; otherwise restrict the chart to the user’s own history and show the agreed shared totals.

Friend goals use each person’s agreed target. Community uses one common steps target and only the participant’s own progress plus anonymous counts. Those alternative formats are not fully mocked in this round.

## Scope

The September 6 audited Beta plan controls product meaning. Profile photos, wallet, live payments, public betting, and automatic rematches remain outside this design. All illustrated stakes are nonredeemable simulation. An active card is not a substitute for explicit agreement review. No app implementation, agreement, hosted system, or product-plan adoption changed.


## Review-page verification

Chrome checks at 1440px desktop and 390px phone viewports found no horizontal page overflow. Light and dark page appearance were rendered. The three new mockups, previous Home, and four remote reference previews loaded. The image dialog opened and closed. No feedback was submitted by the agent. These checks apply to the review page, not the native app.
