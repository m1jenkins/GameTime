# E2E & UI Test Infra: GameTime Strava UI/UX Redesign

## Test Philosophy
- Opaque-box & unit-level UI assertion testing using `xcodebuild`.
- Methodology: Category-Partition + BVA + Pairwise + Workload Testing.
- Compliance: Strict `docs/COPY.md` vocabulary contract, zero forbidden words (`assertNoForbiddenLanguage`), zero AI-slop anti-patterns.

## Feature Inventory & Test Mapping
| # | Feature | Unit Test Target | UI Test Target | Accessibility ID |
|---|---------|------------------|----------------|------------------|
| 1 | Athletic Design System Token Engine | `DomainAndConfigurationTests` | `GameTimeUITests` | `tab.today`, `tab.challenges` |
| 2 | Today Screen / Hero Performance Block | `DomainAndConfigurationTests` | `GameTimeUITests` | `personal.progress`, `personal.pace.day.0-6` |
| 3 | 7-Day Athletic Splits & Dynamic Pace | `DomainAndConfigurationTests` | `GameTimeUITests` | `personal.pace.finish`, `personal.pace.average` |
| 4 | Stakes & Health Sync Status HUD | `DomainAndConfigurationTests` | `GameTimeUITests` | `personal.environment-disclosure` |
| 5 | Challenge History & Detail Ledger | `DomainAndConfigurationTests` | `GameTimeUITests` | `personal.challenge.<uuid>`, `personal.details` |
| 6 | Challenge Creation Flow Overhaul | `DomainAndConfigurationTests` | `GameTimeUITests` | `personal.cadence.daily`, `personal.target`, `personal.commitment.1000`, `personal.submit` |

## Test Runner Commands
- **Xcode Build Check**:
  `xcodebuild -scheme GameTime -destination 'generic/platform=iOS' build`
- **Unit Tests**:
  `xcodebuild test -scheme GameTime -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:GameTimeTests`
- **UI Tests**:
  `xcodebuild test -scheme GameTime -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:GameTimeUITests`
