import ModularArithmetic
import Testing
@testable import Privacy

struct PoseidonTests {
    @Test(arguments: try PoseidonParity.load().vectors)
    func `Hashes match the published vectors`(_ vector: PoseidonParity.Vector) throws {
        let inputs = try vector.inputsBytes.map(Poseidon.Element.init(hex:))

        #expect(try Poseidon.hash(inputs).bigEndianBytes == fixtureBytes(vector.expectedBytes))
    }

    @Test(arguments: [0, 13])
    func `Hashing rejects no inputs and more than twelve inputs`(count: Int) {
        #expect(throws: Poseidon.ValidationError.unsupportedInputCount) {
            try Poseidon.hash(Array(repeating: .zero, count: count))
        }
    }
}
