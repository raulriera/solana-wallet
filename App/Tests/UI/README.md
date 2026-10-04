# UI tests

Use the shared `widgetsUITests` scheme, an existing regular iPhone simulator, and
Product > Test with parallel execution disabled. Only the user runs these tests;
agents may compile them without invoking the Test action or its setup.

The scheme's Test pre-action enables biometrics on the selected simulator.
`OnboardingApp.launch()` sets `UI_TEST_RESET=1` for the first launch of each scenario.
Before service construction, the Debug simulator app deletes its real Accounts and
Themes directories, recovery Keychain records, and preferences. This deletes saved
simulator wallets and appearance settings; use only disposable, unfunded data.
`relaunch()` omits the flag so startup restores records saved through the UI.

Import tests use a public BIP-39 fixture. Create tests generate real disposable,
unfunded wallets whose words may appear in test artifacts. Both exercise production
services and normal storage locations.

The test driver keeps `UI_TEST_NETWORK=devnet` across launches. Debug simulator builds
use the same discovery and RPC services on devnet; ordinary app launches use mainnet.
Import completion requires a successful network scan, including when no funded account is found.

Follow the shared [testing rules](../../../references/testing.md).
