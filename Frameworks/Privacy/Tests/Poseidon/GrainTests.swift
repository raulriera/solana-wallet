import ModularArithmetic
import Testing
@testable import Privacy

struct GrainTests {
    private let fullRounds: Int

    init() throws {
        fullRounds = try PoseidonParity.load().parameters.roundsFull
    }

    @Test(arguments: try PoseidonParity.load().parameters.perArity)
    func `Draws below r reproduce the published round-constant digest`(_ published: PoseidonParity.Width) throws {
        let constants = draws(for: published)
            .lazy
            .filter { Poseidon.Element(bigEndianBytes: $0) != nil }
            .prefix(published.arkCount)

        #expect(PoseidonParity.digest(of: constants) == (try published.roundConstantDigest))
    }

    private func draws(for published: PoseidonParity.Width) -> UnfoldSequence<[UInt8], Grain> {
        sequence(state: Grain(width: published.width, fullRounds: fullRounds, partialRounds: published.roundsPartial)) {
            $0.nextValue()
        }
    }
}
