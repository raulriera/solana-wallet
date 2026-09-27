# Wallet

- First milestone: local recovery phrase creation/import and Solana address derivation.
- New phrases default to 12 English BIP-39 words. All five standard lengths are supported.
- `Wallet` implements `WalletProviding`; `RecoveryPhrase` validates imports. The service retains no secrets and makes no network or persistence calls.
- Address derivation uses BIP-39 passphrases and hardened SLIP-0010 Ed25519 paths, defaulting to `m/44'/501'/0'/0'`. Import requires the original path and passphrase; account discovery isn't implemented.
- CryptoKit supplies SHA-256, HMAC-SHA512, and Ed25519. Security supplies secure randomness. Standard word-list data is included locally; no third-party runtime dependency.
- Verification uses published vectors and independently derived addresses. Only public test phrases are fixtures.
- Secure persistence, biometric access, and transaction signing remain later milestones. UI remains last.

Sources: [BIP-39](https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki), [SLIP-0010](https://github.com/satoshilabs/slips/blob/master/slip-0010.md), [Phantom paths](https://help.phantom.com/articles/12988493966227), [CryptoKit](https://developer.apple.com/documentation/cryptokit/curve25519/signing.md).
