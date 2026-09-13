# GameTime — Fieldwork Glass clickable app

Local UI/UX exploration, September 13, 2026. The owner requested clickable app
screens around the existing challenges page and explicitly required
[`fieldwork-glass-brand-kit.json`](../2026-09-13-creation-directions/fieldwork-glass-brand-kit.json).

Open `index.html` in a browser, or serve this directory and open the local URL.
`fieldwork-app.html` is the equivalent conversation fragment. Use the screen
picker to jump between 22 destinations, or follow buttons and bottom navigation.
Light/dark appearance, glass/solid controls, and result scenarios are selectable.

The follow-up [Liquid Glass and imagery review](LIQUID_GLASS_REVIEW.md) adds
switchable photography, a family of printed movement graphics, and the original no-image
comparison. It records Mobbin references, material corrections, native
implementation requirements and performed checks. Full Imagegen prompts and
saved assets are in [asset-provenance.json](asset-provenance.json).

The latest iteration opens on the redesigned invitation with **Stride print ·
collection** selected. Three companion prints—lace up, fist bump and running—
join the original walking stride. Invitation and agreement now lead with a
person, goal and readable date window. Friend lobby, draft review, invitation
preview and receipts also shed repeated label/value tables. Existing challenge
standings and activity charts retain their useful data layout.

Unslop's diagnosis and minimal copy repairs are recorded in
[copy-rewrites.json](copy-rewrites.json), with findings, protections and validation
in [COPY_REVIEW.md](COPY_REVIEW.md). Assembly applies these replacements to the
active prototype; `reference.html` remains the preserved earlier study.

## Brand and scope

`build.py` reads the exact brand-kit JSON and emits its light/dark color tokens.
Typography remains Barlow Condensed (display) and DM Sans (body). Green club
boards, citrus activity numbers, warm paper, monograms, fine rules, and glass
navigation extend the supplied Fieldwork identity.

`reference.html` preserves the existing Fieldwork Glass study. Its challenge
detail, standings, own-week chart and personal goal are retained in the assembled
prototype. The overview retains its established active-card composition; its
upcoming and history states now connect to the new invitation and result screens.
`screens.css` and `screens.js` add the surrounding flows.

The new screens cover Home, five-step creation, a selectable friend lobby,
invitation preview, invitation review, explicit agreement, confirmation, results,
review request/receipt, community unavailable state, You, Apple Health readiness,
privacy, profile editing, support, earlier agreements and a voluntary exit.
Draft values persist while navigating this preview; reload resets all data.

## Product truth and proposals

Product authority remains PROJECT_MEMORY.md, docs/BUSINESS_MODEL.md,
docs/BETA_IMPLEMENTATION_PLAN.md, PLAN.md, D134/D135 and docs/COPY.md.
This study does not replace any of those records.

- Adopted boundaries: 2–6 friend participants, separate individual goals and
  target-free leaderboards, all four metric choices, full-day scheduling,
  explicit agreement, review, non-punitive exit and nonredeemable simulation.
- Proposed UI: the new compositions, copy, roster controls, receipts, own-day
  charts and navigation. They are not native implementation acceptance.
- Fictional fixtures: every person, target, date, activity value, review notice,
  simulated amount and consent/receipt state. Results show a separate September
  15 scenario; Home and active activity show September 12.
- Still gated: real source acceptance, native timed-run distance tolerance,
  normal signed-in challenge availability, human/native accessibility and launch.
  Community settings stay unselected; its unavailable screen invents no goal,
  amount, participant count or public enrollment.

No SwiftUI source, backend, historical agreement or actual account data changed.
No invitations, support requests or review requests are sent. No Health access,
payments, deployments or third-party design uploads occur.

## Performed checks

- Assembled JavaScript passes `node --check`.
- All 22 destinations rendered in a 320px browser viewport in light and dark,
  with no document horizontal overflow. Dark appearance was separately checked
  against the computed phone color scheme.
- Visually inspected wider Home, compact You, result, and dark Home.
- Exercised invitation → review → explicit consent → local receipt.
- Exercised friend leaderboard creation, 31-day rejection, valid scheduling,
  invalid amount rejection, roster editing and minimum two-person validation.
- Confirmed leaderboards have no target field and consent begins disabled.
- Exercised personal timed-goal required input, distance entry, retained target
  on back navigation, and its complete review screen.
- Exercised missing-data results, review reason validation, saved review text,
  receipt, and paused result display.
- Impeccable's mechanical detector ran with missing parser dependencies, so it
  could only perform regex checks. Its obsolete unused side-border style finding
  was removed during assembly; it did not establish computed contrast coverage.
- Superdesign's CLI could not load because the package registry was unreachable.
  Chrome's CLI bridge could not start; browser verification used the available
  in-app browser instead. No native tests were needed for this prototype-only work.

## Rebuild

```sh
python3 outputs/design/2026-09-13-clickable-app/build.py
node --check outputs/design/2026-09-13-clickable-app/check-syntax.js
```

The standalone preview loads the two brand fonts from Google Fonts and the
version-pinned Lucide icon library from its CDN. The conversation renderer
provides Lucide itself. No application APIs are called.
