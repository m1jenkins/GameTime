# Floodlight 09.4: four pot outcomes

September 27, 2026. [Open the prototype](index.html). **Copy proposal on the
adopted 9.3 look.** 9.3 stays the adopted visual direction (see the top entry of
[the UI adoption history](../../../docs/design/SIGNAL_UI_MIGRATION.md)).
Nothing here changes the native app, accounts, services or product rules.

9.4 is a copy of 9.3 with the Invitation's outcome cards and the pot sheet's
pictograms and copy swapped for four outcomes, and a 3 in the People control.
Tokens, layout, the dial, Home and the Challenge screen are otherwise 9.3.
[Round 9.3's record](../round-9-3/DESIGN.md) still describes everything this
page doesn't mention.

## 1. The rule the copy follows

`ChallengeV1Policy.allocation` for a friend goal: "People who meet their goals
recover their entries and share confirmed misses evenly. Any remainder and an
all-miss pool stay unallocated." `ChallengeV1Policy.missing`: "A missing or
unclear result never proves a missed goal. We return that person's simulated
entry and score the remaining results only if the agreed minimum remains."

## 2. The four outcomes

The same function picks the wording for the cards and the sheet: two people
get the pair wording, three or more get the group wording.

| Outcome | 2 people: card | 3 or more: card |
| --- | --- | --- |
| Everyone reaches it | **Both reach it** · Both stakes back | **Everyone reaches it** · All stakes back |
| Some reach it | **One reaches it** · They get both stakes | **Some reach it** · They split missed stakes |
| Everyone misses | **Both miss** · No one collects | **Everyone misses** · No one collects |
| No confirmed result | **Couldn't confirm** · Stake back, not a miss | same |

The pot sheet uses the same titles with a full sentence under each:

| Outcome | 2 people | 3 or more |
| --- | --- | --- |
| Everyone reaches it | You each get your stake back after results are final. | Everyone gets their stake back after results are final. |
| Some reach it | They get their stake back plus the missed one. | They get their stakes back and split missed stakes evenly. Cents that don't split evenly go to no one. |
| Everyone misses | Neither stake comes back. No one collects the pot. | No stakes come back. No one collects the pot. |
| Couldn't confirm | If we can't confirm someone's result from Apple Health, their stake comes back. It doesn't count as a miss. | same |

What was removed: 9.3's cards "They get both" and "Neither back" (pair-only,
and terse), and 9.3's sheet rows "Reach your goal", "Confirmed misses",
"Everyone misses · Nobody gets their stake back." and "No activity yet". The
timing ("after results are final") moved into the first outcome, and the
missing-data promise moved into "Couldn't confirm". The Invitation's facts
card still says "Missing or partial activity never counts as a miss."

"Couldn't confirm" speaks only about the person whose result we couldn't
confirm. What happens to everyone else when too few confirmed results remain
(for two people, that is every result) is in **Full rules**, not on a card.
9.4 does not change Full rules wording. A group invitation shows the group
sentences the Challenge's Full rules already had in 9.3, plus "The challenge
continues if at least two people remain."

All rows are in [COPY.md](../../../docs/COPY.md) under "Friend-goal pot and
Floodlight screens", with rows for the other labels on these screens,
including the short "3 min ago" freshness line.

## 3. Pictograms

Neutral figures, as before. Two people reuse 9.3's `both`, `one` and `neither`
drawings. Three or more draw three figures: everyone with a check and a coin;
one miss whose coin splits toward two checked figures; three misses with dimmed
coins.

"Couldn't confirm" must not look like a loss:

- the figure stays full color (a miss is dimmed) inside a dashed blue ring;
- its badge is a blue "?" (a miss is a slate "×");
- its coin stays full strength and a blue arrow brings it back to the person
  (a miss dims the coin);
- its card, and its row in the pot sheet, have a pale blue fill and a dashed
  blue edge.

Three new tokens paint it:

| Token | Paints | Light | Dark | SwiftUI |
| --- | --- | --- | --- | --- |
| `--gt-unconfirmed` | Badge, ring, return arrow, card edge | `#0E6FC0` | `#8CCBF2` | `Unconfirmed` |
| `--gt-unconfirmed-ink` | "?" on the badge | `#FFFFFF` | `#0B1A22` | `UnconfirmedInk` |
| `--gt-unconfirmed-wash` | Card and sheet row fill | `#EEF6FD` | `#15262F` | `UnconfirmedWash` |

The generated token table now has 74 rows.

## 4. People: 2, 3, 4, 6

The People control adds 3 (You, Sam, Jordan). The dial gets ring spacing for
three lanes (full: 26.5 spacing, 13 wide, hub 41; compact: 17.5, 8.6, hub 32).
The Invitation now follows the control: 2 is You and Jordan, as in 9.3; 3 adds
Sam; 4 and 6 add Priya, then Maya and Theo. The pot, the Pot tile, the
agreement heading ("You both agree…" or "You all agree…"), the VoiceOver
names and Full rules follow the head count.

## Checks performed

Chromium 153 through Playwright 1.63, at 1440px and 390px, 2× scale, reduced
motion. Full results are in [checks.json](captures/checks.json).

- No console errors or warnings. No horizontal page overflow at 1440px (Side
  by side under light and dark system settings, `#light`, `#dark`) or 390px
  (light and dark system).
- Copy: for 2, 3, 4 and 6 people, in light and dark, the four Invitation cards
  and the four pot-sheet titles match the tables above. No screen contains
  "They get both" as a card line, "Neither back", "Nobody gets their stake
  back." or "No activity yet". At 3 or more, no pair words ("Both reach", "One
  reaches", "Both miss", "Both stakes") appear.
- Sweep: 70 combinations (every day; 2 people; 3, 4 and 6 people with each of
  Jordan's three update states) across all six phones. No malformed dial
  paths, no overflow inside a phone, and no clipped outcome card or row.
- Larger text at 2, 3 and 6 people: no overflow in the Invitation header, the
  outcome cards or the page, in either mode.
- Pot sheet in light and dark moves focus to Close and shows the
  simulated-stakes footnote. Escape returns focus to the stake card.
- Contrast, measured on the rendered colors. Card and row text is 5.97:1 or
  better in light (the secondary line on the blue wash) and 7.08:1 or better
  in dark (target 4.5). "?" on its badge is 5.18 (light) and 10.07 (dark). The
  badge and ring on the wash are 4.75 and 8.84, and the dashed edge on the
  ground 4.87 and 10.4 (target 3). The miss badge measures 3.27 and 3.10,
  unchanged from 9.3. `contrastFailures` is empty.

Captures:
[invitation-rules.png](captures/invitation-rules.png) (3 people, light and dark),
[invitation-rules-2-people.png](captures/invitation-rules-2-people.png),
[pot-sheet.png](captures/pot-sheet.png) (3 people, light),
[pot-sheet-dark.png](captures/pot-sheet-dark.png) (3 people, dark) and
[pot-sheet-2-people.png](captures/pot-sheet-2-people.png).

Not performed: native SwiftUI, VoiceOver, Dynamic Type, rendering on a phone
display, and any device run. Whether people read "They split missed stakes"
and "No one collects" correctly still needs someone to try it.

## Responsible engagement

The outcomes are stated evenly and in the same order every time. There are no
projected winnings, no "who's at risk", no money celebrations, countdowns,
notifications or analytics. "Couldn't confirm" is drawn so that missing data
never looks like a loss, which is the existing promise. The simulated-stakes
wording stays where 9.3 put it.
