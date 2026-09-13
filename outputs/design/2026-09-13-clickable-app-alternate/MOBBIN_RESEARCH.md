# Mobbin research — Signal

Inspected September 13, 2026, before implementation. Mobbin’s connector supplied inline images and app labels. Exact screen links not returned by search were opened and visually inspected in Chrome. Only interaction patterns and hierarchy transfer; no Mobbin screenshots, layouts, branding, artwork or content are embedded in the prototype.

## Supplied references

| Reference inspected | What the screen actually shows | Borrowed | Deliberately avoided |
| --- | --- | --- | --- |
| [Strava leaderboard](https://mobbin.com/screens/0208fae7-8d33-4d85-8270-f8d371facc83) | A qualification note, Overall/Following switch and ranked rows with right-aligned distances | Fixed rank/name/value columns, contextual rules near standings, compact rows | Public visibility requirements, profile photos, orange brand, invite placement and exact composition |
| [Strava activity detail](https://mobbin.com/screens/125cbc4d-55cc-4abc-82d0-4ff489ed616e) | A map with floating back/save/options, a solid lower activity sheet and paired statistics | Clear division between floating controls and solid information; titled activity and aligned metrics | Map/location claims, route artwork, photo identity, PR badges, intelligence prompt and map-led hero |
| [Strava device connection](https://mobbin.com/flows/e53b9705-8d37-4720-975c-5b40e76fb6bd) | Settings → device chooser → Apple Watch introduction with Set up later | A deliberate connection journey, explanation before access, easy exit | Brand grid, unsupported device integrations, full-screen photography and implied permission/readiness from completing setup |
| [Runna Today](https://mobbin.com/screens/be9b0bcc-6c28-4abf-bde0-6b046df1207d) | Week/date strip above completed strength and run records; run metrics; Record workout action | Date context, compact recorded-activity story, concise values associated with the activity | Prescribed workouts, badges, coaching pressure, bright card rails, repeated cards and an in-app workout recorder |
| [Gentler Streak Activities](https://mobbin.com/screens/81ddb60b-a773-448c-b64a-92cef5221268) | Week/Month/Year/All Time, selected-day chart, summary tiles, history and floating bottom controls | Selected day linked to exact values; floating controls separated from solid chart/history | Energy/calorie emphasis, summary tile grid, multi-accent palette, streak incentives and exact shapes |

## Additional searches

- [Garmin Connect steps](https://mobbin.com/screens/9244907f-a9e2-4675-af0d-cda01148dd74): seven daily bars with visible axes and a selected day. Borrowed honest daily buckets and exact totals; avoided a goal ghost/target on a leaderboard, black-green palette and distance inference from steps.
- [Strava splits](https://mobbin.com/screens/35f397b6-0733-419c-ba8a-9d1a659a79f2): aligned split rows and a chart-inspection hint. Borrowed the relationship between a split and its duration; avoided the exact chart styling, HR/elevation columns and copy.
- [Strava run summary](https://mobbin.com/screens/b0c663fc-134d-441f-a45a-1ab1a164824b): workout identity with paired metrics, device and context. Borrowed metric hierarchy; avoided weather, calories, kudos and public social claims.
- [Strava segment leaderboard](https://mobbin.com/screens/bfaa6f9c-b9c9-4a71-b6b9-6e049959832a): ranked time rows, filters and crown emphasis. The aligned times are useful; crown/status competition and upsell did not transfer.
- [Runna plan overview](https://mobbin.com/screens/61249296-39e2-4d16-8d37-a4479b535b88): schedule and current-week navigation. Borrowed bounded week context only, not coaching or prescribed effort.
- [Gentler Streak additional activity view](https://mobbin.com/screens/2d8d8f0d-f00a-40c7-8750-97f70ab1aa62): chart selection above activity history. It reinforced the chart-to-history sequence; summary cards and calories did not transfer.

Two searches naming Robinhood did **not** return a reliably labelled Robinhood screen. They returned [Acorns](https://mobbin.com/screens/29624482-0645-4774-8ac3-1de769640ff2), [Binance](https://mobbin.com/screens/931bba5e-26b6-47e2-9097-f56830fd4720), and [TradingView](https://mobbin.com/screens/b0a08c45-10bf-4d4e-bc41-7955e2906c74). These labels remain intact. No Robinhood-specific screen attribution is claimed. The owner’s request supplies numerical confidence and restraint as design intent. Financial values, trading controls, returns, stock-style area charts and market comparisons from the returned screens were deliberately rejected.

## Resulting decisions

Daily bars describe activity rather than price. The future day is outlined and labelled “Not started”, not rendered as a zero. A selected-day lens and an accessible range control reveal day, amount and completion status. Friend rows expand to only their shared challenge activity. Personal activity has no ranking. Glass lives on floating controls; charts, rows, rules and outcomes remain opaque.

Browser research does not establish native source availability, native Liquid Glass behavior or adoption of any competitor feature.
