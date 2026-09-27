# Encoding

- One `Base58` codec owns the alphabet, encoding, and strict ASCII decoding. Wallet and Transactions share it.
- `decode(_:byteCount:)` requires the caller's exact decoded width and bounds decoding to that allocation. The codec has no built-in Solana width; Transactions supplies 32.
- Codec tests cover known values, leading zeros, forbidden characters, Unicode lookalikes, and width failures. Consumer tests retain wallet address vectors and V1 wire fixtures.
- `Encoding` follows the app's [automatic library merging](linking.md): dynamic in Debug, merged once into the Release app alongside its consumers. This avoids duplicate codec code and debug information from statically linking it into multiple frameworks.

Source: [Apple mergeable libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries.md).
