# Browser verification — September 21, 2026

This record covers the local HTML design study only. It does not establish native iOS implementation, source acceptance, product policy adoption, or release readiness.

## Performed

| Check | Observed result |
| --- | --- |
| JavaScript syntax | `node --check prototype.js` passed |
| Standard iPhone view | 390 × 844 CSS px at 2× screenshot scale; Home primary action entirely above the tab bar; no horizontal body overflow |
| Goal summary | All three verdict answers above the fold at standard 390 × 844 |
| Home → goal | View goal opened the shared goal/rules component |
| Full rules | Expanded and collapsed; own-stake limitation and missing-data protection present |
| Exit | Neutral explanation, no simulated real mutation; Escape closed and restored focus to Leave challenge |
| Modal background and keyboard | Background has `inert`; result sheet traps Tab; Escape restores the underlying view |
| Finished result | September steps sheet shows 52,480 and 61,200 plus separate simulated-return status |
| Settings | Simulated-stake explanation is visible, including no shared pots, transfers, prizes or cash withdrawals |
| Missing activity | Own metric is `—`; status is Waiting for activity; next step says to refresh after Watch sync; no zero or inferred miss |
| Shared-week accessibility | Missing state changes the grid's accessible label; no daily-streak requirement |
| Large type | 22% font increase on Home, Goal, You and Challenges at 320 × 710; no horizontal body overflow; every app button ≥44 CSS px tall |
| Large-type timeline | Final refinement uses two 136 px columns at width 320, verified after reload |
| Narrow review page | Width 390; no document horizontal overflow; three phones and exactly ten system rules |
| Desktop design board | 1320 × 960 at 2×; saved to captures/three-screens.png and visually inspected |
| Final portable export | Three populated phones; zero external script or stylesheet links; portrait atlas embedded as a data URL; no console errors |
| Export completeness | Lavish export reports zero unresolved local assets and zero notices |
| Text contrast | Accent on white 5.06:1; secondary on white 5.38:1; accent on mist 4.59:1; ink on white 17.54:1 |

The full phone images were visually inspected. Home's first composition initially pushed its CTA below the fold; removing a redundant category eyebrow and relocating group privacy explanation to friend details restored the action and freshness line to the first viewport. Rules retain a scrollable body for full terms. You deliberately previews a third dated record at the fold.

The Chrome batch `run` wrapper returned `fn is not a function` and was not treated as a passed test. Its first error is retained in captures/browser-wrapper-failure.txt. Direct Chrome controls captured images; browser-use Playwright controls performed the successful interactions and read-only DOM checks above. The initial export retained a deferred script; moving the source script to the end of the body produced the verified self-contained export.

## Deliverables

- `index.html`: annotated interactive review, source files alongside it.
- `gametime-design.html`: self-contained portable copy with CSS, JavaScript and portrait asset embedded.
- `board.html`: presentation board using the same live components.
- `phone.html?screen=home|goal|you`: device-sized routes.
- `captures/home.png`, `captures/goal-rules.png`, `captures/you-record.png`: 780 × 1688 screenshots.
- `captures/three-screens.png`: 2640 × 1920 presentation image.
- Local Lavish review: http://127.0.0.1:4387/session/c2bfa6d1469e245f

## Unperformed

Physical iPhone testing, native Dynamic Type/VoiceOver acceptance, native glass fidelity, actual haptics, notification delivery, gesture physics, real Health data, source/scoring acceptance, backend mutations, invitations, and money. Reduced-motion and reduced-transparency fallbacks are present in CSS; hardware and native accessibility behavior are not claimed.

Sample people, dates, shared activity, statuses and finished records are fictional. The new personal-consequence-only stake rule and portrait/grid features require separately versioned implementation; existing agreements remain unchanged.

## Follow-up: Home only

- Captured and visually inspected the refined Home at 390 × 844 CSS px / 2×: `captures/home-refined.png` (780 × 1688). Its body fits without scrolling; the source line ends 22.5 CSS px above the tab bar.
- Checked 320 × 710 with 22% larger text, both saved and missing activity. No horizontal overflow; the large metric and unit fit without overlap; all buttons remain at least 44 CSS px tall. Unknown activity retains its explanation and never becomes zero or an inferred miss.
- Opened Sam’s progress from the revised tile, closed with Escape and observed focus return to Sam. View goal still opens the existing goal and rules screen.
- Verified the non-Home functions (`toolbar`, `goal`, `moment`, `you`, `challenges`, rendering and sheet functions) match the previous commit. Existing CSS is unchanged; appended app selectors are scoped to Home. Only Home and its friend tile markup changed.
- `node --check prototype.js` and `git diff --check` passed. No native implementation or native test claim is made.
- Opened the portable Home export: exactly one populated phone, five annotations, zero external script/stylesheet links, embedded portrait atlas and no desktop horizontal overflow. Lavish export reported zero unresolved assets and zero notices.
- Local review: http://127.0.0.1:4387/session/d4daf4d3bea3868b. Deliverables: `home-refinement.html`, portable `gametime-home-refined.html`, and `captures/home-refined.png`. The original Home and three-screen captures are retained as the first iteration; the main portable design export is refreshed to use the current Home.

## Follow-up: palette only

- Compared the prior and new Home at the same 390 × 844 viewport. The rendered HTML and every element’s bounds, font, tracking, margins, padding, border widths and corner radii matched exactly. The recorded comparison is `captures/home-palette-checks.json`.
- `prototype.js` is unchanged. The only app CSS additions are Home-scoped color tokens, text/background/border/stroke colors and equivalent shadow colors; no geometry or behavior declarations changed.
- New palette: background #FAFBFC, surface #F0F2F5 (existing subtle shading ends at this color), text #111318 and accent #245BFF. The Behind label is #9A6700, a separate semantic state color. The other screens retain their existing colors.
- Contrast: accent on background 5.05:1, white CTA label on accent 5.23:1, Behind on background 4.70:1 and text on surface 16.57:1.
- Visually inspected `captures/home-cool-palette.png` (780 × 1688) and `captures/home-palette-with-legend.png` (2240 × 1880). The presentation embeds the exact screen capture to preserve its composition.
- Opened portable `gametime-home-palette.html`: the full image loaded at its original dimensions, exactly four swatches, no external scripts or stylesheets, and no horizontal overflow at 1120 px. Export reported zero unresolved assets and notices. Prior exports remain records of the warm-palette iteration.
- Local palette review: http://127.0.0.1:4387/session/aa2b8c2bf6f752e3. This is a Home design proposal only; no native color migration or policy adoption occurred.

## Follow-up: Goal / Rules visual modules

- At 390 × 844 / 2×, the metric, three verdict cards, connected timeline, Full rules, Leave challenge and Refresh activity all fit above the tabs. Content and viewport heights are both 715 CSS px; utilities end at y=728.7 and tabs begin at y=759. Verdict values contain 4, 5 and 5 words. The only main-screen paragraph element is the one-line goal summary.
- Full rules is absent from the initial rendered screen and opens as a modal sheet. It contains eight short disclosure sections with individual goal tiles, bullets and exact dates. Opening Runs that count closes Everyone’s goal. The background becomes inert; Escape returns focus to Full rules.
- At 320 × 710 with 22% larger text, saved and missing activity states have no horizontal overflow. The metric fits, the timeline becomes two columns and all buttons remain at least 44 CSS px tall. Missing activity displays a dash and no progress fill.
- Home’s rendered HTML and every measured element’s bounds, font, tracking, padding, margins and border widths/radii match the locked Home comparison exactly. Home, friend tiles, shared navigation, You, Challenges and modal-management functions are unchanged. The previous CSS is intact; additions are scoped to Goal. Pixel-for-pixel screenshot equivalence is not claimed.
- Independent read-only agreement review found no missing source exclusions, full-run boundary, missing-data protection, participant minimum, own-stake restriction, review window, exit protection or sharing consent. Timeline uses Sep 27 as the last full day, with the precise Sep 28 midnight cutoff in Full rules. “From Sep 30” is not a guaranteed finalization date; the notice and review windows remain explicit.
- Visually inspected `captures/goal-modules.png`, `captures/goal-full-rules.png` (both 780 × 1688), and `captures/goal-review-board.png` (2240 × 1920). The board has exactly six annotations and four palette swatches.
- Portable export has one populated phone, no external script/stylesheet dependencies, and the exact background #FAFBFC, text #111318 and accent #245BFF. Lavish reported zero unresolved assets and zero notices.
- JavaScript syntax and `git diff --check` passed. This is a design mock; native Liquid Glass rendering, iOS availability behavior, Dynamic Type and human accessibility acceptance remain unperformed.
- Local review: http://127.0.0.1:4387/session/16dd96b07c5a25c7. Earlier exports remain iteration records; `gametime-goal-rules.html` is the latest Goal deliverable.

## Follow-up: Challenges library and You record

- Visually inspected the Challenges and You mocks at 390 × 844 / 2×. Captures are `captures/challenges-library.png` and `captures/you-metric-record.png` (780 × 1688). The annotated two-screen board is `captures/library-record-board.png` (2640 × 1896). Default Challenges shows its active and invited cards together; further library objects continue below. You leads with the compact identity, yearly numbers and two finished metrics; the earlier closure follows on scroll.
- Both routes compute background rgb(250, 251, 252), text rgb(17, 19, 24) and accent #245BFF. They reuse #F0F2F5 surfaces, the existing thin symbols, portrait atlas, metric typography and tabs. Warning remains #9A6700; the sample outcomes do not warrant a warning state. Home and Goal are references, not redesigned screens.
- At 320 × 710 with 22% enlarged text and missing activity, both routes have equal client/scroll widths, no elements extending past the content width, and every visible button is at least 44 CSS px tall. The missing active metric has no progress fill and does not infer a missed goal. This is browser text scaling, not native Dynamic Type acceptance.
- Clicked Invited: only its section remains visible. Accept opens Review invitation with this invitation’s goal and dates, collapsed Full rules, inert background and a preview-only no-response note. Escape closes the sheet and restores focus to Accept. No real acceptance, decline, creation or Health request is performed.
- Home and Goal each match their prior rendered HTML and all measured element bounds, font, tracking, padding, margins and border widths/radii exactly. Home, Goal, fullRules and appNav source blocks are unchanged. Existing CSS remains an intact prefix; additions apply only to new library/record content. Pixel-for-pixel image equivalence is not claimed.
- Independent read-only review checked the record fixtures, copy, invitation consent boundary and Home/Goal scope. Invitation cutoff times were made explicit. The user-authorized `$20 sim` abbreviation remains in the library only. Existing agreement and result facts remain intact; new October fixtures are documented as fictional.
- Opened portable `gametime-challenges-you.html`: two populated screens, four reuse annotations, four swatches, embedded portrait assets, no external script or stylesheet dependencies, no page overflow at 1320 px. Export reported zero unresolved assets and zero notices. Chrome reported no console messages on the board. JavaScript syntax and `git diff --check` passed.
- Local review: http://127.0.0.1:4387/session/0741d0e834b65827. This is a design prototype only; native implementation, real invitation consent/creation and native material rendering remain outside this task.
