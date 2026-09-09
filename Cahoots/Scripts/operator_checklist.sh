#!/bin/sh
# Prints what is ready vs what still needs a human for TestFlight.
set -eu
root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
repo="$(CDPATH= cd -- "$root/.." && pwd)"

ok() { printf '✓ %s\n' "$1"; }
todo() { printf '○ %s\n' "$1"; }
fail() { printf '✗ %s\n' "$1"; }

echo "Cahoots TestFlight readiness"
echo "============================"

if "$root/Scripts/validate_release.sh" >/dev/null 2>&1; then
  ok "App identity (bundle / invite / support / privacy / terms)"
else
  fail "App identity — fix Cahoots/Configuration.xcconfig then re-run Scripts/validate_release.sh"
fi

aasa="$(curl -sS -o /dev/null -w '%{http_code}' -L "https://callumgoco.github.io/.well-known/apple-app-site-association" || true)"
privacy="$(curl -sS -o /dev/null -w '%{http_code}' -L "https://callumgoco.github.io/privacy/" || true)"
if [ "$aasa" = "200" ] && [ "$privacy" = "200" ]; then
  ok "Website invite file + privacy page (callumgoco.github.io)"
else
  fail "Website hosting (AASA=$aasa privacy=$privacy)"
fi

todo "Leaked-password protection — Supabase Auth → Email → enable (Pro plan)"
echo "    https://supabase.com/dashboard/project/wfxmguwfowvtkngqiqfr/auth/providers?provider=Email"

if [ -f "$root/.cron_secret_pending" ]; then
  todo "Paste Edge secret CRON_SECRET from Cahoots/.cron_secret_pending (Vault already set)"
else
  todo "Confirm Edge secret CRON_SECRET matches Vault cron_secret"
fi
todo "Add APNs Edge secrets (APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID, APNS_PRIVATE_KEY)"
echo "    Secrets: https://supabase.com/dashboard/project/wfxmguwfowvtkngqiqfr/settings/functions"
echo "    Apple key: https://developer.apple.com/account/resources/authkeys/list"

todo "Sign in with Apple — App ID capability + Supabase Apple provider"
echo "    Apple IDs: https://developer.apple.com/account/resources/identifiers/list"
echo "    Supabase: https://supabase.com/dashboard/project/wfxmguwfowvtkngqiqfr/auth/providers"

todo "Physical iPhone: Apple sign-in, Keychain stay signed-in, clip check-in, invite link, push"

if git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1 \
  && [ "$(git -C "$repo" rev-parse HEAD)" = "$(git -C "$repo" rev-parse '@{u}')" ]; then
  ok "Cahoots code pushed to origin"
else
  fail "Git push not in sync with origin"
fi
if [ -d "$repo/.github/workflows" ] && [ -n "$(git -C "$repo" status --porcelain -- .github 2>/dev/null || true)" ]; then
  todo "Push CI workflow (needs: gh auth refresh -h github.com -s workflow,repo)"
fi

echo
echo "Details: Documentation/KnownLimitations.md and Documentation/NotificationSetup.md"
