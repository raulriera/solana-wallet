import ModularArithmetic

/// The Poseidon hash over the BN254 scalar field with circom's x⁵ parameters.
///
/// The hash matches light-poseidon v0.4.0, which Solana Rings uses. Its state is a zero domain tag
/// followed by one to twelve inputs, a width t of 2 to 13. The permutation runs 4 full rounds, the
/// width's partial rounds, and 4 more full rounds. Each round adds that round's constants, raises
/// every element to the fifth power in a full round or only the first element in a partial round,
/// and multiplies the state by the MDS matrix. The hash is the first element of the final state.
///
/// The rounds depend only on the number of inputs, never on their values.
enum Poseidon {
    /// An element of the BN254 scalar field.
    typealias Element = FieldElement<BN254ScalarField>

    /// An input list that no supported width accepts.
    enum ValidationError: Error, Equatable {
        /// The hash takes one to twelve inputs.
        case unsupportedInputCount
    }

    /// Hashes one to twelve field elements.
    ///
    /// The first hash of each input count builds the parameters of its width; the process keeps
    /// them for later hashes.
    ///
    /// - Parameter inputs: One to twelve elements, such as canonical 32-byte big-endian values
    ///   decoded with `FieldElement(bigEndianBytes:)`.
    /// - Returns: The hash.
    /// - Throws: ``ValidationError/unsupportedInputCount`` for no inputs or more than twelve.
    static func hash(_ inputs: [Element]) throws -> Element {
        guard let parameters = Parameters.forWidth(inputs.count + 1) else {
            throw ValidationError.unsupportedInputCount
        }
        return permutation(of: [.zero] + inputs, with: parameters)[0]
    }

    /// Applies the Poseidon permutation to a state.
    ///
    /// The rounds update the state in place and write each MDS product to a second array, then
    /// swap the two, so every round reuses both arrays.
    ///
    /// - Parameters:
    ///   - state: Exactly `parameters.width` elements.
    ///   - parameters: The constants of the state's width.
    /// - Returns: The permuted state.
    private static func permutation(of state: consuming [Element], with parameters: Parameters) -> [Element] {
        let firstFullRounds = Parameters.fullRounds / 2
        let partialRounds = firstFullRounds..<firstFullRounds + parameters.partialRounds
        var product = [Element](repeating: .zero, count: parameters.width)
        for round in 0..<Parameters.fullRounds + parameters.partialRounds {
            for index in state.indices {
                state[index] += parameters.roundConstants[round * parameters.width + index]
            }
            if partialRounds.contains(round) {
                state[0] = fifthPower(state[0])
            } else {
                for index in state.indices {
                    state[index] = fifthPower(state[index])
                }
            }
            for (index, row) in parameters.matrix.enumerated() {
                product[index] = zip(row, state).reduce(.zero) { sum, term in sum + term.0 * term.1 }
            }
            swap(&state, &product)
        }
        return state
    }

    /// Applies the S-box.
    ///
    /// - Parameter element: An element of the state.
    /// - Returns: `element` raised to the fifth power.
    private static func fifthPower(_ element: Element) -> Element {
        let square = element * element
        return square * square * element
    }
}
