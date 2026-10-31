# Encoding

Base58 encoding and decoding for Solana addresses, blockhashes, and signatures, a bounds-checked byte reader, a strict CBOR decoder with a deterministic encoder, and a DER decoder.

## Usage

```swift
import Encoding

let encoded = Base58.encode([0, 1]) // "12"
let decoded = Base58.decode(encoded, byteCount: 2) // [0, 1]

let item = try CBOR(decoding: [0x82, 0x01, 0x02]) // .array([.integer(1), .integer(2)])
let bytes = item.encoded // [0x82, 0x01, 0x02]

let value = try DER(decoding: [0x30, 0x03, 0x02, 0x01, 0x05]) // a SEQUENCE that holds INTEGER 5
```
