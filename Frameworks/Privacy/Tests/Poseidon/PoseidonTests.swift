import ModularArithmetic
@testable import Privacy
import Testing

/// Verifies Poseidon hashes against zolana's published parity fixture.
struct PoseidonTests {
    /// Verifies hashes against every published vector for one to twelve inputs.
    ///
    /// The vectors include zeros, ones, repeated bytes, r - 1 in every, the first, or the last
    /// position, counters, and pseudorandom values.
    ///
    /// - Parameter vector: Published canonical inputs and their hash.
    @Test(arguments: try PoseidonParity.load().vectors)
    func `Hashes match the published vectors`(_ vector: PoseidonParity.Vector) throws {
        let inputs = try vector.inputsBytes.map { try #require(Poseidon.Element(bigEndianBytes: fixtureBytes($0))) }

        #expect(try Poseidon.hash(inputs).bigEndianBytes == fixtureBytes(vector.expectedBytes))
    }

    /// Verifies that hashing rejects input counts outside one to twelve.
    ///
    /// No inputs and thirteen inputs would need widths 1 and 14, which have no parameters.
    ///
    /// - Parameter count: An unsupported number of inputs.
    @Test(arguments: [0, 13])
    func `Hashing rejects no inputs and more than twelve inputs`(count: Int) {
        #expect(throws: Poseidon.ValidationError.unsupportedInputCount) {
            try Poseidon.hash(Array(repeating: .zero, count: count))
        }
    }
}
