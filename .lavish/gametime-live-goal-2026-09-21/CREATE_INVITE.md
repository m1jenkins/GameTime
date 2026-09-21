# Create challenge + invite friends

Design-only continuation of the owner's locked September 21 Home, Goal/Rules,
Challenges and You mocks. No native app, backend, existing agreement, or locked
reference file was changed.

## Review and deliverables

- `create-invite.html`: interactive four-screen board with four token-reuse annotations.
- `create-phone.html`: standalone, three-step walkthrough; optional `?screen=goal`,
  `challenge`, `invite`, or `confirm` selects a filled example.
- `gametime-create-invite.html`: portable board export.
- `captures/create-goal.png`: activity, large target input, visual date range.
- `captures/create-challenge.png`: optional name, private setting, three verdict cards,
  editable optional simulated stake, Full rules.
- `captures/invite-friends.png`: selected portraits, contact rows, search, secondary
  Copy/Share, bounded selection and invitation action.
- `captures/create-confirm.png`: target summary, quiet stake, explicitly pending friends.
- `captures/invite-contacts.png`: voluntary Contacts permission explanation.
- `captures/create-invite-board.png`: annotated four-screen overview.
- `captures/create-invite-checks.json`: actual browser check results.

Phone PNGs are 780 × 1688 pixels (390 × 844 CSS pixels, 2×). Screens remain
scrollable at smaller sizes; the primary action stays outside the scrolling body.

## Design source

Source 1: the user's explicitly locked visual system and captures. New pages load
unchanged `design.css`, reuse `assets/friends.png`, and copy the original status
symbols and thin app icons. `create-invite.css` applies only to the new pages.

Background #FAFBFC, surface #F0F2F5, text #111318, accent #245BFF, warning #9A6700.
System sans; heavy tight italic metrics and secondary units; 24 px metric cards;
Goal's restrained frosted agreement modules; filled accent primary and quiet
secondary actions. The creation flow is a full-screen presentation with close/back;
the main Home · Challenges · You navigation remains in the unchanged app references.

## Behavior and fixture assumptions

The fresh walkthrough starts at 20 km over Sep 28–Oct 4, 2026, Pacific Time, with
No stake and no selected friends. Independent later-step examples show an expressly
chosen $20 simulated stake and Sam, Jordan and Priya selected. This is a new outgoing
fictional example called October runs; it does not edit the existing incoming
October runs invitation shown in the library reference.

Activity and target, date range (1–30 days), name, optional stake, selected friends,
and search work locally. Back preserves choices. Full rules, dates, stake and
Contacts use sheets with inert backgrounds, keyboard focus trapping, Escape, and
focus return. Empty search and empty selection have a next action. No contact
permission is actually requested. The three names and reused photos are fictional.
The example has three available contacts and a stated five-friend bound, not a
network directory. Broader contact loading and capacity admission are unimplemented.

The target field and dates are presentation inputs, not approved target limits or
admission rules. No stake is this proposed flow's default. The $10/$20 examples are
illustrative choices, not adopted amount policy. Steps demonstrates a second activity
and units; detailed Steps source acceptance still needs its own applicable policy.
The fully worked agreement uses Apple Watch outdoor runs and preserves the locked
Goal's source exclusions, whole-run boundary, midnight dates, 24/48-hour upload and
correction windows, two-result minimum, missing-data protection, 48-hour review,
72-hour resolution, safe exit and explicit sharing/changed-agreement consent.

Creating the example and sending invites are local visual transitions. Friends stay
Invited; selection, sending, opening a link and viewing a preview do not mean a
friend agreed. Final roster/individual-goal acceptance is beyond this creation-only
study. View challenge opens an explicitly labeled reference to the unchanged Goal
screen. Back to Challenges displays the unchanged library capture. Neither action
pretends to persist this draft in the real app.

Copy and Share open preview explanations. Copy can copy a clearly labeled `.invalid`
sample link; it cannot join anything. Share sends no message. There are no network
requests, account writes, Health queries, notifications, analytics or payment actions.

Optional personal-only simulated consequences follow this brief and the locked
mock's proposal. They require a new agreement version and do not reinterpret D134
allocation or historical Personal/Solo/charity contracts. No friend receives another
friend's stake, no pool exists, and nothing can be paid out or redeemed. No real money
moves. New profile photos, contact access, sharing consent and related controls remain
design proposals. This study does not change native Signal adoption.

## Responsible engagement

The flow supports deliberate, private goal creation. It does not increase stakes
automatically, reward spending, suggest loss recovery, demand daily activity, or
imply that missing activity means a loss. No stake is easy to choose; invitations
still require each person's review. Contacts and sharing are person-initiated.
The confirmation uses one quiet check and the athletic target, without confetti.

## Verification — performed

- Visually inspected all four main screenshots, the Contacts sheet and review board.
- At 390 × 844 every main screen's content fits without scrolling; no horizontal
  overflow. At 320 × 710 all four retain equal content/client widths, with vertical
  scrolling where needed. Every visible app button is at least 44 CSS px high.
- Walked through edited target, dates, name and stake into confirmation. Those values
  and the selected two-friend set persisted correctly. No stake was the fresh default.
- Zero target and invalid date range showed actionable errors. Zero selected friends
  disabled sending. Friend search, no-results copy and live selection counts worked.
- Full rules contained eight sections. Escape restored its trigger. Opening a second
  Contacts sheet retained focus return to the original Contacts action.
- A six-digit target did not cause horizontal overflow; switching to Steps changed
  the target/unit and agreement source copy.
- Responsive board rendered four populated phones at desktop width and stacked them
  without horizontal overflow at 390 px. No browser page errors occurred.
- Portable export embeds the CSS, script, portrait atlas and unchanged destination-reference images; a local follow-up embeds notes and routes the walkthrough link to its first interactive phone. Lavish export reported no unresolved assets or notices.
- JavaScript syntax and whitespace checks passed. Prior mock source/captures were
  untouched. No unrelated native, database or integration suites were warranted.

The preferred Chrome wrapper could not start its bridge. Local headless Chrome via
the already installed Playwright runtime performed captures and interaction checks
outside the filesystem sandbox. This is browser verification, not native acceptance.

Native Liquid Glass, iPhone keyboard/gesture behavior, Dynamic Type, VoiceOver,
physical Health data, actual Contacts permissions, invitation delivery, final consent
and agreement persistence are unperformed and outside this design task.
