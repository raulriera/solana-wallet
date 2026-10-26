# Storage

Values saved on this device, one value per file or Keychain item, behind one `ValueStoring` protocol.

## Usage

```swift
import Storage

let settings: any ValueStoring<[String]> = FileItem(
    url: .applicationSupportDirectory.appending(path: "Bookmarks/list.json"),
    coding: .json([String].self)
)
try await settings.update { $0 = ($0 ?? []) + ["https://example.com"] }

let key: any ValueStoring<String> = KeychainItem(service: "com.example.app.keys", account: "api-key", coding: .utf8)
try await key.save("fixture-key")
let saved = try await key.load()
```

- [`ValueStoring`](Sources/Items/ValueStoring.swift) reads, saves, deletes, and changes one value. `load()` returns `nil` before a value is saved, and deleting a missing value succeeds.
- `update(_:)` reads, changes, and saves in one step, so changes made at the same time don't overwrite each other. Setting the value to `nil` deletes it; an unchanged value isn't saved again.
- [`ValueCoding`](Sources/Coding/ValueCoding.swift) converts values to and from bytes. Use `.json(_:)` for `Codable` values and `.utf8` for text.
- A value whose bytes don't decode back to an equal value isn't saved. Bytes that don't decode are reported as unreadable, never deleted or replaced.

## Protection

- `FileItem` writes atomically with complete file protection by default, so its file is readable only while the device is unlocked. Pass `protection:`, such as `.completeUntilFirstUserAuthentication`, for a file that background work saves while the device is locked.
- `KeychainItem` keeps a generic password in the data protection Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. It never synchronizes through iCloud and needs no biometric authentication. The calling process needs a Keychain access group; without one, such as in a test bundle without a host app, every call throws `KeychainItemError.keychain(status:)` with `errSecMissingEntitlement`.
- [`FileItemError`](Sources/Items/FileItemError.swift) and [`KeychainItemError`](Sources/Items/KeychainItemError.swift) never contain the stored value.

Blocking file and Keychain work runs on one serial queue per kind, outside Swift's cooperative executor. Cancellation is checked before the work starts; it doesn't roll back a completed write.
