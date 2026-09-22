# Friends TestFlight: Phase 1 mocks

September 22, 2026. These are the Phase 1 mocks from the
[friends TestFlight plan](../../docs/FRIENDS_TESTFLIGHT_PLAN.md), under
[D142](../../DECISIONS.md#d142-first-private-testflight-adds-friends-opens-apple-sign-up-and-ships-goals-first).
It is a browser design study for owner approval before Phase 3 native work. It
changes no native app, backend, agreement or hosted state.

Open `index.html` for the board, or with `lavish-axi` to annotate it.
`phone.html?screen=<name>` opens one phone at full size, and `&large=1` enlarges
the text. Serve the directory over HTTP (for example
`python3 -m http.server`) so the stylesheet and script load.

## What is mocked

| Area | Screens (`?screen=`) |
| --- | --- |
| 01 You › Friends | `you`, `friends`, `friends-empty`, `friends-loading`, `friends-offline` |
| 02 Add a friend | `add`, `add-incoming`, `share` |
| 03 Safety | `friend-sheet`, `block-confirm`, `report`, `blocked` |
| 04 Home action rows | `home`, `home-quiet` |
| 05 Invite step | `invite`, `invite-empty` |
| 06 Onboarding | `onboard-age`, `onboard-profile` |
| 07 After a friend challenge saves | `lobby-saved` |

Each phone PNG in `captures/` is 780 × 1688 pixels (390 × 844 CSS at 2×),
taken with headless Chrome using `&capture=1`. `captures/board.png` is the top
of the board at 1480 pixels wide.

## Design source

The locked September 22 native system in `SignalTheme`, `SignalCreationTheme`
and `LiveDesignComponents`: canvas `#FAFBFC`, surface `#F0F2F5`, text
`#111318`, accent `#245BFF` and warning `#9A6700`, in the system sans. The
native captures in `../gametime-native-live-2026-09-22/captures/` set the
Home, You and create-flow proportions. Avatars use initials, as native renders
them, because profile photos remain deferred.

## Decisions the mocks propose

- **Friends is one row under your profile on You.** It shows no count or badge.
  Friends lists requests for you first, then friends, then requests you sent.
  Add a friend and Blocked people come last.
- **Add a friend takes an exact username**, with Find and no
  search-as-you-type. Your own username has Copy and Share. Share hands the
  system sheet one plain sentence, "I'm @alexlee on GameTime. Add me as a
  friend.", with no link.
- **Lookup results:**
  - found: Send request
  - already friends: a note
  - request already sent: points to Cancel
  - they already asked you: `incoming_request_exists` with inline Accept and
    Decline
  - daily cap and lookup rate limit: the COPY.md sentences
  - not found: a spelling hint
  Blocked people in either direction get the same "not found" answer.
- **Tapping a friend shows three actions: Remove friend, Block and Report.**
  Each confirmation says what changes:
  - Remove leaves challenges you already share alone. That matches the server:
    friendship is checked only at invite time.
  - Block leaves both of you out of any unfinished shared challenge, and a
    challenge with fewer than two people left won't count. That is
    `app.challenge_tick_v1` today, which Phase 2 keeps.
  - Unblock doesn't restore the friendship.
  Report takes one of four proposed reasons and an optional note, then says
  "We'll look into it. You can also block them."
- **Home action rows form one compact group above the hero**, most urgent
  first:
  1. awaiting agreement, with "Before Oct 5, 12:00 AM", the challenge start
  2. an incoming request, with Accept and Decline
  3. an invitation, with Review
  4. an accepted request, with dismiss
  At most three show, then "Show 1 more". A row leaves once handled. There are
  no counts, badges or countdowns.
- **The invite step lists accepted friends as checkable rows**, up to five
  ("3 of 5 chosen"). An inline "Add a friend by username" sends a request
  without leaving the step. With no friends, the step says the challenge is
  already saved, and the footer reads "Skip for now". Contacts and links are
  gone.
- **Onboarding asks first**, on "Before you start": the Apple Watch
  requirement (the COPY.md glossary sentence), a simulated-stakes line and the
  existing "I confirm I am 21 or older" toggle. Only then comes "Your profile",
  which keeps today's field rules and adds one sentence: friends need your
  username to send you a request. Nobody under 21 gives us a name or username.
  "I'm under 21" explains and offers Sign out.
- **"Challenge saved." replaces "Challenge locked in."** for an open friend
  lobby. It lists who was invited and says nobody has agreed yet. Then it
  shows three factual steps:
  1. you invited them
  2. you pick the roster from those who accept
  3. everyone agrees before the start, or it's cancelled and nothing counts
  That last step matches `consent_pending` cancellation at `starts_at`.
  Personal goals keep "Challenge locked in."

## Boundaries

- Fictional people and dates only (snapshot Tuesday, September 22, 9:41 AM).
  Buttons change local state. The mocks make no network request and store
  nothing. There are no notifications, analytics or payment actions.
- Report reasons, the Home row order, the three-row limit and the onboarding
  order are proposals awaiting approval.
- **The owner still has to decide the re-request rule after a decline.** Until
  then a declined person can be sent the same request again, up to the daily
  cap. No mock implies a cooldown.
- Native Dynamic Type, VoiceOver and physical rendering are not demonstrated.
  `&large=1` is a browser approximation.
