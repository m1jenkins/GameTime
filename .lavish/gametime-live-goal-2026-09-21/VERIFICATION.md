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
