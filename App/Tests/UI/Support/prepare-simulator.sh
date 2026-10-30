#!/bin/bash
set -euo pipefail

if [[ -n "${TEST_RUNNER_BIOMETRIC_TEST_STATE:-}" ]]; then
    exit 0
fi

if [[ "${PLATFORM_NAME:-}" != iphonesimulator ]]; then
    echo "Onboarding UI tests require an iOS Simulator destination." >&2
    exit 1
fi

simulator=${TARGET_DEVICE_IDENTIFIER:?Xcode must supply the selected test destination}
xcrun simctl bootstatus "$simulator" -b
xcrun devicectl device settings biometrics --device "$simulator" --enable --timeout 30
