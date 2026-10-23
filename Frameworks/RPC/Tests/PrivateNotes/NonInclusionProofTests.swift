import Testing
import RPC

/// Verifies the length checks of non-inclusion proofs.
struct NonInclusionProofTests {
    /// A 32-byte value whose bytes all equal `byte`.
    /// - Parameter byte: The repeated byte.
    /// - Returns: The value.
    private static func value(_ byte: UInt8) -> [UInt8] { Array(repeating: byte, count: 32) }

    /// Verifies a proof with 32-byte values and 40 siblings keeps its values.
    ///
    /// - Throws: A validation error, which these lengths don't produce.
    @Test
    func `Proofs of the nullifier tree's height keep their values`() throws {
        let path = (1...40).map { Self.value(UInt8($0)) }

        let proof = try NonInclusionProof(nullifier: Self.value(0x50), lowElement: Self.value(0x40), lowElementIndex: 3,
                                          highElement: Self.value(0x60), path: path, root: Self.value(0xbb), rootIndex: 99)

        #expect(proof.path == path)
        #expect(proof.lowElement == Self.value(0x40))
        #expect(proof.highElement == Self.value(0x60))
        #expect(proof.lowElementIndex == 3)
        #expect(proof.rootIndex == 99)
    }

    /// Verifies a proof with a path of another height, or a value of another length, is refused.
    ///
    /// - Parameters:
    ///   - values: The nullifier, low element, high element, and root.
    ///   - path: The siblings.
    @Test(arguments: [
        ([value(1), value(2), value(3), value(4)], Array(repeating: value(5), count: 32)),
        ([value(1), value(2), value(3), value(4)], Array(repeating: value(5), count: 41)),
        ([[1], value(2), value(3), value(4)], Array(repeating: value(5), count: 40)),
        ([value(1), [2], value(3), value(4)], Array(repeating: value(5), count: 40)),
        ([value(1), value(2), Array(repeating: 3, count: 33), value(4)], Array(repeating: value(5), count: 40)),
        ([value(1), value(2), value(3), []], Array(repeating: value(5), count: 40)),
        ([value(1), value(2), value(3), value(4)], Array(repeating: value(5), count: 39) + [[5]]),
    ] as [([[UInt8]], [[UInt8]])])
    func `Proofs of another shape are refused`(values: [[UInt8]], path: [[UInt8]]) {
        #expect(throws: PrivateNoteError.invalidProof) {
            try NonInclusionProof(nullifier: values[0], lowElement: values[1], lowElementIndex: 0, highElement: values[2],
                                  path: path, root: values[3], rootIndex: 0)
        }
    }
}
