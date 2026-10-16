# ModularArithmetic

Arithmetic in prime fields with moduli between 2^64 and 2^256. Elements are four 64-bit limbs in Montgomery form, built on the Swift standard library only.

## Fields

| Field | Modulus | Source |
| --- | --- | --- |
| [`BN254ScalarField`](Sources/Fields/BN254ScalarField.swift) | r = `0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001` | [EIP-197](https://eips.ethereum.org/EIPS/eip-197) |
| [`BN254BaseField`](Sources/Fields/BN254BaseField.swift) | p = `0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47` | [EIP-196](https://eips.ethereum.org/EIPS/eip-196) |
| [`P256ScalarField`](Sources/Fields/P256ScalarField.swift) | n = `0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551` | [SEC 2](https://www.secg.org/sec2-v2.pdf), FIPS 186-5 |

The list is closed: only this module can create a [`Modulus`](Sources/Montgomery/Modulus.swift), so each field is tested here.

## Usage

```swift
import ModularArithmetic

typealias Scalar = FieldElement<BN254ScalarField>

let half = Scalar(2).inverse()
let one = half + half // Scalar.one
let bytes = (half * Scalar(4)).bigEndianBytes // 2, as 32 big-endian bytes
```

[`FieldElement`](Sources/Fields/FieldElement.swift) supports `+`, `-`, negation, `*`, and `inverse()`. The inverse of zero is zero.

## Bytes

- `FieldElement(bigEndianBytes:)` accepts exactly 32 big-endian bytes below the modulus, and returns `nil` otherwise.
- `FieldElement(reducing:)` accepts any 32-byte value and reduces it modulo the modulus. Other lengths are a precondition failure.
- `bigEndianBytes` returns the canonical 32-byte encoding.

## Side channels

Field operations have no branches or memory indices that depend on values, equality compares every limb, and inversion raises to the public exponent m - 2. Only `FieldElement(bigEndianBytes:)` branches on a value, to reject it. Swift doesn't guarantee constant-time code, so a different compiler can produce different instructions. The module doesn't enable the processor's data-independent timing mode (DIT), so instruction timing can still vary with values. Values aren't guaranteed to be erased from memory; descriptions and reflection omit them.
