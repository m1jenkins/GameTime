# Floodlight 10: the P0 screens

September 27, 2026. [Open the prototype](index.html). **Proposed, not
adopted.** It puts the adopted 9.4 tokens (Aero Toned in light, Floodlit in
dark) on the screens a friends TestFlight needs first: create, the save
confirmation, Challenges, You and Friends. Earlier rounds and the native app
are unchanged. Every person, username and number is fictional.

The page has the 9.4 Appearance control (Light | Dark | Side by side, with
Side by side as the default). Two more toolbar controls compare options:
**Library filters** (as built, or the brief's Active · Upcoming · Finished)
and **Friends list** (spheres or rows). Light and dark copies of a screen
share one state, so taps in one show up in the other.

## Rules applied on every screen (from 9.1)

- Sky (light) or beams (dark) sit only behind the hero, then fade to the
  ground.
- One lit surface per screen, named in each screen's note. Everything else
  is a Quiet card. Sheets have no lit surface.
- Avatars and buttons are flat. The dial, arcs and pot keep Toned depth.
- Icons are stand-ins named after the SF Symbol each native view uses
  (`figure.run`, `shoeprints.fill`, `person.badge.plus`, `hand.raised` and
  so on). Every `<use>` resolves to one of them.
- Copy comes from the Swift sources. Where round 10 shows something the app
  doesn't have, the screen note says **New**.

## One new token

| Token | Paints | Light | Dark | SwiftUI |
| --- | --- | --- | --- | --- |
| `--gt-link` | Text links such as Edit and Edit goal and dates | `#0F63B6` | `#BFEBFF` | `Link` |

Light Accent (`#0E86E0`) is 3.9:1 on white, too low for link text, so light
links reuse the Button blue. The other 74 tokens are 9.4's, unchanged.

## Screens

### Create with friends: Goal

Source: `ChallengeCreationViews.swift` `activityStep`, `SignalActivityChoices`
in `SignalCreationControls.swift`, and `SignalCreationDateCard` in
`SignalCreationDates.swift`. Lit surface: the activity card.

- Four chips as the app offers them to friends: Steps, Activity minutes,
  Running distance, Timed run. Steps is selected first, as in the app.
- Timed run adds the app's **Whole run** entry, with the number in Barlow
  Condensed at 76pt. The captures show Timed run selected so the entry is
  visible.
- Other activities show "Everyone chooses their goal in the lobby." next to
  you and two dashed seats.
- Dates without steppers: tap **Starts** or **Ends**, then a day on a
  three-week calendar. Moving the start keeps the length. Days before the
  earliest start (today + 2) are disabled, and the range caps at 30 days.
  The app's editor sheet with its circle plus and minus buttons isn't used.

Open: the app edits the time zone in the dates sheet. Round 10 only shows it
("2026 · Pacific Time"). Where should changing it live? The day cells are
40pt tall, a little short of 44.

### Create with friends: Challenge

Source: `ChallengeCreationViews.swift` `reviewStep`, friend mode. Lit surface:
stake and pot.

- One amount, set by you: **$20**, "each · Fee $0", **Edit**. The caption is
  the app's "No real money moves. Nothing can be paid out or redeemed."
- **New:** a pot preview. The pot holds only your $20, you sit in the first
  seat, and five dashed seats wait. Caption: "Just you so far". The app has
  no pot on this step.
- The goal summary and the app's **Private challenge** row follow. The four
  9.4 outcome cards use the group wording, since the roster isn't known yet.
  Three icon facts and **Full challenge rules** come after, then
  **Continue to invite**.
- **Consent row.** The app has no agree switch in friend creation, because
  everyone agrees in the lobby. Round 10 keeps that and lets **Private
  challenge** ("…Everyone reviews the roster and rules before agreeing.")
  stand in for the consent row. Adding a switch for the creator would change
  behavior.

Open: add a creator consent switch here, or keep agreement in the lobby?
Should the pot preview grow as friends are picked, or stay at "Just you so
far" until someone agrees?

### Create with friends: Friends, and No friends yet

Source: `ChallengeCreationInviteView.swift`. Lit surface: Your lobby.

- Friends are 54pt spheres you tap. Picked ones get a ring and a check, and
  the lobby card fills its seats ("2 of 5 chosen"). The button follows the
  app: **Invite 2 friends**, or **Skip for now** with nobody picked.
- **Add a friend by username** opens in place. It handles your own username
  with the app's "That's your username" message. There's no search, as in
  the app.
- Empty state: the app's **No friends yet** card, with the username field
  already open.

Open: should friends picked in this step also show as rows at larger text
sizes, like the Friends list option?

### Personal goal: Goal and Rules

Source: `ChallengeCreationViews.swift` in personal mode and
`SignalCreationGoalEntry`. Lit surfaces: the goal card, then the dial.

- **Outdoor runs | Steps** pills, as the private trial allows. The goal
  number is the biggest thing on the screen. "Over 7 days" and "Apple Watch"
  sit below it.
- Rules: a one-person dial with your goal in the middle and **no pot**. Three
  outcome cards: **You reach it** · "Stake back"; **You miss it** · "No one
  collects it"; **Couldn't confirm** · "Stake back, not a miss" (9.4's blue
  dashed card). They follow the app's rule: "Meet your goal and your
  simulated entry returns. A confirmed miss leaves it unallocated. Missing or
  unclear activity never proves a miss."
- The app's agree switch, "I have read the complete rules and agree",
  enables **Create personal goal**. The personal-and-saved capture shows it
  on.

Open: "You reach it", "You miss it" and "No one collects it" are new short
strings. They aren't in COPY.md yet; add them with UI-test assertions if
adopted. The app's Apple Health readiness block and the optional "Put money
on it" section are left out of this mock.

### Challenge locked in

Source: `ChallengeCreationSuccess.swift`. Lit surface: the goal dial.

A flat check, **Challenge locked in.**, "October runs · Oct 1–7" and one
short line, "$20 simulated · fee $0". A small dial shows the goal. **Go to
Home** is the one blue button, **View goal** is gray text, and one X closes.
No coins, confetti or rules recap, per COPY.md.

Open: a friend lobby's save says **Challenge saved.** with three steps. Round
10 doesn't mock it.

### Challenges

Source: `LiveLibraryView` and `LiveLibraryCard` in `LiveChallengeShell.swift`.
Lit surface: the active challenge, when it leads the list.

- **As built** the filters are **All · Invited (1) · Finished**. Active,
  Upcoming and Finished are sections, and the Invited section becomes **Needs
  your attention** when it holds a row in review. The brief asked for Active ·
  Upcoming · Finished filters, so the toolbar switches to that; Needs your
  attention then stays on top under every filter.
- Every card has a mini dial (people's arcs) or a pot. The invitation card
  shows "20 km each" and "From jordan.b", then **Accept** and **Decline**.
  Decline opens the app's "Decline this invitation?" sheet.
- Mini dials drop the "POT" caption. At card size it rendered at about 4px.

Open: which filters should ship, the app's or the brief's? Should the
"Decline invitation" confirm stay red as in the app, or go calm like Block?

### You

Source: `LiveRecordView.swift`. Lit surface: Your record.

- The Settings gear sits next to the title. Friends is the first row, with
  four faces. The app shows no faces there today.
- Your record: 7 goals met and 9 challenges finished, and one pip per
  finished challenge.
- Each finished challenge is a ring and a card. **Result unavailable** uses
  the 9.4 "couldn't confirm" look: blue dashed ring, "?", pale blue card and
  "It doesn't count against you." A miss is a slate ring with the app's
  **Missed** chip. The app styles Missed as a warning; round 10 keeps it
  slate.

Open: which chip should a missing score show? The app shows whatever the
outcome is. Round 10 uses **Didn't count**.

### Friends, Add by username, Report or block

Source: `FriendsViews.swift`. Lit surface on Friends: Requests for you. The
two sheets have none.

- Friends as spheres, or rows from the toolbar. Requests you sent, **Add a
  friend**, **Blocked people** and "Only you see your friends list." follow.
- The add sheet: the exact-username field, **Find**, then **Send request**,
  and your own username ready to copy or share. Unknown names get the app's
  "We couldn't find @… Usernames need to match exactly" message.
- Friend actions: **Remove friend**, **Block** and **Report** as plain rows,
  with no red. Report asks one question (the app's three reasons) and keeps
  **Send report** disabled until you pick one. Then **Thanks for telling us**
  offers **Block Jordan**. The confirm text for Block and Remove is the app's.

Open: the app's Block alert is a system alert. Round 10 puts it in the same
sheet to keep it calm. Is that acceptable?

## Checks performed

Chromium 153 through Playwright 1.63, reduced motion. Full results are in
[checks.json](captures/checks.json).

- No console errors or warnings. No horizontal page overflow at 1440px (Side
  by side with light and dark system settings, `#light`, `#dark`) or at 390px
  (light and dark system).
- No element sticks out of any phone, and no content scrolls sideways, in any
  of those six views. Larger text (1.3×) in light and dark finds none either.
- Restraint, per phone: at most one lit surface, always inside the sky; one
  sky, at the top; backdrop blur only on the lit surface; no gradient buttons
  or avatars. All 26 phones pass.
- Every icon reference resolves. Required app strings are present on all 13
  screens, and each dark phone's text matches its light twin. No banned
  words (from AGENTS.md and COPY.md, plus forfeit, lost, rank, streak and
  winnings) appear on any default screen.
- 27 interactions pass: activity chips, the Timed run entry, picking start
  and end days, the disabled early days, no steppers, Goal → Challenge,
  picking 4 then 0 friends, your own username, the agree switch enabling
  Create, the Steps pill updating the Rules dial, sheet focus, inert and
  Escape, the Invited filter, Decline, the brief filters, friend rows, the
  report flow, Find and Send request. Side by side stays in step.
- Contrast: every visible text run, including SVG text and inputs, in a
  default state (840 runs) and an alternate state (782 runs). Text is hidden,
  the phone is unrolled to full height, and each run is measured against
  the pixels behind its glyph box (5th percentile). The target is 4.5:1, or
  3:1 for large text. All runs pass except the "$" on the 7px pictogram
  coins in dark (2.94–3.13). At 4× the glyph reads dark on a light coin; the
  low value comes from the coin's rim inside a tiny sample box. It's the same
  drawing as 9.4, it's hidden from VoiceOver, and the card text says the
  outcome. The lowest real text is 4.50 (inactive tab labels, as in 9.3).
- Unslop: the phrase and structure scanners find nothing in the page's
  visible text, this record or the README entry.

Captures: [create-light.png](captures/create-light.png),
[create-dark.png](captures/create-dark.png),
[personal-and-saved.png](captures/personal-and-saved.png),
[library.png](captures/library.png),
[you-and-friends.png](captures/you-and-friends.png) (Light row over Dark
row) and [side-by-side-overview.png](captures/side-by-side-overview.png).

Not performed: native SwiftUI, VoiceOver, Dynamic Type, rendering on a phone,
and any device run.

## Responsible engagement

What this could increase: creating friend challenges, and attention to the
pot while creating one. Controls: the pot preview shows only your own stake
and never projects winnings. The save screen has no money celebration. A
missing result never looks like a loss. Block and Report stay one tap from
every friend, and nobody is told. There are no rankings, streaks, countdowns,
notifications or analytics. The simulated-stakes line appears where amounts
are set.
