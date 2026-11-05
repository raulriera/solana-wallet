# Solana Wallet

A truly open and decentralized Solana wallet for iPhone and iPad. The app connects directly to Solana RPC providers, with no app backend or proxy. Recovery phrases and provider API keys stay on the device.

## Requirements

- Xcode 27 or later
- An iOS 27.1 or later simulator or device

## Run the app

1. Clone the repository:

   ```bash
   git clone git@github.com:raulriera/solana-wallet.git
   ```

2. Open `widgets.xcodeproj` in Xcode.
3. Choose the `widgets` scheme and an iPhone or iPad simulator.
4. Press ⌘R.

The app uses Solana's public RPC by default, so it needs no API key. To use Helius or a custom RPC URL, open Settings > RPC.

To run on a device, choose your team and a unique bundle identifier in the `widgets` target's Signing & Capabilities settings.

## Tests

⌘U runs the Unit test plan, which never uses the network.

The Integration and [UI](App/Tests/UI/README.md) test plans use live providers. They read credentials from `Configuration/Local.xcconfig`, which Git ignores:

1. Copy `Configuration/Local.example.xcconfig` to `Configuration/Local.xcconfig`.
2. Set `HELIUS_API_KEY` to your Helius API key.
3. Set `DEVNET_TEST_SEED` to the recovery phrase of a funded devnet wallet. Tests that move funds send from its first account to its second.

## License

MIT. See [LICENSE.md](LICENSE.md).
