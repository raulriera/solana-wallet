import CryptoKit
import Foundation

/// BIP-39 seed derivation using Apple's HMAC-SHA512 implementation.
enum SeedDerivation {
    /// Derives the 64-byte seed using PBKDF2-HMAC-SHA512 with 2,048 iterations.
    ///
    /// Both inputs use the Unicode NFKD normalization required by BIP-39.
    /// A different passphrase produces a different valid seed; there is no
    /// passphrase correctness check without an independently known address.
    ///
    /// - Parameters:
    ///   - phrase: The validated recovery words.
    ///   - passphrase: The BIP-39 passphrase, including significant whitespace.
    /// - Returns: The derived seed bytes.
    /// - Throws: `CancellationError` if cancelled.
    static func seed(for phrase: RecoveryPhrase, passphrase: String) throws -> [UInt8] {
        try Task.checkCancellation()
        let password = phrase.words.joined(separator: " ").decomposedStringWithCompatibilityMapping
        let key = SymmetricKey(data: Array(password.utf8))
        let salt = "mnemonic" + passphrase.decomposedStringWithCompatibilityMapping
        // The 64-byte output fits one SHA-512 block; PBKDF2 numbers blocks from one.
        var block = Array(HMAC<SHA512>.authenticationCode(for: Array(salt.utf8) + [0, 0, 0, 1], using: key))
        defer { block.erase() }
        var result = block
        for iteration in 1..<2_048 {
            if iteration.isMultiple(of: 64) { try Task.checkCancellation() }
            block = Array(HMAC<SHA512>.authenticationCode(for: block, using: key))
            for index in result.indices { result[index] ^= block[index] }
        }
        try Task.checkCancellation()
        return result
    }
}
