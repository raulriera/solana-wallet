import Foundation
import RPC
import Transactions
import Vault
import Wallet

/// A signer that validates, unlocks, and signs reviewed transactions.
nonisolated struct Signer: TransactionSigning {
    private let validator: any PreparationValidating
    private let store: any RecoveryStoring
    private let wallet: any MessageSigning
    private let transactionBuilder: any TransactionBuilding = TransactionBuilder()

    /// Creates a signer.
    ///
    /// - Parameters:
    ///   - validator: The validator that checks the preparation's fee and lifetime.
    ///   - store: The recovery store that authenticates access to saved accounts.
    ///   - wallet: The message signer.
    init(validator: any PreparationValidating, store: any RecoveryStoring, wallet: any MessageSigning = Wallet()) {
        self.validator = validator
        self.store = store
        self.wallet = wallet
    }

    @concurrent
    func sign(_ preparation: Preparation, for authority: Authority, reason: String) async throws -> SignedTransaction {
        try Task.checkCancellation()
        guard try authority.address == preparation.signer else { throw SigningError.signerMismatch }
        try await validator.validate(preparation)
        let signature = try await signature(for: preparation, by: authority, reason: reason)
        try Task.checkCancellation()
        try await validator.validateLifetime(preparation)
        try Task.checkCancellation()
        let transaction = try transactionBuilder.transaction(
            byAdding: signature, for: preparation.signer, to: preparation.bytes
        )
        try Task.checkCancellation()
        return SignedTransaction(preparation: preparation, transaction: transaction)
    }

    /// Returns an authority's signature over a preparation's message.
    ///
    /// - Parameters:
    ///   - preparation: The validated preparation.
    ///   - authority: The account that signs.
    ///   - reason: The localized reason for authentication.
    /// - Returns: The signature.
    /// - Throws: A storage, signing, or cancellation error.
    private func signature(for preparation: Preparation, by authority: Authority, reason: String) async throws -> Data {
        switch authority {
        case .account(let account):
            try await signature(for: preparation, using: store.recovery(for: account.recoveryID, reason: reason),
                                path: account.path)
        case .oneTime(let account):
            try account.signature(for: preparation.message)
        }
    }

    /// Signs a preparation's message with recovery material.
    ///
    /// - Parameters:
    ///   - preparation: The validated preparation.
    ///   - recovery: The authenticated recovery material.
    ///   - path: The account's derivation path.
    /// - Returns: The signature.
    /// - Throws: A signing or cancellation error.
    private func signature(for preparation: Preparation, using recovery: Recovery, path: DerivationPath) async throws -> Data {
        try Task.checkCancellation()
        return try await wallet.signature(
            for: preparation.message, using: recovery.phrase, expectedAddress: preparation.signer.value,
            passphrase: recovery.passphrase, path: path
        )
    }
}
