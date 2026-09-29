# How GameTime talks

GameTime's adopted direction is friend duels and personal performance
commitments. Today's app still offers seven-day Personal steps challenges.
Write for a person checking what they agreed to, how they are doing, and what
happens next. They are not reading a spec, an audit report, or a schema.
See [BUSINESS_MODEL.md](BUSINESS_MODEL.md) for the new journeys and rules.

The product's domain vocabulary — *snapshot*, *frozen terms*, *observation*,
*query-through*, *inconclusive*, and *cadence* — is precise, and it should stay
precise in the code, schema, and `DECISIONS.md`. Historical and generic systems
also retain *evidence*, *coverage*, and *attestation*. None of it belongs on a
Personal screen. Verification is what GameTime does *for* someone; making them
learn its vocabulary hands them the work instead.

## The rules

**Write what the person sees or needs to do, not what the system computed.**
"Updated from Apple Health 3 min ago" beats "snapshot observed at 14:03 and
queried through 14:02." Same fact, no glossary.

**Every error says what happened and what to do next.** "The snapshot uploader
rejected this observation" tells someone nothing they can act on. "We couldn't
update Apple Health right now. Your last update is still here." does.

**Name the actor.** Prefer "we" for GameTime and "you" for the person. Passive
constructions — *was observed*, *could not be verified*, *is required* — hide
who is doing what, and they are the main reason copy drifts into sounding like
a compliance report.

**Never expose an internal identifier as prose.** A reason code with its
underscores swapped for spaces (`identity_mismatch` → "identity mismatch") is
still a reason code. Map known codes to sentences; show unknown ones as an
explicit `Reference: <code>` so nobody mistakes it for English.
`PersonalReasonText` in `PersonalAccountabilityComponents.swift` is where that
mapping lives.

**Keep build and infrastructure detail out of shipping screens.** "This RPC is
authenticated" or "App Attest is legacy-only" is a note to a developer that a
user found by accident.

**Reassure where the design already protects them.** On current Personal
screens, missing final step data means the week doesn't count against them.
New products must explain their own proof/review rule; never equate a missing
upload with a loss or promise protection the agreed policy does not provide.

**Name the payment mode before stating a consequence.** Internal Stage A is
test-only. The beta Release path uses Stripe sandbox transactions and simulated
payment states. Never let sandbox copy read like a live charge.

**State the exact payment trigger.** For the existing Personal contract, say
“confirmed miss after review,” not
“failure,” “forfeit,” or “we may charge you.” Always pair the trigger with the
frozen amount, $0 outcomes, and the fact that the charge is one-time rather than
recurring.

## Existing Personal payment copy contract

The beta Release path uses the Stripe sandbox contract below. Debug and
historical Stage A fixtures remain separate internal test modes; hosted payment
operation is still a release gate.

### Current Stage A test-only copy

Use **Test commitment — no money will be charged.** for internal Stage A
fixtures.
The beta Release build uses the Stripe sandbox copy below.

### Forward Stripe sandbox copy

Use these exact patterns in the sandbox UI:

- Global banner: **Payment test mode — no real money moves.**
- Payment setup: **Add your test payment method before you start.** Pair it
  with the exact trigger below.
- Saved method: **Test method saved. No test charge exists.**
- Consent: **By starting, you agree that GameTime may create one \(amount) test
  charge only if this challenge is confirmed missed after the review window.
  Missing or unclear step data never counts as a miss.**
- Met goal: **Goal met — $0 test charge.**
- Inconclusive or waived: **This one didn't count — $0 test charge.**
- Cancelled or otherwise closed without a result: **Challenge closed — $0 test
  charge.**
- Provisional miss: **Goal missed — review open. Settlement is paused. Ask us to
  review this result by \(reviewDeadline).**
- Expired provisional miss: **Review window ended — settlement update pending.**
- Review pending: **Under review — settlement paused.**
- Confirmed miss: **Processing one \(amount) test charge.**
- Test payment complete: **Test charge complete — sandbox transaction recorded.**
- Failed or customer action required: **Test payment needs your attention. We
  won't try again automatically.**
- Unavailable: **Payment test status could not be confirmed.**
- Stale last confirmation: **Last confirmed \(checkedAt). We couldn't refresh
  it.**
- Sandbox cancellation confirmation: **This ends the challenge immediately.
  It will stay in your history, and your saved test payment method will not be
  charged.**

Challenge detail presents these states in one **Payment test status** card.
The result card states only how the challenge ended; it never infers review or
settlement state from result timing. An under-review state never promises a
resolution deadline. For nonterminal, attention, failed, stale, and unavailable
states, the only recovery actions are **Refresh** and **Contact Support**.
There is no client-side payment retry, automatic retry claim, or locally authored
settlement transition. Review submission is enabled only for a fresh,
server-confirmed `review_open` state whose exact server deadline is still in
the future. When a previously confirmed review form is retained during Refresh
or after a failed refresh, every review control stays disabled until a fresh
confirmation returns.

Show the saved payment method by brand and last four digits when Stripe provides
them. Never show a full payment number, Stripe identifier, `SetupIntent`,
`PaymentIntent`, mandate, webhook, or idempotency language.

### Personal goal commitment copy (D144)

The optional commitment on a personal goal reuses the banner, setup and saved
method lines above, with these goal-specific lines:

- Toggle: **Put money on it.** Button: **Add test payment method**; the Stripe
  sheet button reads **Save test payment method**.
- Consent: **By starting, you agree that GameTime may create one \(amount) test
  charge, kept by GameTime, only if your full Apple Health total for this goal
  falls short after the review window. Missing or partial activity never counts
  as a miss.**
- Amount row: **Test commitment**, with **charged only if you miss**. Goal
  stake: **\(amount) test charge only if you miss.**
- Committed, not yet final: **Your \(amount) test commitment is set. Nothing is
  charged unless you miss.**
- Met, void or closed: **No test charge — $0.**
- One open commitment: **You already have a goal with money on it. You can add
  money to another goal once that one ends.**
- Unpaid charge: **A test payment needs your attention first. Open that goal’s
  payment status to see what happened.**
- Not available: **Putting money on a goal isn’t available for your account
  yet.**

Charge processing, complete, attention and unknown states use the Forward
Stripe sandbox lines above, in the **Payment test status** card.

### Placement: disclose the environment once, protect each decision

The compact environment banner is the canonical ambient disclosure. Show it
once above the app root in every test-only and Stripe-sandbox configuration:

- **Test commitment — no money will be charged.**
- **Payment test mode — no real money moves.**

Use the same compact component once inside a presented creation sheet because
the sheet covers the root banner. Interactive Demo replaces it with **Demo mode
— no money will be charged. Nothing here leaves your phone.** Do not repeat the
environment promise in ordinary Today, Challenges, You, Privacy, detail, or
signed-out cards. The shared accessibility identifier is
`personal.environment-disclosure`.

Detailed protection copy belongs where a choice has consequences: beside the
selected amount, during test-payment consent, on the confirmation receipt, and
beside a final result or review action. Repetition at those decision points is
intentional. Keep the exact Stripe consent sentence and payment trigger
unchanged; changing placement never changes the agreement or its version.

The confirmation receipt groups the frozen facts under **Your challenge**,
**When it starts**, and **Payment protection**, with no more than four facts in
each group. Longer start and cadence explanations, sandbox cancellation, and
the safe saved-draft explanation stay behind **More details**. Never show the
draft request identifier.

### Historical Personal live-copy proposal — inactive

The following proposed language belongs only to a future version of the old
Personal failure-contingent-charge model. It is not approved live copy and
must not be reused for a funded duel or a deposited performance commitment.
D123 supersedes the assumption that it defines GameTime's future business.
Preserve it as historical context; there is no live mode enabled. The proposed
explanation was:

**Meet your goal and pay $0. If GameTime confirms you missed after the final
Apple Health check and review, we'll charge \(amount) once. This is not a
subscription.**

The live consent is:

**By starting, you authorize GameTime to charge \(amount) once only if this
challenge is confirmed missed after the review window. Missing or unclear step
data never counts as a miss.**

Do not ship this live copy until Release payments, Apple and Stripe approval,
legal terms, age and jurisdiction checks, hosted deployment, and live acceptance
are complete.

## New duel and performance-commitment copy

The opt-in native duel uses the simulated mode and agreement patterns below.
Phase 2(d) adds saved notices, results, participant review and safe exits.
Phase 2(e) adds new-consent rematches and named-recipient links. Performance
commitment screens now begin with opt-in goal agreement and result/review history;
their backend is implemented through Phase 3(e). Keep existing Personal
consent/version text intact.
Use **Challenge again** for a new duel, **Create invitation link**, **Share
invitation**, and **Turn off this link** for person-initiated sharing. State that
only the invited friend can open the link and still needs to agree. Show the
link expiry. Turning off a link does not cancel the existing invitation; keep
that distinction next to the action. Never call a custom app link a public race
page, imply a message was delivered, or reuse a previous consent/return.

Friend, invitation, opponent, result, winner, and rematch are appropriate when
those concepts actually exist in the new journey. Do not show a new duel as an
old Personal week. Charity is removed (D143) and never appears on screen.

- Simulated mode: **Simulated stakes — no real money moves.** At review show
  the two simulated amounts, fee $0, the timing rule, deadline and possible
  outcomes. Never call simulation a funded balance or money locked away.
- Agreement: **You both agree to these rules.** Show event/course, distance,
  chip or elapsed time, proof source, start/end, amount, fee, recipient and
  review/cancellation terms where applicable. An acceptance is never inferred
  from opening an invitation.
- Waiting for proof: **We're waiting for the race results.** Include the exact
  next deadline and action. Inconclusive: **We couldn't confirm this result.
  Neither of you loses your simulated stake.**
- Tie: **Same time — both simulated stakes returned.** Do not present a
  arbitrary winner when precision cannot distinguish the performances.
- Commitment: **Run 5K in under [time] before [date, year, time and zone].**
  Distinguish practice/milestones from an attempt that counts toward the goal.
- Review: **Ask us to review this result by [deadline].** Say what is paused
  and show confirmed server status; an opponent's acknowledgement is not
  an independent decision.
- Saved notice: **Latest result update** or **Earlier result update**. Show its
  original saved time and review deadline. A provisional notice is not final.
- Review receipt: **Your review request is saved.** Keep the request's update
  and reason visible. Map independent decisions to **Review complete — result
  upheld** or **Review complete — duel won’t count**. Never display a raw reason
  code or reviewer identity.
- Confirmed result and simulation are separate: **Result confirmed — simulated
  return update pending.** Only a recorded return can say **Simulated return
  recorded: [amount].** Follow with **Nothing can be paid out or redeemed. No
  real money moved.**
- Safe exit: **Withdraw from duel** or **Report an injury**. Confirm the action
  and explain that neither runner loses a simulated stake. A saved exit does
  not pretend the final result or simulated return is already recorded.
- Rematch: **Challenge again.** Show fresh rules and require both consents.

Any eventual live consent must accurately distinguish: a method saved with no
funds reserved; an expiring authorization; a captured deposit held by a named
provider; a confirmed refund; and a confirmed payout. Name who receives a
forfeiture and all fees before consent. Do not draft those promises by simply
removing “simulated” or “test.” They need the selected, approved funds flow.
Use claims such as “verified” only to describe the actual proof checked, not
as a guarantee against cheating. Avoid loss-chasing, humiliation, pressure to
run injured, or prompts to raise a stake after losing.

## Responsible engagement presentation

For the existing simulated duel and goal reviews, keep a short at-a-glance
summary before consent: activity/source, dates, amount/fee, possible outcomes,
exit and review rules. Keep every existing detailed rule under **Full duel
rules** or **Full goal rules**. Consent text and the agreement stay unchanged;
the summary must not imply support for a new distance or live money.

Future celebrations describe athletic progress, never committed dollars or
paid-challenge frequency. No financial confetti, loss-recovery language,
shaming, forced daily streaks or encouragement to exercise injured. Rest is not
an app failure. A new goal or rematch always requires a fresh deliberate choice.
No prompt may claim that a missing upload means a loss.

After a challenge is saved, the screen says **Challenge locked in.** The line
under it is the goal name and dates, such as **September steps · Sep 24–30**.
A simulated stake, when there is one, stays a short secondary line. The primary
action is **Go to Home**. **View goal** is a quiet secondary action. That
screen does not recap the agreement, timeline, or rules.

An open friend lobby isn't locked in, because nobody has agreed yet. Its screen
says **Challenge saved.**, lists who was invited with **Nobody has agreed yet**,
and then gives three factual steps: you invited them, **You pick the roster**,
and **Everyone agrees before [start date]**. The last step says it locks in when
everyone on the roster agrees, and that if anyone hasn't by the start, it's
cancelled and nothing counts. The quiet action is **View challenge**.

When notifications are implemented, each must have a clear user benefit and a
category the person controls. Ask permission when a person requests a reminder,
not at launch. Display factual deadlines without fabricated urgency. Muting,
declining, pausing new commitments and leaving must use neutral language and
remain easy to find. A future pause on new commitments must never imply that
existing obligations are cancelled or money automatically returned.

## The glossary

Left is what the system calls it. Right is what a screen calls it. If you need
a new term, add a row rather than inventing a second name for something here.

| Domain term | On screen |
| --- | --- |
| snapshot steps, historical trusted steps | steps |
| snapshot observation/update time | "Updated from Apple Health 3 min ago" |
| stale retained snapshot | "Last updated … · Apple Health is temporarily unavailable" |
| frozen terms | what you signed up for; "this locks in when you start" |
| cadence | how it counts |
| daily / cumulative | Every day / Week total |
| legacy Stage A commitment | amount ("Test commitment — no money will be charged.") |
| Stripe sandbox commitment | amount ("Payment test mode — no real money moves.") |
| settlement mode | *(not shown; the environment disclosure covers it)* |
| saved payment method, `SetupIntent` | payment method; "Test method saved" |
| off-session mandate | the exact one-time authorization sentence |
| provisional `missed_goal` | goal missed; review open |
| `review_deadline` | review by |
| off-session `PaymentIntent` | one-time charge |
| failed payment, customer action required | payment needs your attention |
| metric | On a personal goal: Outdoor runs or Steps. On a challenge with friends: Steps, Activity minutes, Running distance, or Timed run. |
| duel agreement / policy | challenge rules; what you both agreed to |
| qualifying attempt | an attempt that counts toward your goal |
| performance commitment | running goal; your goal |
| elapsed time | time from start to finish, including pauses |
| chip time | time from crossing the start to crossing the finish |
| simulation / simulated disposition | simulated stake / simulated result; no real money moves |
| proof revision / durable notice | saved result update; notice saved |
| participant case / resolution | your review request / review complete |
| contact suppression | contact details and shared results are hidden |
| follower projection | progress you chose to share |
| finality / settlement | result confirmed / the actual payment status, shown separately |
| Health permission request | Connect Apple Health |
| App Attest, attestation, provenance | *(legacy/generic only; never shown on Personal)* |
| historical evidence, coverage, diagnostic, eligibility hold | *(legacy v1 only; never shown on Personal v2)* |
| inconclusive, waived | didn't count; "it doesn't count against you". A missing or unclear score's chip on You says **Not confirmed**, never "Didn't count" (see the Floodlight rows below). |
| evidence cutoff, snapshot cutoff | "We'll keep checking Apple Health through …" |
| no successful snapshot | "No step data available yet" plus Apple Health settings help |
| local day | day |
| pending creation, retry record | draft |
| unconfirmed or refused challenge change (`ChallengeV1Store.pending`) | "Your last change didn’t finish." · **Try again** · **Cancel it**. Never "saved action" or "stop waiting". |
| stale projection, last saved view | "This might be out of date. Refresh before you make a choice." |
| protected storage | saved on your phone |
| handle | username |
| pending `friendships` row | friend request |
| accepted friendship | friend |
| decline | Decline. The request disappears; the sender isn't told. |
| `blocks` row | Block / Unblock. "Blocked people can't find you or send you requests." |
| friend or challenge report | Report. "We'll look into it. You can also block them." |
| `friend_incoming_request_exists` | "[username] already sent you a request. Accept it to become friends." |
| daily friend-request cap | "You've reached today's limit for friend requests. Try again tomorrow." |
| username lookup rate limit | "Too many searches. Wait a minute and try again." |
| `challenge_member_unavailable` (another picked person can't join when you lock the roster) | "Someone you picked can't join this challenge. Change who's in, then try again." Never say why or who. |
| account-mode upload (`verification_mode` without device proof) | "Scores come from the Apple Health activity your iPhone sends. We don't run a separate check on the device. If a score looks wrong, ask us to review it." |
| Watch-origin source requirement | "You need an Apple Watch that records to Apple Health on this iPhone. Activity recorded only by iPhone doesn't count." |
| surface, route, view | *(never shown)* |
| Staging, Debug, HealthKit, Supabase | *(never shown; describe the effect)* |

## Friend-goal pot and Floodlight screens

Copy for the adopted Floodlight 9.3 screens (Challenge, Home, Invitation and
the pot sheet), with the 9.4 outcome wording. Since September 28, 2026 the
native first slice uses the rows from "all members meet their goals" through
"challenge header", Home's card label, "sync time, just updated" and "Apple
Health access on a challenge's Health card" (`LiveGoalFloodlight.swift`,
`LiveHomeView`), and the same day's QA rows at the end of the table
(`HomeActionRows.swift`, `ChallengeHealthCopy`). The other rows are designed,
not built. Add new strings and
their `ChallengeV1UITests` or `LiveDesignUITests` assertions in the same
change. The rule behind the pot is
`ChallengeV1Policy.allocation` and `.missing`: people who meet their goals get
their stakes back and split confirmed misses evenly; any remainder and an
all-miss pot go to no one; a result we can't confirm returns that person's
stake and is never a miss. **Full rules** keeps the agreed wording.

Pick the two-person wording when exactly two people are in, and the group
wording for three or more. Don't show a pair sentence to a group: "They get
both" and "Neither back" are wrong for three people. Pictograms use neutral
figures, never a friend's color, and never rank people.

| Domain term | On screen |
| --- | --- |
| all members meet their goals | 2: **Both reach it** · "Both stakes back". 3+: **Everyone reaches it** · "All stakes back". Pot sheet: "You each get your stake back after results are final." / "Everyone gets their stake back after results are final." |
| some members meet, confirmed misses split | 2: **One reaches it** · "They get both stakes". 3+: **Some reach it** · "They split missed stakes". Pot sheet: "They get their stake back plus the missed one." / "They get their stakes back and split missed stakes evenly. Cents that don't split evenly go to no one." |
| all-miss pool, unallocated | 2: **Both miss** · "No one collects". 3+: **Everyone misses** · "No one collects". Pot sheet: "Neither stake comes back. No one collects the pot." / "No stakes come back. No one collects the pot." Never "forfeit" or "lost". |
| missing or unclear result, entry returned | 2: **Couldn't confirm** · "Stakes back · Challenge won't count", with a no-break space in "won't count" so the pair never splits across lines. Pot sheet: "If we can't confirm a result from Apple Health, both stakes come back and the challenge won't count." 3+: **Couldn't confirm** · "Stake back, not a miss". Pot sheet: "If we can't confirm someone's result from Apple Health, their stake comes back. It doesn't count as a miss." Shown in blue with a "?" badge, never with the miss badge or a dimmed coin. The two-person picture shows both people, each getting their own coin back. |
| pot total (stake × people who agreed and are still in) | **POT** over the amount, such as **$60**. Before the start it counts only people who agreed, on the invitation and in the lobby alike. Pot sheet: **The pot**, the amount and "3 × $20". VoiceOver: "Pot: $60 in simulated stakes, $20 each." The dial's pot button adds "Show how the pot works." |
| invitation terms (Floodlight 11.1) | **Stake** "$20 each" · **Fee** "$0", then "Simulated stakes — no real money moves." once. No Pot term and no total that counts people who haven't agreed. The header's pot is the lobby pot: "$20 in the pot", then on screen "Jordan agreed. Your seat fills when you agree." ("Jordan and Sam agreed. …" for more than one). Before anyone agrees: "$0 in the pot" and "Your seat fills when you agree." VoiceOver on the pot: "Pot: $20 in simulated stakes so far. Show how the pot works." |
| agreement heading | 2: **You both agree to these rules.** 3+: **You all agree to these rules.** |
| invitation facts | "Outdoor runs on Apple Watch" (or "Steps on Apple Watch", "Activity minutes on Apple Watch") · "Missing or partial activity never counts as a miss." · "48 h to ask for a review" · "Leave before your result is final" |
| invitation status and sender | **Not started** · "[username] invited you" |
| invitation goal header | "20 km each" with the dates, such as "Sep 28–Oct 4 · Pacific time". VoiceOver starts with the names: "You and Jordan: 20 km each." When goals differ, your own goal with "your goal" in place of "each" (VoiceOver: "Your goal: 20 km."). |
| invitation actions | **Review and agree** · **Decline** · **Full rules**. Decline asks first with the Challenges list's words: **Decline this invitation?** · "You won’t join this challenge. Your existing agreements stay unchanged." · **Decline invitation** · **Keep invitation**. |
| your stake card | **Your stake** with the coin, the progress groove and a flag at your goal ("20 km"). After you reach it: "Comes back when results are final." VoiceOver: "Your simulated stake, $20. Reach 20 kilometres and it comes back after results are final. Show how the pot works." After you reach it: "Your simulated stake, $20. Goal reached. It comes back when results are final. Show how the pot works." |
| snapshot observation/update time, short | "3 min ago" beside a sync icon on Home and the detail card ("2 h ago" after an hour the same day); "Yesterday, 6:10 PM" with a clock icon when late, or the date ("Sep 20, 6:10 PM") before that. VoiceOver keeps the full line: "Updated from Apple Health 3 min ago" for your own update, "Updated 2 h ago" for a friend's, or "Updated yesterday at 6:10 PM". |
| member with no saved update | Name chip: "No update". Detail card: **No update yet** and "Missing or partial activity never counts as a miss." |
| member progress (detail card) | "6.4 / 20 km" · "13.6 km to go", or **Goal reached** with a check. VoiceOver: "Sam, 7.8 of 20 kilometres, 39 percent of their goal." Yours: "You, 6.4 of 20 kilometres, 32 percent of your goal." A goal met adds ", goal reached". With no saved update: "Sam, no update yet." The card's close button: "Close your numbers" or "Close Sam’s numbers". |
| goals met so far (live) | "Everyone reached their goal." · "You and Sam reached your goals." · "Priya reached their goal." With nobody met and nobody selected: "Tap a name to see their numbers." Never a ranking. |
| challenge header | Challenge name, dates ("Sep 21–27") and seven day pips. VoiceOver: "Tuesday, day 2 of 7. Ends Sunday." The dial as a whole: "Progress toward each person’s goal". |
| Home | **Next up** rows: date tile, "[username] invited you" or the challenge name, "with Sam", and **See**. The active card opens with "Open September runs. Pot: $80 in simulated stakes." The native card reads its people and update time after that, as in the member progress and update time rows. The card itself shows the title, "Sep 21–27 · Ends Sunday", your number over "/ 20 km", "No update yet" or **Goal reached** under it, and the goals-met line in a card below. **Next up** rows aren't built yet; Home keeps its existing action rows in Next up's type (see "Home action rows" below). |
| personal goal met, entry returned (Floodlight 10.1 personal Rules) | **You reach it** · "Stake back". |
| personal goal missed, entry unallocated | **You miss it** · "No one collects it". Never "forfeit" or "lost". |
| personal goal, result we can't confirm | **Couldn't confirm** · "Stake back, not a miss", as in the group rows. |
| missing or unclear score on You (record chip) | **Not confirmed**, in the blue dashed style with "It doesn't count against you." Never "Didn't count" or **Missed**. |
| lobby pot before the start (Floodlight 10.1, 11 and 11.1) | "$20 in the pot" (or "$40 in the pot"), counting only people who agreed, then "Priya is invited. A seat fills when that friend agrees." or "Seats fill as friends agree in the lobby." Header count: "2 agreed". A decline reopens the seat and says nothing: never name who declined, and never show "Declined". |
| member exit during a challenge, pot recomputed (Floodlight 11) | **The pot is $60 now** · "Someone left and got their stake back. The challenge continues if at least two people remain." The old amount may appear struck through beside the new one. The leaver keeps the app's "Former participant" · "Left challenge". |
| void: fewer than two people left (Floodlight 11) | **This challenge didn't count** (the app's status) · "A challenge needs at least two people. Every stake comes back." Your row: **Your stake is back**. |
| void: two people, one result we can't confirm (Floodlight 11.1) | **This challenge didn't count** · "If we can't confirm a result from Apple Health, both stakes come back and the challenge won't count." No result chips. |
| finished result summary line (Floodlight 11) | The live sentences in the past: "Everyone reached their goal." · "You reached your goal." · "You, Sam and Priya reached your goals." With nobody met: "No one reached their goal." Never a ranking. |
| result pot table (Floodlight 11) | Header **The pot · $80** and **Simulated return**; one row per person in roster order with the app's **Goal met**, **Goal missed** or **Not confirmed** and the amount. |
| unallocated simulation, result screens (Floodlight 11) | **Goes to no one** with the amount, such as "$0.02" or "$40". Shown only when it isn't $0. |
| cancelled: not everyone agreed by the start (Floodlight 11) | **Challenge cancelled** (the app's status) · "Not everyone agreed before the start, so nothing counts. Your simulated stake comes back." Never say who didn't agree. |
| sync time, just updated (Floodlight 11) | "Just now" beside the sync icon, from the app's "From Apple Health · just now". |
| timed run, live (Floodlight 11.1) | Name chip **Not yet** until a run beats the time, then **Goal reached**. List: "Time target · 25:00", then the best run so far with "Best run", or "No run yet". Create labels the goal **Time target**. |
| received-score leaderboard, later build (Floodlight 11.1 proposal) | **Your saved score** · **Winners split the remaining simulated pool evenly.** (the app's line) · "No valid saved score means your stake comes back." Keep the app's "Unranked — no valid saved score" and "Save activity by …". No medals, podium or trophy. |
| Apple Health access on a challenge's Health card (Floodlight 11.1) | "Manage access in Apple Health" as a link under the card's button, as in Settings. Apple Health buttons stay neutral gray, so each screen keeps one blue action. |
| finished goal detail result (Floodlight 11.1) | A **Your result** card on the page, not behind a row: **Goal missed**, **Goal met** or **Not confirmed**, "Recorded simulated return" and the amount, then "Result confirmed · Recorded Jun 17". |
| review finished, result changed (Floodlight 11.1) | **Result updated**, then one line for the reason: "We rechecked your Apple Health total and corrected it." · "We found the missing activity and added it to your total." · "We rechecked your result against the rules and corrected it." No "You asked" line. |
| review finished, result unchanged (Floodlight 11.1) | **Result stands**, then one line for the reason: "We rechecked your Apple Health total, and it matches your result." · "We didn't find any more activity for these dates." · "We rechecked your result against the rules, and it's right." No "You asked" line. Never "upheld" or "dispute". |
| personal goal with Put money on it, outcome cards (Floodlight 10.1 and 11.1) | **You reach it** · "$0 test charge". **You miss it** · "$20 test charge". **Couldn't confirm** · "Not a miss, no charge". |
| personal goal with Put money on it, amount (Floodlight 11.1) | Rules amount row: **Test commitment** · "$20 test charge only if you miss." The saved screen uses the same line in place of "$20 simulated · fee $0". |
| Apple Health not connected, on a challenge's Health card (Floodlight QA, Sep 28) | **Apple Health isn't connected** · "Connect to check your runs. You can keep browsing without it." ("your steps" or "your activity minutes" for those goals) · **Connect**, a neutral gray button (VoiceOver: "Connect Apple Health") · the "Manage access in Apple Health" link. Your card shows **No update yet** with no update time until something of yours is saved. Other screens keep "Connect Apple Health". |
| update time as the refresh control (Floodlight QA, Sep 28) | On the challenge's person card, the update time ("1 min ago") refreshes; a spinner takes its icon's place while it syncs. No **Refresh activity** pill. VoiceOver: **Refresh activity**, with the value "Updated from Apple Health 1 min ago" (or "Refreshing"). With no saved update there's no time to tap: pull down to refresh, or use the Health card's own button when Apple Health needs attention. |
| leave a challenge in progress (Floodlight QA, Sep 28) | **Leave challenge** as plain muted text across the bottom of the list, never red and never a pill. It still asks first with **Leave safely?**. |
| Home action rows (Floodlight QA, Sep 28) | Titles in Barlow SemiBold 17, details in Barlow Regular 15, muted. The agree row's **Review** is the one blue pill; **Accept**, **Decline** and an invitation row's **Review** are gray. The agree row: **Agree to October runs** · "Agree by Sun, Sep 27", the last day before a midnight start in the challenge's time zone (VoiceOver: "Agree by Sunday, September 27"). Add the time only when it matters: "Agree by Sun, Sep 27, 11:59 PM Central Time" when your own day would end after the deadline, "Agree by Mon, Sep 28, 8:59 AM" when the start isn't at midnight. Never a countdown. Replaces "Before Sep 28, 12:00 AM". |

## Where the copy lives

User-facing strings are Swift literals in the view layer and in the
`errorDescription` of each `LocalizedError` — `PersonalChallengeFlow.swift`,
`PersonalChallengeDetailView.swift`, `TodayView.swift`, `YouView.swift`,
`ChallengesView.swift`, `PersonalAccountabilityComponents.swift`,
`PersonalPaceComponents.swift`, `AppModel.swift`, and `DomainModels.swift`.
Floodlight friend-goal copy lives in `LiveGoalFloodlight.swift`
(`FloodlightChallengeFacts`) and `LiveHomeView`; challenge Apple Health copy
lives in `ChallengeHealthCopy` (`ChallengeHealthViews.swift`). Friends copy lives in
`FriendsViews.swift` and `HomeActionRows.swift`. Friend
error codes map to sentences in `FriendsCopy` (`FriendModels.swift`), which
shows an unknown code only as `Reference: <code>`.
`PersonalSyncCoverage.swift`, `SupabaseMetricUploadClient.swift`, and
`ActivitySyncCoordinator.swift` contain historical/generic error copy only and
must not feed a Personal-v2 screen.

`GameTimeUITests` asserts on visible copy in several places, and
`assertNoForbiddenLanguage` currently fails the suite if a reachable Personal
screen uses the competitive-social vocabulary that version dropped. When new
routes are implemented, scope this check and the candidate copy audit to
Personal screens and add separate duel/commitment assertions. Do not remove
legacy checks globally. New friend/winner/rematch language is valid in the new
products; old financial consent remains exact. Changing a string usually means
changing an assertion; keep them in the same commit. As of September 22 that
suite still expects the retired `Today` shell, and `scripts/beta-native-smoke.py`
doesn't run it. Since September 27 its tests are skipped by name, with the
owner's approval, in `RetiredShellSkips.swift`. Since September 28 the 13
Personal-detail tests run again against `LivePersonalDetailView`, with
`assertNoForbiddenLanguage` scoped to that sheet, not the new shell behind it.
Remove a test's entry when it passes again. Put new product-scoped copy
checks in `ChallengeV1UITests` and `LiveDesignUITests`.

Payment copy also requires tests for sandbox versus live configuration; all nine
authoritative sandbox states (`method_saved`, `review_open`, `under_review`,
`waived`, `no_charge`, `charge_pending`, `charged`, `requires_action`, and
`collection_failed`); expired review, stale and unavailable reads; all $0
outcomes; and scheduled/active sandbox cancellation. Never make a sandbox
fixture or screenshot look like a real charge, and never expose a payment-retry
action.

Accessibility identifiers are test hooks, not copy. Personal v2 must not retain
the removed `personal.sync`, `personal.sync.pending`,
`personal.diagnostic.run`, or `personal.eligibility-hold` hooks. The one
permission action should use a Health-connect identifier consistently.

## Versioned Activity minutes

New `apple_watch_exercise_credit_v2` screens say **Activity minutes**, followed
by the Apple Exercise credit explanation. They must say the value does not
represent every minute of movement and indirectly derived credit may count.
We exclude identifiable manual and unsupported records; do not promise that
all credit caused by manual/imported/third-party activity can be excluded.
Strict v1 screens explain their unavailable source. Never rewrite consent.

| Domain term | On-screen language |
| --- | --- |
| Exercise credit v2 | Activity minutes — Apple Exercise credit recorded by Apple Watch |
| Unknown causal origin | Apple Health doesn’t tell us which activity caused every credit, so indirectly derived credit may count. |
| Historical real leaderboard v1 unavailable | Leaderboard — Not available yet. Explain that this agreement cannot rank incomplete history; keep review and safe exit available. |
| Received-score leaderboard v2 | We rank eligible activity saved by GameTime through the deadline. Missing or late activity doesn’t count. |
| Server-confirmed score | Your saved score · Last saved update · Save activity by [deadline] · Refresh |
| No valid saved score | Unranked — your simulated entry returns. Fewer than two valid scores means the challenge doesn’t count and all entries return. |
| Pending/failed upload | We haven’t confirmed this update. Refresh to recover it. If your saved score is still wrong when results arrive, ask us to review it before the review deadline. |
| Upload the server will never accept (`reason` on a 422), when the challenge can't take a replacement | **Last update not saved** · We couldn’t save this update because this challenge had stopped taking activity. If your saved score is wrong when results arrive, ask us to review it before the review deadline. Refreshing can't change this, so don't suggest Refresh or a connection check. |

For new v2 leaderboards, disclose that a partial saved total still ranks at that
total and a missing run cannot improve a saved time. Do not promise complete
Apple Health history or label a phone-only value as saved. Use factual deadlines
and recovery actions, never pressure to exercise or increase a simulated entry.
Historical consent and Personal’s missing-data promise stay unchanged.
