---
name: "GameTime — Signal (local proposal)"
description: "A cool performance instrument with solid athletic information and glass interaction controls."
colors:
  canvas: "#e9edf3"
  surface: "#fbfcfe"
  panel: "#fff"
  soft: "#eff3f8"
  ink: "#141c28"
  muted: "#5a6879"
  line: "#d8e0eb"
  accent: "#2458ed"
  accent-soft: "#e8efff"
  on-accent: "#fff"
  bar: "#6986c0"
  glass: "rgba(249,252,255,.68)"
  edge: "rgba(255,255,255,.96)"
  lens: "rgba(255,255,255,.74)"
  danger: "#a53636"
  dark-canvas: "#0c1017"
  dark-surface: "#141a23"
  dark-panel: "#141a23"
  dark-soft: "#1d2632"
  dark-ink: "#f1f5fb"
  dark-muted: "#a2afc0"
  dark-line: "#303c4d"
  dark-accent: "#86a9ff"
  dark-accent-soft: "#25375c"
  dark-on-accent: "#0f1c38"
  dark-bar: "#708ccd"
  dark-glass: "rgba(43,55,73,.64)"
  dark-edge: "rgba(207,225,255,.27)"
  dark-lens: "rgba(106,130,167,.25)"
  dark-danger: "#ffb1b1"
  contrast-line: "#758298"
  dark-contrast-line: "#8592a6"
typography:
  performance:
    fontFamily: '-apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif'
    fontSize: "88px"
    fontWeight: 520
    lineHeight: 1
    letterSpacing: "-.04em"
  invitation-value:
    fontFamily: '-apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif'
    fontSize: "80px"
    fontWeight: 520
    lineHeight: 1.05
    letterSpacing: "-.04em"
  metric:
    fontFamily: '-apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif'
    fontSize: "64px"
    fontWeight: 520
    lineHeight: 1.1
    letterSpacing: "-.04em"
  headline:
    fontFamily: '-apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif'
    fontSize: "32px"
    fontWeight: 690
    lineHeight: 1.12
    letterSpacing: "-.025em"
  title:
    fontFamily: '-apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif'
    fontSize: "17px"
    fontWeight: 660
    lineHeight: 1.25
    letterSpacing: "-.025em"
  body:
    fontFamily: '-apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif'
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.45
  row:
    fontFamily: '-apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif'
    fontSize: "14px"
    fontWeight: 600
    lineHeight: 1.45
  label:
    fontFamily: '-apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif'
    fontSize: "12px"
    fontWeight: 600
    lineHeight: 1.45
  caption:
    fontFamily: '-apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif'
    fontSize: "11px"
    fontWeight: 400
    lineHeight: 1.45
  primary-action:
    fontFamily: '-apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif'
    fontSize: "14px"
    fontWeight: 650
    lineHeight: 1.45
  secondary-action:
    fontFamily: '-apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif'
    fontSize: "14px"
    fontWeight: 600
    lineHeight: 1.45
rounded:
  line: "2px"
  bar: "3px"
  tag: "5px"
  preview-control: "6px"
  field: "8px"
  notice: "9px"
  callout: "13px"
  segment-button: "21px"
  segment-lens: "22px"
  capsule: "25px"
  primary: "26px"
  nav-lens: "28px"
  navigation: "33px"
  circle: "50%"
spacing:
  micro: "4px"
  tight: "8px"
  control-gap: "10px"
  row-gap: "12px"
  field-pad: "12px"
  pair-gap: "15px"
  inset: "16px"
  section: "20px"
  content-gutter: "24px"
components:
  button-primary:
    backgroundColor: "color-mix(in srgb,var(--accent) 87%,transparent)"
    textColor: "{colors.on-accent}"
    typography: "{typography.primary-action}"
    rounded: "{rounded.primary}"
    padding: "13px 20px"
    width: "100%"
  button-primary-solid:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.on-accent}"
    typography: "{typography.primary-action}"
    rounded: "{rounded.primary}"
    padding: "13px 20px"
    width: "100%"
  button-secondary:
    backgroundColor: "{colors.glass}"
    textColor: "{colors.ink}"
    typography: "{typography.secondary-action}"
    rounded: "{rounded.capsule}"
    padding: "11px 18px"
    width: "100%"
  button-icon:
    backgroundColor: "{colors.glass}"
    textColor: "{colors.ink}"
    rounded: "{rounded.circle}"
    padding: "0"
    height: "44px"
    width: "44px"
  field:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.field}"
    padding: "12px"
    width: "100%"
  navigation:
    backgroundColor: "{colors.glass}"
    textColor: "{colors.muted}"
    rounded: "{rounded.navigation}"
    padding: "5px"
    height: "65px"
  segmented:
    backgroundColor: "{colors.glass}"
    textColor: "{colors.muted}"
    rounded: "{rounded.capsule}"
    padding: "4px"
  status-tag:
    backgroundColor: "{colors.accent-soft}"
    textColor: "{colors.accent}"
    rounded: "{rounded.tag}"
    padding: "4px 8px"
  notice:
    backgroundColor: "{colors.soft}"
    textColor: "{colors.ink}"
    rounded: "{rounded.notice}"
    padding: "15px 16px"
  ranked-row:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    padding: "13px 0"
    width: "100%"
  chart-callout:
    backgroundColor: "{colors.glass}"
    textColor: "{colors.ink}"
    rounded: "{rounded.callout}"
    padding: "8px 12px"
---

# Design System: GameTime — Signal

## Overview

**Creative North Star: "The cool performance instrument"**

Signal uses large tabular totals, daily bars and aligned activity rows on cool white or dark ink. One blue family carries performance and interaction. Opaque information supports a separate optical layer for controls. This records the user's pinned direction as built, not a new identity choice.

This document and its [sidecar](.impeccable/design.json) apply only to this folder's **browser proposal**. They do not establish production identity, product policy or native acceptance. The [README](README.md) records behavior and scope; [PRODUCT.md](PRODUCT.md), [research](MOBBIN_RESEARCH.md) and [material review](LIQUID_GLASS_REVIEW.md) provide context. The HTML contract records seed `798c9301`, degraded without challengers, no approved comp and a code-led browser study. The initial study’s independent finish verdict was **ship**: saved agreement snapshots, product-specific exit receipts, keyboard focus retention and desktop eyebrow removal are resolved, with no remaining issues in its reviewed scope.

**Key Characteristics:**

- One blue family on a cool neutral field.
- Exact totals with date, units and completion state.
- Solid charts, rows, terms, consent and results.
- Glass controls with opaque and accessibility fallbacks.

## Colors

The frontmatter contains exact source values. Unprefixed tokens describe light mode; `dark-` tokens record the corresponding appearance overrides. They are two coherent appearances, not independent colors to mix.

### Primary

**Accent** identifies actions, selection, progress and the inspected daily bar. **Accent-soft** supports status tags; **bar** supplies unselected chart data. **On-accent** supplies readable action text in each appearance. Tinted primary glass mixes the current accent with transparency; solid mode uses the accent directly.

### Neutral

**Canvas** is the desktop surround; **surface** is opaque application content; **panel** fills fields and solid selected controls. **Soft** groups notices and opaque controls. **Ink**, **muted** and **line** separate primary text, supporting context and record boundaries. **Glass**, **edge** and **lens** define interaction material and selected insets. **Danger** is a semantic error/exit exception, not another performance accent.

Increased contrast maps muted text to ink and substitutes the contrast divider tokens. Appearance selection is explicit; this study does not automatically follow the operating-system light/dark setting.

**The One Performance Accent Rule.** Use the blue family for performance and interaction; reserve danger for errors and exit-related actions.

## Typography

The built interface uses the system sans-serif stack in the frontmatter, with no external fonts. Tabular numerals apply globally. These are browser UI roles, not a proprietary display identity; rendered weights depend on the platform.

- **Performance:** the personal progress band uses `performance` (78px on narrow phones). Invitation and agreement values use `invitation-value` (68px for narrow invitations; long agreement values use 44px, or 36px on narrow phones). The saturated band uses the existing accent/on-accent pair, with no glass.
- **Metric:** primary totals use `metric`; attached units are smaller (23px, weight 450). Narrow screens reduce totals (56px).
- **Headline/title:** screen headings use `headline`, section headings `title`. Receipt headings are slightly larger (34px); information-block headings are smaller (16px).
- **Comparison:** paired statistics use 29px/560; ranked totals use 22px/510 with separate units and rank/name columns.
- **Body/labels:** `body` is the base; row titles use `row`. Supporting paragraphs use 12–13px, with more leading for notices (1.6) and disclosures (1.65). Chart axes, status tags and navigation use 10px. The compact browser sizes are not Dynamic Type acceptance.

**The Exact Readout Rule.** Pair important totals with units and time context; distinguish complete, partial and future activity without inventing a zero.

## Layout

The invitation, agreement and personal-goal refinement adds opaque full-width accent bands and a start-to-end date span. Individual friend proposals occupy independent columns; no chart compares their different targets. The personal privacy statement is an open 32px heading, existing lock symbol and supporting sentence before activity history. Amounts remain ordinary, readable information.

The app is one scrolling column, with 24px content gutters and 112px bottom clearance beneath floating navigation. Toolbars stay outside the scroll area. Rows use fine horizontal rules; ranked rows have four columns (28px, `minmax(0,1fr)`, `auto`, 13px) and an 11px gap. Statistics and compact forms use two columns. Facts align labels left and values right, capped at 65% of the row.

Spacing is an observed set, not a mathematical scale: 4–12px associates content; 16–24px separates groups. Standard activity rows have 17px vertical padding and a 66px minimum height. Home's compressed chart/rows are screen-specific.

The desktop study wrapper has a 1320px maximum width and three columns: 242px rail, flexible stage and 222px notes. Its phone frame is 414 × 868px. At **1120px**, notes hide. At **700px**, the app becomes full width, decorative phone framing disappears, and a disclosure exposes the 21-screen picker plus appearance, material, contrast and motion controls. App height uses `100svh` less the closed preview strip, with a 490px minimum. At **360px**, gutters narrow to 19px and totals, rank gaps and form gaps compress. This presentation geometry is not native safe-area handling.

Routes focus the new heading; in-place selection/switch renders retain the identifiable active control and scroll position. The accent focus ring is 3px with a 3px offset. The chart uses a 2px focus-within ring with a 5px offset.

## Elevation & Depth

Data remains flat and opaque. Glass combines a translucent fill, 20px backdrop blur, 1.5 saturation, 1.03 contrast, bright/dark inset rims, a soft cast shadow and pointer-positioned reflection. Exact light/dark shadows, selected-lens shadows and motion values live in the sidecar. The larger desktop frame shadow is presentation scaffolding.

**The Solid Information Rule.** Keep data, histories, terms, consent and results opaque; reserve glass for navigation, actions, segments and the chart's selected-day readout.

**The Same Geometry Rule.** Opaque fallbacks keep control geometry and selected states while removing blur, reflections and glass elevation.

Solid mode, increased contrast, reduced transparency and unavailable-backdrop-filter fallbacks are implemented. Forced colors supplies system-colored controls, selection outlines and visible chart data. These CSS effects do not establish native Liquid Glass conformance.

## Shapes

Open dividers organize information; enclosing cards are uncommon. Actions use capsules, toolbar controls use circles, and navigation shares one rounded enclosure with a curved inset lens. Fields and notices have smaller corners; tags have a compact rectangular radius. Bars are lightly rounded and the future day is dashed and outlined. Authored SVG icons use a 24-unit view box, 1.7-unit stroke and rounded caps/joins. The three-stroke mark belongs only to this proposal.

## Components

- **Buttons:** primary actions are full-width tinted capsules (50px minimum height); secondary actions are glass capsules (47px minimum). Toolbar circles are 44px. Default text actions are 44px high; compact section/chart links are 32px. Hover uses `brightness(.97)`; pressed glass scales to 97%. Disabled controls use opacity .42 and native disabled semantics. Consent is explicit and unchecked initially.
- **Navigation/segments:** three icon-plus-text navigation positions share one glass enclosure. The current page uses `aria-current`; segment buttons use `aria-pressed`. Selected insets show shape and text treatment as well as color.
- **Chart/readout:** solid daily bars, crosshair and glass callout connect exact date, total and completion state. The range input supports keyboard selection with accessible value text; the SVG has a full text alternative. The callout is pointer-inert and is not a button.
- **Personal progress:** the solid accent band contains an 88px total and a track whose filled length is exactly 95/150. Three internal segments proportionally represent 28, 35 and 32 exercise minutes. It is a static record with a complete accessible label, not a streak or prescribed pace.
- **Date span:** both midnight boundaries, full calendar dates, full-day count and Central Time remain visible. An arrow communicates start-to-end order.
- **Rows:** activity rows align title/context/value; ranked rows expand their shared activity timeline and preserve focus. Personal activity has separate details and splits.
- **Fields/choices:** labeled solid inputs, selects and textareas have a 49px minimum height. Help follows its field; validation uses an alert with a next step. Native checks/radios and labeled `aria-checked` switches preserve explicit state.
- **Notices/facts/terms:** one restrained solid inset, ruled facts and native disclosures keep long rules readable. Saved agreement/receipt snapshots survive later draft edits. Friend and personal exits reopen their matching receipts.
- **Receipts/results:** outlined status symbol, readable outcome heading and factual rows distinguish saved actions, proposed simulated returns and pending results. All fixtures stay fictional and in memory until reload.

The deliberate motion is the callout's 130ms position easing. Navigation/segment lenses declare 340ms, row chevrons 250ms and switch thumbs 200ms, all using `cubic-bezier(.16,1,.3,1)`. Values update immediately; pages have no entrance/count-up animation. Screen rerenders do not demonstrate native morphing. Reduced motion removes transitions, press scaling and new pointer-highlight movement.

## Do's and Don'ts

### Do:

- **Do** preserve the blue family, cool neutrals and tabular readouts within this proposal.
- **Do** keep information opaque and optical material on the established controls.
- **Do** retain dates, units, partial/future states, keyboard focus, explicit consent and easy review/exit routes.
- **Do** preserve geometry and selection when material or accessibility settings change.

### Don't:

- **Don't** spread blur or glare across data, terms, consent or results.
- **Don't** introduce warm paper, vintage print, condensed display, monograms, profile photos, decorative heroes or repeated soft cards into this pinned world.
- **Don't** use color or motion alone to communicate state, or turn status tags into reward badges.
- **Don't** promote the phone frame, study typography, mark, fictional fixtures or browser optics into adopted production identity, policy or native acceptance.
