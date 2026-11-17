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

## Security

The app turns on Apple's [Enhanced Security](https://developer.apple.com/documentation/xcode/enabling-enhanced-security-for-your-app) protections:

- Pointer authentication and hardware-checked pointer arithmetic.
- Hardware memory tagging, a hardened heap, and read-only dyld data.
- Platform restrictions.

Recovery phrases stay in Keychain items on the device. Reading them needs Face ID, Touch ID, or the device passcode. They never sync to iCloud and are not in backups.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Tests

⌘U runs the Unit test plan, which never uses the network. The UI test plan uses live providers; see [UI tests](App/Tests/UI/README.md) for its setup.

## License

MIT. See [LICENSE.md](LICENSE.md).
