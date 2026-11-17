import ModularArithmetic
import Testing
@testable import Privacy

struct HashChainTests {
    @Test(arguments: try HashChainVectors.load().left4)
    func `Left chains match the published vectors`(_ vector: NonzeroHashChainVectors.Chain) throws {
        let elements = try vector.inputs.map { try Poseidon.Element(hex: $0) }

        #expect(HashChain.left4(elements).bigEndianBytes == (try fixtureBytes(vector.output)))
    }

    @Test(arguments: try HashChainVectors.load().right4)
    func `Right chains match the published vectors`(_ vector: NonzeroHashChainVectors.Chain) throws {
        let elements = try vector.inputs.map { try Poseidon.Element(hex: $0) }

        #expect(HashChain.right4(elements).bigEndianBytes == (try fixtureBytes(vector.output)))
    }

    @Test(arguments: 1...4)
    func `Binary right chains match the published chains of unused slots`(count: Int) throws {
        let unusedSlot = Poseidon.hash(.zero, .zero, .zero)
        let expected = try HashChainVectors.load().treeSlots.zeroSuffixChains[count - 1]

        #expect(HashChain.right(Array(repeating: unusedSlot, count: count)).bigEndianBytes == (try fixtureBytes(expected)))
    }

    @Test(arguments: [
        (0, "0000000000000000000000000000000000000000000000000000000000000000"),
        (1, "0532fd436e19c70e51209694d9c215250937921b8b79060488c1206db73e9946"),
        (16, "1a323c8c2b0e9395a3705dd8b4d8cee34f8eebd5fef167237a2a06eab6a87019"),
    ] as [(Int, String)])
    func `Chains of zeros match their values`(groups: Int, expected: String) throws {
        #expect(HashChain.zeroSuffix(groups: groups).bigEndianBytes == (try fixtureBytes(expected)))
    }
}
