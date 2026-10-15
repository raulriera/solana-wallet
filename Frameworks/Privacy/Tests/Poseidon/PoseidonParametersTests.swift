import ModularArithmetic
@testable import Privacy
import Testing

/// Verifies each width's generated Poseidon parameters against zolana's published parity fixture.
struct PoseidonParametersTests {
    /// Verifies that each width's generated parameters have the published partial rounds and
    /// constant digests.
    ///
    /// The fixture's `roundsPartial` gives each width's count, from 56 for width 2 to 65 for width 13.
    /// The digests cover the round constants in order and the MDS matrix entries by row, in the
    /// format that ``PoseidonParity/digest(of:)`` computes.
    ///
    /// - Parameter published: The published partial rounds and digests of one width.
    @Test(arguments: try PoseidonParity.load().parameters.perArity)
    func `Generated parameters match the published partial rounds and digests`(_ published: PoseidonParity.Width) throws {
        let parameters = try #require(Poseidon.Parameters.forWidth(published.width))

        #expect(parameters.partialRounds == published.roundsPartial)
        #expect(PoseidonParity.digest(of: parameters.roundConstants.map(\.bigEndianBytes)) == (try published.roundConstantDigest))
        #expect(PoseidonParity.digest(of: parameters.matrix.joined().map(\.bigEndianBytes)) == (try published.matrixDigest))
    }

    /// Verifies that widths outside 2 to 13 have no parameters.
    ///
    /// The fixture publishes widths 2 to 13 only: a domain tag followed by one to twelve inputs.
    ///
    /// - Parameter width: A width below 2 or above 13.
    @Test(arguments: [-1, 0, 1, 14])
    func `Widths outside 2 to 13 have no parameters`(width: Int) {
        #expect(Poseidon.Parameters.forWidth(width) == nil)
    }

    /// Verifies that repeated requests for a width return equal parameters.
    ///
    /// The first request for a width builds its parameters and later requests return the stored
    /// copy, so every request sees the same constants and matrix.
    ///
    /// - Parameter published: The published width to request.
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
