# Attestation

Verification of AWS Nitro Enclaves attestation documents against a caller's policy.

## Usage

```swift
import Attestation
import CryptoKit

let policy = NitroPolicy(
    measurements: [NitroPolicy.Measurement(pcr0: pcr0, pcr1: pcr1, pcr2: pcr2)],
    publicKey: nil,
    maximumAge: 600
)
let key = try Curve25519.KeyAgreement.PublicKey(
    rawRepresentation: claimedKey,
    attestedBy: document,
    nonce: nonce,
    userData: userData,
    policy: policy,
    at: .now
)
```
