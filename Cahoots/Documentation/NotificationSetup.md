# Notification setup

## Local planning

`NotificationPlanBuilder` produces one-shot requests for the next seven days across every active group. It considers challenge timezone, selected weekdays, completion/recovery state, open votes, global quiet hours, the default reminder time, and per-group reminder/update settings.

The plan includes:

- Daily personal reminders.
- Evening-incomplete reminders.
- Thirty-minute deadline warnings.
- Vote-opened alerts shortly after a proposal starts (when the local plan rebuilds in time).
- Four-hour vote warnings, or a near-immediate warning when at least ten minutes remain.
- Round-starting alerts on the morning of a scheduled challenge’s start day.
- Evening incomplete reminders that mention how many crew-mates still need to check in (no names or quantities on the lock screen).

Identifiers contain the notification type, group, challenge/proposal, and requirement date. Rebuilding atomically removes stale requests for completed challenges, closed votes, left groups, muted groups, and completed/recovery days. Candidates are ordered by fire date and importance, then capped at 60 requests.

Quiet-hour adjustments move a request to quiet-hours end only when it will still fire before its relevant deadline; otherwise the request is omitted. Lock-screen text intentionally contains no workout quantities, points, or media thumbnails.

## Votes & round updates (remote)

When a steward opens a vote, starts a round, a proposal passes, or a scheduled round activates, `private.enqueue_crew_update_pushes` inserts `push_outbox` rows for other members (or all members when there is no actor) who have **Votes & round updates** (`challenge_updates_enabled`) on. Quiet hours defer `send_after` until quiet-hours end in the member’s profile timezone. `dispatch-pushes` delivers them on the next cron tick.

Deep links:

- Vote opened → `cahoots://vote/{groupID}/{proposalID}`
- Round scheduled / started / proposal passed → `cahoots://log/{groupID}`

These are separate from friend-posted check-in alerts (`friendActivityMode`).

## Friend-posted alerts (remote)

When a member submits a proof check-in, `submit-workout` fans out to peers. New accounts and unset prefs default to **immediate**.

| `friendActivityMode` | Behaviour |
|---|---|
| `immediate` (default) | Try APNs now; on failure enqueue `push_outbox` for retry |
| `digest` | Insert `push_digest_events`; `dispatch-pushes` sends an evening summary after quiet-hours end (local timezone) |
| `off` | No remote alert |

Quiet hours for immediate mode defer into the digest queue. Completers see “Jordan just posted.” Incomplete members see “Jordan posted — log yours to see it.” Digests summarize counts without quantities. Deep links use `cahoots://log/{groupID}` and are handled on tap by `CahootsAppDelegate` → `AppStore.handleNotificationUserInfo`.

Local reminders embed the same `deepLink` (plus `kind` / `groupID` / optional `proposalID`) in `UNNotificationContent.userInfo`. Vote reminders use `cahoots://vote/{groupID}/{proposalID}` and open Crew → Voting. Round-starting reminders use `cahoots://log/{groupID}` and open Today check-in routing.

`dispatch-pushes` runs every minute via `pg_cron` → `private.invoke_dispatch_pushes()` → Edge Function (requires Vault secret `cron_secret` matching Edge `CRON_SECRET`). Invalid APNs tokens (`410` / `BadDeviceToken` / `Unregistered`) are deleted from `device_push_tokens`.

Vault `cron_secret` and Edge `CRON_SECRET` / `APNS_*` are configured on the live project by the operator.

### Edge secrets (never in the iOS app)

Set on the Supabase project for Edge Functions (Dashboard → Edge Functions → Secrets, or Project Settings → Edge Functions):

- `CRON_SECRET` — must match Vault `cron_secret`
- `APNS_KEY_ID` — Apple key ID
- `APNS_TEAM_ID` — Apple team ID (`PVP9QSJ25G`)
- `APNS_BUNDLE_ID` — `com.callumoconnor.cahoots`
- `APNS_PRIVATE_KEY` — full `.p8` PEM (including `-----BEGIN PRIVATE KEY-----` headers)

### Create the Apple push key (APNs)

1. Open [Apple Keys](https://developer.apple.com/account/resources/authkeys/list).
2. Create a key → enable **Apple Push Notifications service (APNs)** → Continue → Register.
3. Download the `.p8` once. Note the **Key ID**.
4. Paste into Supabase Edge secrets as above (`APNS_PRIVATE_KEY` = file contents, `APNS_KEY_ID` = Key ID, `APNS_TEAM_ID` = `PVP9QSJ25G`).

Without APNs secrets, immediate sends enqueue to `push_outbox` and digests are marked processed without delivery until secrets exist.

Never embed APNs private keys in the app.

## Sign in with Apple (dashboard)

1. [Apple Identifiers](https://developer.apple.com/account/resources/identifiers/list) → App ID `com.callumoconnor.cahoots` → enable **Sign in with Apple**.
2. Supabase Dashboard → Authentication → Providers → **Apple** → enable.
3. For native iOS, Client IDs usually include the bundle ID `com.callumoconnor.cahoots`. Follow the current Supabase Apple provider form (Secret Key / Team ID / Key ID from an Apple Sign in key if asked).
4. Test on a real iPhone (simulator Sign in with Apple is unreliable).

## Permission lifecycle

The explanation sheet is offered only when the user has a scheduled or active challenge and authorization is undetermined. Dismissal is persisted. If authorization is denied, Cahoots keeps in-app deadline/vote status and offers a link to iOS Settings. Plans rebuild after launch, foregrounding, significant time/timezone changes, group switching, reconciliation, check-in, recovery, and settings changes.

## Target capabilities

The target contains Push Notifications, Background Modes, Sign in with Apple, and Associated Domains entitlements. Before a signed release:

1. Enable those capabilities on the production App ID and provisioning profile.
2. Confirm the generated entitlements resolve `aps-environment` to `production` for Release (`development` is retained for Debug).
3. Test authorization, quiet hours, timezone changes, background execution, and a live friend-posted push on a physical device.
