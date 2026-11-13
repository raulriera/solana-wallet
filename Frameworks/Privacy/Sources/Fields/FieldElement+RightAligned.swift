import Foundation
import ModularArithmetic
import Redaction

extension FieldElement {
    /// Creates an element by reducing at most 32 right-aligned big-endian bytes modulo the field's modulus.
    ///
    /// - Parameter bytes: At most 32 big-endian bytes.
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
