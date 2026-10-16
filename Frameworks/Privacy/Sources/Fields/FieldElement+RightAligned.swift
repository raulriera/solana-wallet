import Foundation
import ModularArithmetic

extension FieldElement {
    /// Reduces at most 32 big-endian bytes, right-aligned in a 32-byte value, modulo the field's
    /// modulus.
    ///
    /// The bytes are the value's lowest-order bytes, and zeros fill the rest. The 32-byte buffer
    /// that holds the value is zeroed before it's released, so a secret, such as a nullifier secret
    /// or key material, leaves no copy in it. The returned element isn't erased.
    ///
    /// - Parameter bytes: At most 32 big-endian bytes.
    /// - Precondition: `bytes` contains at most 32 bytes.
    init(reducingRightAligned bytes: some ContiguousBytes) {
        var value = [UInt8](repeating: 0, count: 32)
        defer { value.erase() }
        bytes.withUnsafeBytes { source in
            precondition(source.count <= 32, "A field element holds at most 32 bytes.")
            value.withUnsafeMutableBytes { target in
                UnsafeMutableRawBufferPointer(rebasing: target[(target.count - source.count)...]).copyMemory(from: source)
            }
        }
        self.init(reducing: value)
    }
}
