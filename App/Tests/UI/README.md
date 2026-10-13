# UI tests

The `widgets` scheme's `UI` test plan runs these tests, without parallel clones. Select an
existing regular iPhone simulator, choose Product > Test Plan > UI, and use Product > Test or the
Test navigator. Only the user runs these tests, on request.

The scheme's Test pre-action enables biometrics on the selected simulator before every test run,
unless `TEST_RUNNER_BIOMETRIC_TEST_STATE` is set for the biometric-tests skill.
`OnboardingApp.launch()` sets `UI_TEST_RESET=1` for the first launch of each scenario.
Before service construction, the Debug simulator app deletes its real Accounts and
Themes directories, recovery and provider Keychain records, and preferences. This deletes saved
simulator wallets and appearance settings; use only disposable, unfunded data.
`relaunch()` omits the flag so startup restores records saved through the UI.

Import tests use a public BIP-39 fixture; the Security test imports it, then opens its backup in Settings. Create tests generate real disposable,
unfunded wallets whose words may appear in test artifacts. Both exercise production
services and normal storage locations.

Onboarding tests use the app's normal mainnet discovery client and submit no transactions.
Import completion requires a successful network scan, including when no funded account is found.
Completion tests open the wallet on Solana's public RPC without a key. The token test chooses Helius with
`HELIUS_API_KEY` from ignored local configuration; the rejection test uses a dummy key.
The token test pastes BONK's public mint address into a new wallet's portfolio, then removes the token; it leaves the address on the simulator clipboard, which can sync to the Mac.

Follow the shared [testing rules](../../../references/testing.md).
