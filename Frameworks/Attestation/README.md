# Attestation

Verification of AWS Nitro Enclaves attestation documents. A document passes when:

- Its COSE_Sign1 ES384 signature verifies with a certificate chain to the pinned AWS Nitro Enclaves root.
- Its SHA-384 PCR0 through PCR2 match one of the policy's measurements, and PCR0 isn't a debug enclave's.
- It holds the client's nonce, the claimed public key, and the caller's user data.

A policy can also pin the one public key it allows, and its `maximumAge` says how long a caller may reuse a passed attestation.

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
