# Round

Round is a native iPhone MVP for private workout challenges between friends: agree on one measurable rule, check in on scheduled days, and compete through consistency without rewarding unsafe volume.

## What works

- Single welcome screen, Sign in with Apple architecture, and no-credential demo entry.
- Multiple simultaneous group memberships with persisted selection and group-scoped Today, Group, Leaderboard, activity, submissions, and results.
- Private group creation, universal/custom invite routing, QR/share UI, joining, ownership transfer, roles, removal, leaving, blocking, reporting, and invite rotation/revocation.
- Multi-step activity/target/schedule/duration/deadline/recovery proposal builder.
- Automatic forty-eight-hour voting, scheduled challenge activation, timezone-aware deadlines, streak reconciliation, round completion, and next-challenge results actions.
- Today states for upcoming, rest, incomplete, complete, closed, provisional, and offline sync.
- Honour-system check-ins with required private proof clips, capped points, spoilered peer quantities until you check in, stable scoring keys, provisional standings, and a persistent single-flight retry queue with rejection/manual-retry states.
- Round/all-time leaderboards, group-scoped results, activity, Profile, appearance, editable quiet hours, and per-group notification controls.
- Versioned v3 persistence with explicit recovery for corrupt data, deterministic clocks, privacy-safe logging, MetricKit, a privacy manifest, release icons, a test plan, and CI/release validation scripts.
- Supabase PostgreSQL schema, RLS, transactional RPCs, immutable score ledger, and Edge Function boundaries.

## Requirements

- Xcode 26.6 or later (the project also targets iOS 18.0 and newer).
- An iPhone simulator or iPhone; portrait is the supported MVP orientation.
- No backend account is required for demo mode.

## Run the app

1. Open `Pact.xcodeproj` in Xcode.
2. Select the `Pact` scheme and an iPhone destination.
3. Run. The installed display name is **Round**.
4. Complete the welcome screen. With a populated `Configuration.xcconfig` the app runs live, so create an account, sign in with Apple, or sign in with email. Demo mode and **Explore the demo** appear automatically only when those Supabase build settings are absent.

The working name is centralised at `AppIdentity.name` in `Pact/Core/Models/DomainModels.swift` and through `CFBundleDisplayName` in project settings.

## Architecture

The source tree is feature-first. `AppStore` is the observable presentation boundary; pure reconcilers/planners own round lifecycle and notification decisions; repositories own I/O; and `OfflineSyncCoordinator` owns the check-in queue. See [Architecture](Documentation/Architecture.md).

No large architecture framework or third-party UI library is used. The live client talks to Supabase's supported HTTP/Auth interfaces so the project remains immediately buildable without resolving an external package.

## Demo mode

Demo mode seeds two joined groups—**Saturday Crew** and **Lunch Break Club**—with distinct challenges, standings, results, activity, invitations, settings, and a pending offline check-in. Mutations persist in the versioned local snapshot. See [Demo mode](Documentation/DemoMode.md).

## Release configuration

Copy `Configuration.example.xcconfig` to a private configuration file and provide the production bundle identifier, invite host, support email, privacy URL, and terms URL. Configure the app target to use it for Release, then run:

```sh
Scripts/validate_release.sh
Scripts/ci.sh
```

The validator intentionally blocks an archive while placeholder identity/legal values or icon assets remain. Universal-link hosting is documented in [Invite routing](Documentation/InviteRouting.md); notification and capability setup is documented in [Notification setup](Documentation/NotificationSetup.md).

## Supabase and Sign in with Apple

1. Apply `supabase/migrations/202608070001_initial_round_schema.sql` to a Supabase project.
2. Deploy the functions under `supabase/functions`.
3. Configure Apple as an Auth provider in Supabase and add Sign in with Apple to the app identifier/capabilities.
4. Copy `Configuration.example.xcconfig` to `Configuration.xcconfig`, enter the project URL and public anonymous key, then assign it as the app target's Debug/Release base configuration (or define the same build settings in Xcode).

Never put the service-role key or APNs private key in the app. Full steps: [Supabase setup](Documentation/SupabaseSetup.md) and [Notification setup](Documentation/NotificationSetup.md).

## Tests

In Xcode, use **Product → Test**. Command-line examples:

```sh
xcodebuild test -project Pact.xcodeproj -scheme Pact -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PactTests
xcodebuild test -project Pact.xcodeproj -scheme Pact -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PactUITests
```

See [Testing](Documentation/Testing.md) for test launch arguments and the visual-QA matrix.

## Outside this MVP

Public discovery, chat, location, HealthKit proof, automatic Vision rep counting, purchases, and automatic times-per-week allocation are intentionally outside scope. Short private group workout proof clips are in scope. Production Apple signing, universal-link hosting, live backend deployment, and physical-device certification require external inputs. See [Known limitations](Documentation/KnownLimitations.md).
