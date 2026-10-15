import ModularArithmetic
import Synchronization

extension Poseidon {
    /// The round constants and MDS matrix of one state width.
    ///
    /// The constants come from the Grain LFSR method of the `generate_parameters_grain.sage` script in
    /// [hadeshash](https://extgit.isec.tugraz.at/krypto/hadeshash), with which light-poseidon generated
    /// its tables for each width.
    /// The hadeshash authors have deprecated that script. It is used because Solana Rings fixes
    /// circom's BN254 x⁵ parameters, which light-poseidon's tables hold.
    struct Parameters: Sendable {
        /// The full rounds of every width: half before the partial rounds and half after them.
        static let fullRounds = 8

        /// The partial rounds of widths 2 to 13, by width.
        ///
        /// From light-poseidon v0.4.0 (`PARTIAL_ROUNDS` in `light-poseidon/src/parameters/bn254_x5.rs`,
        /// first twelve entries), matching the `roundsPartial` values of zolana's Poseidon parity fixture.
        private static let partialRoundCounts = [
            2: 56, 3: 57, 4: 56, 5: 60, 6: 60, 7: 63, 8: 64, 9: 63, 10: 60, 11: 66, 12: 60, 13: 65,
        ]

        /// The widths built so far, by width.
        private static let built = Mutex<[Int: Self]>([:])

        /// Returns the parameters of one width, building them on the first request for that width.
        ///
        /// Building takes milliseconds, so it runs outside the lock and never blocks requests for
        /// other widths. Concurrent first requests for one width may each build it; the generation
        /// is deterministic, and the first copy stored is the one every caller gets. The process
        /// keeps every width it builds.
        ///
        /// - Parameter width: The number of state elements, t.
        /// - Returns: The width's parameters, or `nil` for a width outside 2 to 13.
        static func forWidth(_ width: Int) -> Self? {
            guard let partialRounds = partialRoundCounts[width] else { return nil }
            if let parameters = built.withLock({ $0[width] }) {
                return parameters
            }
            let parameters = Self(width: width, partialRounds: partialRounds)
            return built.withLock { widths in
                if let stored = widths[width] {
                    return stored
                }
                widths[width] = parameters
                return parameters
            }
        }

        /// The number of state elements, t.
        let width: Int

        /// The number of partial rounds.
        let partialRounds: Int

        /// One constant for each element in each round; round r adds `roundConstants[r × t + i]`
        /// to element i.
        let roundConstants: [Element]

        /// The t × t MDS matrix, by row; element i of the new state is the sum over j of
        /// `matrix[i][j]` times element j.
        let matrix: [[Element]]

        /// Generates the parameters of one width.
        ///
        /// The generator draws the round constants first, discarding draws at or above r. It then
        /// draws 2t values reduced modulo r, x₀ to xₜ₋₁ followed by y₀ to yₜ₋₁, and sets each matrix
        /// entry M[i][j] to (xᵢ + yⱼ)⁻¹. The script resamples when the 2t values repeat, when some
        /// xᵢ + yⱼ is zero, or when the matrix fails its security checks. The published matrix
        /// digests show that it kept the first sample for every supported width, so this generator
        /// uses the first sample without those checks.
        ///
        /// - Parameters:
        ///   - width: The number of state elements, t.
        ///   - partialRounds: The number of partial rounds for that width.
        private init(width: Int, partialRounds: Int) {
            var grain = Grain(width: width, fullRounds: Self.fullRounds, partialRounds: partialRounds)
            var roundConstants: [Element] = []
            while roundConstants.count < (Self.fullRounds + partialRounds) * width {
                // A draw at or above r has no canonical element, so the generator draws again.
                if let constant = Element(bigEndianBytes: grain.nextValue()) {
                    roundConstants.append(constant)
                }
            }
            let samples = (0..<2 * width).map { _ in Element(reducing: grain.nextValue()) }
            self.width = width
            self.partialRounds = partialRounds
            self.roundConstants = roundConstants
            matrix = samples.prefix(width).map { x in
                samples.suffix(width).map { y in (x + y).inverse() }
            }
        }
    }
}
