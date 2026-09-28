---
name: biometric-tests
description: Run this project's real Vault tests with or without simulator biometric enrollment, or diagnose protectionUnavailable. Mock-based Vault tests need no simulator setup.
---

# Biometric tests

1. Discover existing devices with `xcrun simctl list devices available`; select a
   compatible runtime and biometric type by UUID. Never hardcode local identities.
2. Use an isolated, unfunded simulator for enrollment changes. Never reset, clone,
   or change enrollment on a device holding retained wallet recovery.
3. Run [scripts/test.sh](scripts/test.sh) from the repository root:

   ```sh
   bash .agents/skills/biometric-tests/scripts/test.sh <UUID> unenrolled
   bash .agents/skills/biometric-tests/scripts/test.sh <UUID> enrolled
   ```

The script boots the selected device if needed, reports enrollment, runs the
selected real Keychain check without parallel simulator clones, and prints its
log/result location. It **does not change enrollment**. On an isolated booted
device, use `xcrun devicectl device settings biometrics --device <UUID> --enable`
(or `--disable`) before the corresponding run. Restore its initial state afterward.

For a pending authentication prompt, use
`xcrun devicectl device simulate biometrics --device <UUID> --success` (or `--failure`).
A nonmatch may leave the prompt open; inspect the result before sending another.

Require the selected test to execute and pass; the opposite mode is skipped.
Missing enrollment is not unsupported hardware. Simulator Keychain reads can
succeed without prompting, so these checks do not prove hardware enforcement.
Keep the process handle and inspect its log before retrying after a tool timeout.
Funded tests follow [testing.md](../../../references/testing.md).
