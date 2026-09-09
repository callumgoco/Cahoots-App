# Known limitations

- The live Supabase backend (schema, RLS, Edge Functions, Storage, Realtime publication, email auth, and server-authoritative mutations) is deployed for project `wfxmguwfowvtkngqiqfr`. Demo mode remains available when `Configuration.xcconfig` is missing.
- Email confirmation must be disabled in the Supabase Auth dashboard for local email sign-up testing, or accounts must be confirmed before the first sign-in. With confirmation enabled, the app shows a “Confirm your email” notice instead of failing into a password sign-in. Apple Sign in still needs Services ID / provider configuration in the Apple Developer portal and Supabase Auth.
- Offline mutation support is intentionally limited to workout check-ins. Live mode now persists pending check-ins in a local SwiftData overlay across process death. Voting, recovery use, proposals, membership, governance, and invite administration require connectivity.
- Production invite host, legal URLs, and support contact are set locally in gitignored `Configuration.xcconfig` (currently `callumgoco.github.io` + `callumgoconnor@gmail.com`). Hosted pages + AASA live at that GitHub Pages site. Replace with a custom domain later if you want. Never commit `Configuration.xcconfig`.
- AASA is hosted at `https://callumgoco.github.io/.well-known/apple-app-site-association` (also kept in-repo under `web/.well-known/`). See [Invite routing](InviteRouting.md).
- Background processing, Sign in with Apple on device, universal links, and Keychain need final physical-device certification with production entitlements. Device tokens register to `device_push_tokens`; friend-posted delivery uses `submit-workout` + `dispatch-pushes` once APNs secrets are configured (see [Notification setup](NotificationSetup.md)).
- Enable **Leaked password protection** in the Supabase Auth dashboard (HaveIBeenPwned) before a public TestFlight. Security Advisor still warns while it is off.
- The local cache uses a versioned v3 aggregate and a last-known-good backup. A larger post-beta data set may justify incremental SwiftData entities and a dedicated schema version beyond the snapshot migration.
- Times-per-week scheduling remains deferred until weekly allocation and recovery semantics are specified. Daily and selected-weekday schedules are supported.
- Photo avatars, StoreKit, HealthKit, public discovery, chat, location, and automatic Vision rep counting remain post-beta work. Deterministic `AvatarMark` initials/icons ship now; `profiles.avatar_path` is reserved for a later photo upload path. Workout proof clips upload to the private `workout-proofs` bucket; expired clip rows, orphan objects (>24h without a clip row), and account deletion remove matching Storage objects. Peer playback uses the spoiler-gated `clip-download-url` Edge Function (short-lived signed URLs).
- `profiles.apple_subject_id` is server-managed and not client-selectable; Rest access uses column grants that omit it for `anon`/`authenticated` (table-level SELECT was revoked and re-granted without that column).
- English is the only shipped localization. User-facing strings live in `Localizable.xcstrings` (source language `en`) and are ready for translation and plural review; no additional locales ship in v1.
- Invite mutations use security-definer RPCs; `group_invites` RLS is a single member SELECT policy (no overlapping admin FOR ALL).

## Operator checklist (pre-TestFlight)

1. ~~Populate real values in gitignored `Configuration.xcconfig`~~ (done: GitHub Pages identity).
2. ~~Host AASA + privacy/terms~~ (done: `https://callumgoco.github.io`).
3. Enable leaked-password protection in Supabase Auth (Pro plan).
4. Paste Edge `CRON_SECRET` from `.cron_secret_pending` (Vault already set) and add `APNS_*` secrets from an Apple push key.
5. Enable Sign in with Apple on the App ID + Supabase Apple provider.
6. Device-certify on a physical iPhone.
7. Commit/push the Cahoots tree (never commit `Configuration.xcconfig` or `.cron_secret_pending`).
