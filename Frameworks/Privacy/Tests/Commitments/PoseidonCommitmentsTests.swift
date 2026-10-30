import ModularArithmetic
@testable import Privacy
import Testing

struct PoseidonCommitmentsTests {
    @Test
    func `Fixed-input hashes equal the throwing hash`() throws {
        let inputs = (1...12).map { Poseidon.Element(UInt64($0)) }

        #expect(Poseidon.hash(inputs[0]) == (try Poseidon.hash([inputs[0]])))
        #expect(
            Poseidon.hash(
                inputs[0], inputs[1], inputs[2], inputs[3], inputs[4], inputs[5],
                inputs[6], inputs[7], inputs[8], inputs[9], inputs[10], inputs[11]
            ) == (try Poseidon.hash(inputs))
        )
    }
}
