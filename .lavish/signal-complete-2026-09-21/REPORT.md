# Complete Signal iPhone review — revision 1

This is the clickable browser proposal for owner review. Approval is pending. It does not establish native visual fidelity, enable product policies, change an account, or move money. Native implementation and route-by-route simulator evidence follow explicit approval of this mockup.

Prepared against local `main` at `4b7cf469501992bd7bc4f3500a80f3b8373eec06` on September 21, 2026. All people, dates, activity and requests in the mockup are fictional, held in browser memory, and resettable. System-owned screens are marked stand-ins, with their entry, cancellation, return and error paths represented.

## Design authority

The design source is the owner's selected **GameTime Signal** system and feedback in this task. The unchanged September 13 reference is included alongside the proposal. Source files: `outputs/design/2026-09-13-clickable-app-alternate/DESIGN.md`, `index.html`, `signal.css`, and `signal.js`. The current migration, fidelity and copy contracts and current domain behavior control newer flows. Cobalt is historical comparison only.

The proposal uses upright system typography, blue tabular activity readouts with units and dates, cool neutral opaque content, aligned open rows, and a separate glass control layer. Amounts and commitments follow activity. No saturated blue content hero, condensed display type, greeting hero, invented lifetime statistics, or fabricated daily activity series is introduced.

### Material and accessibility

- iOS 26+: native `TabView` and `NavigationStack`, system bars, sheets, menus and pickers; system glass button styles for appropriate actions. Custom glass only where a native control cannot express the interaction.
- iOS 18: the same hierarchy and spacing with native tab/navigation controls, standard materials and bordered controls. No simulated Liquid Glass implementation.
- Reduce Transparency: opaque control backing. Increase Contrast: stronger text and separators. Reduce Motion: no required animation. Larger text: wrapping rows and scrolling content, with readable units and dates.
- Content and accepted rules remain opaque; no glass cards behind long text or activity charts. Native scroll-edge behavior should remain automatic.

The browser previews material intent only. Native iOS 26 refraction, OS presentations, VoiceOver behavior and physical-device rendering cannot be proved by CSS.

Verified Apple references: [Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/), [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/), [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views), and [GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer). The basic glass effect/styles are available in iOS 26.0; the newer `GlassButtonStyle.init(Glass)` overload requires iOS 26.1 and must not be used without an availability guard.

## Preserved behavior and data limits

- Direct Personal creation remains **Goal & dates → Review**. Generic creation adds Type. Dates, time zone and amount are optional editors, not mandatory stages. Exact input and saved agreements remain intact. The activity check and deliberate consent are separate.
- Ordinary Home leads with a specific challenge's saved activity. It does not sum overlapping challenges or invent ordinary daily totals. Only retained Personal has a daily series supplied by its existing separate source policy.
- All four Personal goal metrics and all four friend goal metrics are represented. Friends can have different targets. Timed success requires strictly beating the accepted time, with pauses included and accepted distance bounds retained.
- Multi-person selection, own proposals, freeze, independent consent, reopening, links, blocking and reports retain their existing boundaries. The creator does not agree for other people.
- D141 leaderboard fixtures rank saved scores. Partial saved scores remain eligible; no valid saved score is unranked with return, fewer than two valid scores voids the challenge, and older v1 history stays unavailable. No financial engagement prompts are added.
- Community totals are anonymous, delayed and suppressed when privacy conditions are unmet. The phone does not reveal which threshold failed.
- Profile counts describe bounded loaded records. Partial and stale states remain distinct. There is no invented streak, join date, lifetime total or win ratio.
- Retained Personal keeps its original creation, consent, cancellation, seven-day review and nine sandbox payment states. Historical decision-point consent is unchanged. Refresh cannot rewrite its result. Missing final data does not count against the person.
- Local experiment routes are reviewable in a separate appendix. Their older weekly, duel, commitment and metric rules remain distinct. They are not linked into ordinary product navigation.
- Existing private-trial policy flags, permissions, admission rules and deployment boundaries remain unchanged. Showing a broader configuration in the mockup does not enable it on the installed phone.

## Native route families

All source paths below are under `ios/GameTime/GameTime/`. Individual browser routes and checked states are recorded in `verification/routes-result.json`.

| Reachable family | Native behavior sources | Mockup module |
| --- | --- | --- |
| Launch, Apple sign-in and onboarding | `LaunchingView.swift`, `GameTimeApp.swift`, `AppleSignIn.swift`, `AppModel.swift` | `account.js` |
| Home, activity, Challenges and bounded profile | `AppShellView.swift`, `SignalChallengeViews.swift`, `ChallengeProfileView.swift`, `ChallengeProfileSnapshot.swift` | `prototype.js` |
| Goal creation and editors | `ChallengeCreationViews.swift`, `ChallengeCreationDraft.swift` | `creation.js` |
| Four Personal and four friend goal details, rules, reviews and exits | `ChallengeV1Views.swift`, `ChallengeV1Policy.swift`, `ChallengeHealthViews.swift` | `goals.js` |
| Invitation intake and age confirmation | `ChallengeV1EntryViews.swift`, `ChallengeInvitation.swift` | `goals.js`, `account.js` |
| People, exact username, reusable links, roster, proposals, independent consent | `ChallengeV1Views.swift`, `ChallengeV1EntryViews.swift` | `social.js` |
| Leaderboards, results, ties, unranked, void and unavailable history | `ChallengeV1Views.swift`, `ChallengeV1Policy.swift`, `RECEIVED_LEADERBOARD_V2.md` | `social.js` |
| Community entry, agreement, private progress, privacy and reports | `ChallengeV1Views.swift`, current community disclosure contract | `prototype.js`, `goals.js` |
| Health permission, source and readiness states | `ChallengeHealthViews.swift`, `YouView.swift`, goal-specific readers | `account.js` |
| Settings, privacy, support, sign-out, deletion, recovery and appeal | `YouView.swift`, `GameTimeApp.swift`, `AppleSignIn.swift` | `account.js` |
| Retained Personal daily activity, history, setup, drafts, review and cancellation | `TodayView.swift`, `ChallengesView.swift`, `PersonalChallengeDetailView.swift`, `PersonalChallengeFlow.swift`, `PersonalPaymentStatusCard.swift` | `legacy.js` |
| Local-only duel, commitment, weekly and metric practice | `DuelViews.swift`, `DuelInvitationView.swift`, `DuelLifecycleViews.swift`, `PerformanceCommitmentViews.swift`, `PerformanceCommitmentLifecycleViews.swift`, `WeeklyViews.swift`, `MetricPrototypeView.swift` | `experiments.js` |

The Debug-only source-investigation harness is excluded from app navigation scope. `SourceInvestigationView.swift:1,7–9` requires a dedicated launch argument and `GameTimeApp.swift:212–215` replaces the app root with it. There is no in-app entry; the Local experiment routes in `AppShellView.swift:133–139` are included.

## Review and verification

Use the left journey navigation for connected flows and **Every screen** for direct access to any screen. The State selector covers loading, empty, stale, failure and lifecycle variants where supported. Reviewer-only controls outside the phone advance fictional other-person responses or clocks. Back, Close, edit, refresh, review, save and exit paths operate on local state. Opening a saved-receipt route without its saved request shows the missing-record state.

**Completed browser checks:** 182 routes, 672 route/state renders, 728 layout combinations, and 11 connected behavior checks passed. Route links, headings, undefined content and horizontal overflow checks reported no failures. These counts include the separate 47-route local experiment appendix.

`verification/routes-result.json` records the final route/state inventory. `layout-result.json` checks content and descendant horizontal bounds at 390-point/default/light iOS 26, 320-point/large/light iOS 26, 320-point/large/dark/opaque iOS 26, and 390-point/default/dark/opaque iOS 18. This is a browser geometry check, not native accessibility acceptance. `journeys-result.json` records connected behavior checks. Representative rendered browser screenshots are stored beside them. Copy was reviewed using Unslop and `docs/COPY.md`; exact historical consent was preserved.

## Work after approval

Implement the approved shared composition, typography and controls, then migrate every native route family above without changing its behavior or configuration. Verify actual rendered native routes in light and dark, with compact layout, Dynamic Type, Reduce Transparency and the iOS 18 fallback. Capture route IDs, source revision, OS/device/configuration, state fixture, screenshot and observed outcome. Run meaningful existing behavior checks and active iPhone product guards. Record any system-owned or physical-device gate that remains unperformed; browser results and passing tests alone do not establish Signal fidelity.

No hosted mutation, deployment, push or physical-phone installation is included in this review artifact.
