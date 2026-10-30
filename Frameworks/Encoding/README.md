# Encoding

Base58 encoding and decoding for Solana addresses, blockhashes, and signatures.

## Usage

```swift
import Encoding

let encoded = Base58.encode([0, 1]) // "12"
let decoded = Base58.decode(encoded, byteCount: 2) // [0, 1]
```
