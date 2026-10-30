import CryptoKit
public import Foundation

extension Wallet: MessageSigning {
    @concurrent
    public func signature(
        for message: Data,
        using phrase: RecoveryPhrase,
        expectedAddress: String,
        passphrase: String,
        path: DerivationPath
    ) async throws -> Data {
        try Task.checkCancellation()
        guard !message.isDerivationInput else { throw SigningError.reservedMessage }
        let signature = try Self.withVerifiedAccount(
            phrase, passphrase: passphrase, path: path, expectedAddress: expectedAddress,
            mismatch: SigningError.signerMismatch
        ) { key, _ in
            try Task.checkCancellation()
            return try key.signature(for: message)
        }
        try Task.checkCancellation()
        return signature
    }
}
