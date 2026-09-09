# Working on Cahoots

The Xcode project lives in `Cahoots/`. Open `Cahoots/Cahoots.xcodeproj` with the `Cahoots` scheme.

## This working copy is configured for live Supabase

`Cahoots/Configuration.xcconfig` exists here and holds real credentials for Supabase project
`wfxmguwfowvtkngqiqfr`. It is the first entry in `Cahoots/.gitignore`, so it does not appear in
grep, glob, or codebase search results. Only the placeholder template
`Cahoots/Configuration.example.xcconfig` is searchable, and its `YOUR_PROJECT` values are exactly
what `SupabaseConfiguration.bundled` rejects.

Do not conclude from the absence of search hits that the app runs in demo mode. Read
`Cahoots/Configuration.xcconfig` directly — reading a gitignored file works even though searching
for it does not. Unless that file is missing or still holds `YOUR_` placeholders, assume:

- `SupabaseConfiguration.bundled` resolves, so `AppEnvironment.make` builds `LiveAppRepository`
  and a non-nil `SupabaseAuthService`.
- `store.mode` is `.live`, so `signIn` and `signUp` reach Supabase instead of returning the
  "Live sign-in is not configured." banner.
- The last onboarding page shows Sign in with Apple plus **Continue with email**, and no
  **Explore the demo** button.

The credentials reach the app through the xcconfig, which is the `baseConfigurationReference`
for the app target's Debug and Release configs, then through `$(SUPABASE_URL)` and
`$(SUPABASE_ANON_KEY)` substitution in `Cahoots/Configuration/Cahoots-Info.plist`.

## Demo mode still matters

The demo fallback is real for anyone building without that gitignored file: a fresh clone, CI, or
an isolated agent worktree. `OnboardingView` branches on `store.mode` in three places, so keep
both paths working rather than deleting the demo branch. See `Cahoots/Documentation/DemoMode.md`.

## Secrets

Never move the anon key, service-role key, or APNs private key into a tracked file, and never
add a `!Configuration.xcconfig` negation to `.gitignore`.
