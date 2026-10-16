import ModularArithmetic
@testable import Privacy
import Testing

/// Verifies the packed input flags against zolana's published vectors.
struct InputFlagsTests {
    /// Verifies every published vector that allows padding inputs, from 1 to 49 inputs, including
    /// a value that crosses 128 bits.
    ///
    /// - Parameter vector: A published packing.
    @Test(arguments: try PublicInputVectors.load().inputFlags.filter(\.allowsDummyInputs))
    func `Flags match the published vectors`(_ vector: PublicInputVectors.Flags) throws {
        #expect(InputFlags.pack(treeIndexes: vector.treeIndexes).bigEndianBytes == (try fixtureBytes(vector.inputFlags)))
    }

    /// Verifies that the published vectors left out are the three that forbid padding inputs,
    /// which this module never proves.
    @Test
    func `Three published vectors forbid padding inputs`() throws {
        let names = try PublicInputVectors.load().inputFlags.filter { !$0.allowsDummyInputs }.map(\.name)

        #expect(names == ["one_input_policy_off", "two_inputs_second_tree_policy_off", "forty_nine_inputs_last_slot"])
    }
}
