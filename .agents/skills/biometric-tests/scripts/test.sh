#!/bin/bash
# Runs one real Keychain check without changing biometric enrollment.
set -euo pipefail

if [[ $# -ne 2 ]] || [[ "$2" != enrolled && "$2" != unenrolled ]]; then
    echo "Usage: bash test.sh <simulator-uuid> <enrolled|unenrolled>" >&2
    exit 2
fi

simulator=$1
state=$2
inventory=$(xcrun simctl list devices available)
if ! device=$(grep -F -- "($simulator)" <<< "$inventory"); then
    echo "Simulator not found. Select a UUID from: xcrun simctl list devices available" >&2
    exit 2
fi
case "$device" in
    *'(Shutdown)'*) xcrun simctl boot "$simulator" ;;
    *'(Booted)'*) ;;
    *) echo "Simulator is transitioning; inspect its state before retrying." >&2; exit 1 ;;
esac
xcrun simctl bootstatus "$simulator" -b
xcrun devicectl device settings biometrics --device "$simulator"

repository=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
cd "$repository"
run=$(mktemp -d "${TMPDIR:-/tmp}/biometric-tests.XXXXXX")
echo "Biometric test artifacts: $run"
TEST_RUNNER_BIOMETRIC_TEST_STATE="$state" xcodebuild \
    -project widgets.xcodeproj -scheme widgets -configuration Debug \
    -destination "platform=iOS Simulator,id=$simulator" \
    -derivedDataPath "$run/DerivedData" \
    -parallel-testing-enabled NO -collect-test-diagnostics never \
    -only-testing:widgetsTests/BiometricStorageTests \
    -resultBundlePath "$run/results.xcresult" test > "$run/test.log" 2>&1

tail -n 25 "$run/test.log"
