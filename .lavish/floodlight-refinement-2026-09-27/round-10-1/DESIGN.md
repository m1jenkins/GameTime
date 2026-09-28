# Floodlight 10.1: round 10 with the owner's fixes

September 27, 2026. [Open the prototype](index.html). **Proposed, not
adopted.** This is round 10 with the fixes and answers the owner approved on
September 27. Round 10, round 9.4 and earlier rounds are unchanged, except that
the round 9.3 page header now says "Adopted". Nothing native changed. Every
person, username and number is fictional.

The page keeps the Appearance control (Light | Dark | Side by side), the
Friends list control (spheres or rows) and Larger text. The Library filters
switch is gone. The 9.1 restraint rules, the 9.4 tokens and `--gt-link` carry
over unchanged, and 10.1 adds no tokens.

## Fixes

### 1. Create > Goal no longer leads with a distance

Source: `ChallengeCreationViews.swift` `activityStep`, `SignalCreationDates.swift`.

- The Goal screen and its capture now start on **Running distance**. Friends
  choose their goals in the lobby, so the lit card shows the chips and "Everyone
  chooses their goal in the lobby." There's no number, and "kilometres" doesn't
  appear.
- **Timed run** has its own phone, **Goal · Timed run**, and reads as a time
  target. A **Time target** label sits over a gray "MM:SS" in Barlow at 40pt,
  beside the app's "Everyone chooses their goal in the lobby." The creator's
  **Whole run** distance is a small row below it, with a 24pt number. The
  round 10 hero, "5 kilometres" at 76pt, is gone. **New:** the "Time target"
  label and the "MM:SS" placeholder.
- The calendar is folded by default. Tap **Starts** or **Ends** to open it.
  Picking a start moves you to the end, and picking the end folds it again.
  Tapping the open button a second time also folds it.

### 2. Only the live card has a dial

Source: `LiveChallengeShell.swift` `LiveLibraryCard`.

- The active challenge keeps its mini dial and pot. The invitation, the card
  in review and the upcoming cards show only their number and people.
- Finished cards get a flat result ring: a track and your arc in one solid
  color, with no plate, glow or gloss. Your number sits inside ("22.4 KM",
  "71.3K STEPS") and "Your goal: …" sits beside it.

### 3. Needs your attention is at the very top

Under **All**, the order is Needs your attention, then **Active** (the live
card), then Upcoming, then Finished. The live card is still the screen's one
lit surface, so the sky now reaches down to include the attention cards and
the live card.

### 4. The coin "$" is gone

The 7px "$" on the pictogram coins measured 2.94–3.13 in dark, so it's removed.
A thin inner rim at 38% of the coin ink marks each coin instead. The "?" badge
on "Couldn't confirm" grew from a 5.6 to a 6.8 radius. Its 7.4px "?" had been
picking up the card at the rim (3.62 at the 5th percentile on one phone), and
now passes. The contrast sweep has zero misses (see Checks).

## Answers applied

- **Library filters:** the app's **All · Invited (1) · Finished**, with Active
  and Upcoming as section headings. The toolbar switch to the brief's filters
  is removed.
- **No creator agree switch.** The Challenge step keeps **Private challenge**
  ("…Everyone reviews the roster and rules before agreeing."). Agreement stays
  in the lobby.
- **Pot seats fill only on agreement.** The Challenge step's pot still says
  "Just you so far". On the Friends step, **Your lobby** is now a pot holding
  only your $20. Each picked friend sits in a dashed seat with a small avatar
  in their color, and open seats keep the plus. The text beside it says "$20 in
  the pot" and "Sam and Jordan are invited. A seat fills when that friend
  agrees." **New:** both lines. That pot drops its "POT" caption, which measured
  4.46 at this size, because the text beside it names the pot.
- **Time zone:** a small row inside the dates card: globe, "Time zone",
  **Pacific Time** and a chevron. It's 44pt tall. It opens a Time zone sheet
  listing zones the way `SignalTimeZone.name` writes them ("Eastern Time · New
  York"). Calendar day cells are now 44pt tall and at least 44pt wide.
  **New:** the sheet's line "Each day runs midnight to midnight in this time
  zone.", adapted from the app's dates editor.
- **Accessibility text sizes:** a **Friends · larger text** phone shows picked
  friends as rows (avatar, full name, username, a round check). The Larger text
  checkbox switches the regular Friends phone to rows too. At that size the
  lobby pot sits above its text.
- **Personal strings in COPY.md:** "You reach it" · "Stake back", "You miss it"
  · "No one collects it", "Couldn't confirm" · "Stake back, not a miss", and the
  **Not confirmed** chip were added as rows at the end of the Floodlight table.
  The glossary row for inconclusive and waived now points to the chip. No other
  COPY.md line changed.
- **Apple Health readiness** (`ChallengeHealthStatusView`, `readiness: true`)
  sits above the agree switch on the personal Rules screen. It starts at
  **Connect Apple Health**, with the app's explanation and button. Tapping it
  shows **Activity found**, the app's sentence and **Refresh activity check**.
  As in the app, **Create personal goal** needs both the agree switch and a
  ready check. One difference: the app draws that button in the primary style.
  Here it's a neutral button, so the screen keeps one blue action.
- **Put money on it** (`ChallengeCommitmentSection`, D144) is a switch at the
  top of the Rules panel. It's off on the Rules phone and on in **Rules · Put
  money on it**. When it's on, the card shows "Payment test mode — no real
  money moves.", "Add your test payment method before you start." and **Add
  test payment method**. After that it shows "Test method saved. No test charge
  exists." The amount row becomes **Test commitment** · "$20.00 · charged only
  if you miss". The caption becomes the payment test banner, the full rules
  switch to the commitment sentence, and the consent sentence appears above
  the agree switch once a method is saved. Create also needs the saved method.
  **New:** the commitment short lines on the outcome cards, "$0 test charge",
  "$20 test charge" and "Not a miss, no charge". They come from the app's
  "Meet your goal: $0 test charge…" sentence but aren't in COPY.md (see open
  questions).
- **Challenge saved.** A new **Challenge saved** phone follows
  `ChallengeCreationSuccess.swift` for an open lobby. It has an envelope mark,
  "Challenge saved.", "September runs · Sep 29–Oct 5" and "$20 simulated · fee
  $0". The lit **Invited** card says "Nobody has agreed yet" and shows each
  friend's username and "Invited" in a pending dashed seat. Three steps follow:
  "You invited 2 friends", "You pick the roster", and "Everyone agrees before
  Sep 29", with the app's details. Then **Go to Home** and a quiet **View
  challenge**. **Invite 2 friends** on the Friends step opens this screen.
- **Decline this invitation?** is calm. **Decline invitation** is a neutral
  gray button with ink text, not red and not blue. **Keep invitation** stays
  the quiet way out.
- **Not confirmed:** the You chip for a missing score now reads **Not
  confirmed**, in the blue dashed style, with "It doesn't count against you."
- **The Block confirm is the system alert.** Block and Remove friend now
  present a stand-in for `FriendConfirmation`'s `.alert`, in light and dark. It
  is 270pt wide with a 14pt radius, a 17pt semibold title, a 13pt message, and
  **Cancel** (bold, left) and **Block** (destructive, right) in a split row. The
  friend sheet stays underneath. Escape or Cancel returns to it. A separate
  **Block alert** phone shows it. The text colors are Apple's Increase Contrast
  system blue and red (`#0040DD`/`#D70015` light, `#409CFF`/`#FF6961` dark).
  The default system blue and red measure about 3.0–3.4:1 on the alert
  background. We don't control those colors, because iOS draws the real alert.

## Screens added

Goal · Timed run, Friends · larger text, Challenge saved, Rules · Put money on
it, and Block alert. That makes 18 screens and 36 phones.

## Open questions

1. The commitment short lines on the personal outcome cards ("$0 test charge",
   "$20 test charge", "Not a miss, no charge") need COPY.md rows if adopted.
   They also keep the stake-back pictograms. Should a committed goal get its
   own pictograms?
2. Is "Time target" over "MM:SS" the right label for the timed hero, or should
   it name the rule ("Finish under your goal time")?
3. The lobby pot lines ("$20 in the pot", "A seat fills when that friend
   agrees.") need COPY.md rows if adopted. Should the pot also appear on the
   invitee's side before they agree?
4. The Apple Health button is neutral here and primary in the app. Keep one
   blue action per screen, or match the app?
5. `ChallengeCreationSuccess` still shows "$20 simulated · fee $0" for a goal
   with money on it. That's the app's current behavior, and the mock follows
   it. Should the saved screen say "$20 test charge only if you miss." instead?

## Checks performed

Chromium 153 through Playwright 1.63 from the global npx cache, with reduced
motion. Full results are in [checks.json](captures/checks.json).

- No console errors or warnings. No horizontal page overflow at 1440px (Side by
  side with light and dark system settings, `#light`, `#dark`) or at 390px
  (light and dark system).
- No element sticks out of any phone, and no content or sheet scrolls sideways,
  in any of those six views. Larger text (1.3×) finds none in light or dark.
- Restraint, per phone: at most one lit surface, always inside the sky; one
  sky, at the top; backdrop blur only on the lit surface; no gradient buttons
  or avatars. All 36 phones pass. The system alert stand-in uses no blur.
- Every icon reference resolves. Required app strings are present on all 18
  screens, and each dark phone's text matches its light twin. No banned words
  appear on any default screen. The list is AGENTS.md and COPY.md's, plus
  forfeit, lost, rank, streak, winnings, charity and "Didn't count".
- 61 interaction checks pass, and two more record the library's section
  headings and filter labels. They cover:
  - **Create:** Running distance by default with no kilometres; Timed run as
    a time target; the calendar folded, then unfolded by Starts; 44pt days;
    disabled early days; moving the start keeps the length; picking the end
    folds the calendar; no steppers; the 44pt time zone row and its sheet
    carrying through to Challenge.
  - **Friends and save:** pending seats in the lobby pot; picking 4, then 0
    friends; rows at larger text; Invite 2 friends opening Challenge saved.
  - **Personal:** Create stays off until agree and Apple Health are both done;
    Put money on it needs a saved method.
  - **Library:** attention above the live card; one mini dial; flat finished
    rings; filters as built; the calm Decline confirm.
  - **You and Friends:** Not confirmed; the report flow; the Block and Remove
    alerts, with Cancel on the left, focus on Cancel, and Escape; Find and Send
    request.
  - **Everywhere:** side by side stays in step.
- Contrast covers every visible text run, including SVG text and inputs, in a
  default state (998 runs) and an alternate state (840 runs). The toolbar is
  unstuck, each phone is unrolled to full height, and text is hidden. Each run
  is then measured against the pixels behind its glyph box at 2× (5th
  percentile). The target is 4.5:1, or 3:1 for large text. Text under an open
  sheet or alert is skipped, and so is disabled text. **Zero misses in both
  states.** The lowest normal text is 4.50 (inactive tab labels, as in 9.3).
- Unslop: the phrase and structure scanners find nothing in this record or the
  README entry. On the page's visible text, the phrase scanner finds nothing.
  The structure scanner raises one soft "opener repetition" flag on the raw
  text, because every phone appears twice (light and dark). With duplicate
  lines removed, it finds nothing.

Captures: [create-light.png](captures/create-light.png),
[create-dark.png](captures/create-dark.png),
[personal-and-saved.png](captures/personal-and-saved.png) (Rules scrolled to
Apple Health and the agree switch, both on; Put money on it scrolled to its
card), [library.png](captures/library.png),
[you-and-friends.png](captures/you-and-friends.png),
[side-by-side-overview.png](captures/side-by-side-overview.png),
[lobby-saved.png](captures/lobby-saved.png) and
[block-alert.png](captures/block-alert.png).

Not performed: native SwiftUI, VoiceOver, Dynamic Type, rendering on a phone,
and any device run. The alert is a drawing of the iOS alert, not the system
one.

## Responsible engagement

What this could increase: creating friend challenges, and putting money on a
personal goal. Controls:

- The pot counts only money from people who agreed. Invited friends never
  appear as filled seats.
- Put money on it is off by default. It sits behind a test banner and a saved
  method, and it states "charged only if you miss".
- Missing data never reads as a loss. The chip says "Not confirmed" and the
  card says "It doesn't count against you."
- Declining an invitation is calm. Block and Remove keep the app's plain
  system alert, and nobody is told.
- There are no rankings, streaks, countdowns, notifications or analytics.
