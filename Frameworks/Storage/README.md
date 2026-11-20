# Storage

Values saved on the device, one value per file or Keychain item, behind one `ValueStoring` protocol.

## Usage

```swift
import Storage

let bookmarks: any ValueStoring<[String]> = FileItem(
    url: .applicationSupportDirectory.appending(path: "Bookmarks/list.json"),
    coding: .json([String].self, version: 1, unusable: .replaced(with: []))
)
try await bookmarks.update { $0 = ($0 ?? []) + ["https://example.com"] }

let key: any ValueStoring<String> = KeychainItem(service: "com.example.app.keys", account: "api-key", coding: .utf8)
try await key.save("fixture-key")
let saved = try await key.load()
```
