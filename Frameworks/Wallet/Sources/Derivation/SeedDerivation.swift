import CryptoKit
import Foundation

/// A namespace for BIP-39 seed derivation.
enum SeedDerivation {
    /// Derives the 64-byte BIP-39 seed of a recovery phrase.
    ///
    /// - Parameters:
    ///   - phrase: The validated recovery words.
    ///   - passphrase: The BIP-39 passphrase.
    /// - Returns: The 64-byte seed.
    /// - Throws: `CancellationError` if cancelled.
    static func seed(for phrase: RecoveryPhrase, passphrase: String) throws -> [UInt8] {
        try Task.checkCancellation()
        let password = phrase.words.joined(separator: " ").decomposedStringWithCompatibilityMapping.decomposedStringWithCanonicalMapping
        let key = SymmetricKey(data: Array(password.utf8))
        let salt = "mnemonic" + passphrase.decomposedStringWithCompatibilityMapping.decomposedStringWithCanonicalMapping
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
