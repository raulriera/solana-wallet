import Algorithms
import Foundation
import ModularArithmetic

/// The commitments to fixed-length byte values.
enum PackedBytes {
    /// The length of each chunk, in bytes.
    private static let chunkLength = 31

    /// Hashes a 32-byte value.
    ///
    /// - Parameter bytes: The 32 bytes to hash.
    /// - Returns: The commitment to `bytes`.
    static func hash32(_ bytes: [UInt8]) -> Poseidon.Element {
        precondition(bytes.count == 32, "hash_bytes_32 needs exactly 32 bytes.")
        return fold(bytes)
    }

    /// Hashes a 33-byte value.
    ///
    /// - Parameter bytes: The 33 bytes to hash.
    /// - Returns: The commitment to `bytes`.
    static func hash33(_ bytes: [UInt8]) -> Poseidon.Element {
        precondition(bytes.count == 33, "hash_bytes_33 needs exactly 33 bytes.")
        return fold(bytes)
    }

    /// Folds the chunks of a value into its commitment.
    ///
    /// - Parameter bytes: The value.
    /// - Returns: The first chunk's field value, folded with each later chunk.
    private static func fold(_ bytes: [UInt8]) -> Poseidon.Element {
        let chunks = bytes.chunks(ofCount: chunkLength)
        return chunks.dropFirst().reduce(field(of: chunks.first ?? [])) { hash, chunk in
            Poseidon.hash(hash, field(of: chunk))
        }
    }

    /// Right-aligns at most 31 bytes in a field element.
    ///
    /// - Parameter bytes: The bytes, at most 31.
    /// - Returns: The bytes as a field element.
    static func field(of bytes: some ContiguousBytes) -> Poseidon.Element {
        bytes.withUnsafeBytes { source in
            precondition(source.count <= chunkLength, "A field element holds at most 31 bytes.")
            return Poseidon.Element(reducingRightAligned: source)
        }
    }
}
