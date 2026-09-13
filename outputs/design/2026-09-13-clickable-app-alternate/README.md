# GameTime — Signal

A second, independent visual study, September 13, 2026. Open [the clickable prototype](index.html). The original [Fieldwork Glass study](../2026-09-13-clickable-app/index.html) is preserved beside it.

Signal translates the brief’s numerical confidence and athletic activity storytelling into a precise daily instrument. Large totals, honest daily charts and compact ranked rows replace Fieldwork’s warm paper, club boards, condensed headings and printed imagery. The interface carries no trading language, account balance, stock-style chart, badge economy or exercise pressure.

## Run and explore

Open `index.html` directly, or serve the design folder:

```sh
python3 -m http.server 8793 --bind 127.0.0.1 --directory outputs/design
```

Then open `http://127.0.0.1:8793/2026-09-13-clickable-app-alternate/index.html`.

The desktop rail jumps to nine principal screens. On a phone, open **Signal · Fictional preview** for the full 21-screen picker and appearance controls. The app itself supports navigation through Home, Challenges and You. The phone content scrolls beneath the floating navigation bar.

Deep links use `?screen=leaderboard&appearance=dark&material=solid`. Optional `contrast=more` and `motion=reduced` make fallbacks easy to compare. All assets are local HTML/CSS/JS and authored SVG icons. There are no external fonts, scripts, application requests, credentials, analytics or persistence. Reload resets every draft and response.

## Design thesis

The usage scene is a quick check of an athletic week, often in daylight. Cool white is the opening appearance; dark ink is a complete alternate for lower ambient light. Activity remains the first thing to read in both.

- **Hierarchy:** screen → activity total → exact time context → daily plot → actionable invitation → distinct friend and personal progress. Amounts appear at decisions and outcomes rather than dominating Home.
- **Palette:** light content `#FBFCFE`, ink `#141C28`, secondary text `#5A6879`, silver dividers `#D8E0EB`, electric blue `#2458ED`. Dark content `#141A23`, text `#F1F5FB`, secondary `#A2AFC0`, dividers `#303C4D`, blue `#86A9FF`. All accents belong to one blue family. Inactive bars use contrast-checked shades.
- **Typography:** the native system sans stack, with Helvetica Neue/Arial fallback, supports the iOS study without loading a web display font. Tabular numerals are global. Primary activity totals are 64 px, headings 32 px, row titles 14–16 px, compact supporting text 11–13 px. No condensed face, italic editorial display or decorative monospacing.
- **Component grammar:** open data sections, thin horizontal rules, fixed rank/name/value columns, solid activity rows, paired statistics and plain term lists. Rounded geometry is concentrated in interaction controls. Notices use a restrained solid inset; charts and consent never become a stack of glass cards.
- **Icons:** original 24-unit stroked SVG symbols at a consistent 1.7-unit weight. No copied competitor icons, monograms or participant photography. The three-stroke GameTime mark belongs only to this proposal.

## Invitation and personal-goal refinement

The second pass keeps Signal’s palette and controls while giving invitations, agreement review and the personal goal more varied composition. Invitation goals sit in an opaque blue-tinted band; exact start/end dates form a horizontal span; each friend’s proposal has its own column without ranking the targets. Agreement summaries use the same date and proposal patterns across all formats, with full rules and explicit consent preserved.

The personal goal now leads with a solid accent section for 95 exercise minutes. Its three segments represent the recorded 28, 35 and 32 minutes, within exactly 95/150 of the total track. “This goal is yours” follows immediately as an open privacy statement. Home totals, personal progress and activity distance receive selective blue emphasis. Dates, amounts, rule text, saved agreements and all action behavior remain intact; financial amounts receive no new promotional emphasis. No new accent family or animation was introduced.

## Signature interaction

Drag across the weekly bar chart. A floating glass lens follows the selected day and reveals its exact total and status. Keyboard users focus **Explore daily steps** and use arrow keys, Home or End. An accessible value names the full date, total and completion state. The chart also has a complete text alternative.

Saturday is explicitly partial; Sunday says **Not started**, rather than inventing a zero. The activity totals sum to 38,620. A friend row also expands into a precise, arithmetically consistent shared activity timeline. Personal activity opens an independent detail screen with meaningful run splits; it never becomes a friend ranking.

## Liquid Glass rules

Glass belongs to navigation, toolbar actions, segmented controls, primary/secondary buttons and the selected-day interaction callout. It combines a translucent body, backdrop blur/saturation, directional rim lighting, inset edge shading, soft elevation and pointer-reactive highlights. The moving lens reveals background color and grid structure beneath it. This is an optical browser approximation, not native Liquid Glass.

The data layer stays opaque: chart fill, axes, totals, ranked rows, activity history, rules, consent and results. A consistent capsule/circle language groups controls. The glass chrome can move over content; content is never blurred for decoration.

**Solid mode** preserves identical control geometry and replaces blur, glare and elevation with opaque fills and a readable border. CSS handles `prefers-reduced-transparency`, `prefers-contrast`, `prefers-reduced-motion`, unsupported backdrop filters and forced colors. The preview also exposes explicit contrast and motion controls. Normal text, focus and selected states do not depend only on tint.

Apple’s [Materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials) and [custom Liquid Glass guidance](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views) informed the separation of content from interaction chrome. See the [material review](LIQUID_GLASS_REVIEW.md) for the native mapping and validation boundary.

## Motion rules

The deliberate moving element is the selected-day glass lens: 130 ms position easing, preserving the exact value immediately. Interactive glass responds to a pointer through bounded highlights. Pressed glass controls scale to 97%; navigation and segmented-control lenses have a 340 ms ease-out when their existing geometry changes. Page renders themselves are immediate; no animated page entry or chart count-up is claimed. The browser redraws segmented controls on a screen change, so this is not a native morphing demonstration.

Reduced motion removes transitions, press scaling and pointer-driven highlights. There is no ambient animation, confetti, reward pulse, countdown pressure or prescribed exercise.

## Clickable journeys

- Home → day scrubber → friend standings / personal goal → activity splits.
- Challenges → active / upcoming / finished → detail, invitation or result.
- Create → format → one of four activities → dates → simulated amount → draft → friend selection when relevant → full agreement → explicit consent → receipt.
- Invitation → review → deliberate checkbox → saved example response, while another friend still needs to agree. Declining is neutral.
- Result → standard / tie / missing-data scenarios → validated review reason and optional note → saved example request → paused simulated result.
- You → Health example states, privacy, pause on new commitments, support note, earlier agreements and voluntary exit.
- Friend and personal exits retain distinct histories and pending simulated-return receipts. Pausing new commitments leaves existing reads, reviews and exits available.

Field validation covers 1–30 full days, starts 2–30 calendar days after the fictional September 12 clock, whole simulated dollars from $1–$500, valid positive goals, strict timed syntax, a chosen running distance, and a minimum two-person friend roster. Target fields never appear for a leaderboard. A timed leaderboard’s distance describes the run being compared; it is not a qualifying performance target. Friends’ goal proposals cannot be edited by the creator. New agreement consent begins unchecked. Explicit acceptance snapshots the complete agreement and receipt independently of later draft edits. Saved agreements are read-only; returning to them does not ask for consent again.

## Product truth, fixtures and proposals

The adopted product records remain PROJECT_MEMORY.md, docs/BUSINESS_MODEL.md, docs/BETA_IMPLEMENTATION_PLAN.md, PLAN.md, D134/D135 and docs/COPY.md. [PRODUCT.md](PRODUCT.md) records only the supplied context for this study. [DESIGN.md](DESIGN.md) describes this alternate visual system only.

**Preserved product boundaries:** separate personal goals and friend challenges; target-free friend leaderboards; individually proposed friend targets; 2–6 people; scheduled full-day windows; explicit full agreement and consent; accurate review timing; non-punitive exits; no loss inferred from missing data; nonredeemable simulation and fee $0; historical Personal access preserved.

**Fictional data:** Mason, Maya, Jordan, Alex, Riley and Sam; all goals, activities, timestamps, dates, simulated amounts and responses. Today is a fictional Saturday, September 12, 2026. The result screen is a separate September 15 scenario, not a result already reached by Today. Review and support buttons save examples only. No invitations or messages are sent and no Health data is read.

**Proposed UI:** Signal’s visual world, chart lens, expanded shared rows, navigation, screen compositions and copy. A sample personal timed run remains available for design exploration, while real timed-running availability and its distance tolerance remain unaccepted. No community launch numbers, source acceptance, provider, beneficiary or real-money rule is selected. No simulator/native accessibility or device test is implied.

**Unchanged scope:** production SwiftUI, backend, database, adopted contracts and the Fieldwork study. The original dirty/untracked Fieldwork files were recorded before this work and preserved.

## Research and verification

All five supplied Mobbin references were visually inspected. Additional searches covered Strava, Garmin Connect, Runna, Gentler Streak and Robinhood. Robinhood searches returned other reliably labelled apps; no screen was misattributed. The complete borrowed/avoided record is in [MOBBIN_RESEARCH.md](MOBBIN_RESEARCH.md).

Verification results and limitations are recorded in [VERIFICATION.md](VERIFICATION.md), with raw browser observations in [verification.json](verification.json). Screenshots cover phone and desktop, light/dark, and glass/solid. The [Home comparison](screenshots/comparison-home.png) and [challenge comparison](screenshots/comparison-detail.png) place actual Fieldwork and Signal browser captures side by side.

No native test suite was run because no native or production code changed.
