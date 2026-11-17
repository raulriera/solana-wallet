# UI tests

Run the `UI` test plan of the `widgets` scheme on an iOS Simulator.

## Setup

1. Copy `Configuration/Local.example.xcconfig` to `Configuration/Local.xcconfig`.
2. Set `HELIUS_API_KEY` to your Helius API key.
3. Set `DEVNET_TEST_SEED` to the recovery phrase of a wallet with devnet SOL.

The tests need a network connection: they read Solana mainnet and devnet through public RPC and Helius.

## Simulator data

Each scenario erases the app's wallets, contacts, token lists, Keychain items, and settings on the simulator, so use a simulator without data you want to keep. The tests enable Face ID on the simulator and leave addresses on its clipboard, which can sync to your Mac.
