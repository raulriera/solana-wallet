import ModularArithmetic
@testable import Privacy
import Testing

struct GrainTests {
    private let fullRounds: Int

    private let widths: [PoseidonParity.Width]

    init() throws {
        let parameters = try PoseidonParity.load().parameters
        fullRounds = parameters.roundsFull
        widths = parameters.perArity
    }

    @Test(arguments: try PoseidonParity.load().parameters.perArity)
    func `Draws below r reproduce the published round-constant digest`(_ published: PoseidonParity.Width) throws {
        let constants = draws(for: published)
            .lazy
            .filter { Poseidon.Element(bigEndianBytes: $0) != nil }
            .prefix(published.arkCount)

        #expect(PoseidonParity.digest(of: constants) == (try published.roundConstantDigest))
    }

    @Test(arguments: try PoseidonParity.load().parameters.perArity)
    func `Every draw is below 2^254`(_ published: PoseidonParity.Width) {
        let invalidDrawIndices = draws(for: published)
            .prefix(published.arkCount)
            .enumerated()
            .filter { $0.element.count != 32 || $0.element[0] & 0b1100_0000 != 0 }
            .map(\.offset)

        #expect(invalidDrawIndices.isEmpty)
    }

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

    @Test
    func `Different widths produce different streams`() {
        let firstDraws = Set(widths.map { Array(draws(for: $0).prefix(1)) })

        #expect(firstDraws.count == widths.count)
    }

    private func draws(for published: PoseidonParity.Width) -> UnfoldSequence<[UInt8], Grain> {
        sequence(state: Grain(width: published.width, fullRounds: fullRounds, partialRounds: published.roundsPartial)) {
            $0.nextValue()
        }
    }
}
