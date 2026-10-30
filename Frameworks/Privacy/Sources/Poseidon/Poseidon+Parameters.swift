import ModularArithmetic
import Synchronization

extension Poseidon {
    /// The round constants and MDS matrix of one state width.
    struct Parameters: Sendable {
        static let fullRounds = 8

        /// The number of partial rounds of widths 2 to 13, by width.
        private static let partialRoundCounts = [
            2: 56, 3: 57, 4: 56, 5: 60, 6: 60, 7: 63, 8: 64, 9: 63, 10: 60, 11: 66, 12: 60, 13: 65,
        ]

        /// The parameters built so far, by width.
        private static let built = Mutex<[Int: Self]>([:])

        /// Returns the parameters of one width, building them on the first request.
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

        let partialRounds: Int

        /// The constants of each round, where round r adds `roundConstants[r × t + i]` to element i.
        let roundConstants: [Element]

        /// The t × t MDS matrix, by row.
        let matrix: [[Element]]

        /// Creates the parameters of one width.
        ///
        /// - Parameters:
        ///   - width: The number of state elements, t.
        ///   - partialRounds: The number of partial rounds for that width.
        private init(width: Int, partialRounds: Int) {
            var grain = Grain(width: width, fullRounds: Self.fullRounds, partialRounds: partialRounds)
            var roundConstants: [Element] = []
            while roundConstants.count < (Self.fullRounds + partialRounds) * width {
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
