# UI tests

The `widgets` scheme's `UI` test plan runs these tests; see the shared
[testing rules](../../../references/testing.md) for how and when to run it.

## Setup and reset

- The scheme's Test pre-action runs [prepare-simulator.sh](Support/prepare-simulator.sh), which enables
  biometrics on the selected simulator unless `TEST_RUNNER_BIOMETRIC_TEST_STATE` is set for the
  biometric-tests skill.
- `OnboardingApp.launch()` sets `UI_TEST_RESET=1` for the first launch of each scenario. Before
  service construction, the Debug simulator app deletes its persistent and ephemeral directories,
  its recovery, provider, and private-balance Keychain records, and its preferences. This erases the
  simulator's saved wallets, contacts, token lists, and appearance settings; use only disposable,
  unfunded data.
- `relaunch()` omits the flag so startup restores records saved through the UI.

## Fixtures

- Import tests use a public BIP-39 fixture; the Security test imports it, then opens its backup in
  Settings. Create tests generate disposable, unfunded wallets.
- Onboarding uses the app's mainnet discovery client and submits no transactions; import completion
  requires a successful scan, even when it finds no funded account. Completion tests open the wallet
  on Solana's public RPC without a key; the provider rejection test uses a dummy Helius key.
- The token test chooses Helius with `HELIUS_API_KEY` from ignored local configuration, pastes BONK's
  public mint address into a new wallet's portfolio, then removes the token.
- The contacts tests paste a public address into a new wallet's Contacts tab.
- The token and contacts tests leave their address on the simulator clipboard, which can sync to the Mac.
- The network test switches a new wallet's window to Devnet, which reads Solana's public devnet RPC.
