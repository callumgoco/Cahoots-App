# Known limitations

- The live Supabase backend (schema, RLS, Edge Functions, Storage, Realtime publication, email auth, and server-authoritative mutations) is deployed for project `wfxmguwfowvtkngqiqfr`. Demo mode remains available when `Configuration.xcconfig` is missing.
- Email confirmation must be disabled in the Supabase Auth dashboard for local email sign-up testing, or accounts must be confirmed before the first sign-in. Apple Sign in still needs Services ID / provider configuration in the Apple Developer portal and Supabase Auth.
- Offline mutation support is intentionally limited to workout check-ins. Voting, recovery use, proposals, membership, governance, and invite administration require connectivity.
- Production invite domain, legal URLs, and support contact still use placeholders. `Scripts/validate_release.sh` deliberately fails while placeholder values remain.
- The invite domain still needs a deployed `apple-app-site-association` file; see [Invite routing](InviteRouting.md).
- Background processing, remote APNs delivery, Sign in with Apple on device, universal links, and Keychain need final physical-device certification with production entitlements.
- The local cache uses a versioned v3 aggregate and a last-known-good backup. A larger post-beta data set may justify incremental SwiftData entities and a dedicated schema version beyond the snapshot migration.
- Times-per-week scheduling remains deferred until weekly allocation and recovery semantics are specified. Daily and selected-weekday schedules are supported.
- Photo avatars, StoreKit, HealthKit, public discovery, chat, location, and automatic Vision rep counting remain post-beta work. Workout proof clips upload to the private `workout-proofs` bucket; APNs friend-posted delivery still needs an APNs worker.
- English is the only shipped localization. User-facing strings are extracted into a String Catalog, ready for translation and plural review.
