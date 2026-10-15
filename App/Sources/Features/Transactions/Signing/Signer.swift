import Foundation
import RPC
import Transactions
import Vault
import Wallet

/// A stateless coordinator for validating, unlocking, and signing reviewed V1 transactions.
nonisolated struct Signer: TransactionSigning {
    private let validator: any PreparationValidating
    private let store: any RecoveryStoring
    private let wallet: any MessageSigning
    private let transactionBuilder: any TransactionBuilding = TransactionBuilder()

    /// Creates a signer with protected recovery storage and protocol-based dependencies.
    ///
    /// - Parameters:
    ///   - rpc: The provider used to recheck the reviewed fee and original lifetime.
    ///   - store: The recovery store that authenticates access to the selected wallet.
    ///   - wallet: The account-bound message signer. The default is `Wallet`.
    init(rpc: any RPC, store: any RecoveryStoring, wallet: any MessageSigning = Wallet()) {
        validator = PreparationValidator(rpc: rpc)
        self.store = store
        self.wallet = wallet
    }

    /// Validates the reviewed bytes before unlocking, then signs them without substitution.
    ///
    /// Expiry is checked before authentication and again after signing, so a message
    /// that expired during authentication never yields a usable signature. The original
    /// blockhash, amount, recipient, and fee configuration are never refreshed automatically.
    /// Recovery material stays local to this operation and isn't returned or cached.
    ///
    /// - Parameters:
    ///   - preparation: The preparation whose details the user has approved.
    ///   - account: The selected account and its shared recovery identity.
    ///   - reason: The localized explanation shown by the recovery store during authentication.
    /// - Returns: The typed signed transaction and the unchanged review data.
    /// - Throws: A prerequisite, dependency, or cancellation error.
    @concurrent
    func sign(_ preparation: Preparation, for account: Account, reason: String) async throws -> SignedTransaction {
        try Task.checkCancellation()
        guard account.address == preparation.signer else { throw SigningError.signerMismatch }
        let path = account.path
        try await validator.validate(preparation)
        let signature = try await signature(for: preparation, recoveryID: account.recoveryID, path: path, reason: reason)
        try Task.checkCancellation()
        let transaction = try transactionBuilder.transaction(
            byAdding: signature, for: preparation.signer, to: preparation.bytes
        )
        try Task.checkCancellation()
        return SignedTransaction(preparation: preparation, transaction: transaction)
    }

    /// Limits recovery material's lifetime to authentication and local signing.
    ///
    /// Recovery is released as soon as the signature exists; the lifetime recheck that
    /// follows runs without it and discards the signature if the message expired.
    ///
    /// - Parameters:
    ///   - preparation: The already validated review data.
    ///   - recoveryID: The shared recovery identifier.
    ///   - path: The selected account's derivation path.
    ///   - reason: The localized authentication explanation.
    /// - Returns: The signature from the recovered account matching the selected required signer.
    /// - Throws: A storage, expiry, signing, or cancellation error.
    private func signature(for preparation: Preparation, recoveryID: UUID, path: DerivationPath, reason: String) async throws -> Data {
        let signature = try await signature(for: preparation, using: store.recovery(for: recoveryID, reason: reason), path: path)
        try Task.checkCancellation()
        try await validator.validateLifetime(preparation)
        try Task.checkCancellation()
        return signature
    }

    /// Signs with recovery material whose lifetime ends when this call returns.
    ///
    /// - Parameters:
    ///   - preparation: The already validated review data.
    ///   - recovery: The authenticated recovery material, owned by this call only.
    ///   - path: The selected account's derivation path.
    /// - Returns: The signature over the reviewed message.
    /// - Throws: A signing or cancellation error.
    private func signature(for preparation: Preparation, using recovery: Recovery, path: DerivationPath) async throws -> Data {
        try Task.checkCancellation()
        return try await wallet.signature(
            for: preparation.message, using: recovery.phrase, expectedAddress: preparation.signer.value,
            passphrase: recovery.passphrase, path: path
        )
    }
}
