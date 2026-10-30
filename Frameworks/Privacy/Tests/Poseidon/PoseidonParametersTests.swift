import ModularArithmetic
@testable import Privacy
import Testing

struct PoseidonParametersTests {
    @Test(arguments: try PoseidonParity.load().parameters.perArity)
    func `Generated parameters match the published partial rounds and digests`(_ published: PoseidonParity.Width) throws {
        let parameters = try #require(Poseidon.Parameters.forWidth(published.width))

        #expect(parameters.partialRounds == published.roundsPartial)
        #expect(PoseidonParity.digest(of: parameters.roundConstants.map(\.bigEndianBytes)) == (try published.roundConstantDigest))
        #expect(PoseidonParity.digest(of: parameters.matrix.joined().map(\.bigEndianBytes)) == (try published.matrixDigest))
    }

    @Test(arguments: [-1, 0, 1, 14])
    func `Widths outside 2 to 13 have no parameters`(width: Int) {
        #expect(Poseidon.Parameters.forWidth(width) == nil)
    }

    @Test(arguments: try PoseidonParity.load().parameters.perArity)
    func `Repeated requests for a width return equal parameters`(_ published: PoseidonParity.Width) throws {
        let first = try #require(Poseidon.Parameters.forWidth(published.width))
        let second = try #require(Poseidon.Parameters.forWidth(published.width))

        #expect(second.width == first.width)
        #expect(second.partialRounds == first.partialRounds)
        #expect(second.roundConstants == first.roundConstants)
        #expect(second.matrix == first.matrix)
    }
}
