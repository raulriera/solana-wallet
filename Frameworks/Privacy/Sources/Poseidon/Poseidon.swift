import ModularArithmetic

/// The Poseidon hash over the BN254 scalar field with the x⁵ S-box.
enum Poseidon {
    /// An element of the BN254 scalar field.
    typealias Element = FieldElement<BN254ScalarField>

    /// An error that rejects a list of inputs.
    enum ValidationError: Error, Equatable {
        case unsupportedInputCount
    }

    /// Hashes one to twelve field elements.
    ///
    /// - Parameter inputs: The one to twelve elements to hash.
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
    /// - Parameters:
    ///   - state: The state, with `parameters.width` elements.
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

    /// Raises an element to the fifth power.
    ///
    /// - Parameter element: An element of the state.
    /// - Returns: `element` raised to the fifth power.
    private static func fifthPower(_ element: Element) -> Element {
        let square = element * element
        return square * square * element
    }
}
