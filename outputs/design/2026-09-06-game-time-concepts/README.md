# Game Time — first visual direction

Four imagegen page concepts: Today, duel detail, goal progress, and connections.

The follow-up adds [weekly steps and activity-minute concepts](weekly-challenges.md), with two additional images and [their exact prompts](weekly-prompts.md). All six are available in the comparison gallery.

## Direction

Warm white, sharp near-black typography, and restrained athletic orange. The performance or next competition leads; surrounding details use simple rows, generous spacing and precise alignment. Retain the existing Today / Challenges / You navigation.

| Screen | Primary job | Visual emphasis |
| --- | --- | --- |
| Today | See the next duel and personal goal | Human matchup, route, then best attempt |
| Duel | Understand the agreed race | Equal participants, date, course and plain rules |
| Goal | See how close the best official attempt is | Large race time, comparable attempt history and target |
| Connections | Choose a source for training progress | Recognizable providers, connection state and one next action |

The orange is a proposed refinement of the current app accent, not a new adopted brand decision. These pages are a coherent first direction for discussion. Dates, people, performances and routes are fictional.

## References and limits

- [Strava activity detail on Mobbin](https://mobbin.com/screens/125cbc4d-55cc-4abc-82d0-4ff489ed616e): inspected the route-led composition and clearly labeled metric grid.
- [Strava device connection flow on Mobbin](https://mobbin.com/flows/e53b9705-8d37-4720-975c-5b40e76fb6bd): inspected provider selection and the optional setup path.
- [Robinhood chart documentation](https://robinhood.com/us/en/support/articles/using-charts/): confirms simple chart types and time-span selection. The proposed large numeric hierarchy follows the owner's design brief.
- [Kalshi navigation documentation](https://help.kalshi.com/en/articles/13823842-finding-markets): describes topic-based discovery. Clear event framing is an interpretation of the owner's Kalshi reference, not a copied screen.
- Mobbin searches naming Robinhood and Kalshi returned screens from other products in both standard and deep searches. No retrieved screen was misidentified as either app.
- No competitor interaction recording was available. Haptics below are a Game Time proposal; they are not a verified inventory of Robinhood behavior.

## Motion and haptics proposal

| Interaction | Proposed feedback |
| --- | --- |
| Move between actual chart points | One subtle selection tick as the selected attempt changes; show its date and time |
| Change a distance or date choice | Native selection feedback only when the choice changes |
| Press a primary action | Brief 0.98 press response; release restores the button |
| Successfully connect a device | One success haptic with persistent Connected text and last update |
| Save a check-in or accept an invitation | One confirmation haptic after the save succeeds |
| Confirm a personal best | Brief number transition and a restrained success haptic; the result remains readable |
| Waiting, sync, errors or result review | Stable content and plain status; no repeating attention feedback |

Use a visual equivalent for every haptic and a reduced-motion alternative. Static mockups cannot validate timing, tactile feel, Dynamic Type, VoiceOver or runtime behavior. Reference for implementation: [Apple haptic design guidance](https://developer.apple.com/design/human-interface-guidelines/playing-haptics).

## Product interpretation

Friend duels and personal performance commitments are the adopted business direction. The backend supports local simulated flows; the screenshots propose how a future native experience could present them.

Stakes remain visibly simulated. Garmin running sync is a proposed integration. The existing Apple Health connection supports steps. Training activity and personal check-ins do not become official race proof. No native source, payment flow, provider connection, agreement or deployment is changed by this work.

The duel screenshot shows a person who already agreed; it is not the final consent screen. The complete rules still need their own review flow. A qualifying goal attempt must be strictly under the target: the displayed 25:42 has not met the under-25:00 goal.

## Visual review notes

These are first-pass raster concepts. In the next design iteration, replace “42 sec to your goal” on Today and Goal with “43 sec faster to break 25:00” at whole-second precision, or the simpler “Closing in on 25:00.” Improving by exactly 42 seconds would equal the boundary rather than beat it. The goal chart's generated point positions are approximate, particularly the 25:42 point; a native chart must plot the exact values. The two route illustrations are placeholders and should use the same event course in implementation. Typography, copy, simulated status and the training-versus-race distinction were visually inspected. All four images have matching 853 × 1844 dimensions; the local gallery loads and exposes four enlarge controls.

## Files

- [Review all four concepts](index.html)
- [Today](01-today.png)
- [Duel](02-duel.png)
- [Goal progress](03-goal.png)
- [Connections](04-connections.png)
- [Exact generation prompts](prompts.md)

Generation mode: built-in imagegen, one call per page. The generated images are saved unchanged from the imagegen output.
