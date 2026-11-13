import Foundation
import Redaction
import Wallet

/// The versioned recovery payload stored in the Keychain.
struct StoredRecovery: Codable, Redacted {
    let version: Int
    let phrase: String
    let passphrase: String

    /// Encodes recovery material as a stored payload.
    ///
    /// - Parameter recovery: The recovery material to encode.
    /// - Returns: The JSON payload.
    /// - Throws: ``KeychainStoreError/invalidRecovery`` if encoding fails.
    static func encode(_ recovery: Recovery) throws -> Data {
        let stored = StoredRecovery(
            version: 1, phrase: recovery.phrase.words.joined(separator: " "),
            passphrase: recovery.passphrase
        )
        do { return try JSONEncoder().encode(stored) }
        catch { throw KeychainStoreError.invalidRecovery }
    }

    /// Decodes and validates stored recovery material.
    ///
    /// - Parameter data: The stored JSON payload.
    /// - Returns: The validated recovery material.
    /// - Throws: ``KeychainStoreError/invalidRecovery`` for unsupported or malformed data.
    static func decode(_ data: Data) throws -> Recovery {
        do {
            let stored = try JSONDecoder().decode(Self.self, from: data)
            guard stored.version == 1 else { throw KeychainStoreError.invalidRecovery }
            return try Recovery(
                phrase: RecoveryPhrase(stored.phrase), passphrase: stored.passphrase
            )
        } catch { throw KeychainStoreError.invalidRecovery }
    }

    /// Creates a stored payload.
    ///
    /// - Parameters:
    ///   - version: The payload format version.
    ///   - phrase: The space-separated recovery words.
    ///   - passphrase: The BIP-39 passphrase.
    private init(version: Int, phrase: String, passphrase: String) {
        self.version = version
        self.phrase = phrase
        self.passphrase = passphrase
    }
}
