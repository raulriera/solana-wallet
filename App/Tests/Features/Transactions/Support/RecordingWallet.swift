import Foundation
import Wallet

/// Counts signing attempts while delegating cryptography to the actual wallet.
actor RecordingWallet: MessageSigning {
    private(set) var messages: [Data] = []

    /// Signs using the real account-bound implementation without retaining recovery material.
    ///
    /// - Parameters:
    ///   - message: The exact message to record and sign.
    ///   - phrase: A public recovery fixture.
    ///   - expectedAddress: The account the signing service expects to recover.
    ///   - passphrase: The fixture's original BIP-39 passphrase.
    ///   - path: The fixture's account derivation path.
    /// - Returns: The real Ed25519 signature.
    /// - Throws: An account-mismatch, derivation, or cancellation error.
    func signature(for message: Data, using phrase: RecoveryPhrase, expectedAddress: String,
                   passphrase: String, path: DerivationPath) async throws -> Data {
        messages.append(message)
        return try await Wallet().signature(for: message, using: phrase, expectedAddress: expectedAddress,
                                            passphrase: passphrase, path: path)
    }
}
