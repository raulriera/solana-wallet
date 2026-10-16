import ModularArithmetic
@testable import Privacy
import Testing

/// Verifies the fixed-length byte commitments against zolana's published vectors and
/// independently derived values.
///
/// zolana publishes `hash_bytes` vectors for 0, 1, 31, 32, 62, and 63 bytes, and a 33-byte vector
/// in its owner-identity section. Values of up to 31 bytes are packed field elements, so the 0-, 1-,
/// and 31-byte vectors check `field(of:)`. The module hashes only the lengths that Solana Rings uses,
/// 32 and 33 bytes, so the 62- and 63-byte vectors have no entry point.
struct PackedBytesTests {
    /// Verifies that values of up to 31 bytes pack into the published field elements.
    ///
    /// - Parameter vector: A published value of at most 31 bytes and its field element.
    @Test(arguments: try CommitmentVectors.load().hashBytes.filter { $0.input.count <= 62 })
    func `Values of up to 31 bytes pack into the published field elements`(_ vector: CommitmentVectors.ByteHash) throws {
        #expect(PackedBytes.field(of: try fixtureBytes(vector.input)).bigEndianBytes == (try fixtureBytes(vector.output)))
    }

    /// Verifies 32-byte commitments against the published vector of that length.
    ///
    /// The vector's 32 bytes are a 31-byte chunk and a 1-byte chunk, so it checks one fold.
    ///
    /// - Parameter vector: A published 32-byte value and its commitment.
    @Test(arguments: try CommitmentVectors.load().hashBytes.filter { $0.input.count == 64 })
    func `Commitments to 32 bytes match the published vector`(_ vector: CommitmentVectors.ByteHash) throws {
        #expect(PackedBytes.hash32(try fixtureBytes(vector.input)).bigEndianBytes == (try fixtureBytes(vector.output)))
    }

    /// Verifies 33-byte commitments against the published vector of that length.
    ///
    /// The vector's 33 bytes are a 31-byte chunk and a 2-byte chunk.
    @Test
    func `Commitments to 33 bytes match the published vector`() throws {
        let vector = try CommitmentVectors.load().ownerIdentity

        #expect(PackedBytes.hash33(try fixtureBytes(vector.hashBytes33Input)).bigEndianBytes == (try fixtureBytes(vector.hashBytes33)))
    }

    /// Verifies 32-byte commitments to repeated bytes against independently derived values.
    ///
    /// The values come from a separate Python implementation of Poseidon and `hash_bytes_N`. Zero
    /// bytes, SOL's mint address, hash to `Poseidon(0, 0)`, not to zero. All-ones bytes fill each
    /// chunk to its largest value.
    ///
    /// - Parameters:
    ///   - byte: The byte that fills all 32 positions.
    ///   - hex: The expected commitment.
    @Test(arguments: [
        (0x00, "2098f5fb9e239eab3ceac3f27b81e481dc3124d55ffed523a839ee8446b64864"),
        (0xff, "1f1c2e68e0d62a9a2991c8e69b40a368635a6d1eb5fe183e4e5d6bece7dae4c3"),
    ] as [(UInt8, String)])
    func `Commitments to 32 repeated bytes match independently derived values`(byte: UInt8, hex: String) throws {
        #expect(PackedBytes.hash32(Array(repeating: byte, count: 32)).bigEndianBytes == (try fixtureBytes(hex)))
    }

    /// Verifies 33-byte commitments to repeated bytes against independently derived values.
    ///
    /// The values come from a separate Python implementation of Poseidon and `hash_bytes_N`. Zero
    /// bytes also hash to `Poseidon(0, 0)`, because the length isn't encoded. All-ones bytes fill
    /// each chunk to its largest value.
    ///
    /// - Parameters:
    ///   - byte: The byte that fills all 33 positions.
    ///   - hex: The expected commitment.
    @Test(arguments: [
        (0x00, "2098f5fb9e239eab3ceac3f27b81e481dc3124d55ffed523a839ee8446b64864"),
        (0xff, "2edc51f5f630735c7707e0e9729fa72b79412549d95b685b9ac47132db6671b3"),
    ] as [(UInt8, String)])
    func `Commitments to 33 repeated bytes match independently derived values`(byte: UInt8, hex: String) throws {
        #expect(PackedBytes.hash33(Array(repeating: byte, count: 33)).bigEndianBytes == (try fixtureBytes(hex)))
    }
}
