# GameTime Daymark mock-up set

> **Scope — September 4, 2026.** These are visual references for the
> Personal steps implementation, not the future product roadmap. Their
> solo-only/no-opponent constraints do not override the adopted friend-duel and
> performance-commitment model in [BUSINESS_MODEL.md](../BUSINESS_MODEL.md).
> Mockups are not proof of implemented features, verified results or money.
> Preserve existing app behavior until a separate implementation task changes it.

Status: visual direction exploration only. These raster mock-ups do not change
the shipping SwiftUI implementation or product behavior.

## Visual thesis

**A private seven-day promise appears as a calm route of seven daymarks: one
clear current marker carries the only dominant metric while the rest of the
week remains quietly legible.**

The direction abstracts the sunrise-and-stepping-stones app icon into a
repeatable UI motif without representing a GPS route, a social competition, or
a game. It deliberately differs from the existing chart, vertical-course, and
daily-split design explorations.

## Screens

| Screen | Image | Main user job |
| --- | --- | --- |
| Active Today | `challenge-mockups/gametime-daymark-today-v1.png` | Understand the remaining daily steps and the exact cutoff. |
| Review before start | `challenge-mockups/gametime-daymark-review-v1.png` | Confirm a seven-day plan and its protected test-payment terms. |
| Finished week | `challenge-mockups/gametime-daymark-result-v1.png` | Understand a completed result and its Apple Health source. |

## System decisions

- **Hierarchy:** remaining/current step reality first, seven-day context second,
  Health freshness and commitment terms last.
- **Signature:** seven softly faceted, flat daymarks form a compact diagonal or
  arch. Their labels carry state and value; color never stands alone.
- **Palette:** mist-lilac canvas, deep-plum text, apricot for the current action,
  moss for a confirmed goal, and river-blue for Apple Health information.
- **Platform stance:** native navigation, tab bars, sheets, disclosure rows, and
  a single unmistakable primary action. The brand expression sits in content,
  not in custom navigation controls.
- **Money posture:** a test commitment is a quiet receipt, never a balance,
  reward, prize, or emotionally charged metric.

## Interaction and accessibility notes

- Expose the daymark sequence as an ordered, VoiceOver-readable list. At
  accessibility Dynamic Type sizes, reflow it into a vertical sequence rather
  than shrinking day labels or figures.
- Preserve text and symbol cues for current, met, upcoming, Health-connected,
  and payment-test states.
- Maintain 44 pt targets for the challenge action and disclosure rows. Use
  tabular figures for changing step totals.
- The active screen should use an automatic freshness row by default; any
  explicit refresh remains a quiet secondary recovery action.
- A miss, missing data, and a payment-review state need their own plain-language
  variants. Do not transform the calm result composition into a red alert or a
  celebratory payout screen.
