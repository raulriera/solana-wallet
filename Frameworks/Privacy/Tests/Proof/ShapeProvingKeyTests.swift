@testable import Privacy
import Testing

/// Verifies the proving-key digests of the supported shapes against zolana's lock file.
struct ShapeProvingKeyTests {
    /// Verifies each supported shape's digest against its key file's entry.
    ///
    /// - Parameter shape: A supported shape.
    @Test(arguments: Shape.supported)
    func `Digests match the lock file`(shape: Shape) throws {
        let entry = try #require(try ProvingKeyVectors.load().keys["transfer_confidential_\(shape.inputs)_\(shape.outputs).key"])

        #expect(shape.provingKeyDigest == (try fixtureBytes(entry.sha256)))
    }

    /// Verifies that the lock file's transfer keys are exactly the supported shapes, so no shape
    /// lacks a key and no key lacks a shape.
    @Test
    func `The lock file's transfer keys are the supported shapes`() throws {
        let names = try ProvingKeyVectors.load().keys.keys.filter { $0.hasPrefix("transfer_confidential_") }

        #expect(Set(names) == Set(Shape.supported.map { "transfer_confidential_\($0.inputs)_\($0.outputs).key" }))
    }
}
