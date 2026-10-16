import ModularArithmetic
@testable import Privacy
import Testing

/// Verifies the chains that fold a transact proof's public inputs against zolana's published
/// vectors.
struct HashChainTests {
    /// Verifies every published left chain, from no elements to 54, and a zero in the middle.
    ///
    /// - Parameter vector: A published chain.
    @Test(arguments: try HashChainVectors.load().left4)
    func `Left chains match the published vectors`(_ vector: NonzeroHashChainVectors.Chain) throws {
        let elements = try vector.inputs.map { try Poseidon.Element(hex: $0) }

        #expect(HashChain.left4(elements).bigEndianBytes == (try fixtureBytes(vector.output)))
    }

    /// Verifies every published right chain, from no elements to 54, with zeros in the middle, at
    /// the end, and everywhere.
    ///
    /// - Parameter vector: A published chain.
    @Test(arguments: try HashChainVectors.load().right4)
    func `Right chains match the published vectors`(_ vector: NonzeroHashChainVectors.Chain) throws {
        let elements = try vector.inputs.map { try Poseidon.Element(hex: $0) }

        #expect(HashChain.right4(elements).bigEndianBytes == (try fixtureBytes(vector.output)))
    }

    /// Verifies the binary right chain against zolana's chains of 1 to 4 unused tree slots, whose
    /// hash is `Poseidon(0, 0, 0)`.
    ///
    /// - Parameter count: The number of unused slots.
    @Test(arguments: 1...4)
    func `Binary right chains match the published chains of unused slots`(count: Int) throws {
        let unusedSlot = Poseidon.hash(.zero, .zero, .zero)
        let expected = try HashChainVectors.load().treeSlots.zeroSuffixChains[count - 1]

        #expect(HashChain.right(Array(repeating: unusedSlot, count: count)).bigEndianBytes == (try fixtureBytes(expected)))
    }

    /// Verifies that the binary right chain folds from the last element, `Poseidon(a, Poseidon(b, c))`,
    /// and that an empty list chains to zero and one element to itself.
    @Test
    func `Binary right chains fold from the last element`() {
        let (a, b, c) = (Poseidon.Element(1), Poseidon.Element(2), Poseidon.Element(3))

        #expect(HashChain.right([a, b, c]) == Poseidon.hash(a, Poseidon.hash(b, c)))
        #expect(HashChain.right([a]) == a)
        #expect(HashChain.right([]) == .zero)
    }

    /// Verifies chains of zeros: none is zero, one group is an independently computed value, and 16
    /// groups are zolana's published chain of 49 zeros.
    ///
    /// - Parameters:
    ///   - groups: The number of groups after the first zero.
    ///   - expected: The chain.
    @Test(arguments: [
        (0, "0000000000000000000000000000000000000000000000000000000000000000"),
        (1, "0532fd436e19c70e51209694d9c215250937921b8b79060488c1206db73e9946"),
        (16, "1a323c8c2b0e9395a3705dd8b4d8cee34f8eebd5fef167237a2a06eab6a87019"),
    ] as [(Int, String)])
    func `Chains of zeros match their values`(groups: Int, expected: String) throws {
        #expect(HashChain.zeroSuffix(groups: groups).bigEndianBytes == (try fixtureBytes(expected)))
    }
}
