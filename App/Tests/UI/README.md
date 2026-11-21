# UI tests

Run the `UI` test plan of the `widgets` scheme on an iOS Simulator with a network connection.

## Setup

1. Copy `Configuration/Local.example.xcconfig` to `Configuration/Local.xcconfig`.
2. Set `HELIUS_API_KEY` to your Helius API key.
3. Set `DEVNET_TEST_SEED` to the recovery phrase of a wallet with devnet SOL.

Use a simulator without app data you want to keep: the tests erase it.

Test results (`.xcresult` bundles) record your API key and recovery phrase. Do not share them or attach them to issues.
