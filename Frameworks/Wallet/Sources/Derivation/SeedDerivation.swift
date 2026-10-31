import CommonCrypto
import Foundation

/// A namespace for BIP-39 seed derivation.
enum SeedDerivation {
    /// An error from the platform key derivation.
    enum DerivationError: Error {
        case derivationFailed
    }

    private static let rounds: UInt32 = 2_048

    /// The length of a BIP-39 seed, in bytes.
    private static let seedLength = 64

    /// Derives the 64-byte BIP-39 seed of a recovery phrase with PBKDF2-HMAC-SHA512.
    ///
    /// - Parameters:
    ///   - phrase: The validated recovery words.
    ///   - passphrase: The BIP-39 passphrase.
    /// - Returns: The 64-byte seed.
    /// - Throws: `CancellationError` if cancelled, or ``DerivationError/derivationFailed`` if CommonCrypto fails.
    static func seed(for phrase: RecoveryPhrase, passphrase: String) throws -> [UInt8] {
        try Task.checkCancellation()
        let password = phrase.words.joined(separator: " ").decomposedStringWithCompatibilityMapping.decomposedStringWithCanonicalMapping
        let salt = "mnemonic" + passphrase.decomposedStringWithCompatibilityMapping.decomposedStringWithCanonicalMapping
        var seed = [UInt8](repeating: 0, count: seedLength)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2), password, password.utf8.count, salt, salt.utf8.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512), rounds, &seed, seedLength
        )
        guard status == CCCryptorStatus(kCCSuccess) else { throw DerivationError.derivationFailed }
        return seed
    }
}
