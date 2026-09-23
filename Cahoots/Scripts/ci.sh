#!/bin/sh
set -eu

project_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
destination="${CI_DESTINATION:-platform=iOS Simulator,name=iPhone 16,OS=18.6}"
derived_data="${CI_DERIVED_DATA:-/tmp/CahootsCIDerivedData}"

# The app target requires this base configuration. It is gitignored because local
# copies hold credentials, so CI and fresh clones use the placeholder template.
# YOUR_ values are rejected by SupabaseConfiguration.bundled, which keeps demo mode.
if [ ! -f "$project_root/Configuration.xcconfig" ]; then
  cp "$project_root/Configuration.example.xcconfig" "$project_root/Configuration.xcconfig"
fi

xcodebuild -project "$project_root/Cahoots.xcodeproj" -scheme Cahoots -destination "$destination" -derivedDataPath "$derived_data" test CODE_SIGNING_ALLOWED=NO
xcodebuild -project "$project_root/Cahoots.xcodeproj" -scheme Cahoots -configuration Release -destination 'generic/platform=iOS' -derivedDataPath "$derived_data" archive -archivePath "$derived_data/Cahoots.xcarchive" CODE_SIGNING_ALLOWED=NO

