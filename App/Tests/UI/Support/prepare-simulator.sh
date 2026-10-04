#!/bin/bash
# The UI-test scheme runs this automatically before XCTest starts, including individual tests.
set -euo pipefail

if [[ "${PLATFORM_NAME:-}" != iphonesimulator ]]; then
    echo "Onboarding UI tests require an iOS Simulator destination." >&2
    exit 1
fi

simulator=${TARGET_DEVICE_IDENTIFIER:?Xcode must supply the selected test destination}
xcrun simctl bootstatus "$simulator" -b
xcrun devicectl device settings biometrics --device "$simulator" --enable --timeout 30
