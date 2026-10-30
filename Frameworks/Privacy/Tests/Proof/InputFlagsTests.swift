import ModularArithmetic
@testable import Privacy
import Testing

struct InputFlagsTests {
    @Test(arguments: try PublicInputVectors.load().inputFlags.filter(\.allowsDummyInputs))
    func `Flags match the published vectors`(_ vector: PublicInputVectors.Flags) throws {
        #expect(InputFlags.pack(treeIndexes: vector.treeIndexes).bigEndianBytes == (try fixtureBytes(vector.inputFlags)))
    }

    @Test
    func `Three published vectors forbid padding inputs`() throws {
        let names = try PublicInputVectors.load().inputFlags.filter { !$0.allowsDummyInputs }.map(\.name)

        #expect(names == ["one_input_policy_off", "two_inputs_second_tree_policy_off", "forty_nine_inputs_last_slot"])
    }
}
