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
    private let transactionBuilder: any TransactionBuilding

    /// Creates a signer with protected recovery storage and protocol-based dependencies.
    ///
    /// - Parameters:
    ///   - rpc: The provider used to recheck the reviewed fee and original lifetime.
    ///   - store: The recovery store that authenticates access to the selected wallet.
    ///   - wallet: The account-bound message signer. The default is `Wallet`.
    ///   - messageBuilder: The local encoder used to check the reviewed intent.
    ///   - transactionBuilder: The assembler that verifies and fills the selected signature slot.
    init(
        rpc: any RPC,
        store: any RecoveryStoring,
        wallet: any MessageSigning = Wallet(),
        messageBuilder: any MessageBuilding = MessageBuilder(),
        transactionBuilder: any TransactionBuilding = TransactionBuilder()
    ) {
        validator = PreparationValidator(rpc: rpc, messageBuilder: messageBuilder, transactionBuilder: transactionBuilder)
        self.store = store
        self.wallet = wallet
        self.transactionBuilder = transactionBuilder
    }

    /// Validates the reviewed bytes before unlocking, then signs them without substitution.
    ///
    /// Expiry is checked before and after authentication. The original blockhash,
    /// amount, recipient, and fee configuration are never refreshed automatically.
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
    /// - Parameters:
    ///   - preparation: The already validated review data.
    ///   - recoveryID: The shared recovery identifier.
    ///   - path: The path constructed from the selected account's index.
    ///   - reason: The localized authentication explanation.
    /// - Returns: The signature from the recovered account matching the selected required signer.
    /// - Throws: A storage, expiry, signing, or cancellation error.
    private func signature(for preparation: Preparation, recoveryID: UUID, path: DerivationPath, reason: String) async throws -> Data {
        let recovery = try await store.recovery(for: recoveryID, reason: reason)
        try Task.checkCancellation()
        try await validator.validateLifetime(preparation)
        try Task.checkCancellation()
        return try await wallet.signature(
            for: preparation.message, using: recovery.phrase, expectedAddress: preparation.signer.value,
            passphrase: recovery.passphrase, path: path
        )
    }
}
