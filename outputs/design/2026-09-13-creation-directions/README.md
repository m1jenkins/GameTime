# GameTime redesign exploration — September 13, 2026

Status: proposed design directions, not an owner selection or native implementation. The owner opened the full visual and interaction design for reconsideration, starting with challenge creation. Cobalt is the current implemented interface, not a constraint on these concepts.

Follow-up: the owner selected **Fieldwork for continued ideation** and requested Liquid Glass and a richer challenge page. [The second exploration](FIELDWORK_GLASS.md) records that preference and the new proposal. The status above describes the original three-direction comparison; the follow-up is not approval of a complete native redesign.

## Recommendation: Fieldwork

Make GameTime feel like an inviting sports club with the information discipline of a well-designed score sheet. Strong typography, warm chalk, deep green, a restrained citrus accent, and deliberate rules between sections provide character across creation, progress and results. People and athletic activity lead; consequential decisions stay calm and explicit.

Three principles govern the proposal:

- Each screen answers one clear question and offers one clear next step.
- Show the challenge taking shape as readable content, with plain labels and a reviewable summary.
- Carry the same type hierarchy, status language and metric treatment from the draft through the active challenge and result.

Avoid an endless settings form, a card around every fact, and casino-like treatment of simulation. The goal is better comprehension and voluntary participation, not faster or more frequent commitments.

## What is wrong with creation today

The source review used `ChallengeV1EntryViews.swift` at local main `ae5aa5d`, together with saved Cobalt native screenshots. A fresh Simulator run was unavailable because the local CoreSimulator service connection failed. The saved images are historical render evidence, not screenshots of a new build.

| Priority | Observed issue | Consequence | Proposed correction |
| --- | --- | --- | --- |
| High | Mode, activity and format render as separated blue picker values, with little persistent label context | They resemble text links; the relationship between the three decisions is unclear | Dedicated choice stages, persistent question labels, short descriptions, visible selection marks |
| High | Dates, timezone, duration, amount and explanations share a continuous column | People must parse the entire form to understand the challenge | People → activity → format or goal → schedule → draft review |
| High | Friend creation ends with “Create lobby” without a strong preview of the resulting experience | The user may confuse making a draft with inviting people, obtaining agreement or starting a challenge | Preview the challenge and show the next lifecycle step explicitly |
| Medium | Duration and amount use detached stock steppers; timezone is an editable `America/Chicago` string | Values are cumbersome to enter and scheduling exposes an internal representation | Labeled inputs, optional duration shortcuts, native date controls and searchable human-readable timezone selection |
| Medium | Creation shares little of the branded metric/type hierarchy seen on Cobalt Home | It feels like a separate utility screen rather than the start of the same experience | One coherent visual language for choices, summaries, active progress and results |

## Mobbin references inspected

These are interpretations of visible screenshots. The flow tool supplied evenly spaced previews, not an inspection of every screen or a usability study. Competitor assets and signature layouts are not copied into the concepts.

| Reference | Observed strength | Transfer to GameTime | Boundary |
| --- | --- | --- | --- |
| [Runna goal selection](https://mobbin.com/screens/b37d1bdf-41a6-43c8-9b4d-ac803f9e693a) | Prominent target value, grouped units and choices, strong bottom action | Make the chosen activity and target the visual subject | No imported training recommendation or unearned personalized goal |
| [Equinox+ goal selection](https://mobbin.com/screens/31fc4dba-04c3-4bcf-8345-3a908db86e08) | One question, visible progress, clear option boundaries | Separate decisions instead of presenting a database-shaped form | Avoid its density and small low-contrast unselected labels |
| [Tempo challenge flow](https://mobbin.com/flows/58435743-d608-46a5-a510-c23f4b1a05cf) | Duration choices and a calendar form a focused scheduling step | Give schedule its own composition and plain date summary | GameTime's permitted windows remain its own; no copied duration defaults |
| [Strava group-challenge flow](https://mobbin.com/flows/99c7f52e-f59c-417d-ac9f-6159061dd3eb) | Progressive setup and a visible progress indicator | Preserve a sense of position and easy backtracking | GameTime separates per-person goals from target-free leaderboards; Strava's optional target is not the same rule |
| [Nike Run Club club screen](https://mobbin.com/screens/a0a8a45f-dd2d-4efb-ab36-4816a4d44470) | Strong numerical hierarchy and aligned friend results | Let athletic metrics carry identity across the app | No public ranking, profile-photo scope or financial status hierarchy is imported |
| [Gentler Streak activities](https://mobbin.com/screens/81ddb60b-a773-448c-b64a-92cef5221268) | One progress story above secondary summaries and history | Support a calmer everyday movement direction | No readiness, recovery or medical inference from challenge activity |

## Three directions

### 01 — Fieldwork · recommended

Thesis: editorial sports-club character with clear, deliberate decisions.

Use warm chalk and deep green in light appearance, ink surfaces and a light green action in dark appearance. Narrow display typography contrasts with normal-width readable body text. Parallel rules, compact labels, large athletic numbers and small monograms become recurring signatures. Creation uses a featured friend choice and a quieter personal option; Home uses a single strong active-challenge composition with unboxed secondary progress.

Starting tokens: canvas `#F5F3EC`, text `#162837`, action `#193B31`, selection `#E7EBDF`, accent `#D9EF85`. These are proposed semantic roles, not adopted brand assets. The interactive concept uses Barlow Condensed for display and DM Sans for body as visual studies; native font selection, bundling and Dynamic Type remain an implementation decision.

Risk: narrow type can become a fashion treatment that compromises readability. Restrict it to short titles and major metrics; dates, explanations, controls and rules use a normal-width face.

### 02 — Pulse

Thesis: more intense, performance-oriented competition.

Large uppercase headings, a graphic “VS.” friend choice, larger numerical scale, violet selection surfaces and citrus progress emphasis. The dark variant gives it its strongest personality. Home resembles a focused performance board; the creation choice is more poster-like than Fieldwork's score-sheet structure.

Risk: it can read like esports or a betting product and make ordinary exercise feel too competitive. Personal goals and every amount/review/result state need a quieter treatment. Choose this only if that intensity is central to the desired brand.

### 03 — Daylight

Thesis: everyday movement with human warmth.

Serif display headings, centered introductory compositions, generous rounded choices, soft green and clay surfaces, and less emphasis on competitive rank. Home leads with movement and personal progress. The visual tone remains welcoming when data is unavailable or someone leaves.

Risk: the gentler character may understate GameTime's distinctive friend competition. It needs a strong, legible result system so warmth does not turn outcomes vague.

## Creation journey proposal

1. **People:** With friends or Just for me. Explain the difference before asking for parameters. Community remains a join flow, not a user-created product.
2. **Activity:** Steps, Exercise time, Running distance, or Timed run. Pair every label with one sentence about what counts. A shipped selector must reflect actual source availability.
3. **Format or goal:** Friends choose individual goals or a leaderboard. Personal users set their own target. Timed runs also need whole-run distance. Friend goal targets are proposed separately in the lobby by each person; a leaderboard never shows a target input.
4. **Schedule:** Native dates, a few editable duration shortcuts, and a human-readable timezone. Display the exact midnight boundaries on review. The concept's dates and duration shortcuts are examples, not new adopted defaults.
5. **Draft preview:** Activity, format, people, dates, relevant target/distance and explicitly simulated amount. Explain what happens next. Friends proceed to a lobby, individual target proposals where applicable, roster selection and separate agreement by everyone. Personal users proceed to their complete agreement and consent.

The clickable study stops at the draft preview. It does not create a server lobby, invite anyone, grant consent or schedule a goal. It does not replace the complete agreement. Back navigation preserves entered values within the current preview. Persistent draft recovery is a proposal requiring deliberate native implementation.

## Extend the system across the app

- **Home:** actionable review/consent notices take priority when present, followed by active progress and the next scheduled challenge. The pictured Home has no pending action, so the active challenge leads. A large metric must have its unit and update state beside it.
- **Challenges:** creation, invitations, community entry, active/upcoming challenges and history. Prioritize plain status grouping over a feed of interchangeable tiles.
- **Challenge detail:** stable title, exact window, own activity, comparable friend rows and current result state. A leaderboard uses absolute values; friend goals use each person's own target. Unknown results remain unknown and ties preserve co-winners.
- **You:** account, Apple Health readiness, sharing/privacy, safety, support and existing agreements. No financial or exercise-pressure engagement layer is added by this study.
- **Review and results:** quieter layouts with complete terms, exact amounts, fees, outcome/review/exit consequences, a specific action and a durable receipt. Athletic outcome and simulated allocation remain separate.

Home · Challenges · You is used to isolate the visual comparison against the current product jobs. The shell can be reconsidered in a later information-architecture pass; this exploration does not treat the current navigation as sacred.

## States and native acceptance still needed

Design loading, no-data, unavailable source, stale retained data, invalid input, admission-limit failure, interrupted save, declined invitation, incomplete agreement, tie, provisional result, review pending and safe exit. Do not erase an entered draft or last confirmed activity after a recoverable failure. Put the remedy beside the relevant decision.

Native implementation should retain system navigation/back gestures, accessible date/number entry and keyboard behavior. Brand expression belongs in content hierarchy. Start with 20–24 point gutters, 44-point minimum actions, a small spacing scale, text that grows with Dynamic Type, and semantic light/dark roles. Use motion only to explain progression and selected state; honor Reduce Motion.

This prototype is a visual/interaction study. It does not establish native accessibility, VoiceOver, localization, physical Health validation, new product acceptance or launch readiness. Original product/data agreements stay intact while the interface is reconsidered. No app source was changed.

## Performed prototype checks

The final fragment passed JavaScript syntax validation. A local Chrome preview exercised the same direction, screen and appearance bindings exposed by the conversation controls. All 18 combinations of three directions, two appearances and creation/Home/detail fit a verified 320-pixel frame without horizontal overflow. Wider layouts were also inspected. Creation screenshots for all three directions, Fieldwork Home and the schedule stage were visually inspected; the final Home check confirmed the wordmark and surrounding theme contrast fixes.

Interaction checks passed for activity selection, target-free friend leaderboards, required timed-run distance, duration validation, draft summary navigation, required personal targets and preserving a target when navigating back. A local shim exercised the Tweak object bindings; the host's controls panel itself was not browser-tested. Native app tests were not run because this exploration changes no app code.
