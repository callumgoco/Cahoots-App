# Round MVP implementation plan

## Repository audit

- Starting point: a new Xcode 26.6 SwiftUI project with app, unit-test, and UI-test targets.
- Existing code: one `Hello, world!` view and the generated app entry point; no reusable product code or dependencies.
- Project model: Xcode file-system-synchronised groups, so feature files beneath `Pact/` are discovered automatically.
- Baseline deployment target: iOS 26.5 from the template. The MVP lowers this to iOS 18.0 and limits the app to portrait iPhone, matching the product brief.
- Source control: this folder is not currently a Git worktree. Changes are therefore verified through file inspection, clean builds, and tests rather than Git diffs.

## Implementation sequence

1. Record the required Mobbin design review and establish Round's original design tokens.
2. Add domain models and isolated rules for scoring, schedules, voting, invitations, streaks, and ranking.
3. Add a feature-first app shell with injected repositories and automatic demo/live environment selection.
4. Build onboarding, private-group entry, Today, Group, challenge proposal/voting, check-in, leaderboard, and Profile flows.
5. Persist demo state and queued submissions with SwiftData; expose explicit synced, pending, failed, and rejected states.
6. Add Sign in with Apple, Keychain session storage, local notification scheduling, and Supabase REST/Edge Function scaffolding.
7. Add transactional PostgreSQL migrations, RLS policies, database functions, Edge Functions, and representative seed data.
8. Add behavioural unit tests and primary-path XCUITests.
9. Build and run tests, then review screenshots on compact and large simulators, light/dark appearance, and accessibility text sizes.
10. Finish operator, privacy, architecture, and known-limitations documentation.

## Architectural decisions

- `AppStore` is the observable presentation boundary. Domain rules remain pure and independently testable.
- Views receive state from the environment; repositories are injected through `AppEnvironment` and never called directly from leaf views.
- Demo mode is the safe default when Supabase configuration is absent. Its state persists locally and supports the complete primary journey.
- Shared server state is authoritative in live mode. The client computes only a clearly labelled provisional score while a submission is pending.
- The immutable score-event ledger is the source of final points. Leaderboard aggregates are derived, not directly editable.
- Navigation uses native `TabView`, typed destinations, sheets, and navigation stacks.
- Native frameworks are preferred: SwiftUI, SwiftData, AuthenticationServices, UserNotifications, Network, Security, and CoreImage.

## Verification gates

- A clean simulator build with no severe warnings.
- Domain and repository tests pass.
- UI tests assert onboarding, demo entry, group/proposal/vote/check-in, leaderboard, and preference behaviours.
- Demo mode launches without credentials and retains mutations between launches.
- Simulator screenshots are reviewed for hierarchy, spacing, contrast, clipping, and touch targets.

