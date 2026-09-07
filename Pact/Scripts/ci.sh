#!/bin/sh
set -eu

project_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
destination="${CI_DESTINATION:-platform=iOS Simulator,name=iPhone 16}"
derived_data="${CI_DERIVED_DATA:-/tmp/RoundCIDerivedData}"

xcodebuild -project "$project_root/Pact.xcodeproj" -scheme Pact -destination "$destination" -derivedDataPath "$derived_data" test CODE_SIGNING_ALLOWED=NO
xcodebuild -project "$project_root/Pact.xcodeproj" -scheme Pact -configuration Release -destination 'generic/platform=iOS' -derivedDataPath "$derived_data" archive -archivePath "$derived_data/Round.xcarchive" CODE_SIGNING_ALLOWED=NO

