# Testing and QA

## Automated coverage

The Swift Testing target covers scoring, majority/tie voting rules, vote deadlines and repeat reconciliation, London/UTC/DST schedules, scheduled/active/completed transitions, streak and recovery semantics, v1-to-v3 migration, check-in spoiler visibility, workout clip rules, multi-group scoping, invite and log-workout routing, governance permissions, deterministic notification plans, the 60-request cap, idempotent accepted offline submissions, and the complete retry/backoff/manual-retry path.

The UI target contains eight end-to-end flows plus light/dark launch checks. It covers onboarding, create/join, proposal building, vote changes, stubbed camera check-in points, notification settings, leaderboard access, and switching between two joined groups. UI-test launches suppress only the notification primer so unrelated flows cannot trigger the system permission alert.

## Commands

```sh
xcodebuild -project Cahoots.xcodeproj -scheme Cahoots -destination 'platform=iOS Simulator,name=iPhone 16' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project Cahoots.xcodeproj -scheme Cahoots -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:CahootsTests CODE_SIGNING_ALLOWED=NO
xcodebuild -project Cahoots.xcodeproj -scheme Cahoots -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:CahootsUITests CODE_SIGNING_ALLOWED=NO
```

`Cahoots.xctestplan` includes both targets. `Scripts/ci.sh` provides a provider-neutral build/test/unsigned-archive sequence; set `CI_DESTINATION` when the CI simulator name differs.

## Current automated result — 7 August 2026

- Debug simulator build: passed.
- Domain suite: 29 tests, 0 failures.
- UI flows: all eight functional flows passed; light and dark launch checks passed.
- Remaining signed-archive validation is blocked intentionally until production identity values and Apple signing are supplied.

## Release-device matrix

Before TestFlight, repeat the principal flows on compact and Pro Max iPhones in light/dark mode, accessibility text sizes, Increased Contrast, Reduce Motion, and VoiceOver. Physical-device certification must cover local notifications, background retry, Keychain, Sign in with Apple, haptics, universal links, timezone changes, and Release provisioning.

Workout clip camera (physical iPhone only — simulator uses the stub): open Log workout, wait briefly on the choose screen, tap Record, and confirm the preview is already live or appears within about a second instead of a multi-second “Setting up camera…” hold. Also check cold Record (tap immediately), Skip then reopen and Record again, flip camera, and save a clip of at least two seconds.

The existing visual reference captures are stored under `Documentation/QA-*.png`; regenerate them after material UI changes.
