# Wallet

- First milestone: local recovery phrase creation/import and Solana address derivation.
- New phrases default to 12 English BIP-39 words. All five standard lengths are supported.
- `Wallet` implements `WalletProviding`; `RecoveryPhrase` validates imports. The service retains no secrets and makes no network or persistence calls.
- Address derivation uses BIP-39 passphrases and hardened SLIP-0010 Ed25519 paths, defaulting to `m/44'/501'/0'/0'`. Import requires the original path and passphrase; account discovery isn't implemented.
- CryptoKit supplies SHA-256, HMAC-SHA512, and Ed25519. Security supplies secure randomness. Standard word-list data is included locally; no third-party runtime dependency.
- Verification uses published vectors and independently derived addresses. Only public test phrases are fixtures.
- Secure persistence, biometric access, and transaction signing remain later milestones. UI remains last.
- Approved storage access: current biometric enrollment only, with no device-passcode fallback. Enrollment changes require recovery from the backup phrase and any original BIP-39 passphrase.
- Approved storage boundary: a separate `Vault` framework exposes `RecoveryStoring`, implemented by `KeychainStore`, for saving, retrieving, and deleting recovery material.
- Storage is device-only: no iCloud synchronization or cloud backup of recovery material. Use non-synchronizing Keychain items with `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` and `biometryCurrentSet`.
- Onboarding and backup guidance must explain that the recovery phrase is the only recovery method; neither the app nor iCloud can restore it. Losing access to the device or its enrolled biometrics requires the backup. Any original BIP-39 passphrase and derivation path are also required; biometrics do not replace the backup.

Sources: [BIP-39](https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki), [SLIP-0010](https://github.com/satoshilabs/slips/blob/master/slip-0010.md), [Phantom paths](https://help.phantom.com/articles/12988493966227), [CryptoKit](https://developer.apple.com/documentation/cryptokit/curve25519/signing.md).
