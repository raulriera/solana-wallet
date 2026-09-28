import Foundation
import RPC
import Transactions
import Vault

/// The app's typed entry point for preparing and signing V1 transactions.
nonisolated struct TransactionCoordinator: TransactionCoordinating {
    private let preparer: any TransactionPreparing
    private let signer: any TransactionSigning

    /// Creates the wallet workflow with a shared provider and protected recovery store.
    ///
    /// - Parameters:
    ///   - rpc: The provider used for prerequisite checks and simulation.
    ///   - store: The recovery store that authenticates access to the selected wallet.
    init(rpc: any RPC, store: any RecoveryStoring) {
        self.init(preparer: Preparer(rpc: rpc), signer: Signer(rpc: rpc, store: store))
    }

    /// Creates a workflow with independently supplied preparation and signing services.
    ///
    /// - Parameters:
    ///   - preparer: The service that produces unsigned review data.
    ///   - signer: The service that validates and signs an approved preparation.
    init(preparer: any TransactionPreparing, signer: any TransactionSigning) {
        self.preparer = preparer
        self.signer = signer
    }

    /// Prepares an unsigned SOL transaction for user review.
    ///
    /// - Parameters:
    ///   - transfer: The sender, recipient, and amount in lamports.
    ///   - configuration: The explicit priority fee and execution resource limits.
    /// - Returns: The exact message, fee, expiry, and simulation observations.
    /// - Throws: A preparation error or `CancellationError` if cancelled.
    func prepare(_ transfer: Transfer, configuration: Configuration) async throws -> Preparation {
        try await preparer.prepare(transfer, configuration: configuration)
    }

    /// Prepares an imported V1 transaction for the selected required signer.
    ///
    /// - Parameters:
    ///   - transaction: The typed transaction supplied by the import boundary.
    ///   - signer: The selected account whose signature slot must be empty.
    /// - Returns: Exact transaction inspection, fee, and simulation observations.
    /// - Throws: A validation, RPC, or cancellation error.
    func prepare(_ transaction: Transaction, for signer: Address) async throws -> Preparation {
        try await preparer.prepare(transaction, for: signer)
    }

    /// Authenticates wallet access and signs the exact preparation approved by the user.
    ///
    /// The caller obtains explicit approval before invoking this operation.
    /// Signing doesn't broadcast the transaction or substitute new review data.
    ///
    /// - Parameters:
    ///   - preparation: The unchanged preparation whose details the user approved.
    ///   - walletID: The identifier of the selected wallet's protected recovery.
    ///   - reason: The localized explanation for biometric authentication.
    /// - Returns: The reviewed preparation and verified signed transaction.
    /// - Throws: A validation, authentication, signing, or cancellation error.
    func sign(_ preparation: Preparation, for walletID: UUID, reason: String) async throws -> SignedTransaction {
        try await signer.sign(preparation, for: walletID, reason: reason)
    }

}
