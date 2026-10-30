/// The numbers of input and output slots of a transact proof's circuit.
struct Shape: Sendable, Hashable {
    let inputs: Int

    let outputs: Int

    /// The number of signer identities that the shape's proof publishes.
    var signerWidth: Int { min(inputs, 60 - inputs) + 1 }

    /// Every shape that the prover supports, cheapest first.
    static let supported = [
        (1, 2), (1, 4), (1, 8), (2, 2), (2, 4), (1, 16), (2, 8), (3, 2), (3, 4), (2, 16),
        (3, 8), (4, 2), (4, 4), (4, 8), (5, 2), (5, 4), (4, 16), (5, 8), (6, 2), (6, 4),
        (5, 16), (6, 8), (8, 2), (8, 4), (8, 8), (8, 16), (12, 2), (12, 4), (12, 8), (16, 2),
        (16, 4), (16, 8), (24, 2), (24, 4), (32, 2), (40, 2), (48, 2), (49, 2),
    ].map { Shape(inputs: $0.0, outputs: $0.1) }

    /// Returns the cheapest supported shape that holds a transact's slots.
    ///
    /// - Parameters:
    ///   - inputs: The number of inputs, before padding.
    ///   - outputs: The number of outputs, before padding.
    /// - Returns: The shape, or `nil` if none holds the slots.
    static func fitting(inputs: Int, outputs: Int) -> Shape? {
        supported.first { inputs <= $0.inputs && outputs <= $0.outputs }
    }
}
