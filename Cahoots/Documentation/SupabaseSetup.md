# Supabase setup

## Project

Live project URL: `https://wfxmguwfowvtkngqiqfr.supabase.co`

## Create and migrate

1. Migrations live under `supabase/migrations/` and are the source of truth.
2. Applied to the `wfxmguwfowvtkngqiqfr` project via the Supabase MCP `apply_migration` tool (or `supabase db push` when the CLI is linked):
   - `202608070001_initial_round_schema.sql`
   - `202608200001_workout_clips_and_spoilers.sql`
   - `202609070001_live_backend_completion.sql` (profile bootstrap, missing RPCs, Realtime, Storage, cron)
3. Confirm RLS is enabled on every public table and run the Security Advisor. `group_invites` uses a single member SELECT policy; invite writes go through security-definer RPCs (`20260909201841_phase4_invite_policy_consolidation.sql`).
4. Deploy Edge Functions with JWT verification enabled (except cron-gated ones that use `x-cron-secret`, and Apple’s ASN webhook):
   - `app-snapshot`
   - `submit-workout`
   - `finalize-vote`
   - `clip-upload-url`
   - `clip-download-url`
   - `delete-account`
   - `purge-workout-clips` (`verify_jwt` false)
   - `dispatch-pushes` (`verify_jwt` false; friend-posted outbox + digests)
   - `sync-entitlement` (Cahoots Plus purchase sync)
   - `storekit-notifications` (`verify_jwt` false; App Store Server Notifications V2)
5. Private Storage bucket `workout-proofs` is created by the completion migration. Object path: `{group_id}/{challenge_id}/{requirement_date}/{user_id}/{clip_id}.mov`.

The schema creates all MVP tables, indexes, eligible-voter snapshots, score ledger, privacy/moderation data, transaction functions, and policies. The service role is used only in trusted server jobs, never the iOS client.

## Authentication

### Email / password (ready now)

The welcome screen leads with **Create account** in live mode, then Sign in with Apple, then **Sign in**. Sign-up and sign-in open dedicated email forms; sign-up sends `display_name` and `timezone` in user metadata; `handle_new_user` creates the `profiles` row automatically.

**Dashboard step required for local testing:** Authentication → Providers → Email → disable **Confirm email**, otherwise new accounts cannot sign in until confirmed.

### Apple Sign in

1. In Apple Developer, enable Sign in with Apple for App ID `com.callumoconnor.cahoots`.
2. Create the Services ID / key required by Supabase Auth.
3. Configure the Apple provider and redirect URL in Supabase Auth.
4. The Xcode target already includes the Sign in with Apple entitlement.

Access and refresh tokens are stored in Keychain. The client refreshes on 401 before forcing re-login.

## iOS configuration

Copy `Configuration.example.xcconfig` to the gitignored `Configuration.xcconfig`, fill `SUPABASE_URL` and the **public anonymous key**, and keep it assigned as the app target's base configuration (already wired in `project.pbxproj`). Values enter Info.plist through `INFOPLIST_KEY_SUPABASE_URL` and `INFOPLIST_KEY_SUPABASE_ANON_KEY`.

If either value is missing, invalid, or still contains a placeholder, the app intentionally launches demo mode.

Because `Configuration.xcconfig` is gitignored, a completed setup leaves no trace in any tracked file and does not surface in search results, while the searchable `Configuration.example.xcconfig` always shows placeholders. Read `Configuration.xcconfig` directly before concluding that a checkout is unconfigured.

## Live write path

Mutations go through `RepositoryCommand` → `LiveAppRepository.perform` → Postgres RPCs, then a fresh `app-snapshot` reload. Demo mode uses `SnapshotCommandApplier` for the same commands against SwiftData.

Workout clips are uploaded via `clip-upload-url` (signed URL) before `submit-workout`.

## Realtime

Group-scoped tables are in the Realtime publication: `challenge_proposals`, `votes`, `challenges`, `activity_feed_items`, `score_events`, `submissions`, `group_memberships`. Realtime is an invalidation aid; it is not scoring authority.

## Server jobs

`pg_cron` schedules:

- `finalize-expired-votes` every 5 minutes
- `activate-due-challenges` / `complete-due-challenges` every 15 minutes
- `purge-expired-workout-clips` daily at 03:00 UTC (clips past deadline + 48h or on ended rounds; orphan `workout-proofs` objects older than 24h; newer check-ins also drop that member’s older-day clips)
- `dispatch-pushes` every minute (no-ops until Vault `cron_secret` is set)

## Production checklist

- Replace the placeholder support contact and invite-link domain in `Configuration.xcconfig`.
- Disable email confirmation only for development; use real confirmation (or Apple) in production.
- Exercise RLS as two unrelated users and removed/blocked users.
- Configure rate limits, log redaction, backups, PITR, and alerting.
- Rotate keys and document incident response.
