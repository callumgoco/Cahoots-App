#!/bin/sh
set -eu

project_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
destination="${CI_DESTINATION:-platform=iOS Simulator,name=iPhone 16,OS=18.6}"
derived_data="${CI_DERIVED_DATA:-/tmp/CahootsCIDerivedData}"

xcodebuild -project "$project_root/Cahoots.xcodeproj" -scheme Cahoots -destination "$destination" -derivedDataPath "$derived_data" test CODE_SIGNING_ALLOWED=NO
xcodebuild -project "$project_root/Cahoots.xcodeproj" -scheme Cahoots -configuration Release -destination 'generic/platform=iOS' -derivedDataPath "$derived_data" archive -archivePath "$derived_data/Cahoots.xcarchive" CODE_SIGNING_ALLOWED=NO

