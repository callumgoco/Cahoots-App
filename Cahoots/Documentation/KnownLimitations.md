# Known limitations

- The live Supabase backend (schema, RLS, Edge Functions, Storage, Realtime publication, email auth, and server-authoritative mutations) is deployed for project `wfxmguwfowvtkngqiqfr`. Demo mode remains available when `Configuration.xcconfig` is missing.
- Email confirmation must be disabled in the Supabase Auth dashboard for local email sign-up testing, or accounts must be confirmed before the first sign-in. With confirmation enabled, the app shows a “Confirm your email” notice instead of failing into a password sign-in. Apple Sign in still needs Services ID / provider configuration in the Apple Developer portal and Supabase Auth.
- Offline mutation support is intentionally limited to workout check-ins. Live mode now persists pending check-ins in a local SwiftData overlay across process death. Voting, recovery use, proposals, membership, governance, and invite administration require connectivity.
- Production invite host, legal URLs, and support contact come from gitignored `Configuration.xcconfig`. Marketing + legal pages are hosted at `https://cahoots-app.netlify.app/` (AASA under `/.well-known/apple-app-site-association`). Never commit `Configuration.xcconfig`.
- Background processing, Sign in with Apple on device, universal links, and Keychain need final physical-device certification with production entitlements. Device tokens register to `device_push_tokens`. Live lock-screen alerts (friend-posted, crew updates, and time-based reminders) use `submit-workout` / `enqueue_crew_update_pushes` / `enqueue_due_reminders` + `dispatch-pushes` once APNs secrets are configured (see [Notification setup](NotificationSetup.md)).
- Enable **Leaked password protection** in the Supabase Auth dashboard (HaveIBeenPwned) before a public TestFlight. Security Advisor still warns while it is off.
- The local cache uses a versioned v3 aggregate and a last-known-good backup. A larger post-beta data set may justify incremental SwiftData entities and a dedicated schema version beyond the snapshot migration.
- Times-per-week scheduling remains deferred until weekly allocation and recovery semantics are specified. Daily and selected-weekday schedules are supported.
- Photo avatars, HealthKit, public discovery, chat, location, and automatic Vision rep counting remain post-beta work. Deterministic `AvatarMark` initials/icons ship now; `profiles.avatar_path` is reserved for a later photo upload path. Workout proof clips upload to the private `workout-proofs` bucket; retention is deadline + 48h (or round end), with older-day clips removed on a newer check-in; orphan objects (>24h without a clip row) and account deletion also remove Storage objects. Peer playback uses the spoiler-gated `clip-download-url` Edge Function (short-lived signed URLs).
- **Cahoots Plus** (StoreKit 2) gates a second crew membership: Free = 1 active crew, Plus = up to 10. See [Monetization](Monetization.md). Migration + `sync-entitlement` / `storekit-notifications` (Apple JWS verification) are live on `wfxmguwfowvtkngqiqfr`. Local runs use the shared scheme’s `Cahoots.storekit` catalog. Production still needs App Store Connect products, a 7-day annual intro offer, Edge secret `APPLE_BUNDLE_ID=com.callumoconnor.cahoots`, and ASN V2 pointed at `…/functions/v1/storekit-notifications` before relying on live purchases.
- `profiles.apple_subject_id` is server-managed and not client-selectable; Rest access uses column grants that omit it for `anon`/`authenticated` (table-level SELECT was revoked and re-granted without that column).
- English is the only shipped localization. User-facing strings live in `Localizable.xcstrings` (source language `en`) and are ready for translation and plural review; no additional locales ship in v1.
- Invite mutations use security-definer RPCs; `group_invites` RLS is a single member SELECT policy (no overlapping admin FOR ALL).
- Local and remote notification taps route through `UNUserNotificationCenterDelegate` into `AppStore.handleNotificationUserInfo` / `AppRoute` (`cahoots://log/…`, `cahoots://vote/…`). Cold-start taps are buffered until `AppStore` is attached at launch.

## Operator checklist (pre-TestFlight)

1. ~~Populate real values in gitignored `Configuration.xcconfig`~~ (done: `cahoots-app.netlify.app` + support email).
2. ~~Host AASA + privacy/terms~~ (done: `https://cahoots-app.netlify.app`). Redeploy `web/terms/index.html` so the hosted terms include the Cahoots Plus subscription section.
3. Enable leaked-password protection in Supabase Auth (Pro plan).
4. ~~Paste Edge `CRON_SECRET` and add `APNS_*` secrets~~ (done by operator). Still set Edge secret `APPLE_BUNDLE_ID=com.callumoconnor.cahoots`.
5. Enable Sign in with Apple on the App ID + Supabase Apple provider (if not already live-tested).
6. Turn on **Confirm email** in Supabase Auth for production, with redirect URL on `cahoots-app.netlify.app`.
7. App Store Connect: Paid Apps agreement, Plus SKUs + annual 7-day intro, ASN V2 → `storekit-notifications` (Production + Sandbox).
8. Device-certify on a physical iPhone (Apple Sign In, universal links, push tap from a killed app → check-in/vote, failed-proposal push, reminder after force-quit, camera/clips, Keychain, background sync, sandbox Plus purchase).
9. ~~Apply `delete_group` on live~~ (done via pactapp MCP).
10. ~~Phase 2 reliability hardening on live~~ (rate-limit caps, storage membership checks, one submission/day, push-token cleanup; Edge Functions redeployed for rate-limit + activity-feed fix).
11. ~~Phase 3–4 maintainability/polish~~ (file splits, outbox cleanup cron, finalize-vote hardening, notification-settings shim, settings chrome, themed chips, workout a11y).
12. Commit/push the Cahoots tree (never commit `Configuration.xcconfig` or leftover secret scratch files).
