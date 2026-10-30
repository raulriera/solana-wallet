# ModularArithmetic

Arithmetic in the BN254 scalar, BN254 base, and P-256 scalar prime fields, built on the Swift standard library only.

## Usage

```swift
import ModularArithmetic

typealias Scalar = FieldElement<BN254ScalarField>

let half = Scalar(2).inverse()
let one = half + half // Scalar.one
let bytes = (half * Scalar(4)).bigEndianBytes // 2, as 32 big-endian bytes
```
