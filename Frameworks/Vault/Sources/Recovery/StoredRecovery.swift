import Foundation
import Wallet

/// The versioned representation stored inside the protected Keychain value.
struct StoredRecovery: Codable {
    let version: Int
    let phrase: String
    let passphrase: String

    /// Encodes recovery material for protected storage.
    ///
    /// - Parameter recovery: The material to preserve without changing its passphrase.
    /// - Returns: A versioned JSON payload containing secrets.
    /// - Throws: ``KeychainStore/Failure/invalidRecovery`` if encoding fails.
    static func encode(_ recovery: Recovery) throws -> Data {
        let stored = StoredRecovery(
            version: 1, phrase: recovery.phrase.words.joined(separator: " "),
            passphrase: recovery.passphrase
        )
        do { return try JSONEncoder().encode(stored) }
        catch { throw KeychainStore.Failure.invalidRecovery }
    }

    /// Decodes and validates stored recovery material.
    ///
    /// - Parameter data: The authenticated Keychain value.
    /// - Returns: Validated recovery material using the original passphrase.
    /// - Throws: ``KeychainStore/Failure/invalidRecovery`` for unsupported or malformed data.
    static func decode(_ data: Data) throws -> Recovery {
        do {
            let stored = try JSONDecoder().decode(Self.self, from: data)
            guard stored.version == 1 else { throw KeychainStore.Failure.invalidRecovery }
            return try Recovery(
                phrase: RecoveryPhrase(stored.phrase), passphrase: stored.passphrase
            )
        } catch { throw KeychainStore.Failure.invalidRecovery }
    }

    /// Creates a versioned representation from validated recovery material.
    ///
    /// - Parameters:
    ///   - version: The payload format version.
    ///   - phrase: The space-separated recovery words.
    ///   - passphrase: The unmodified BIP-39 passphrase.
    private init(version: Int, phrase: String, passphrase: String) {
        self.version = version
        self.phrase = phrase
        self.passphrase = passphrase
    }
}
