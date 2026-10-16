import Foundation
import ModularArithmetic

/// Solana Rings' fixed-length byte commitments, `hash_bytes_N` in zolana's specification.
///
/// The bytes split into consecutive 31-byte chunks, the last of which may be shorter. Each chunk is
/// right-aligned in a 32-byte big-endian value, which is below 2^248 and so below r. The first chunk
/// starts the hash, and each later chunk folds in as `Poseidon(hash, chunk)`. The hash doesn't
/// encode the length, so the protocol fixes the length of each value. The specification forbids a
/// variable-length byte hash, so only the lengths that Solana Rings uses have entry points.
enum PackedBytes {
    /// The number of bytes in each chunk.
    private static let chunkLength = 31

    /// Hashes a 32-byte value, such as a mint address, as `hash_bytes_32`.
    ///
    /// The value is a 31-byte chunk followed by a 1-byte chunk, so the hash is one Poseidon
    /// permutation. The zero address, SOL's mint, hashes to `Poseidon(0, 0)`, not to zero.
    ///
    /// - Parameter bytes: Exactly 32 bytes.
    /// - Returns: The commitment to `bytes`.
    /// - Precondition: `bytes` contains exactly 32 bytes.
    static func hash32(_ bytes: [UInt8]) -> Poseidon.Element {
        precondition(bytes.count == 32, "hash_bytes_32 needs exactly 32 bytes.")
        return fold(bytes)
    }

    /// Hashes a 33-byte value, such as a tagged owner public key, as `hash_bytes_33`.
    ///
    /// The value is a 31-byte chunk followed by a 2-byte chunk, so the hash is one Poseidon
    /// permutation.
    ///
    /// - Parameter bytes: Exactly 33 bytes.
    /// - Returns: The commitment to `bytes`.
    /// - Precondition: `bytes` contains exactly 33 bytes.
    static func hash33(_ bytes: [UInt8]) -> Poseidon.Element {
        precondition(bytes.count == 33, "hash_bytes_33 needs exactly 33 bytes.")
        return fold(bytes)
    }

    /// Folds the chunks of a value into its commitment.
    ///
    /// - Parameter bytes: The value.
    /// - Returns: The first chunk's field value, folded with each later chunk.
    private static func fold(_ bytes: [UInt8]) -> Poseidon.Element {
        stride(from: chunkLength, to: bytes.count, by: chunkLength)
            .reduce(field(of: bytes.prefix(chunkLength))) { hash, start in
                Poseidon.hash(hash, field(of: bytes.dropFirst(start).prefix(chunkLength)))
            }
    }

    /// Right-aligns at most 31 bytes in a field element, `hash_bytes_N` for N up to 31.
    ///
    /// The bytes are a big-endian integer below 2^248, and so below r; no Poseidon permutation runs.
    /// The 32-byte buffer that holds the bytes is zeroed before it's released, so a secret, such as
    /// a nullifier secret, leaves no copy in it. The returned element isn't erased.
    ///
    /// - Parameter bytes: At most 31 bytes.
    /// - Returns: The bytes as a field element.
    /// - Precondition: `bytes` contains at most 31 bytes.
    static func field(of bytes: some ContiguousBytes) -> Poseidon.Element {
        var value = [UInt8](repeating: 0, count: 32)
        defer { value.erase() }
        bytes.withUnsafeBytes { source in
            precondition(source.count <= chunkLength, "A field element holds at most 31 bytes.")
            value.withUnsafeMutableBytes { target in
                UnsafeMutableRawBufferPointer(rebasing: target[(target.count - source.count)...]).copyMemory(from: source)
            }
        }
        return Poseidon.Element(reducing: value)
    }
}

private extension [UInt8] {
    /// Overwrites every byte with zero before the buffer is released.
    ///
    /// This reduces secret residue in memory on a best-effort basis. Swift may have copied the
    /// bytes elsewhere, and those copies are not affected.
    mutating func erase() {
        withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
    }
}
