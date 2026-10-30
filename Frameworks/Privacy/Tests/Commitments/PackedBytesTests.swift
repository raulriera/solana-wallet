import ModularArithmetic
@testable import Privacy
import Testing

struct PackedBytesTests {
    @Test(arguments: try CommitmentVectors.load().hashBytes.filter { $0.input.count <= 62 })
    func `Values of up to 31 bytes pack into the published field elements`(_ vector: CommitmentVectors.ByteHash) throws {
        #expect(PackedBytes.field(of: try fixtureBytes(vector.input)).bigEndianBytes == (try fixtureBytes(vector.output)))
    }

    @Test(arguments: try CommitmentVectors.load().hashBytes.filter { $0.input.count == 64 })
    func `Commitments to 32 bytes match the published vector`(_ vector: CommitmentVectors.ByteHash) throws {
        #expect(PackedBytes.hash32(try fixtureBytes(vector.input)).bigEndianBytes == (try fixtureBytes(vector.output)))
    }

    @Test
    func `Commitments to 33 bytes match the published vector`() throws {
        let vector = try CommitmentVectors.load().ownerIdentity

        #expect(PackedBytes.hash33(try fixtureBytes(vector.hashBytes33Input)).bigEndianBytes == (try fixtureBytes(vector.hashBytes33)))
    }

    @Test(arguments: [
        (0x00, "2098f5fb9e239eab3ceac3f27b81e481dc3124d55ffed523a839ee8446b64864"),
        (0xff, "1f1c2e68e0d62a9a2991c8e69b40a368635a6d1eb5fe183e4e5d6bece7dae4c3"),
    ] as [(UInt8, String)])
    func `Commitments to 32 repeated bytes match independently derived values`(byte: UInt8, hex: String) throws {
        #expect(PackedBytes.hash32(Array(repeating: byte, count: 32)).bigEndianBytes == (try fixtureBytes(hex)))
    }

    @Test(arguments: [
        (0x00, "2098f5fb9e239eab3ceac3f27b81e481dc3124d55ffed523a839ee8446b64864"),
        (0xff, "2edc51f5f630735c7707e0e9729fa72b79412549d95b685b9ac47132db6671b3"),
    ] as [(UInt8, String)])
    func `Commitments to 33 repeated bytes match independently derived values`(byte: UInt8, hex: String) throws {
        #expect(PackedBytes.hash33(Array(repeating: byte, count: 33)).bigEndianBytes == (try fixtureBytes(hex)))
    }
}
