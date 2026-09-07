# Notification setup

## Local planning

`NotificationPlanBuilder` produces one-shot requests for the next seven days across every active group. It considers challenge timezone, selected weekdays, completion/recovery state, open votes, global quiet hours, the default reminder time, and per-group reminder/update settings.

The plan includes:

- Daily personal reminders.
- Evening-incomplete reminders.
- Thirty-minute deadline warnings.
- Four-hour vote warnings, or a near-immediate warning when at least ten minutes remain.

Identifiers contain the notification type, group, challenge/proposal, and requirement date. Rebuilding atomically removes stale requests for completed challenges, closed votes, left groups, muted groups, and completed/recovery days. Candidates are ordered by fire date and importance, then capped at 60 requests.

Quiet-hour adjustments move a request to quiet-hours end only when it will still fire before its relevant deadline; otherwise the request is omitted. Lock-screen text intentionally contains no workout quantities, points, or media thumbnails.

## Friend-posted alerts

When a member submits a proof check-in, peers with per-group `friendActivityMode` set to `immediate` receive a remote alert (live backend). Completers see “Jordan just posted.” Incomplete members see “Jordan posted — log yours to see it.” Digest mode aggregates into an evening summary; Off suppresses the alert. Deep links use `round://log/{groupID}` to open that group’s Log Workout session.

## Permission lifecycle

The explanation sheet is offered only when the user has a scheduled or active challenge and authorization is undetermined. Dismissal is persisted. If authorization is denied, Round keeps in-app deadline/vote status and offers a link to iOS Settings. Plans rebuild after launch, foregrounding, significant time/timezone changes, group switching, reconciliation, check-in, recovery, and settings changes.

## Target capabilities

The target contains Push Notifications, Background Modes, Sign in with Apple, and Associated Domains entitlements. Before a signed release:

1. Enable those capabilities on the production App ID and provisioning profile.
2. Confirm the generated entitlements resolve `aps-environment` to `production` for Release (`development` is retained for Debug).
3. Test authorization, quiet hours, timezone changes, and background execution on a physical device.

Remote/APNs delivery remains a backend deployment concern and is outside this non-Supabase milestone. Never embed APNs private keys in the app.
