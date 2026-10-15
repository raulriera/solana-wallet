import ModularArithmetic
@testable import Privacy
import Testing

/// Verifies the Grain generator directly against zolana's published round-constant digests.
///
/// Each width's generator is seeded with the fixture's full and partial rounds, independent of
/// ``Poseidon/Parameters``.
struct GrainTests {
    /// The published number of full rounds, which seeds every width's generator.
    private let fullRounds: Int

    /// The published rounds and round-constant counts of every width.
    private let widths: [PoseidonParity.Width]

    /// Reads the published full rounds and widths from the fixture.
    ///
    /// - Throws: A test failure if the fixture is missing, or an error if it can't be read or decoded.
    init() throws {
        let parameters = try PoseidonParity.load().parameters
        fullRounds = parameters.roundsFull
        widths = parameters.perArity
    }

    /// Verifies that the draws below r reproduce each width's published round-constant digest.
    ///
    /// The round constants are the first published count of draws below r, in order, which is
    /// (full rounds + partial rounds) × t; canonical decoding accepts exactly the values below r,
    /// and the filter drops the others, as the parameter generation does. The digest has the format
    /// that ``PoseidonParity/digest(of:)`` computes.
    ///
    /// - Parameter published: The published rounds and round-constant digest of one width.
    @Test(arguments: try PoseidonParity.load().parameters.perArity)
    func `Draws below r reproduce the published round-constant digest`(_ published: PoseidonParity.Width) throws {
        let constants = draws(for: published)
            .lazy
            .filter { Poseidon.Element(bigEndianBytes: $0) != nil }
            .prefix(published.arkCount)

        #expect(PoseidonParity.digest(of: constants) == (try published.roundConstantDigest))
    }

    /// Verifies that every draw is 32 bytes below 2^254, with the top two bits of its first byte clear.
    ///
    /// The field's modulus r has 254 bits, so each draw takes 254 bits. The test checks as many
    /// draws as the published round-constant count, the least that the round constants need, and
    /// collects the indices of draws that are not 32 bytes or have either top bit set, so a failure
    /// lists them.
    ///
    /// - Parameter published: The published rounds and round-constant count of one width.
    @Test(arguments: try PoseidonParity.load().parameters.perArity)
    func `Every draw is below 2^254`(_ published: PoseidonParity.Width) {
        let invalidDrawIndices = draws(for: published)
            .prefix(published.arkCount)
            .enumerated()
            .filter { $0.element.count != 32 || $0.element[0] & 0b1100_0000 != 0 }
            .map(\.offset)

        #expect(invalidDrawIndices.isEmpty)
    }

    /// Verifies that two generators with the same seed produce the same stream.
    ///
    /// The generators draw in turn, so state shared between them would make the second draw of
    /// each pair continue the first generator's stream. The test compares the first 8 draws of each.
    ///
    /// - Parameter published: The published rounds of one width.
    @Test(arguments: try PoseidonParity.load().parameters.perArity)
    func `Generators with the same seed produce the same stream`(_ published: PoseidonParity.Width) {
        var first = draws(for: published).makeIterator()
        var second = draws(for: published).makeIterator()
        var firstDraws: [[UInt8]?] = []
        var secondDraws: [[UInt8]?] = []

        for _ in 0..<8 {
            firstDraws.append(first.next())
            secondDraws.append(second.next())
        }

        #expect(firstDraws == secondDraws)
    }

    /// Verifies that every width starts a different stream.
    ///
    /// Widths 2 and 4 share 56 partial rounds; 5, 6, 10, and 12 share 60; and 7 and 9 share 63. Their
    /// seeds differ only in the width, so distinct first draws show that the width alone changes
    /// the stream.
    @Test
    func `Different widths produce different streams`() {
        let firstDraws = Set(widths.map { Array(draws(for: $0).prefix(1)) })

        #expect(firstDraws.count == widths.count)
    }

    /// Returns the endless stream of draws for one width.
    ///
    /// - Parameter published: The published width and partial rounds that seed the generator.
    /// - Returns: The generator's 32-byte draws, in order.
    private func draws(for published: PoseidonParity.Width) -> UnfoldSequence<[UInt8], Grain> {
        sequence(state: Grain(width: published.width, fullRounds: fullRounds, partialRounds: published.roundsPartial)) {
            $0.nextValue()
        }
    }
}
