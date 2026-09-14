# Crisp cobalt design system

> **Historical design, deprecated September 13, 2026.** Signal is the official native UI/UX. Use [the migration contract](../SIGNAL_UI_MIGRATION.md) for current work; the system below describes the superseded cobalt UI.

The approved [Home concept](approved-home.png) sets the visual direction. The
native UI uses current challenge projections; the concept's names and totals
exist only in `CobaltRenderedTests`.

## Foundations

| Purpose | Light | Dark |
| --- | --- | --- |
| Canvas | `#FFFFFF` | `#0C1220` |
| Surface | `#FFFFFF` | `#151E2E` |
| Primary text | `#101724` | `#F5F7FC` |
| Secondary text | `#526176` | `#B3C0D5` |
| Interactive brand | `#0752F5` | `#9BB5FF` |
| Featured content | `#0752F5` | `#0752F5` |
| On featured content | white | white |
| Selection | `#EAF0FF` | `#253759` |
| Divider / progress track | `#E1E7F0` | `#34425A` |
| Error | `#B22D40` | `#FFADBA` |
| Warning | `#775200` | `#E9C784` |
| Success | `#216A52` | `#99D9C0` |

`CompetitiveTrustTheme` owns these values. Old `Daybreak`/`Athletic` token names
are compatibility aliases for retained historical flows, not separate palettes.
The historical product remains intentionally light-only. Local Beta retains its
existing system appearance behavior.

`CobaltDisplay` uses the bundled Barlow Condensed Black Italic face, with
Dynamic Type scaling relative to large titles. The upright Black face supports
callers that request it. Names, rules, fields, units and controls remain upright.
Large metrics use the same italic display family, with units that reflow when
necessary. Cumulative progress combines value and target without rounding away
seconds or fractional kilometres. The historical font helpers honor `relativeTo`.

The font files come from the [official Google Fonts repository](https://github.com/google/fonts/tree/main/ofl/barlowcondensed).
Their SIL Open Font License is bundled as `BarlowCondensed-OFL.txt`; both faces
are registered in all three app configurations. A runtime check requires the
actual named italic font and its italic trait. Existing Hanken Grotesk and
Bricolage Grotesque retain their licenses. No text is stretched or skewed.

## Composition

Home keeps action/recovery items in the server's section order. Its first
eligible active friend challenge receives the broad cobalt panel. Personal
progress and upcoming challenges use open rows. Secondary rows retain your own
activity, which is important when several challenges are present.

Rank, name and total stay aligned. The current account has both a `You` label
and a leading rule. Avatars contain initials only. Unknown results have no rank;
ties share competition rank; timed leaderboards order lower elapsed values
first. Departed counterpart details remain hidden. Goal progress is clamped for
cumulative metrics and never inferred from missing data. A timed goal states
the whole-run distance and strict time to beat without a percentage bar.

Forms and account content use open sections and dividers. Retained summary and
notice cards have restrained 12–14 point corners and no shadow. Destructive
controls use the semantic error color and keep native confirmation dialogs.
Result/review actions precede participant details so their deadlines remain
prominent. Full terms and exact consequential consent remain available.

## Native behavior

The deployment target remains iOS 18. Native bars use platform material on 26+;
the older system retains an opaque semantic background. Beta's retained custom
tab strip preserves three independent `NavigationStack`s and the previously
accepted accessibility menu alternative. Its control surface uses the actual
`glassEffect` API on 26+, with an opaque fallback under Reduce Transparency and
on 18. Content remains opaque. No custom animation is required by the redesign.
Existing button animations respect Reduce Motion.

## Honest limitations

The selected wire model has no timestamp for the adopted delayed community
aggregate contract. Exact participant counts are therefore withheld in catalog,
join and detail. This UI does not claim the backend privacy work is complete.
All new-domain activity remains fictional and stakes nonredeemable. Existing
physical source, hosted-client, support/deletion and release prerequisites remain
separate from visual verification.
