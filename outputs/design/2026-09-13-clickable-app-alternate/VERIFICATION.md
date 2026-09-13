# Signal verification

Performed September 13, 2026. Prototype-only checks, using fictional fixtures.

## Browser results

- 252 combinations passed: 21 destinations × 3 viewports × light/dark × glass/solid. Viewports: 390×844, 1440×1000 and 320×740. Every destination had a heading; document and content regions had no horizontal overflow.
- Eleven journey groups passed, including all twelve combinations of friend leaderboard, individual friend goals and personal goals across the four activities. Leaderboards never displayed a target input; creator UI never edited someone else’s goal; every agreement began with unchecked consent.
- Tested keyboard and pointer chart scrubbing, future-day text, expandable rankings, invitation acceptance/decline, five-step creation, invalid dates/duration/amount/roster, timed-goal syntax and retained fields, review validation and retained notes, paused results, admission pause, and separate personal/friend exits with correct history.
- No JavaScript errors or failed requests in the final pass.
- Chrome DevTools Protocol emulation confirmed `prefers-reduced-transparency` and `prefers-contrast` remove backdrop filtering and shadows. `prefers-reduced-motion` reduced the navigation lens transition to `0s`. Explicit reduced-motion mode also removed pseudo-element transitions.
- Source review confirmed opaque unsupported-backdrop fallback and forced-colors styles. Forced-colors and unsupported-filter rendering were not separately emulated.

The first browser pass identified density and state refinements: Home’s plot was shortened to bring its separate progress rows closer; personal exits no longer hide the friend challenge; exit-history actions select the correct product; admission pause became an explicit visible notice; inactive chart bars gained more contrast; and explicit reduced-motion mode was extended to pseudo-elements. One final matrix/flow pass validated those changes. The first console listener saw a generic 404 while capturing the original study; the final pass records request URLs and found no failed requests.

## Contrast measurements

These are calculated WCAG contrast ratios of resolved solid palette colors, not an exhaustive pixel audit of translucent glass over every scroll position.

| Pair against content background | Light | Dark |
| --- | --- | --- |
| Main text | 16.68:1 | 15.97:1 |
| Secondary text | 5.54:1 | 7.85:1 |
| Accent text / selected data | 5.54:1 | 7.60:1 |
| Unselected chart bars | 3.54:1 | 5.26:1 |

## Methods and artifacts

Chrome CLI was used to open and interact with Fieldwork, inspect the exact Mobbin pages and inspect Signal. Some CLI bridge invocations timed out; selecting the known page recovered normal commands. For repeatable multi-viewport screenshots and accessibility media emulation, the bundled Playwright runtime drove a separate local headless Chrome. Its first sandboxed launch failed; the authorized local run succeeded after sandbox escalation. The Browser plugin skill was not available; the browser paths above were used.

The Impeccable detector ran once. Missing HTML parser modules limited it to regex checks, which reported no findings. It cannot establish computed contrast or complete design acceptance. No extra product context or aesthetic approval was requested: the supplied detailed brief and repository authority already resolved those choices. The optional concept seed ran degraded without challengers; the user’s explicitly pinned direction controlled the design.

[verification.json](verification.json) contains the exact matrix, journey groups, media observations and color measurements. [verify.cjs](verify.cjs) preserves the browser check script. It is a design verification utility, not a production test. It requires Playwright, a Chrome executable and the loopback server; its bundled local paths can be overridden as documented in the script.

The screenshots directory includes:

- Phone Home and leaderboard in every light/dark and glass/solid combination.
- Desktop Home in all four appearance/material combinations.
- Phone personal goal, creation, invitation, agreement, result and You.
- Captured original Fieldwork Home and detail, matching Signal captures, and the two labelled side-by-side comparisons.

Fieldwork and Signal retain their own app frame heights and scrolling composition in the comparisons. The images do not recreate or recolor the original. A SHA-256 comparison against the recorded starting files confirmed every existing Fieldwork file remained unchanged.

## Boundary

These checks establish local browser behavior at the stated viewports. They do not establish native Liquid Glass rendering, physical-device performance, VoiceOver, Dynamic Type, human accessibility acceptance, Health-source correctness, real timed-distance tolerance, hosted state, production readiness, distribution or money. No production test suite or native simulator was run.

## Independent finish review

The fresh Impeccable finish review accepted the visual direction and requested four material corrections: snapshot accepted agreements separately from later drafts, fix the swapped departed-product receipt links, preserve focus after in-place control redraws, and remove two desktop eyebrow labels. Those changes were applied in one batch.

[review-verification.json](review-verification.json) records focused checks of accepted agreement retention after changing name, dates, format and amount in a later draft; read-only saved terms; each departed product’s receipt; keyboard focus after segmented, format, metric and switch changes; and removal of the two desktop labels in all four appearance/material modes. Affected desktop/phone screenshots were refreshed, with four added captures of saved agreement, both exit receipts and visible keyboard focus. The full 252-case matrix remains the immediately preceding broad pass; the final changes received focused validation rather than an unnecessary full rerun.

The independent verdict pass scored all four fixes **resolved**, found no regressions in the affected recaptures, and returned **ship**. The [final review table](REVIEW.md) preserves that disposition and its scope.

## Invitation and personal-goal refinement

A subsequent refinement changed only the alternate study and its scoped design notes. It adds solid accent progress, an earlier personal privacy statement, horizontal date spans and independent friend-proposal columns. Glass remains on the existing controls.

The completed browser pass covered **72 combinations** (Home, personal goal, activity, invitation, agreement and receipt × 390×844, 1440×1000 and 320×740 × light/dark × glass/solid), plus **85 assertions**. All had headings and no horizontal overflow; there were no JavaScript errors or failed requests. All twelve format/activity agreement combinations retained explicit unchecked consent. Long names and six-person agreements fit the narrow viewport. Exact dates, amounts, fee, full rules and individual targets were checked, including selected timed-run distance/time. Saved agreements survived later draft changes; decline, pause, personal activity and personal exit behavior passed.

The actual progress fill measured 95/150 of the track. New performance-section text contrast measured **5.69:1 light / 7.34:1 dark**; invitation supporting text measured **4.94:1 / 5.30:1**. Reduced transparency, increased contrast, reduced motion and forced colors were emulated. The source for full rules, consent event handling, agreement snapshots and receipts is unchanged from the initial study. Visual inspection used a first batched phone/desktop pass and one confirmation pass; a redundant divider between the date and amount sections was removed in the batch between them.

Chrome CLI was used for direct inspection, and the bundled Playwright runtime drove the repeatable matrix and journeys (Browser plugin not available). The first test attempt needed its harness corrected to open the collapsed mobile screen picker before choosing a destination; the completed pass exercises that visible interaction. Local asset version queries prevent an already-open preview from retaining the earlier design.

[Refinement browser observations](/Users/user/.codex/visualizations/2026/09/13/01a09954-e9b5-7fb1-8997-0b8df4dfac0c/signal-refinement/verification.json) and the adjacent captures preserve this pass separately from the original matrix and screenshots above. The initial independent review remains a dated record of the first study; no new independent reviewer or native validation is claimed for this refinement. Physical-device accessibility, VoiceOver, Dynamic Type and other browser engines remain untested.
