# Floodlight 11.1: edge states with the owner's decisions

September 27, 2026. [Open the prototype](index.html). **Proposed, not
adopted.** This is round 11 with the ten decisions the owner, Mason, approved
on September 27. It keeps the round 10.1 look unchanged: the same tokens, light
Aero Toned and dark Floodlit, and the Appearance control (Light | Dark | Side
by side). Round 11, round 10.1 and earlier rounds are untouched, except that
round 9.3's footer now says "Adopted". Nothing native changed. Every person,
username and number is fictional.

The page has 32 screens and 64 phones, up from 25 and 50. Pair notes mark
approved changes **Adopted**, new words **New** and differences from the app
**Departs**. [Round 11's record](../round-11/DESIGN.md) still describes the
screens this round didn't change. It also covers the app rules behind every
state.

## What changed, by decision

**1. Two-person Couldn't confirm.** With two people, one result we can't
confirm leaves one scored result, and a challenge needs two. So the
two-person card now reads **Couldn't confirm** · "Stakes back · Challenge won't
count". Its picture shows both people, each getting their own coin back (polish
edit a). The pot sheet sentence is "If we
can't confirm a result from Apple Health, both stakes come back and the
challenge won't count." Groups of 3 or more keep **Couldn't confirm** · "Stake
back, not a miss" and their sheet sentence. Round 11 had no two-person outcome
cards, so 11.1 adds them on a new **Invitation · two people** phone and a new
**The pot · two people** sheet. The two-person **Couldn't confirm** result
screen now uses the same sentence under "This challenge didn't count". It
replaces round 11's "We couldn't confirm one result, and a challenge needs
two. Every stake comes back."

**2. How a review ends.** Two new phones, **Result updated** and **Result
stands**, sit on the goal detail. A **Your review** card holds the title and
one line for the reason you picked. A control in each pair note switches
between the app's three reasons:

| Reason (app) | Result updated | Result stands |
| --- | --- | --- |
| My total looks wrong | We rechecked your Apple Health total and corrected it. | We rechecked your Apple Health total, and it matches your result. |
| Activity is missing | We found the missing activity and added it to your total. | We didn't find any more activity for these dates. |
| My result looks wrong | We rechecked your result against the rules and corrected it. | We rechecked your result against the rules, and it's right. |

The title and line stand alone; there is no "You asked: …" line (polish edit
c). When the result changes, the number, chip and return change with it
(70,215 steps, **Goal met**, $20), and the full bar is in your own color
(polish edit d). When it stands, they stay (68,940, **Goal missed**, $0).
Neither says "upheld" or "dispute".

**3. The invitation shows "$20 each".** The terms are **Stake** "$20 each" and
**Fee** "$0". The Pot term is gone. The header's pot is now the lobby's pot. It
counts only people who agreed: Jordan made the challenge and agreed, so it
holds $20 and reads "$20 in the pot". Your seat, and Sam's in a group, is a
dashed seat with a small avatar until you agree. Under the pot the header says
"Jordan agreed. Your seat fills when you agree." on screen, not only in
VoiceOver (polish edit b). Tapping the pot opens the pot sheet. The AX5
invitation follows the same rule. The lobby keeps "$40 in the
pot" (you and Sam agreed) and "A seat fills when that friend agrees." Both
lobby rows are now in COPY.md.

**4. A decline reopens the seat silently.** Round 11 already did this. The
lobby phone moved into the new invitation section. Its note is marked Adopted,
and a check confirms that neither the name nor "Declined" appears.

**5. Manage access in Apple Health** stays on the challenge's Health card, as
a link under the neutral **Refresh activity** button. It is marked Adopted.

**6. The result is on the page.** The goal detail's **Your result** card holds
the chip, "Recorded simulated return" with the amount, and now "Result
confirmed · Recorded Jun 17". The separate Result confirmed row is gone, and
**Full rules** takes its place. This applies to Missed, Not confirmed and both
review outcomes.

**7. Timed runs show the best run so far.** Unchanged from round 11, now
marked Adopted.

**8. One blue action per screen.** Every Apple Health button stays neutral
gray. A new check confirms that no phone shows more than one blue button,
sheets included, and that no Health card button is blue.

**9. Put money on it.** A new **Put money on it** section has two phones.
**Rules · Put money on it** shows the saved test method, the outcome lines
"$0 test charge", "$20 test charge" and "Not a miss, no charge", and the amount
row **Test commitment** · "$20 test charge only if you miss." **Goal saved ·
money on it** uses that line under "Challenge locked in." All of these lines
are now COPY.md rows.

**10. Leaderboard pot line and Time target.** The leaderboard's pot card uses
the app's "Winners split the remaining simulated pool evenly." Round 11's
"Ties split it evenly." is dropped, and "No valid saved score means your stake
comes back." stays. The phone keeps its **Proposed** pill because leaderboards
are still for a later build. On the timed run, each person's time reads "Time
target · 25:00", the label Create uses, in place of "Under 25:00".

## Polish edits, September 27

Mason approved four more edits the same day. They answer four of the open
questions and are made in place in this round.

- **a. Two-person picture.** The Couldn't confirm picture shows both people.
  Each has their own coin under them with an arrow back, and the person we
  couldn't confirm has the dashed ring and "?" badge. Before, two coins went
  to one person.
- **b. Seat line on screen.** "Jordan agreed. Your seat fills when you agree."
  now sits under "$20 in the pot" on all three invitations, AX5 included. The
  pot button's VoiceOver label drops the line so it isn't read twice.
- **c. No "You asked".** Review cards show the title and one line only.
- **d. Met bar.** A met goal's bar uses the member's own color, not the button
  blue, so blue stays reserved for the screen's one action.

## COPY.md

Changes stay inside "Friend-goal pot and Floodlight screens". Existing rows
changed: Couldn't confirm (two-person wording added, and the two-person
picture), pot total (counts only people who agreed), invitation terms (the
seat line on screen), lobby pot, the two-person void, the timed run, the
leaderboard, and the two review outcomes (no "You asked" line). New rows:
Apple Health access on the Health card, the goal detail result, the two review
outcomes, and the two Put money on it rows. No other line in COPY.md changed.

## Departures from the app

- The goal detail shows the result on the page. The app keeps it in the Your
  result sheet.
- The saved screen for a goal with money on it says "$20 test charge only if
  you miss." `ChallengeCreationSuccess` still shows "$20 simulated · fee $0".
- The invitation has no Pot term and shows a lobby pot. The app has no
  invitation pot yet.
- Carried from round 11: the Not confirmed chip (the app says "Didn't count"),
  the empty-state dial, radio rows for the review reasons, and the leaderboard
  without a dial.

## Remaining open question

**Native work.** Decisions 6 and 9 need `LiveGoalDetail` and
`ChallengeCreationSuccess` changes. The review outcome lines need the review
decision to reach the client. The on-screen seat line and the met bar color
need matching native changes too. This round doesn't touch native code.

## Checks performed

Chromium 153 through Playwright 1.63 from the global npx cache
(`/Users/user/.npm/_npx/6bcb61ec6d5aea22`) and nothing else, with reduced
motion. [checks.json](captures/checks.json) has the full results.

- No console errors or warnings. No horizontal page overflow at 1440px (Side by
  side with light and dark system settings, `#light`, `#dark`) or at 390px
  (light and dark system).
- No element sticks out of any phone, and no content or sheet scrolls sideways,
  in those six views, or with two-person results and the alternate states.
- **Restraint** on all 64 phones: at most one frosted surface, always inside
  the sky, and never a frosted card on a screen with a dial. One sky per phone,
  no beams outside it, and backdrop blur only on the lit surface. No gradient
  buttons, avatars or Quiet cards, and no raster images. All pass.
- Every icon reference resolves. Each screen shows its required strings, and
  each dark phone's text matches its light twin. No banned words appear on any
  phone. The scan now reads "won't" as a contraction, so "Challenge won't
  count" isn't flagged as "won".
- **80 interaction and policy checks pass**, up from 54 in round 11 and 76
  before the polish edits. The new ones cover each decision:
  - **1:** the two-person card and sheet wording in light and dark, the pair
    titles and heading, no pair wording on group or AX5 invitations, and the
    two-person void using the new sentence with $20 and $20.
  - **2:** all six review lines, one for each reason and outcome, in light and
    dark; the result card changes only when updated; no "upheld" or
    "dispute".
  - **3:** terms read "Stake $20 each" and "Fee $0" on all three invitations.
    No $40, $60 or Pot term appears before anyone else agrees. The invitation
    pot equals $20 × filled seats, with 1 filled seat and 1 or 2 pending. The
    lobby pot equals $20 × Agreed chips ($40).
  - **4:** no "Declined" and no name in the lobby, light and dark.
  - **5:** "Manage access in Apple Health" on the Health card.
  - **6:** a Your result card on four detail screens, and no Result confirmed
    row.
  - **7 and 10:** best run shown, three "Time target" labels, and the app's
    leaderboard line with the Proposed pill.
  - **8:** one blue button at most on every phone, and neutral Health buttons.
  - **9:** the money line on the Rules and saved phones, and the three outcome
    lines in order.
  - **Polish a–d:** the two-person picture has two people, two coins, two
    return arrows and one "?" on both invitation phones and the pot sheet. The
    seat line is visible on all six invitation phones and gone from the pot
    button's label. No phone says "You asked". The met bar matches the
    member color in light and dark and differs from the button blue.
- **Contrast** covers every visible text run, including SVG text: 1,496 in the
  default state and 1,546 in an alternate state. The alternate state adds the
  two-person results, the other review reasons and the closed sheets. The
  method is round 11's: phones unrolled, text hidden, the pixels behind each
  glyph box read at 2× (5th percentile), and a target of 4.5:1, or 3:1 for
  large text. **Zero misses.** The lowest normal text is 4.50 (inactive tab
  labels, unchanged from 9.3), and the lowest large text is 4.31 (the AX5
  invitation's "jordan.b invited you", which moved down slightly as the header
  grew).
- **Unslop:** the phrase and structure scanners find nothing in this record
  or the README entry. On the page's visible text, with duplicate lines
  removed, the phrase scanner raises round 11's one soft flag: "No one
  reached their goal." and "No stakes come back." are separate lines, joined
  when the text was extracted. The structure scanner no longer flags opener
  repetition. The ratio is now 0.561 against 0.55, up from 0.547 before the
  polish edits.

Captures, all in [captures/](captures/):
[outcomes-two-and-group.png](captures/outcomes-two-and-group.png),
[invitation-and-lobby.png](captures/invitation-and-lobby.png),
[review-results.png](captures/review-results.png),
[detail-and-health.png](captures/detail-and-health.png) and
[timed-run.png](captures/timed-run.png) (phones unrolled to full height), plus
the section captures [empty-states.png](captures/empty-states.png),
[health-and-sync.png](captures/health-and-sync.png),
[invitation-flow.png](captures/invitation-flow.png),
[someone-leaves.png](captures/someone-leaves.png),
[results.png](captures/results.png),
[results-two-people.png](captures/results-two-people.png),
[review-and-cancelled.png](captures/review-and-cancelled.png),
[put-money-on-it.png](captures/put-money-on-it.png),
[formats.png](captures/formats.png), [ax5.png](captures/ax5.png) and
[width-390-dark.png](captures/width-390-dark.png).

The polish edits re-saved six captures: outcomes-two-and-group,
invitation-and-lobby, review-results, invitation-flow, review-and-cancelled
and ax5. The rest are the earlier files. Two of them, timed-run and
detail-and-health, differed only by sub-pixel shifts from the taller sections
above, so they were kept.

Not performed: native SwiftUI, real Dynamic Type, VoiceOver, rendering on a
phone, or any device run.

## Responsible engagement

The decisions touch money wording, reviews and timed runs.

- A test charge is stated once, plainly, and only for a miss. Missing data is
  "Not a miss, no charge".
- Review outcomes explain what we checked and never blame anyone. You can only
  ask about your own result.
- The invitation no longer shows a pot that includes people who haven't
  agreed, so it can't make the stakes look bigger than they are.
- The timed run shows your best run with no ranking, streak or countdown. The
  leaderboard stays a later-build proposal.
