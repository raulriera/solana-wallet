# Wallet

- First milestone: local recovery phrase creation/import and Solana address derivation.
- New phrases default to 12 English BIP-39 words. All five standard lengths are supported.
- `Wallet` implements `WalletProviding`; `RecoveryPhrase` validates imports. The service retains no secrets and makes no network or persistence calls.
- Address derivation uses BIP-39 passphrases and hardened SLIP-0010 Ed25519 paths, defaulting to `m/44'/501'/0'/0'`. Import requires the original path and passphrase; account discovery isn't implemented.
- CryptoKit supplies SHA-256, HMAC-SHA512, and Ed25519. Security supplies secure randomness. Standard word-list data is included locally; no third-party runtime dependency.
- The shared [Encoding](encoding.md) framework supplies Base58 address encoding; Wallet doesn't maintain a separate codec.
- Verification uses published vectors and independently derived addresses. Only public test phrases are fixtures.
- `Vault` implements secure persistence and biometric access. Transaction signing remains a later milestone; UI remains last.
- Approved storage access: current biometric enrollment only, with no device-passcode fallback. Enrollment changes require recovery from the backup phrase and any original BIP-39 passphrase.
- Approved storage boundary: a separate `Vault` framework exposes `RecoveryStoring`, implemented by `KeychainStore`, for saving, retrieving, and deleting recovery material.
- Storage is device-only: no iCloud synchronization or cloud backup of recovery material. Use non-synchronizing Keychain items with `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` and `biometryCurrentSet`.
- Onboarding and backup guidance must explain that the recovery phrase is the only recovery method; neither the app nor iCloud can restore it. Losing access to the device or its enrolled biometrics requires the backup. Any original BIP-39 passphrase and derivation path are also required; biometrics do not replace the backup.
- `KeychainStore(service:)` saves a `Recovery` under a caller-owned UUID, rejects overwrites, retrieves it with `recovery(for:reason:)`, and removes it with `deleteRecovery(for:)`. Failed reads preserve storage. Cancellation dismisses authentication but doesn't undo completed writes or deletions.
- Offline tests verify requested storage policy, recovery, duplicate protection, failures, context invalidation on cancellation, deletion scope, and masked descriptions.
- Simulator verification (Xcode/iOS 27.1): direct Touch ID prompts and match/nonmatch events work. Protected Keychain reads returned data without authentication, reproduced with direct Apple SDK calls outside Vault. Hardware enforcement and enrollment invalidation remain unverified; do not weaken the storage policy to accommodate the simulator.

Sources: [BIP-39](https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki), [SLIP-0010](https://github.com/satoshilabs/slips/blob/master/slip-0010.md), [Phantom paths](https://help.phantom.com/articles/12988493966227), [CryptoKit](https://developer.apple.com/documentation/cryptokit/curve25519/signing.md), [Keychain biometrics](https://developer.apple.com/documentation/localauthentication/accessing-keychain-items-with-face-id-or-touch-id.md), [enrollment binding](https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/biometrycurrentset.md).
