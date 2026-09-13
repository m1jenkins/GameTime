# Fieldwork, second exploration: glass and movement

The owner chose Fieldwork for continued ideation, requested Liquid Glass elements, and asked for a more interesting challenge page. This records that preference and a new proposal. It does not select a final native implementation. The first exploration remains a historical comparison of three directions.

## Direction

Keep Fieldwork's warm paper, deep green, condensed display typography, readable body text and restrained citrus. Give the challenge a recognizable identity and make progress more legible. The main recommendation is the **green club board** header. A **paper scorecard** variant remains available for comparison.

The challenge detail now has:

- A green editorial header with dates, the current day within the challenge, a large own step total and the person's rank. The faint oval lane motif is decorative sports imagery, not a route, chart or progress indicator.
- A floating glass switch between **Standings** and **Your week**. The switch overlaps the header/content boundary so its material has a visible purpose.
- Aligned friend rows with initials, current values and per-person update times. Proportional bars use a common 0–50,000-step display scale in this example; that scale is not a qualifying target.
- An interactive own-day chart with exact values, a partial current day, and a distinct future day. Previous/next controls provide 44-pixel targets in addition to selecting the bars.
- Exact end time, simulation disclosure, and reachable challenge details, review and leaving information.

The **Challenges** overview also changes: glass status filters, a green friend challenge preview, a different personal-goal composition, an upcoming goal and a neutral history empty state. Home, creation and the personal-goal detail use the same control treatment. This addresses both possible meanings of “challenge page.”

## Where glass belongs

[Apple's materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials) places Liquid Glass in the navigation and control layer. The prototype uses that hierarchy:

| Element | Proposed treatment |
| --- | --- |
| Back, add and challenge-options controls | Circular regular glass, lightly influenced by the background |
| Standings / Your week and challenge-status switch | One regular-glass container with a clear selected state |
| App navigation | A floating regular-glass bar, with visible labels |
| Creation Continue action | A prominent tinted glass action |
| Challenge title, metrics, standings and activity chart | Solid content backgrounds |
| Dates, amounts, rules, review and exit explanations | Quiet solid backgrounds with normal readable text |

The concept uses translucent fills, backdrop blur, subtle edge highlights and shadows to study the material. It is **not native Liquid Glass** and does not reproduce Apple's optical rendering or platform interaction behavior. Clear glass is not proposed for these ordinary content backgrounds.

For a later iOS 26+ implementation, prefer native system navigation and controls. Use native glass button styles and `glassEffect` for the few custom controls that need it. Group related custom glass elements with `GlassEffectContainer`; reserve morphing transitions for meaningful control changes. Verify exact API behavior against [Apple's custom-view guidance](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views) and the target SDK. Provide a solid fallback and honor Reduce Transparency, Increase Contrast and Reduce Motion. A browser mockup cannot validate these native behaviors.

## Activity and product boundaries

The sample week remains September 7–13, 2026. All activity is fictional. The six daily own values are 5,100, 6,380, 7,240, 5,980, 8,020 and 5,900 steps, summing to the displayed 38,620. Saturday is partial; Sunday has not started. Friend values remain Maya 42,850, You 38,620 and Jordan 35,400. These are not account data or newly established Health readings.

The daily chart is a **proposed data presentation**. A current challenge total cannot establish a historical daily breakdown. Native implementation needs an authorized, source-correct own-day projection and explicit unavailable/partial/corrected states. Until that exists, show an honest unavailable-history state; never synthesize the chart from the total. No friend daily history, route, heart rate, training readiness or exercise recommendation is introduced by the proposal.

The [Strava laps reference](https://mobbin.com/screens/f99cb5ad-6c1e-456b-9bfc-5542dd13611a) inspected on Mobbin demonstrates the relationship between a visual pattern and precise numeric detail. The transfer here is a chart paired with exact values. Its training metrics and activity rules are not imported. Earlier Fieldwork references remain recorded in the first exploration.

The leaderboard has no target. Personal and friend goal agreements retain their own target rules. Creating a friend lobby, choosing individual targets, selecting the roster and obtaining every person's agreement remain separate steps. All amounts remain nonredeemable simulation. No invitation, notification, financial action, hosted mutation or Health access occurs in the concept.

The added visual interest supports understanding progress and comparing agreed challenge results. It introduces no pressure alerts, loss-recovery prompts, money celebrations, stake escalation or automatic social sharing.

## Still to resolve

Choose between the recommended green header and the paper variant after reviewing both appearances. Refine how much of the header persists when scrolling in a native app; this fragment expands naturally rather than simulating a fixed-height phone scroll view. Verify compact-device information order and Dynamic Type before fixing final dimensions.

Source-backed own-day history, stale/partial/no-data states, native VoiceOver order, real glass rendering, scroll-edge behavior, haptics, localization and physical Health validation remain separate implementation and acceptance work. No SwiftUI source changed in this exploration.

## Performed checks

The final fragment passed JavaScript syntax validation. At an explicitly measured 320-pixel frame, 40 combinations of five screens, two headers, two material treatments and two appearances had no horizontal content overflow. Decorative lane art is intentionally clipped by the header and excluded from the content-overflow check. Wider challenge/detail views were also visually inspected.

Fifteen additional checks passed for view switching and keyboard focus, the own-day chart, exact selected values, previous/next controls, the future-day state, rule access, the options menu, overview navigation, upcoming/history filters, personal-goal navigation, creation and removing backdrop filtering in solid mode. The local test harness initially used an invalid numeric attribute selector; that harness error was corrected before the completed run. A shim exercised the same Tweak bindings; the conversation host's controls panel was not browser-tested.

Inspected renders include green-header standings in light/dark, the own-week chart, the compact Challenges overview, and the final paper-header week with day-navigation controls. These browser checks do not establish native Liquid Glass, Dynamic Type, VoiceOver or physical-device acceptance.
