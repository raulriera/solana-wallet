@testable import Privacy
import Testing

/// Verifies the supported shapes and the choice of the cheapest one that fits.
struct ShapeTests {
    /// Verifies that the first shape in cost order that holds the slots is chosen, even where a
    /// later shape is smaller in one dimension.
    ///
    /// - Parameters:
    ///   - inputs: The number of inputs.
    ///   - outputs: The number of outputs.
    ///   - expected: The chosen shape's inputs and outputs.
    @Test(arguments: [
        (1, 0, [1, 2]), (1, 2, [1, 2]), (2, 3, [2, 4]), (1, 9, [1, 16]), (3, 5, [3, 8]),
        (5, 5, [5, 8]), (7, 2, [8, 2]), (13, 3, [16, 4]), (25, 1, [32, 2]), (49, 2, [49, 2]),
    ] as [(Int, Int, [Int])])
    func `The cheapest shape that holds the slots is chosen`(inputs: Int, outputs: Int, expected: [Int]) throws {
        let shape = try #require(Shape.fitting(inputs: inputs, outputs: outputs))

        #expect([shape.inputs, shape.outputs] == expected)
    }

    /// Verifies that slots beyond every supported shape have no shape.
    ///
    /// - Parameters:
    ///   - inputs: The number of inputs.
    ///   - outputs: The number of outputs.
    @Test(arguments: [(50, 1), (1, 17), (25, 3), (17, 9)] as [(Int, Int)])
    func `Slots beyond every shape have no shape`(inputs: Int, outputs: Int) {
        #expect(Shape.fitting(inputs: inputs, outputs: outputs) == nil)
    }

    /// Verifies the signer width, the payer and `min(inputs, 60 - inputs)` other owners, below and
    /// above 30 inputs, where the two bounds meet.
    ///
    /// - Parameters:
    ///   - inputs: The shape's inputs.
    ///   - outputs: The shape's outputs.
    ///   - expected: The signer width.
    @Test(arguments: [(1, 2, 2), (2, 4, 3), (8, 16, 9), (32, 2, 29), (40, 2, 21), (49, 2, 12)] as [(Int, Int, Int)])
    func `Signer widths follow zolana's owner signer slots`(inputs: Int, outputs: Int, expected: Int) {
        #expect(Shape(inputs: inputs, outputs: outputs).signerWidth == expected)
    }
}
