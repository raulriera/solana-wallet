# Vault

Device-only Keychain storage for wallet recovery phrases, unlocked with biometrics or the device passcode.

## Recovery reads

Each recovery read authenticates the person on its own. Inside `withSharedAuthentication`, the first read authenticates and later reads reuse that authentication until the operation ends.

```mermaid
sequenceDiagram
    participant Caller
    participant Store as KeychainStore
    participant Keychain
    participant Auth as Face ID or passcode
    Note over Caller,Auth: Each read authenticates on its own
    Caller->>Store: Read the recovery
    Store->>Keychain: Read the item with a new context
    Keychain->>Auth: Ask the person
    Auth-->>Keychain: The person is verified
    Keychain-->>Store: The recovery
    Store->>Store: End the context
    Store-->>Caller: The recovery
    Note over Caller,Auth: Several reads share one authentication
    Caller->>Store: Start a shared authentication
    Caller->>Store: First read
    Store->>Keychain: Read the item with the shared context
    Keychain->>Auth: Ask the person
    Auth-->>Keychain: The person is verified
    Keychain-->>Store: The recovery
    Store-->>Caller: The recovery
    Caller->>Store: Later read
    Store->>Keychain: Read the item with the shared context
    Keychain-->>Store: The recovery, reusing the authentication
    Store-->>Caller: The recovery
    Caller->>Store: End the operation
    Store->>Store: End the shared context
```

## Usage

Add `NSFaceIDUsageDescription` to the app's Info.plist.

```swift
import Vault
import Wallet

let store: any RecoveryStoring = KeychainStore(service: "com.example.wallet.recovery")
try await store.save(Recovery(phrase: phrase, passphrase: passphrase), for: recoveryID)

let restored = try await store.recovery(for: recoveryID, reason: "Unlock this wallet")
```
