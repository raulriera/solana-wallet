import ModularArithmetic
import Testing
@testable import Privacy

struct InputFlagsTests {
    @Test(arguments: try PublicInputVectors.load().inputFlags.filter(\.allowsDummyInputs))
    func `Flags match the published vectors`(_ vector: PublicInputVectors.Flags) throws {
        #expect(InputFlags.pack(treeIndexes: vector.treeIndexes).bigEndianBytes == (try fixtureBytes(vector.inputFlags)))
    }
}
