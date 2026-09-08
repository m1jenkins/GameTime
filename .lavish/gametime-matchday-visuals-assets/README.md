# GameTime — Matchday iconography and visuals

September 7, 2026. Original design concepts. No app code changed.

## Recommendation

Continue the accepted Matchday composition. Develop its paired lanes into a consistent family of content icons, metric artwork, monogram tiles, and status stamps.

- Small icons use an original 24 × 24 grid, 1.75-unit strokes, rounded joins, and simple counters.
- Event artwork uses orange and ivory silhouettes on ink: soles, movement, running route, and timing dial.
- Monogram tiles use initials and an 8-point corner. Borders identify the participant; they never imply percentage complete.
- Status stamps accompany explicit text. The finish stamp belongs only to a confirmed athletic goal result, regardless of any simulated amount.
- Preserve familiar system navigation and Apple Health branding.

## Deliverables

- [Review](review.html): theme and icon-size controls, previous/refined Home comparison, state examples, references.
- [Metric artwork](01-metric-artwork.png): four metric illustrations on one raster concept sheet.
- [Refined Home](02-home-refined.png): imagegen edit of the accepted Matchday layout.
- [Vector icon sheet](03-icon-sheet.svg).
- [Icons](icons/): 12 individual editable SVGs.
- [Stamps](stamps/): 3 individual editable SVG concepts.
- [Exact prompts](prompts.md).
- [Mobbin records](mobbin-sources.json): 11 returned screens; names correspond to actual results.

Built-in imagegen created the artwork and edited the Home mockup. Selected outputs were copied into this workspace, preserving originals. SVGs were authored directly for deterministic, scalable icon output. All generation prompts and input roles are recorded.

## Research and transfer

[AllTrails achievement](https://mobbin.com/screens/1ca64dd4-eddc-435a-b7d8-ec1cb1c22383): visually inspected a tree silhouette on a triangular token. Transfer a distinctive simple silhouette. Do not reproduce its token shape or tree.

[Gentler Streak status](https://mobbin.com/screens/597f67c9-a016-40a8-b3fd-2e0c6cd70bf9): the illustration relates to the status heading. Transfer contextual imagery. The new GameTime objects do not provide medical or exercise recommendations.

[Phantom sports prediction event](https://mobbin.com/screens/0d42cfe6-357c-407b-95b8-eca5e0c2b77f): small symbols repeat across named outcomes. Transfer a consistent symbol family, without probabilities or financial actions.

[Oddible designer case study](https://www.flatstudio.co/work/oddible-ios): inspected the published custom icon sheet in Chrome. Repeated rounded strokes and deliberate gaps establish a family across unrelated functions. The original GameTime geometry is independently authored; no competitor assets are bundled.

[Ladder milestone badges](https://mobbin.com/screens/596685a2-58bd-4f29-9766-5fa80836ed48): inspected its large central badge and subordinate milestones. The small status stamp is a restrained treatment for an actual result, not a new collection, streak, or reward program.

## Proposed icon semantics

Steps: two separated soles.
Exercise time: moving figure; label always present.
Running distance: route with endpoints.
Timed run: stopwatch with an inner lane.
Friend goals: separate goal flags.
Leaderboard: aligned bars without a target.
Personal goal: a single flag and approach marks.
Invitation: note with an explicit plus.
Challenge rules: document.
Scheduled: calendar.
Waiting for data: open arcs and neutral center.
Goal met: finish gate with a check.

Use decorative accessibility treatment beside an equivalent visible label; otherwise give the control an explicit accessible name. Individual SVG title elements identify the standalone asset. Enlarging the icon does not replace a proper touch target.

## Scope and validation

The source of the review styling is GameTime's existing palette and system typography, extended through the user-accepted Matchday direction. Custom icons remain proposals. Native implementation, Dynamic Type, VoiceOver, contrast in real materials, and comprehension with people remain unverified.

The generated small Steps and stopwatch icons are approximations. The individual SVGs are the precise reference for future implementation. Artwork is decorative and is not a progress gauge, activity chart, or accepted result. The metric sheet remains a four-up concept, not four independently packaged production illustrations.

The Home fixture retains 4 people, 34,120 versus 32,480 steps, and $20 simulated each. It shows no target for the leaderboard. Personal goal remains strictly under 6:00, with 6:14 as the best shown attempt. The status examples are independent fictional cases: a future scheduled event, missing activity, and a confirmed 5:58 one-mile result. They do not alter the Home timeline.

Beta strategy is unchanged: friend goals, target-free friend leaderboards, personal goals, and the adopted community steps format. Initials respect deferred profile photos. No live money, messages, persistent reward system, new consent, or changed challenge agreements are introduced.


## Review checks

Inspected the generated artwork and Home edit, the 12 icons at enlarged and actual sizes, and the state stamps in dark appearance. The theme and icon-size controls work. All images loaded at desktop width. The 390-pixel browser preview revealed that the hero image widens the page; the HTML review is currently best viewed at desktop width. Standalone PNG and SVG deliverables remain available independently.
