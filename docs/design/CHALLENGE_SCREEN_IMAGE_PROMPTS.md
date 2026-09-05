# Zero-beige challenge screen image prompts

> **Scope — September 4, 2026.** These are visual references for the
> Personal steps implementation, not the future product roadmap. Their
> solo-only/no-opponent constraints do not override the adopted friend-duel and
> performance-commitment model in [BUSINESS_MODEL.md](../BUSINESS_MODEL.md).
> Mockups are not proof of implemented features, verified results or money.
> Preserve existing app behavior until a separate implementation task changes it.

Mode: built-in image-generation tool.

Reference input: none. All three directions were generated from scratch so the existing beige screen could not anchor the composition.

These prompts produce design-reference raster images, not shipping UI assets.

## Signal Sheet

~~~text
Use case: ui-mockup
Asset type: high-fidelity, shippable iOS personal step-challenge detail screen, full portrait iPhone screenshot
Primary request: Design a completely original direction named "Signal Sheet". It should combine the numerical confidence and chart-first hierarchy of a modern finance app with the immediacy of a fitness-progress screen, without copying any brand, logo, signature color, or proprietary UI.

Product context:
- This is GameTime, a private seven-day personal walking challenge backed by Apple Health.
- It is not betting, trading, a social competition, or a casino.
- Use only supported facts: seven daily step totals, daily goal, weekly total, current day, deadline, Apple Health freshness, test commitment, and verification rule.
- No opponent, leaderboard, workout route, calories, heart rate, readiness score, winnings, balance, or coaching claim.

Visual concept:
- Cool white edge-to-edge canvas. Absolutely no beige, cream, parchment, or warm paper.
- No rounded card stack. Organize with typography, plotted data, whitespace, and hairline dividers.
- Palette: black ink, emerald-teal for verified movement, cobalt for required pace and actions, violet only for test commitment, amber for deadline.
- Contemporary neutral sans serif with tabular figures. Oversized numbers, compact uppercase labels, precise alignment.
- Flat fills, no gradients, no glow, no shadows, no glassmorphism.

Exact screen structure and copy:
1. Native status bar and compact navigation: back chevron, title "Your challenge", overflow icon.
2. Open headline:
   status "IN PROGRESS"
   huge "42,350"
   label "steps this week"
   result "+2,350 ahead of pace"
   "Day 4 of 7 · Ends Friday, 11:59 PM"
3. A full-width seven-day chart with no surrounding card:
   solid emerald line labeled "Verified progress"
   dashed cobalt line labeled "Required pace"
   Mon through Sun axis, a direct label "42,350", and a target rule labeled "70,000 goal"
   show verified data only through the current day; do not imply unsupported intraday data
4. A flush three-column quote rail separated by vertical hairlines:
   "GOAL 70,000"
   "LEFT 27,650"
   "ELAPSED 4 DAYS"
5. A source row:
   Apple Health icon
   "Apple Health"
   "Updated 3 sec ago"
   compact trailing action "SYNC"
6. A divider-only terms ledger:
   "Daily target 10,000"
   "Test commitment $10.00"
   "Timezone America/Chicago"
   "How results are verified" with chevron
7. Native three-tab bar: Today, Challenges selected in cobalt, You.

Composition:
- 9:19.5 portrait iPhone proportions with realistic status and home indicators.
- The headline and chart own most of the screen.
- Critical text must remain readable at screenshot size.
- Differentiate verified versus required with solid/dashed line and labels, not color alone.

Avoid:
- beige, rounded cards, dark hero card, floating panels, capsule overload
- Robinhood acid green, feather imagery, trade controls, ticker chips, gains/loss arrows
- Strava orange, routes, kudos, crowns
- Apple Activity Rings or medals, WHOOP circular scores
- gambling vocabulary, celebration confetti, urgency countdowns
- photographic people, maps, decorative blobs, fake logos, misspelled copy, extra tabs
~~~

## Training Splits

~~~text
Use case: ui-mockup
Asset type: high-fidelity, shippable iOS personal step-challenge detail screen, full portrait iPhone screenshot
Primary request: Design a completely original direction named "Training Splits". Make the seven days themselves the interface, like an athletic split sheet crossed with the blunt, single-task confidence of a modern finance app. Do not copy any brand, logo, signature color, route treatment, or proprietary UI.

Product context:
- This is GameTime, a private seven-day personal walking challenge backed by Apple Health.
- It is not betting, trading, a social competition, or a casino.
- Use only supported facts: seven daily step totals, daily goal, current day, deadline, Apple Health freshness, test commitment, and verification rule.
- No opponent, leaderboard, workout route, calories, heart rate, readiness score, streak, winnings, balance, forecast, or coaching claim.

Visual concept:
- Cool white canvas structured by full-width horizontal bands. Absolutely no beige or cream.
- No rounded card stack. Every day is a flush row; the current day expands into the live workspace.
- Palette: saturated ultramarine for navigation and trusted source utility, hot coral-red for the current day, green for completed days, cool gray for future days, violet only for test commitment.
- Bold condensed athletic display type for day labels and metrics, paired with a clean native sans serif for utility text. Use tabular figures.
- Flat solid color, black hairlines, no gradients, no shadows, no glass.

Exact screen structure and copy:
1. A full-width ultramarine header approximately 150 points tall:
   native status bar
   back chevron and overflow icon
   small title "WEEK CHALLENGE"
   huge "DAY 3 / 7"
   "10,000 steps daily"
2. Seven edge-to-edge day rows:
   - MON: green side rule, checkmark, "GOAL MET", "10,842"
   - TUE: green side rule, checkmark, "GOAL MET", "11,104"
   - WED: expanded hot coral-red live band with "WED", "TODAY · ENDS 11:59 PM", huge "7,350 STEPS", "2,650 TO GO", and a thin progress rule ending at "10,000"
   - THU, FRI, SAT, SUN: compact cool-white rows with hollow state marker, "UP NEXT", and em dash for value
3. Attach a full-width cobalt provenance utility rail directly below the live week:
   Apple Health icon
   "APPLE HEALTH"
   "UPDATED 3 SEC AGO"
   trailing rectangular action "SYNC STEPS"
4. A single white receipt row separated by hairlines:
   "TEST COMMITMENT · $10.00 · NO MONEY WILL BE CHARGED"
   chevron
   violet only on the TEST COMMITMENT label
5. Native bottom tabs: Today, Challenges selected in ultramarine, You.

Composition:
- 9:19.5 portrait iPhone proportions with realistic iOS status and home indicators.
- The expanded Wednesday row is the only large content block.
- Completed/current/upcoming use icons and text as well as color.
- Critical copy is readable and not clipped.

Avoid:
- beige, tan, cream, rounded cards, floating surfaces, capsule overload
- line charts, activity rings, route maps, circular readiness scores
- copied Strava orange or routes, Robinhood acid green or trade controls, WHOOP dials, Apple rings
- winnings, balance, profit/loss, buy/sell, odds, celebration confetti, countdown pressure
- gradients, glossy 3D, photos, decorative illustrations, fake logos, extra tabs
~~~

## Night Course

~~~text
Use case: ui-mockup
Asset type: high-fidelity, shippable iOS personal step-challenge detail screen, full portrait iPhone screenshot
Primary request: Design a completely original direction named "Night Course". It should borrow broad principles from premium fitness instrumentation and modern finance apps—full-bleed dark canvas, one decisive live metric, precise typography, dense but calm data, and a single electric accent—without copying any brand, logo, exact palette, rings, charts, or proprietary UI.

Product context:
- This is GameTime, a private seven-day personal walking challenge backed by Apple Health.
- It is not betting, trading, a social competition, or a casino.
- Use only supported facts: seven daily step totals, daily goal, current day, exact local cutoff, challenge end, Apple Health freshness, test commitment, and verification rule.
- No opponent, leaderboard, workout route, calories, heart rate, readiness score, streak, winnings, balance, forecast, or coaching claim.

Visual concept:
- One uninterrupted near-black / obsidian canvas from status bar to tab bar. Absolutely no beige or cream.
- No rounded card stack. Organize with position, type, a vertical route line, checkpoints, and hairline dividers.
- Palette: obsidian background, warm white text, electric aqua for live movement, cobalt for trusted-source utility, violet only for the test commitment, amber for deadline. Avoid Robinhood acid green, Strava orange, and Apple Activity Ring colors/geometry.
- Typography feels contemporary, narrow, athletic, and numeric with tabular figures; still legible and native.
- High contrast, flat fills, no gradients, no glow, no glassmorphism, no shadows.

Exact screen structure and copy:
1. Native dark status bar and compact top navigation: back chevron, small title "7-DAY COURSE", overflow icon.
2. Hero is open on the black canvas, not inside a shape:
   eyebrow "TODAY · DAY 3 OF 7"
   huge metric "2,650"
   unit line "steps left today"
   smaller exact deadline "Cutoff tonight · 11:59 PM CDT"
   tiny movement summary "7,350 of 10,000"
3. Directly below, a full-height vertical course/timeline becomes the main interface. A thin aqua line runs down the left through seven day checkpoints:
   - MON: solid completed checkpoint, "10,842" and "Goal met"
   - TUE: solid completed checkpoint, "11,104" and "Goal met"
   - WED · NOW: enlarged outlined aqua checkpoint and an expanded inline readout, "7,350 / 10,000", with a long horizontal progress rule integrated into the course; add "Ends 11:59 PM"
   - THU, FRI, SAT, SUN: small hollow checkpoints with "Upcoming"
   Keep the rows flush and separated by subtle dark hairlines, not individual boxes.
4. Insert a narrow cobalt source checkpoint attached to the Wednesday section: Apple Health heart icon or simple health cross, "APPLE HEALTH · UPDATED JUST NOW", with a compact text action "UPDATE". Do not say Apple verified.
5. Near the route finish, show exact challenge consequence in a compact, unambiguous receipt ledger using dividers only:
   "CHALLENGE ENDS · SUN, AUG 16 · 11:59 PM CDT"
   "TEST COMMITMENT · $10.00"
   "NO MONEY WILL BE CHARGED"
   "Verified from Apple Health after the cutoff"
   Use violet only as a small semantic label for TEST COMMITMENT; never make the dollar amount look like winnings.
6. Bottom native three-tab bar integrated into black canvas: Today, Challenges selected in aqua, You. Correct safe-area inset.

Composition:
- 9:19.5 portrait iPhone proportions, realistic iOS status and home indicators.
- The hero occupies about 25% of the screen; the course occupies about 55%; receipt and tabs fit without clipping.
- Use a strong asymmetric left rail and generous negative space. Make it feel like a live performance instrument, not a dashboard of cards.
- Critical text must be readable at screenshot size and numbers should align cleanly.
- Differentiate completed/current/upcoming with shape, labels, and typography, not color alone.

Avoid:
- beige, tan, cream, parchment, warm paper, rounded rectangular cards, floating panels, capsule overload
- copied Robinhood neon/feather/trade controls; copied Strava orange/routes/kudos; copied WHOOP circular scores; copied Apple rings/medals
- charts that imply unsupported intraday data
- profit/loss arrows, stock tickers, buy/sell language, gambling vocabulary, celebration confetti, urgency countdowns
- gradients, glossy 3D, photographic people, maps, illustrations, decorative blobs
- fake logos, misspelled copy, illegible microtext, extra navigation tabs
~~~
