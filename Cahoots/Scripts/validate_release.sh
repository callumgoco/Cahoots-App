#!/bin/sh
set -eu

project_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
settings="$(xcodebuild -project "$project_root/Cahoots.xcodeproj" -scheme Cahoots -configuration Release -showBuildSettings)"

value_for() {
  printf '%s\n' "$settings" | awk -F ' = ' -v key="$1" '$1 ~ "^[[:space:]]*" key "$" { print $2; exit }'
}

failed=0
for key in PRODUCT_BUNDLE_IDENTIFIER CAHOOTS_INVITE_HOST CAHOOTS_SUPPORT_EMAIL CAHOOTS_PRIVACY_URL CAHOOTS_TERMS_URL; do
  value="$(value_for "$key")"
  case "$value" in
    ""|*invalid*|*yourcompany*|*yourdomain*)
      echo "Release configuration is missing a production value for $key."
      failed=1
      ;;
  esac
done

for icon in Cahoots_light.png Cahoots_dark.png Cahoots_tinted.png; do
  if [ ! -s "$project_root/Cahoots/Assets.xcassets/AppIcon.appiconset/$icon" ]; then
    echo "Missing app icon asset: $icon"
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  exit 1
fi

echo "Release configuration validated."

