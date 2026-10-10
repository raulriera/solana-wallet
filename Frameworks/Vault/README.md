# Vault

Device-only Keychain storage for wallet recovery material that opens with biometrics or the device passcode.

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
- `deleteAllRecovery()` removes every record in the service, including records no wallet uses. Call it only for an explicit app reset.
- [`KeychainStoreError`](Sources/Storage/KeychainStoreError.swift) distinguishes duplicate records, unavailable recovery or protection, authentication failures, invalid recovery, and Keychain errors.

## Protection

Storage requires a device passcode; biometrics are optional. Records use `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` and `userPresence`, with no iCloud synchronization or migration to another device. Biometric enrollment changes don't affect access; removing the device passcode deletes records.

Cancellation dismisses pending authentication; it does not undo completed writes or deletions. Blocking Keychain operations run on a private queue outside the main actor.

The caller owns backup and recovery workflows. Restoring an account requires the original phrase, any BIP-39 passphrase, and derivation path; device authentication does not replace that backup. Recovery descriptions omit secrets, but explicit properties expose them and do not guarantee memory erasure; the raw Keychain payload is zeroed after use on a best-effort basis.

Simulator Keychain reads can succeed without a prompt. Authentication enforcement and passcode fallback require physical-device verification.
