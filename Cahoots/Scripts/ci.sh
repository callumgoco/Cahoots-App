#!/bin/sh
set -eu

project_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
derived_data="${CI_DERIVED_DATA:-/tmp/CahootsCIDerivedData}"

# The app target requires this base configuration. It is gitignored because local
# copies hold credentials, so CI and fresh clones use the placeholder template.
# YOUR_ values are rejected by SupabaseConfiguration.bundled, which keeps demo mode.
if [ ! -f "$project_root/Configuration.xcconfig" ]; then
  cp "$project_root/Configuration.example.xcconfig" "$project_root/Configuration.xcconfig"
fi

# GitHub's macOS runners sometimes start xcodebuild before CoreSimulator has
# rebuilt its device cache, so preinstalled iPhones look missing.
attempt=0
while [ "$attempt" -lt 6 ]; do
  xcrun simctl list devices available >/dev/null 2>&1 || true
  if xcrun simctl list devices available 2>/dev/null | grep -q "iPhone"; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 3
done

if [ -n "${CI_DESTINATION:-}" ]; then
  destination="$CI_DESTINATION"
else
  destination="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)
candidates = []
marker = "SimRuntime.iOS-"
for runtime, devices in data.get("devices", {}).items():
    if marker not in runtime:
        continue
    version = tuple(int(part) for part in runtime.split(marker, 1)[1].split("-") if part.isdigit())
    for device in devices:
        if not device.get("isAvailable", True):
            continue
        name = device.get("name", "")
        if not name.startswith("iPhone"):
            continue
        candidates.append((
            name == "iPhone 16" and version[:2] == (18, 6),
            name == "iPhone 16",
            version,
            name,
            device["udid"],
        ))
if not candidates:
    print("No available iPhone simulator.", file=sys.stderr)
    sys.exit(1)
candidates.sort()
_, _, _, name, udid = candidates[-1]
print(f"platform=iOS Simulator,id={udid}")
print(f"Selected simulator: {name} ({udid})", file=sys.stderr)
')"
fi

echo "Using destination: $destination"
xcodebuild -project "$project_root/Cahoots.xcodeproj" -scheme Cahoots -destination "$destination" -derivedDataPath "$derived_data" test CODE_SIGNING_ALLOWED=NO
xcodebuild -project "$project_root/Cahoots.xcodeproj" -scheme Cahoots -configuration Release -destination 'generic/platform=iOS' -derivedDataPath "$derived_data" archive -archivePath "$derived_data/Cahoots.xcarchive" CODE_SIGNING_ALLOWED=NO

