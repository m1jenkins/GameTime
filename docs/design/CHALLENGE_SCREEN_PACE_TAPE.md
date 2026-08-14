# GameTime Pace Tape mock-up set

Status: visual-direction exploration only. These raster references do not
change the shipping SwiftUI implementation or product behavior.

## Visual thesis

**A private commitment reads like a live instrument: the current step total is
the quote, the week is a compact performance tape, and the source is a precise,
quietly visible data record.**

Pace Tape takes the transferable qualities of contemporary performance and
financial apps—high numerical confidence, dense event state, and a single clear
action—without using their brands, market mechanics, or visual signatures.

## Screens

| Screen | Image | Main user job |
| --- | --- | --- |
| Active Today | `challenge-mockups/gametime-pace-tape-today-v1.png` | Understand the verified total, remaining steps, cutoff, and weekly context. |
| Review before start | `challenge-mockups/gametime-pace-tape-review-v1.png` | Review a seven-day commitment and protected test-payment terms in one place. |
| Finished week | `challenge-mockups/gametime-pace-tape-result-v1.png` | Read a durable result, source timestamp, and quiet $0 outcome. |

## System decisions

- **Hierarchy:** the current verified step total leads; remaining effort and
  exact cutoff follow; Health freshness and test terms stay visible but quiet.
- **Signature:** the Week Tape is a seven-column square-cell matrix. It is a
  readable summary of a seven-day step goal, not a price chart, activity ring,
  route, or leaderboard.
- **Palette:** ink/graphite canvas; off-white text; citron for one primary
  action or selected state; movement green for achieved movement; signal blue
  for Apple Health; violet only for test-commitment context.
- **Surfaces:** one substantial live/summary surface per state, then divider-led
  data rather than a stack of decorative cards.
- **Platform stance:** retain native iOS navigation, tab bar, sheet, button,
  and disclosure affordances. The expression belongs in data density and type,
  not custom behavior.

## Boundaries and implementation notes

- The product is not a market. Never introduce trading language, odds, prices,
  P&L, balance, wallet, payouts, rewards, or buy/sell controls.
- The test commitment must stay below the goal/progress hierarchy and use the
  current payment-mode copy contract in `docs/COPY.md` before shipping.
- Use **Active** rather than **Live** when automatic Health updates are not
  continuous; always pair the state with a concrete Apple Health update time.
- VoiceOver should expose the Week Tape as an ordered summary of seven days,
  including each total/state. At large Dynamic Type, reflow it to an accessible
  vertical list rather than shrinking labels or cells.
- Ship semantic light, dark, increased-contrast, and Reduce Transparency
  variants; the mock-up is intentionally a dark-direction reference, not a
  complete appearance matrix.
- Goal completion can acknowledge earned movement, but must not animate or
  glamorize the related $0 test-charge outcome.
