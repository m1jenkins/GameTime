# Floodlight 11: edge states

September 27, 2026. [Open the prototype](index.html). **Proposed, not
adopted.** Round 11 draws the states the P0 screens hit when things aren't
normal. It uses the round 10.1 look unchanged: the same tokens, light Aero Toned
and dark Floodlit, and the Appearance control (Light | Dark | Side by side).
Round 10.1 and earlier rounds are untouched, and nothing native changed. Every
person, username and number is fictional.

The page has 25 screens, 50 phones. Each pair note names its Swift source and
marks new words **New** and departures from the app **Departs**. A **People**
control on the results section switches between two people and a group.

The 9.1 restraint rules carry over. Each screen has one sky or set of beams,
and it sits behind the hero. Each screen has at most one lit surface: the dial,
or one frosted card, never both. Everything else is a Quiet card. Avatars and
buttons are flat, icons are SF Symbol stand-ins, and no screen celebrates
money. Round 11 adds no tokens. It adds four small CSS overrides for contrast;
see [Contrast fixes](#contrast-fixes).

## What the app does today

Found in the Swift sources, and these rules shape every screen below:

- **Apple Health never tells us about a denial.** HealthKit hides read denial
  (`HealthKitActivityClient.swift`), so denied, partly granted and genuinely
  empty all show `ChallengeHealthCopy` **No matching activity yet**. There is no
  per-type copy.
- **A leaver gets their stake back.** `challenge_evaluate_policy_v1` returns
  full amounts to anyone who left or can't be confirmed. The rest are scored
  only if at least two confirmed results remain. Otherwise the challenge voids
  ("This challenge didn't count") and every stake comes back.
- **Two people with one unconfirmed result voids.** Only one confirmed result
  is left, which is below the minimum of two.
- **Winners get their stake plus an even share of confirmed misses, rounded
  down to the cent.** The leftover cents, or the whole pot if everyone
  misses, stay unallocated.
- **You can only ask for a review of your own result**, within 48 hours of the
  result notice, with one of three reasons and no free text. Nobody can dispute
  someone else's result.
- **Cancelled** means the creator cancelled before the start, or not everyone
  agreed by the start. Fewer than two people left is a void, not a
  cancellation.
- **Leaderboards are off in build 1** (D140, D142) and aren't offered in
  Create. The received-score rules for a later build are in D141.
- The app has no pot total, no Floodlight dial and no "Not confirmed" chip yet.
  COPY.md's Floodlight rows are the agreed copy for those.

## Empty states

**Home · first time.** Source: `LiveChallengeShell.swift` `LiveEmptyState`.
The app's "Your first challenge", "Choose a goal and the dates that work for
you." and **Create a challenge**, on one frosted card. The art is the mini dial
with nothing on it: the plate, the ticks and one empty track. It has no pot,
because nobody has put in a stake. *Departs:* the app shows plain text.

**Home · between challenges.** Source: `LiveHomeView`, `homeState == .content`.
The app's "No active challenge", "Your finished goals are in You.", **Create a
challenge** and **View your record**. A pending invitation still shows under
Next up.

**Challenges · empty.** Source: `LiveLibraryView`. All uses the app's
`LiveEmptyState`. Invited and Finished show the app's one-liners, "No
invitations waiting." and "No finished challenges yet.", with no card and no
lit surface. The filters drop their count badge. "Use an invitation link"
stays at the bottom.

**You · empty.** Source: `LiveRecordView.swift` `emptyRecord`,
`FriendsViews.swift` `empty()`. The record reads 0 and 0 in the muted color,
with three empty pips, so a zero never looks like a failure. The Friends row
reads "Add your first friend", the title of the app's empty Friends screen.
The empty card is the app's.

## Syncing, stale data and Apple Health

**Refreshing.** Source: `LiveGoalDetail.swift` Refresh activity,
`ChallengeHealthStatusView` `pendingDelivery`. Your card keeps the last saved
number (18.2) while it shows "On this phone: 19.6 km" and "Waiting to send this
update". The dial moves only when we save. Jordan has no saved update, so their
lane shows the dashed waiting marker and their name chip says **No update**.
The quiet card underneath uses the app's friend-sheet line "This is their last
saved activity. Missing activity isn't a missed goal." The button reads
**Refreshing…** and is disabled, as in the app. A control in the pair note
finishes the refresh, and then the card shows "Just now" and "Last saved
update …".

**Home · stale.** Source: `LiveHomeView.sourceLine`, `.temporarilyUnavailable`.
The sync icon becomes a clock with "Yesterday, 6:10 PM", as COPY.md's row
says. One quiet card carries the app's "Activity temporarily unavailable" and
its sentence, with **Refresh**. The dial keeps its last saved arcs, and
nothing turns red or gray.

**No activity found (denied).** Source: `ChallengeHealthCopy.noEligibleDataYet`,
`readiness: false`. This is what a denied permission looks like, because the
app can't detect one. Your lane shows the waiting marker. The card uses the
app's title, its sentence ("Missing activity doesn't count against you.") and
**Refresh activity**. *Departs:* it adds **Manage access in Apple Health**,
the app's Settings link, to the card. It opens Apple's help page, not an
app-settings deep link.

**Agree · missing activity (partly granted).** Source: the Review and agree
sheet, `ChallengeHealthStatusView` `readiness: true`. If a friend allows Steps
but not Workouts, a running challenge reads exactly like no activity. The sheet
uses the app's readiness sentence ("…in the last 30 days. Check your Apple
Health settings…"). **Agree to this challenge** stays off even after the agree
switch, as in the app. The mock doesn't name which data type is off, because
we can't know.

## Someone leaves or declines

**Lobby · a friend declines.** Source: decline in `LiveChallengeShell.swift`,
lobby roster labels. Jordan declined. Their dashed seat becomes an open seat
again and their row leaves the roster. Nobody is told who declined. **The pot
doesn't change:** it only ever held stakes from people who agreed (you and
Sam, $40). The roster chips are the app's **Agreed** and **Reviewing the
rules**. The header count "2 agreed" is **New**.

**Leave safely?** Source: `LiveGoalDetail.swift` `confirmationDialog`. It's the
app's dialog and words, drawn with iOS action sheet metrics. The text uses
Apple's Increase Contrast grays, red and blue, as 10.1's alert does. The
creator sees **Cancel challenge** instead before the start. The on-screen
**Leave challenge** is a calm gray button. Red appears only in the system
dialog.

**Someone left.** Source: "With you" in `LiveGoalDetail.swift`. Priya's track
leaves the dial and the other three keep their places. The hub drops from $80
to $60. The pot card shows $80 struck through beside $60, then **New** "The
pot is $60 now" and "Someone left and got their stake back." The second
sentence, "The challenge continues if at least two people remain.", is the
rules' own. The leaver shows as the app's "Former participant" and "Left
challenge", with a gray person symbol instead of their avatar.

**Down to one.** Source: `statusText` void. Sam left a two-person challenge.
The screen uses the app's "This challenge didn't count", then **New** "A
challenge needs at least two people. Every stake comes back." and "Your stake
is back". The dial has no hub, because there's no pot left.

## Finished results

Source: `ChallengeV1Policy.allocation` and `.missing`, `LiveGoalDetail`
`resultContent`, and the amounts from `challenge_evaluate_policy_v1`. Every
result screen shows a pill with the app's **Result confirmed**, a compact dial
with each final arc and the pot, one summary line, the pot sheet sentence from
COPY.md, and a pot table in roster order. Rows are never ordered by amount.
Chips are the app's **Goal met** and **Goal missed**, plus COPY.md's **Not
confirmed**.

| Outcome | 2 people (you, Sam) | 3 or more |
| --- | --- | --- |
| Everyone reaches it | $20, $20 | 3 people: $20 each |
| Some reach it | You $40, Sam $0 | 4 people, Jordan misses: $26.66 × 3, Jordan $0, **Goes to no one** $0.02 |
| Everyone misses | $0, $0, **Goes to no one** $40 | 3 people: $0 each, **Goes to no one** $60 |
| Couldn't confirm | **Voids**: $20, $20, "This challenge didn't count" | Jordan unconfirmed gets $20 back; you $40, Sam $0 |

- **New:** "Goes to no one" (the app says "Unallocated simulation"), "No one
  reached their goal.", the table headers **The pot · $80** and **Simulated
  return**, and the two-person void sentence "We couldn't confirm one result,
  and a challenge needs two. Every stake comes back."
- The summary lines reuse the live sentences ("Everyone reached their goal.",
  "You, Sam and Priya reached your goals.").
- Amounts sit in plain Barlow. The screen has no coins, confetti or glow, and
  the winners' rows look like everyone else's apart from the chip.
- **Flag on 9.4:** the Couldn't confirm card, "Stake back, not a miss", is true
  for the unconfirmed person. In a two-person challenge it leaves out that the
  other result stops counting too. See open question 2.

## Missed and unconfirmed on the goal detail

**Missed.** Source: `LiveGoalDetail` hero, verdict and allocation. The frosted
card uses the app's **Missed** chip in the slate miss style (never red), the
number, a slate bar and "Your goal: 70,000 steps". Below it are a Quiet
day-by-day card, the app's "If you miss · Only a confirmed miss counts", a
**Your result** card ("Goal missed", "Recorded simulated return $0", the app's
"Nothing can be paid out or redeemed. No real money moved.") and the **Result
confirmed · Recorded Jun 17** row. *Departs:* the app keeps the result card
inside the Your result sheet. The mock shows it on the page.

**Not confirmed.** The frosted card turns blue and dashed, with "Result
unavailable" and "It doesn't count against you." Days without saved activity
are dashed blue, not empty. *Departs:* the app's chip says "Didn't count" and
its result says "Your entry returns". The mock uses COPY.md's **Not
confirmed** and "Stake back, not a miss", as 10.1 did on You. It's a
three-person challenge on purpose: with two people, the whole challenge would
void.

## Review requests and a cancelled challenge

**Ask us to review.** Source: the Your result sheet in `LiveGoalDetail`. It
shows "Latest result update", "Goal missed", "Proposed simulated return $0",
"Review by Sep 23, 6:00 PM", the app's three reasons and **Ask us to review**,
with no free text. The goal behind stays "In review". *Departs:* the app uses a
menu picker, and the mock shows the reasons as radio rows so all three are
visible.

**Review requested.** The sheet shows the app's "Your review request is saved.
We're checking your result.", "Requested Sep 22, 8:12 PM" and **Refresh
result**, with the rules' sentence about the 72-hour reviewer window below. The
app has no words for how a review ends beyond "Review complete. Refresh for
the latest result." See open question 4.

**Challenge cancelled.** Source: `statusText`, `LiveGoalRules.swift`. The one
frosted card holds an `xmark.circle` in a gray well, the app's "Challenge
cancelled", **New** "Not everyone agreed before the start, so nothing
counts." and the rules' "Your simulated stake comes back." The line under it
is the decline sheet's "Your existing agreements stay unchanged." It never
says who didn't agree.

## Timed run and leaderboard

**Timed run: fits the dial as a yes or no.** Source: `ChallengeV1Policy`
timed scoring, `headerSummary`. One eligible whole run strictly under your time
meets the goal, so there's no partial progress to draw. A track stays empty,
with the dashed waiting marker, until a run counts. Then it fills to the flag.
A half-filled arc for "close to your time" would suggest progress that the
rule doesn't have. Each person keeps their own time from the lobby. The list
shows each time and the best run so far. **New:** "Not yet", "Best run", "No
run yet". "Goal reached" and "Time includes pauses." are the app's.

**Leaderboard: deliberately departs from the dial (later build).** Source:
received scores in `LiveGoalDetail` (D141). A leaderboard has no goal, so there
is no track to fill, and the dial must never rank people. The screen shows your
saved score in the frosted card, with the app's "Save activity by …" and
"Missing or late activity doesn't count.". Below it is a list in saved-score
order, with small gray rank numbers and the app's "—" and "Unranked — no valid
saved score". It has no medals, podium or trophy. **New:** "Highest saved score
takes the pot" and "Ties split it evenly. No valid saved score means your stake
comes back." The app's own line is "Winners split the remaining simulated pool
evenly." A **Proposed** pill marks the phone. Build 1 doesn't offer it.

## AX5 Dynamic Type

Sizes follow iOS AX5: Body 53pt, Subheadline 49pt, Footnote 44pt, Caption 40pt,
Title 58pt and Large Title 60pt. Display numbers go up to 96pt.

**Home · AX5.** Everything stacks in one column. The dial moves above your
number at full card width. Next up rows wrap under their date tile. The tab
bar keeps its size, as iOS does, and its labels show in the large content
viewer.

**Invitation · AX5.** Built from the 9.3 Invitation. The pot sits above the
goal. Your stake, Pot and Fee stack. Outcome cards become one column with the
picture on the left. Each fact row puts its symbol above its sentence. **Not
started** wraps onto its own row beside Back. Review and agree grows to two
lines. Every button is at least 44pt tall.

## Contrast fixes

A four-lane dial draws smaller text than the screens 9.3 measured, so three
round 10.1 styles fell below 4.5:1 here. Round 11 overrides them in its own CSS
and leaves round 10.1 unchanged:

- Initials on a filled lane token are black in light. Priya's purple with the
  72% ink mix measured 3.76.
- Initials in a dashed waiting marker, on the dial and under it, use ink. In
  dark, under the dial, they had inherited the near-black avatar ink (1.04).
- The pot's gloss crescent drops to 40% opacity. The POT caption measured
  4.09–4.47 on the smaller four-lane hub.
- The small pot chip centers its text. Its baseline alignment had pushed the
  glyphs over the chip's top edge.

## Open questions

1. **Apple Health help.** Should "Manage access in Apple Health" sit on the
   challenge's Health card, or stay only in Settings as it does today?
2. **Two-person Couldn't confirm.** Should the 9.4 invitation card say more
   for two people, for example "Stake back. The challenge won't count."?
   Today's card is right only for the person whose result we can't confirm.
3. **Decline in the lobby.** Is a silent open seat right for the creator, or
   should the roster say "Declined" for the people they picked?
4. **Review outcome.** The app has no words for "your result changed" or "your
   result stands". Should those be written before build 1?
5. **Timed runs.** Should the best run so far show at all, or only met / not
   yet, to keep pressure down?
6. **Detail result card.** Show "Goal missed" and the $0 return on the page, as
   here, or keep them behind the Result confirmed row, as the app does?
7. **Leaderboard pot line.** "Highest saved score takes the pot" or the app's
   "Winners split the remaining simulated pool evenly"?
8. **The invitation's pot** shows everyone's stakes ($60) before anyone
   agrees, as 9.3 does. The lobby pot counts only people who agreed. Should
   the invitation match the lobby?

## Checks performed

Chromium 153 through Playwright 1.63 from the global npx cache, with reduced
motion. The full results are in [checks.json](captures/checks.json).

- No console errors or warnings. No horizontal page overflow at 1440px (Side by
  side with light and dark system settings, `#light`, `#dark`) or at 390px
  (light and dark system).
- No element sticks out of any phone, and no content or sheet scrolls sideways,
  in those six views. The same holds with two-person results and the alternate
  states.
- **Restraint**, checked on each of the 50 phones: at most one frosted surface,
  always inside the sky, and never a frosted card on a screen with a dial. Each
  phone has one sky at the top and no beams outside it. Backdrop blur appears
  only on the lit surface. No gradient buttons, avatars or Quiet cards, and no
  raster images. All pass.
- Every icon reference resolves. The app strings each screen must show are
  present on all 25 screens, and each dark phone's text matches its light twin.
  No banned words appear on any phone. The list is AGENTS.md's and COPY.md's,
  plus forfeit, lost, loser, streak, winner, won, winnings, charity, podium,
  medal, jackpot and "cash out". No chip or pill says "Didn't count".
- **54 interaction and policy checks pass.** Their names are in
  checks.json. They cover:
  - **Empty states:** one action on Home; no pot on empty dials; the three
    library filters.
  - **Refresh:** the saved number holds while refreshing; stale data clears on
    Refresh.
  - **Health:** Agree stays off without activity.
  - **Pot:** the lobby pot counts only people who agreed; $80 to $60 with
    three lanes; no hub after a void.
  - **Leave safely?:** Cancel below the destructive button, focus on Cancel,
    Escape.
  - **Results:** every amount above for both head counts, including $26.66
    and 2¢; roster order; the two-person void has no chips or pot hub.
  - **Review:** reason picking, the saved state, no free-text field.
  - **Formats:** timed lanes are yes or no; the leaderboard has no dial or
    trophies and lists unranked people last.
  - **AX5:** 53pt body, one column, dial above the number, 44pt targets.
  - **Appearance:** Light and Dark each show only their own phones.
- **Contrast** covers every visible text run, including SVG text: 1,166 runs
  in the default state and 1,170 in an alternate state. The alternate state has
  the empty filters, the finished refresh, sheets and the action sheet closed,
  and two-person results. For each run, phones are unrolled to full height with
  the text hidden, then the pixels behind its glyph box are read at 2× (5th
  percentile). The target is 4.5:1, or 3:1 for large text. **Zero misses.**
  The lowest normal text is 4.50 (inactive tab labels, unchanged from 9.3). The
  lowest large text is 4.32 (the AX5 date).
- **Unslop:** the phrase and structure scanners find nothing in this record
  or the README entry. On the page's visible text, with duplicate lines
  removed, the structure scanner finds nothing. The phrase scanner raises one
  soft flag: "No one reached their goal." followed by "No stakes come back."
  Those are two separate lines on the Everyone misses screen, the summary and
  COPY.md's agreed pot sentence, joined when the text was extracted.

Captures, all in [captures/](captures/):
[empty-states.png](captures/empty-states.png),
[health-and-sync.png](captures/health-and-sync.png),
[pot-shrinks.png](captures/pot-shrinks.png),
[results.png](captures/results.png) (3 or more),
[results-two-people.png](captures/results-two-people.png),
[detail-missed-unconfirmed.png](captures/detail-missed-unconfirmed.png),
[review-and-cancelled.png](captures/review-and-cancelled.png),
[formats.png](captures/formats.png),
[ax5.png](captures/ax5.png) (phones unrolled to full height) and
[width-390-dark.png](captures/width-390-dark.png).

Not performed: native SwiftUI, real Dynamic Type, VoiceOver, rendering on a
phone, or any device run. The action sheet is a drawing of the iOS dialog, not
the system one.

## Responsible engagement

Round 11 could affect staying in a challenge you want to leave, reading
results as winning or losing, and chasing a timed run.

- Leaving is one calm button and the system's own dialog. The screen says
  the stake comes back, and nobody is named when someone leaves or declines.
- Missing or unreadable data never reads as a miss: waiting markers, blue
  dashed cards, "Not confirmed", and a void when too few results remain.
- Results list people in roster order with plain amounts: no ranking, coins or
  celebration. "Goes to no one" is stated flatly.
- The leaderboard stays a later-build proposal with gray rank numbers and no
  trophies. The timed run shows met or not yet, and question 5 asks whether to
  drop the best time.
- There are no notifications, streaks, countdowns or analytics. Health
  permission is never requested from these screens.
