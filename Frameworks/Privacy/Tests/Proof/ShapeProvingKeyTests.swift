@testable import Privacy
import Testing

struct ShapeProvingKeyTests {
    @Test(arguments: Shape.supported)
    func `Digests match the lock file`(shape: Shape) throws {
        let entry = try #require(try ProvingKeyVectors.load().keys["transfer_confidential_\(shape.inputs)_\(shape.outputs).key"])

        #expect(shape.provingKeyDigest == (try fixtureBytes(entry.sha256)))
    }

    @Test
    func `The lock file's transfer keys are the supported shapes`() throws {
        let names = try ProvingKeyVectors.load().keys.keys.filter { $0.wholeMatch(of: /transfer_confidential_\d+_\d+\.key/) != nil }

        #expect(Set(names) == Set(Shape.supported.map { "transfer_confidential_\($0.inputs)_\($0.outputs).key" }))
    }
}
