/// The numbers of input and output slots of a transact proof's circuit.
///
/// The prover has keys for 38 shapes, which zolana's `SPP_SUPPORTED_SHAPES` lists in order of
/// proving cost. A transact uses the first shape that holds its inputs and outputs and pads the
/// remaining slots.
struct Shape: Sendable, Hashable {
    /// The number of input slots.
    let inputs: Int

    /// The number of output slots.
    let outputs: Int

    /// The number of signer identities that the shape's proof publishes, `Shape::signer_width`: the
    /// fee payer and up to `min(inputs, 60 - inputs)` other input owners.
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
    /// - Returns: The first supported shape with at least as many input and output slots, or `nil`
    ///   if none has enough.
    static func fitting(inputs: Int, outputs: Int) -> Shape? {
        supported.first { inputs <= $0.inputs && outputs <= $0.outputs }
    }
}
