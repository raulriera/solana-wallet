import CryptoKit
import Foundation

extension Curve25519.KeyAgreement.PublicKey {
    /// The number of bytes in a tagged representation.
    static let taggedRepresentationLength = 33

    /// The first byte of a tagged representation.
    private static let tag: UInt8 = 4

    /// The field's modulus, 2²⁵⁵ − 19, in little-endian bytes.
    private static let modulus: [UInt8] = [0xed] + Array(repeating: 0xff, count: 30) + [0x7f]

    /// Creates a key from its 33-byte tagged representation, `0x04 ‖ u`.
    ///
    /// - Parameter taggedRepresentation: The tag 4 and the key's little-endian `u`-coordinate.
    /// - Throws: `CryptoKitError.incorrectKeySize` unless there are 33 bytes, or `CryptoKitError.invalidParameter` for
    ///   another tag or a `u` at or above the modulus.
    init(taggedRepresentation: some ContiguousBytes) throws {
        let bytes = taggedRepresentation.withUnsafeBytes { [UInt8]($0) }
        guard bytes.count == Self.taggedRepresentationLength else { throw CryptoKitError.incorrectKeySize }
        let u = bytes.dropFirst()
        guard bytes[0] == Self.tag, u.reversed().lexicographicallyPrecedes(Self.modulus.reversed()) else {
            throw CryptoKitError.invalidParameter
        }
        try self.init(rawRepresentation: u)
    }

    /// The key's 33-byte tagged representation, `0x04 ‖ u`.
    var taggedRepresentation: Data {
        Data([Self.tag]) + rawRepresentation
    }
}
