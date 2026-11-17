# Redaction

Keeps secret values out of `print`, `dump`, string interpolation, logs, and the debugger, and zeroes secret byte arrays.

## Usage

```swift
import Redaction

struct APIKey: Redacted {
    let value: String
}

print(APIKey(value: "fixture-key"))
// APIKey
```

To show a different name, such as one that includes an enclosing type, implement `description`.

To zero a secret byte array in place:

```swift
var seed: [UInt8] = [0x01, 0x02]
seed.erase()
```
