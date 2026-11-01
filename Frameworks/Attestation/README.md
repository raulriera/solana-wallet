# Attestation

Verification of AWS Nitro Enclaves attestation documents for the Solana Rings encrypted prover: the document's COSE_Sign1 ES384 signature and its certificate chain to the pinned AWS Nitro Enclaves root.

## Usage

```swift
import Attestation
import CryptoKit

let key = try Curve25519.KeyAgreement.PublicKey(
    rawRepresentation: hpkePublicKey,
    attestedBy: document,
    nonce: nonce,
    policy: .devnet,
    at: .now
)
```
