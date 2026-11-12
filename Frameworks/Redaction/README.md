# Redaction

Keeps secret values out of `print`, `dump`, string interpolation, logs, and the debugger. A type that adopts `Redacted` describes itself by its type name and reflects no stored properties.

## Usage

```swift
import Redaction

struct APIKey: Redacted {
    let value: String
}

print(APIKey(value: "fixture-key"))
// APIKey
```

To show a different name, such as one that includes an enclosing type, implement `description`. The debug description and dumps use it too.
