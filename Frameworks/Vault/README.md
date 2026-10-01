# Vault

Device-only Keychain storage for wallet recovery material, protected by the device's current biometric enrollment.

## Example Usage

Inject [`RecoveryStoring`](Sources/Storage/RecoveryStoring.swift), implemented by `KeychainStore`. Choose a stable service identifier, retain the UUID used to identify the shared recovery, and provide `NSFaceIDUsageDescription` in the calling app's Info.plist.

Given a validated `RecoveryPhrase`, its original passphrase, and a recovery UUID:

```swift
import Vault
import Wallet

let store: any RecoveryStoring = KeychainStore(service: "com.example.wallet.recovery")
let recovery = Recovery(phrase: phrase, passphrase: passphrase)
try await store.save(recovery, for: recoveryID)

let restored = try await store.recovery(
    for: recoveryID,
    reason: "Unlock this wallet"
)
```

- `save(_:for:)` inserts a new record and rejects an existing wallet ID.
- `recovery(for:reason:)` uses a fresh authentication context. Supply a localized, nonsecret reason for the system prompt. Failed reads preserve the stored record.
- `deleteRecovery(for:)` removes that shared recovery record; a missing record is a no-op.
- [`KeychainStore.Failure`](Sources/Storage/KeychainStore.swift) distinguishes duplicate records, unavailable recovery or protection, authentication failures, invalid recovery, and Keychain errors.

## Protection

Storage requires a device passcode and enrolled biometrics. Records use `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` and `biometryCurrentSet`, with no device-passcode fallback, iCloud synchronization, or migration to another device. Changing biometric enrollment invalidates access.

Cancellation dismisses pending authentication; it does not undo completed writes or deletions. Blocking Keychain operations run on a private queue outside the main actor.

The caller owns backup and recovery workflows. Restoring an account requires the original phrase, any BIP-39 passphrase, and derivation path; biometrics do not replace that backup. Recovery descriptions omit secrets, but explicit properties expose them and do not guarantee memory erasure.

Simulator Keychain reads can succeed without a prompt. Biometric enforcement and enrollment-change invalidation require physical-device verification.
