# Architecture

## Runtime boundaries

- **App shell:** `RoundApp`, `RootView`, `AppEnvironment`, and `AppStore` own dependency injection, lifecycle events, navigation, the selected group, and presentation state.
- **Pure domain layer:** `RoundStateReconciler`, `VotingEngine`, `ScheduleEngine`, `ScoringEngine`, `StreakEngine`, and `LeaderboardEngine` perform deterministic calculations without UI or persistence dependencies.
- **Time:** `AppClock` supplies current time and boundary sleeping. Tests use `FixedAppClock`; production uses `SystemAppClock`.
- **Persistence:** `DemoAppRepository` stores a versioned snapshot envelope and a last-known-good backup. `SnapshotMigrator` upgrades legacy snapshots through v2 to v3 (workout proof clips). Undecodable data produces an explicit recovery state and is never silently replaced by seed data.
- **Offline sync:** `OfflineSyncCoordinator` owns the check-in queue, single-flight ordering, stable client UUIDs, retry metadata, accepted receipts, rejection history, and manual retries. Shared group operations remain online-only.
- **Check-in visibility:** `CheckInVisibility` redacts peer quantities and clip paths until the viewer completes, uses recovery, or the daily deadline passes. `WorkoutClipRules` enforces 2s–10min proof clips (one set clip, or start+finish for minutes/distance).
- **Notifications:** `NotificationPlanBuilder` builds a deterministic, privacy-safe seven-day plan across every active group. Friend-posted remote alerts use per-group `friendActivityMode`. `NotificationScheduling` isolates the system notification centre.
- **Routing:** `AppRoute` validates HTTPS and development-scheme invite links; `AppStore` retains pending routes through onboarding or authentication.
- **Diagnostics:** privacy-aware `Logger` categories cover lifecycle, persistence, sync, notifications, and routing. `MetricKit` collection uses Apple’s first-party diagnostics pipeline.

## State flow

```text
Lifecycle or user intent
  -> AppStore
     -> pure validation / RoundStateReconciler
     -> AppRepository save or single-submission sync
     -> versioned snapshot
     -> notification-plan rebuild
  -> group-scoped SwiftUI projection
```

`RoundStateReconciler` runs after load, foregrounding, significant time/timezone changes, mutations, successful sync, and scheduled boundaries. It is idempotent: repeated runs cannot create duplicate challenges, score keys, activity events, or round results.

## Multi-group isolation

Active groups are derived only from the current user’s active memberships. The selected group ID is a device preference and is validated after every load or membership mutation. Challenges, proposals, votes, submissions, recoveries, activity, standings, and results are filtered by that group before reaching a view. Switching groups resets group-specific sheets and navigation.

## Scoring authority

The local accepted ledger uses a stable key made from challenge, user, requirement date, and event type. A requirement can score once. Pending offline submissions are projected as provisional points and never inserted into the accepted ledger until synchronization succeeds. The live adapter treats the server as authoritative: mutations go through `RepositoryCommand` RPCs and a fresh `app-snapshot` reload.

## Data migration

`RoundSwiftDataMigrationPlan` declares the current store schema and is the required path for future entity changes. Inside the aggregate, the current snapshot schema is v3. Migration to v2 adds group/challenge identities to standings, converts the legacy notification preference into global plus per-group settings, creates group-scoped `RoundResult` records, and supplies stable scoring keys. Migration to v3 adds proof-clip arrays on submissions. The original stored payload and last-known-good snapshot remain available until the migrated record saves successfully.

## Concurrency

Presentation and local persistence are main-actor isolated. The sync coordinator permits one drain at a time and processes operations oldest-first. Notification scheduling is actor-isolated. Background processing is best-effort and always preserves queue state before completing or rescheduling a task.
