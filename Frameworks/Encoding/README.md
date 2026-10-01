# Encoding

Shared Base58 encoding and decoding for Solana addresses, blockhashes, and signatures. Uses the case-sensitive Bitcoin alphabet without a checksum.

## Usage

```swift
import Encoding

let encoded = Base58.encode([0, 1]) // "12"
let decoded = Base58.decode(encoded, byteCount: 2) // [0, 1]
```

[`Base58`](Sources/Base58/Base58.swift) preserves leading zero bytes as `1` characters. Decoding requires an exact byte count and returns `nil` for malformed text or a different decoded length. It accepts ASCII only, without trimming whitespace or normalizing characters.

The codec is synchronous and stateless. It validates encoding, not account existence, ownership, or signature validity.
