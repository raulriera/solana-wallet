@testable import Privacy
import Testing

/// Verifies the supported shapes and the choice of the cheapest one that fits.
struct ShapeTests {
    /// Verifies the list against zolana's `SPP_SUPPORTED_SHAPES`: 38 distinct shapes from one input
    /// and two outputs to 49 inputs and two outputs.
    @Test
    func `The supported shapes match zolana's list`() {
        let shapes = Shape.supported

        #expect(shapes.count == 38)
        #expect(shapes.first == Shape(inputs: 1, outputs: 2))
        #expect(shapes.last == Shape(inputs: 49, outputs: 2))
        #expect(Set(shapes.map { [$0.inputs, $0.outputs] }).count == 38)
    }

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
}
